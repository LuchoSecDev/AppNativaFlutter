import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/carrito/ui/carrito_screen.dart';
import 'package:stockpilot/catalogo/ui/buscar_producto_screen.dart';
import 'package:stockpilot/home_screen.dart';
import 'package:stockpilot/venta/venta_providers.dart';

import '../support/carrito_apoyo.dart';
import '../support/fake_adapter.dart';

/// La caja y los productos pueden cambiar fuera de la app (la web): estas pruebas comprueban que la app vuelve a
/// preguntar al volver a primer plano, al tirar para actualizar y con los botones «Actualizar», con el cliente HTTP
/// REAL y un servidor falso con los ejemplos reales del backend.
void main() {
  late ServidorFalso servidor;

  void programarCajaAbierta() => servidor.programar(
    'GET',
    '/api/caja/sesion',
    RespuestaFalsa.deEjemplo('10_K1_caja_abierta'),
  );

  void programarCajaCerrada() => servidor.programar(
    'GET',
    '/api/caja/sesion',
    RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'),
  );

  void programarSinRed(String ruta) => servidor.programar(
    'GET',
    ruta,
    const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
  );

  Future<void> abrir(
    WidgetTester tester, {
    Widget pantalla = const HomeScreen(),
    bool cajaAbierta = true,
  }) async {
    servidor = ServidorFalso();
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
    servidor.programar(
      'GET',
      '/api/productos',
      RespuestaFalsa.deEjemplo('13_C1_lista_de_productos'),
    );
    if (cajaAbierta) {
      programarCajaAbierta();
    } else {
      programarCajaCerrada();
    }
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
          almacenCarritoProvider.overrideWithValue(AlmacenEnMemoria()),
          almacenVentaPendienteProvider.overrideWithValue(
            AlmacenVentaEnMemoria(),
          ),
        ],
        child: MaterialApp(home: pantalla),
      ),
    );
    await tester.pumpAndSettle();
  }

  int consultasDeCaja() => servidor.veces('GET', '/api/caja/sesion');
  int consultasDeProductos() => servidor.veces('GET', '/api/productos');

  /// Lo que hace Android al mandar la app al fondo y traerla de vuelta.
  Future<void> irseYVolver(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  bool venderActivo(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Vender'))
          .onPressed !=
      null;

  group('al volver a la app', () {
    testWidgets(
      'si la caja se cerró en la web: pasa a «Caja cerrada», lo explica y bloquea Vender',
      (tester) async {
        await abrir(tester);
        expect(find.text('Caja abierta'), findsOneWidget);
        expect(venderActivo(tester), isTrue);
        expect(consultasDeCaja(), 1);
        final productosAntes = consultasDeProductos();

        programarCajaCerrada();
        await irseYVolver(tester);

        expect(find.text('Caja cerrada'), findsOneWidget);
        expect(
          find.textContaining('se cerró desde otro lugar'),
          findsOneWidget,
        );
        expect(venderActivo(tester), isFalse);
        expect(consultasDeCaja(), 2);
        expect(
          consultasDeProductos(),
          productosAntes + 1,
          reason: 'también se actualizan los productos',
        );
      },
    );

    testWidgets(
      'si la caja se abrió en la web: pasa a «Caja abierta» y habilita Vender',
      (tester) async {
        await abrir(tester, cajaAbierta: false);
        expect(find.text('Caja cerrada'), findsOneWidget);
        expect(venderActivo(tester), isFalse);

        programarCajaAbierta();
        await irseYVolver(tester);

        expect(find.text('Caja abierta'), findsOneWidget);
        expect(venderActivo(tester), isTrue);
      },
    );

    testWidgets('sin conexión: no pasa nada visible, conserva lo que se veía', (
      tester,
    ) async {
      await abrir(tester);
      programarSinRed('/api/caja/sesion');
      programarSinRed('/api/productos');
      await irseYVolver(tester);
      expect(find.text('Caja abierta'), findsOneWidget);
      expect(venderActivo(tester), isTrue);
      expect(consultasDeCaja(), 2);
    });

    testWidgets('solo al volver: irse a segundo plano no consulta nada', (
      tester,
    ) async {
      await abrir(tester);
      final productosAntes = consultasDeProductos();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(consultasDeCaja(), 1);
      expect(consultasDeProductos(), productosAntes);
    });
  });

  group('actualizar a mano', () {
    testWidgets(
      'tirar hacia abajo en el inicio actualiza la caja y los productos',
      (tester) async {
        await abrir(tester);
        final productosAntes = consultasDeProductos();
        programarCajaCerrada();
        await tester.fling(
          find.byType(ListView).first,
          const Offset(0, 400),
          1000,
        );
        await tester.pumpAndSettle();
        expect(find.text('Caja cerrada'), findsOneWidget);
        expect(consultasDeCaja(), 2);
        expect(consultasDeProductos(), productosAntes + 1);
      },
    );

    testWidgets('el botón de la tarjeta de caja actualiza SOLO la caja', (
      tester,
    ) async {
      await abrir(tester);
      final productosAntes = consultasDeProductos();
      programarCajaCerrada();
      await tester.tap(find.byTooltip('Actualizar la caja'));
      await tester.pumpAndSettle();
      expect(find.text('Caja cerrada'), findsOneWidget);
      expect(consultasDeCaja(), 2);
      expect(consultasDeProductos(), productosAntes);
      // También está con la caja cerrada (para ver si la abrieron en la web).
      expect(find.byTooltip('Actualizar la caja'), findsOneWidget);
    });

    testWidgets(
      'con la caja cerrada, el botón de la tarjeta detecta que la abrieron en la web',
      (tester) async {
        await abrir(tester, cajaAbierta: false);
        expect(find.text('Caja cerrada'), findsOneWidget);
        programarCajaAbierta();
        await tester.tap(find.byTooltip('Actualizar la caja'));
        await tester.pumpAndSettle();
        expect(find.text('Caja abierta'), findsOneWidget);
        expect(venderActivo(tester), isTrue);
      },
    );

    testWidgets(
      'en el carrito, «Actualizar» consulta caja y productos y avisa «Actualizado»',
      (tester) async {
        await abrir(tester, pantalla: const CarritoScreen());
        final productosAntes = consultasDeProductos();
        programarCajaCerrada();
        await tester.tap(find.byTooltip('Actualizar caja y precios'));
        await tester.pumpAndSettle();
        expect(consultasDeCaja(), 2);
        expect(consultasDeProductos(), productosAntes + 1);
        expect(find.text('Actualizado.'), findsOneWidget);
        // La caja cerrada se refleja de inmediato: el escáner queda bloqueado.
        expect(find.text('Abre la caja para escanear.'), findsOneWidget);
      },
    );

    testWidgets('en el carrito, sin conexión avisa que no se pudo actualizar', (
      tester,
    ) async {
      await abrir(tester, pantalla: const CarritoScreen());
      programarSinRed('/api/productos');
      await tester.tap(find.byTooltip('Actualizar caja y precios'));
      await tester.pumpAndSettle();
      expect(
        find.text('No se pudo actualizar. Revisa tu conexión.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'en el buscador de productos, «Actualizar» vuelve a descargar la lista y avisa',
      (tester) async {
        await abrir(tester, pantalla: const BuscarProductoScreen());
        expect(consultasDeProductos(), 1); // la carga inicial
        await tester.tap(find.byTooltip('Actualizar la lista'));
        await tester.pumpAndSettle();
        expect(consultasDeProductos(), 2);
        expect(find.text('Actualizado.'), findsOneWidget);
      },
    );
  });
}
