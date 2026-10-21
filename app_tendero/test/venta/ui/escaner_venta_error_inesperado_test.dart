import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/catalogo/catalogo_providers.dart';
import 'package:stockpilot/scan_stabilizer.dart';
import 'package:stockpilot/venta/ui/escaner_venta_screen.dart';
import 'package:stockpilot/venta/venta_providers.dart';

import '../../support/carrito_apoyo.dart';
import '../../support/fake_adapter.dart';

/// Si al buscar un código llega algo que NO es un error de red ni del servidor (por ejemplo, un producto con un campo
/// de otro tipo), el escáner no debe quedarse congelado en silencio: avisa, sigue escaneando y deja el error a la vista
/// de Flutter para que no se pierda.
void main() {
  const arroz = '7701234000011';
  const rutaArroz = '/api/productos/barcode/$arroz';

  /// Una «cámara» falsa: un botón que entrega 3 lecturas iguales del arroz, como la real al estabilizarse.
  Widget camaraFalsa(
    BuildContext context,
    ScanStabilizer estabilizador,
    bool pausado,
    ValueChanged<String> alConfirmar,
  ) => Column(
    children: [
      Text(pausado ? 'PAUSADO' : 'ESCANEANDO'),
      ElevatedButton(
        onPressed: () {
          for (var i = 0; i < 3; i++) {
            final confirmado = estabilizador.leer(
              arroz,
              pausado: pausado,
              ahora: DateTime(2026, 10, 5, 10),
            );
            if (confirmado != null) {
              alConfirmar(confirmado);
            }
          }
        },
        child: const Text('Leer'),
      ),
    ],
  );

  Future<ProviderContainer> abrir(
    WidgetTester tester,
    RespuestaFalsa respuestaDelCodigo,
  ) async {
    final servidor = ServidorFalso()
      ..programar('GET', rutaArroz, respuestaDelCodigo);
    final dio = crearClienteApi(
      baseUrl: 'https://servidor.test',
      cookieJar: CookieJar(),
      adapter: servidor,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          sesionProvider.overrideWith(() => SesionFija(sesionActiva())),
          catalogoProvider.overrideWith(
            () => CatalogoFijo(
              EstadoCatalogo.listo([
                producto(1, 'Arroz Diana 1Kg', precio: '4500.00', cantidad: 10),
              ]),
            ),
          ),
          almacenCarritoProvider.overrideWithValue(AlmacenEnMemoria()),
          almacenVentaPendienteProvider.overrideWithValue(
            AlmacenVentaEnMemoria(),
          ),
        ],
        child: MaterialApp(
          home: EscanerVentaScreen(construirVista: camaraFalsa),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  /// El ejemplo REAL 11 con un campo cambiado de tipo (la categoría como número): no hay un ejemplo real así.
  RespuestaFalsa productoConCampoRaro() => RespuestaFalsa(200, {
    'success': true,
    'data': {
      'id_producto': 1,
      'codigo': 'ARR-001',
      'codigo_barras': arroz,
      'nombre_producto': 'Arroz Diana 1Kg',
      'categoria': 5,
      'precio': '4500.00',
      'cantidad': 10,
      'estado': 'Disponible',
    },
  });

  /// Corre [accion] anotando los errores que Flutter recibe, y vuelve a poner el manejador de siempre ANTES de devolver
  /// el control: si las aserciones de la prueba corrieran con el manejador cambiado, un fallo quedaría tragado y la
  /// prueba se colgaría en vez de fallar.
  Future<List<FlutterErrorDetails>> capturandoErrores(
    Future<void> Function() accion,
  ) async {
    final reportados = <FlutterErrorDetails>[];
    final anterior = FlutterError.onError;
    FlutterError.onError = reportados.add;
    try {
      await accion();
    } finally {
      FlutterError.onError = anterior;
    }
    return reportados;
  }

  testWidgets(
    'un producto con un campo de otro tipo: avisa, no agrega, sigue escaneando y reporta el error a Flutter',
    (tester) async {
      late ProviderContainer c;
      final reportados = await capturandoErrores(() async {
        c = await abrir(tester, productoConCampoRaro());
        await tester.tap(find.text('Leer'));
        await tester.pumpAndSettle();
      });

      expect(c.read(carritoProvider).lineas, isEmpty);
      expect(
        find.text('No se pudo leer ese producto. Inténtalo de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('ESCANEANDO'), findsOneWidget, reason: 'no se congela');
      expect(reportados, hasLength(1), reason: 'el error no se pierde');
    },
  );

  testWidgets('tras ese error se puede volver a leer el mismo código', (
    tester,
  ) async {
    final reportados = await capturandoErrores(() async {
      await abrir(tester, productoConCampoRaro());
      await tester.tap(find.text('Leer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leer'));
      await tester.pumpAndSettle();
    });
    expect(find.text('ESCANEANDO'), findsOneWidget);
    expect(reportados, hasLength(2), reason: 'cada lectura fallida se reporta');
  });
}
