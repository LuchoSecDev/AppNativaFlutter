import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/auth/ui/auth_gate.dart';
import 'package:stockpilot/catalogo/catalogo_providers.dart';
import 'package:stockpilot/catalogo/producto.dart';
import 'package:stockpilot/catalogo/ui/buscar_producto_screen.dart';

import '../../support/fake_adapter.dart';

/// Un catálogo de prueba con casos que importan: tildes, agotado, inactivo y sin código de barras.
const _lista = [
  {
    'id_producto': 1,
    'codigo': 'ARR-001',
    'codigo_barras': '7701234000011',
    'nombre_producto': 'Arroz Diana 1Kg',
    'categoria': 'Granos',
    'precio': '4500.00',
    'cantidad': 10,
    'estado': 'Disponible',
    'nivel_stock': 'ok',
  },
  {
    'id_producto': 2,
    'codigo': 'ACE-001',
    'codigo_barras': null,
    'nombre_producto': 'Aceite Gourmet 1L',
    'categoria': 'Aceites',
    'precio': '12000.00',
    'cantidad': 5,
    'estado': 'Disponible',
    'nivel_stock': 'ok',
  },
  {
    'id_producto': 3,
    'codigo': 'CAF-001',
    'codigo_barras': '7709990000012',
    'nombre_producto': 'Café Sello Rojo 250g',
    'categoria': 'Bebidas',
    'precio': '9800.00',
    'cantidad': 0,
    'estado': 'Disponible',
    'nivel_stock': 'agotado',
  },
  {
    'id_producto': 4,
    'codigo': 'VIE-001',
    'codigo_barras': null,
    'nombre_producto': 'Producto descontinuado',
    'categoria': 'Varios',
    'precio': '1000.00',
    'cantidad': 3,
    'estado': 'Inactivo',
    'nivel_stock': 'ok',
  },
];

