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
import '../../support/estado_producto_apoyo.dart';
import '../../support/fake_adapter.dart';

/// El escáner de venta ante un producto vencido: [C2] ya trae `estado_vencimiento` (ejemplo real 11), así que se
/// avisa «vencido» al leer el código, antes de que el servidor rechace todo el carrito. Lo que vence hoy se agrega.
///
/// Las respuestas se arman a partir del ejemplo REAL 11 cambiándole solo `estado_vencimiento`: no hay un ejemplo
/// real de [C2] con un producto vencido.
void main() {
  const arroz = '7701234000011';
  const rutaArroz = '/api/productos/barcode/$arroz';

  late ServidorFalso servidor;

  /// El ejemplo 11 con el vencimiento que se pida.
  RespuestaFalsa c2Con(Map<String, Object?>? estadoVencimiento) {
    final cuerpo = Map<String, dynamic>.of(
      cuerpoDeEjemplo('11_C2_producto_por_codigo_de_barras')!
          as Map<String, dynamic>,
    );
    final data = Map<String, dynamic>.of(cuerpo['data'] as Map<String, dynamic>)
      ..['estado_vencimiento'] = estadoVencimiento;
    return RespuestaFalsa(200, {...cuerpo, 'data': data});
  }

  /// Una «cámara» falsa: un botón que entrega 3 lecturas iguales del arroz, como la real al estabilizarse.
  Widget camaraFalsa(
    BuildContext context,
    ScanStabilizer estabilizador,
    bool pausado,
    ValueChanged<String> alConfirmar,
  ) => ElevatedButton(
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
  );

  Future<ProviderContainer> leer(
    WidgetTester tester,
    Map<String, Object?>? estadoVencimiento,
  ) async {
    servidor = ServidorFalso()
      ..programar('GET', rutaArroz, c2Con(estadoVencimiento));
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
                productoConEstado('Arroz Diana 1Kg', id: 1, precio: '4500.00'),
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
    await tester.tap(find.text('Leer'));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  testWidgets('vencido: no se agrega y avisa que está vencido', (tester) async {
    final c = await leer(tester, {'tipo': 'vencido', 'dias': -2});
    expect(c.read(carritoProvider).lineas, isEmpty);
    expect(
      find.text('«Arroz Diana 1Kg» está vencido y no se puede vender.'),
      findsOneWidget,
    );
  });

  testWidgets('vence hoy: se vende, se agrega', (tester) async {
    final c = await leer(tester, {'tipo': 'hoy', 'dias': 0});
    expect(c.read(carritoProvider).lineas.single.idProducto, 1);
  });

  testWidgets('sin vencimiento (el ejemplo real): se agrega como siempre', (
    tester,
  ) async {
    final c = await leer(tester, null);
    expect(c.read(carritoProvider).lineas.single.idProducto, 1);
  });
}