void main() {
  late ServidorFalso servidor;

  /// Abre la app con sesión iniciada y el catálogo programado por cada prueba, y entra a «Consultar productos».
  Future<void> abrirBuscador(
    WidgetTester tester,
    void Function(ServidorFalso s) programarCatalogo,
  ) async {
    servidor = ServidorFalso();
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
    servidor.programar(
      'GET',
      '/api/session-info',
      RespuestaFalsa.deEjemplo('05_S4_session_info'),
    );
    servidor.programar(
      'GET',
      '/api/caja/sesion',
      RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'),
    );
    programarCatalogo(servidor);
    final caducidad = StreamController<void>.broadcast();
    addTearDown(caducidad.close);
    final dio = crearClienteApi(
      baseUrl: 'https://servidor.test',
      cookieJar: CookieJar(),
      adapter: servidor,
      onSessionExpired: () => caducidad.add(null),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          sesionCaducadaProvider.overrideWithValue(caducidad.stream),
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consultar productos'));
    await tester.pumpAndSettle();
  }

  void conLista(ServidorFalso s) =>
      s.programar('GET', '/api/productos', const RespuestaFalsa(200, _lista));

  Future<void> escribir(WidgetTester tester, String texto) async {
    await tester.enterText(find.byType(TextField), texto);
    await tester.pumpAndSettle();
  }

  group('consultar productos', () {
    testWidgets(
      'muestra los productos disponibles ordenados, con precio en pesos y stock',
      (tester) async {
        await abrirBuscador(tester, conLista);
        expect(find.text('Arroz Diana 1Kg'), findsOneWidget);
        expect(find.text('Aceite Gourmet 1L'), findsOneWidget);
        expect(find.text('Café Sello Rojo 250g'), findsOneWidget);
        expect(find.text(r'$4.500'), findsOneWidget);
        expect(find.text(r'$12.000'), findsOneWidget);
        expect(find.textContaining('Stock: 10'), findsOneWidget);
        // Orden alfabético: Aceite, Arroz, Café.
        double y(String t) => tester.getTopLeft(find.text(t)).dy;
        expect(y('Aceite Gourmet 1L'), lessThan(y('Arroz Diana 1Kg')));
        expect(y('Arroz Diana 1Kg'), lessThan(y('Café Sello Rojo 250g')));
      },
    );

    testWidgets('un producto inactivo no se ofrece', (tester) async {
      await abrirBuscador(tester, conLista);
      expect(find.text('Producto descontinuado'), findsNothing);
    });

    testWidgets('un producto agotado aparece, marcado como «Agotado»', (
      tester,
    ) async {
      await abrirBuscador(tester, conLista);
      expect(find.text('Agotado'), findsOneWidget);
    });

    testWidgets('al escribir filtra, sin importar mayúsculas ni tildes', (
      tester,
    ) async {
      await abrirBuscador(tester, conLista);
      await escribir(tester, 'ARROZ');
      expect(find.text('Arroz Diana 1Kg'), findsOneWidget);
      expect(find.text('Aceite Gourmet 1L'), findsNothing);

      await escribir(tester, 'cafe'); // el producto se llama «Café»
      expect(find.text('Café Sello Rojo 250g'), findsOneWidget);
      expect(find.text('Arroz Diana 1Kg'), findsNothing);
    });

    testWidgets('también encuentra por código de barras y por código interno', (
      tester,
    ) async {
      await abrirBuscador(tester, conLista);
      await escribir(tester, '7701234000011');
      expect(find.text('Arroz Diana 1Kg'), findsOneWidget);
      await escribir(tester, 'ace-001');
      expect(find.text('Aceite Gourmet 1L'), findsOneWidget);
    });

    testWidgets(
      'sin coincidencias lo dice, y el botón de borrar devuelve toda la lista',
      (tester) async {
        await abrirBuscador(tester, conLista);
        await escribir(tester, 'zzzz');
        expect(find.text('No encontré productos con «zzzz».'), findsOneWidget);
        await tester.tap(find.byTooltip('Borrar búsqueda'));
        await tester.pumpAndSettle();
        expect(find.text('Arroz Diana 1Kg'), findsOneWidget);
        expect(find.textContaining('No encontré'), findsNothing);
      },
    );

    testWidgets(
      'al tocar un producto muestra sus datos, incluido si no tiene código de barras',
      (tester) async {
        await abrirBuscador(tester, conLista);
        await tester.tap(find.text('Aceite Gourmet 1L'));
        await tester.pumpAndSettle();
        expect(find.text(r'Precio: $12.000'), findsOneWidget);
        expect(find.text('Stock: 5 unidades'), findsOneWidget);
        expect(find.text('Código de barras: sin asociar'), findsOneWidget);
      },
    );

    testWidgets('una tienda sin productos lo dice', (tester) async {
      await abrirBuscador(
        tester,
        (s) => s.programar(
          'GET',
          '/api/productos',
          const RespuestaFalsa(200, <dynamic>[]),
        ),
      );
      expect(
        find.text('La tienda no tiene productos disponibles.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'si no se puede cargar: muestra el error y «Reintentar» descarga de nuevo',
      (tester) async {
        await abrirBuscador(tester, (s) {
          s.programar(
            'GET',
            '/api/productos',
            const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
          );
          conLista(s);
        });
        expect(
          find.textContaining('No hay conexión con el servidor'),
          findsOneWidget,
        );
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
        expect(find.text('Arroz Diana 1Kg'), findsOneWidget);
      },
    );

    testWidgets(
      '«tirar para actualizar» vuelve a descargar; si falla, conserva la lista con un aviso',
      (tester) async {
        await abrirBuscador(tester, (s) {
          conLista(s);
          s.programar(
            'GET',
            '/api/productos',
            const RespuestaFalsa.falloDeRed(DioExceptionType.receiveTimeout),
          );
        });
        await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
        await tester.pumpAndSettle();
        expect(servidor.veces('GET', '/api/productos'), 2);
        expect(
          find.textContaining('No se pudo actualizar la lista'),
          findsOneWidget,
        );
        expect(
          find.text('Arroz Diana 1Kg'),
          findsOneWidget,
        ); // la lista anterior sigue a la vista
      },
    );
  });

  group('modo «elegir producto» (lo usará el carrito)', () {
    /// Abre la pantalla de elegir sobre un catálogo fijo, sin pasar por la sesión ni el servidor.
    Future<void> abrirElegir(
      WidgetTester tester,
      void Function(Producto) alElegir,
    ) async {
      final productos = [for (final j in _lista) Producto.desdeJson(j)];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogoProvider.overrideWith(
              () => _CatalogoFijo(EstadoCatalogo.listo(productos)),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (contexto) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(contexto).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            BuscarProductoScreen(alElegir: alElegir),
                      ),
                    ),
                    child: const Text('Abrir'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('tocar un producto con stock lo entrega y vuelve atrás', (
      tester,
    ) async {
      Producto? elegido;
      await abrirElegir(tester, (p) => elegido = p);
      expect(find.text('Elegir producto'), findsOneWidget);
      await tester.tap(find.text('Arroz Diana 1Kg'));
      await tester.pumpAndSettle();
      expect(elegido?.id, 1);
      expect(find.text('Elegir producto'), findsNothing); // volvió atrás
    });

    testWidgets(
      'un producto AGOTADO no se puede elegir: avisa y se queda en la pantalla',
      (tester) async {
        Producto? elegido;
        await abrirElegir(tester, (p) => elegido = p);
        await tester.tap(find.text('Café Sello Rojo 250g'));
        await tester.pumpAndSettle();
        expect(elegido, isNull);
        expect(find.textContaining('está agotado'), findsOneWidget);
        expect(find.text('Elegir producto'), findsOneWidget);
      },
    );
  });
}

/// Un notificador del catálogo con un estado fijo, para probar la pantalla sin sesión ni servidor.
class _CatalogoFijo extends CatalogoNotifier {
  _CatalogoFijo(this._estado);

  final EstadoCatalogo _estado;

  @override
  EstadoCatalogo build() => _estado;
}
