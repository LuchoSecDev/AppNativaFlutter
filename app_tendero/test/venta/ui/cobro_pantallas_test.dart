import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/caja/caja_models.dart';
import 'package:stockpilot/caja/caja_providers.dart';
import 'package:stockpilot/carrito/carrito_models.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/carrito/ui/carrito_screen.dart';
import 'package:stockpilot/catalogo/catalogo_providers.dart';
import 'package:stockpilot/catalogo/producto.dart';
import 'package:stockpilot/home_screen.dart';
import 'package:stockpilot/venta/venta_models.dart';
import 'package:stockpilot/venta/venta_providers.dart';

import '../../support/carrito_apoyo.dart';
import '../../support/fake_adapter.dart';

class _CajaAbiertaFija extends CajaNotifier {
  @override
  EstadoCaja build() => const EstadoCaja.abierta(
    SesionCaja(
      idSesion: 1,
      montoApertura: '50000.00',
      fechaApertura: '2026-10-04T15:30:00.000Z',
    ),
  );
}

/// Las pantallas del cobro con el cliente HTTP REAL y un servidor falso con los ejemplos reales del backend.
void main() {
  const clave = '4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22';
  const ruta = '/api/registrar-venta-carrito';

  late ServidorFalso servidor;
  late AlmacenEnMemoria almacenCarrito;
  late AlmacenVentaEnMemoria almacenVenta;
  var llamadasAlGenerador = 0;

  // Lo que ya tiene la app descargado (puede estar «viejo» respecto de lo que dice el servidor).
  Producto arroz({String precio = '4500.00', int cantidad = 10}) =>
      producto(1, 'Arroz Diana 1Kg', precio: precio, cantidad: cantidad);
  final aceite = producto(
    2,
    'Aceite Gourmet 1L',
    precio: '12000.00',
    cantidad: 5,
  );

  ProviderContainer contenedor(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  /// [catalogoDelServidor] es lo que el servidor responderá cuando la pantalla de cobro vuelva a descargar los
  /// precios (por defecto, el ejemplo real: arroz a $4.500 con 10 en stock, aceite a $12.000 con 5).
  Future<void> abrir(
    WidgetTester tester, {
    Widget pantalla = const CarritoScreen(),
    List<Producto>? productosDeLaApp,
    List<LineaCarrito> lineas = const [
      LineaCarrito(idProducto: 1, nombre: 'Arroz Diana 1Kg', cantidad: 2),
    ],
    AlmacenVentaEnMemoria? ventaPrevia,
    RespuestaFalsa? catalogoDelServidor,
  }) async {
    llamadasAlGenerador = 0;
    servidor = ServidorFalso();
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
    servidor.programar(
      'GET',
      '/api/productos',
      catalogoDelServidor ??
          RespuestaFalsa.deEjemplo('13_C1_lista_de_productos'),
    );
    almacenCarrito = AlmacenEnMemoria();
    if (lineas.isNotEmpty) {
      almacenCarrito.datos['carrito_v1_2_1'] = lineas;
    }
    almacenVenta = ventaPrevia ?? AlmacenVentaEnMemoria();
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
              EstadoCatalogo.listo(productosDeLaApp ?? [arroz(), aceite]),
            ),
          ),
          cajaProvider.overrideWith(() => _CajaAbiertaFija()),
          almacenCarritoProvider.overrideWithValue(almacenCarrito),
          almacenVentaPendienteProvider.overrideWithValue(almacenVenta),
          generadorDeClaveProvider.overrideWithValue(() {
            llamadasAlGenerador++;
            return llamadasAlGenerador == 1
                ? clave
                : 'otra-clave-$llamadasAlGenerador';
          }),
          // Sin reintentos automáticos en estas pruebas: el desenlace se ve de inmediato.
          esperasDeReintentoProvider.overrideWithValue(const []),
        ],
        child: MaterialApp(home: pantalla),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder campoEfectivo() => find.widgetWithText(TextField, 'Efectivo recibido');

  Future<void> abrirCobro(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Cobrar en efectivo'));
    await tester.pumpAndSettle();
  }

  Future<void> escribir(WidgetTester tester, String pesos) async {
    await tester.enterText(campoEfectivo(), pesos);
    await tester.pump();
  }

  Future<void> confirmar(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar cobro'));
    await tester.pumpAndSettle();
  }

  void programarVentaOk() => servidor.programar(
    'POST',
    ruta,
    RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
  );

  void programarSinRed() => servidor.programar(
    'POST',
    ruta,
    const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
  );

  group('la pantalla de cobro en efectivo', () {
    testWidgets(
      'verifica los precios, muestra el total, el cambio o lo que falta, y solo deja confirmar si alcanza',
      (tester) async {
        await abrir(tester);
        await abrirCobro(tester);

        expect(servidor.veces('GET', '/api/productos'), 1);
        expect(find.text('Total a cobrar'), findsOneWidget);
        expect(find.text(r'$9.000'), findsOneWidget);
        expect(find.textContaining('El total cambió'), findsNothing);

        ElevatedButton confirmarCobro() => tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Confirmar cobro'),
        );
        expect(confirmarCobro().onPressed, isNull, reason: 'sin escribir nada');

        await escribir(tester, '5000');
        expect(find.text(r'Faltan $4.000'), findsOneWidget);
        expect(confirmarCobro().onPressed, isNull);

        await escribir(tester, '8999');
        expect(find.text(r'Faltan $1'), findsOneWidget);
        expect(confirmarCobro().onPressed, isNull);

        await escribir(tester, '9000');
        expect(find.text(r'Cambio: $0'), findsOneWidget);
        expect(confirmarCobro().onPressed, isNotNull);

        await escribir(tester, '10000');
        expect(find.text(r'Cambio: $1.000'), findsOneWidget);
        expect(confirmarCobro().onPressed, isNotNull);
      },
    );

    testWidgets('«Monto exacto» escribe el total', (tester) async {
      await abrir(tester);
      await abrirCobro(tester);
      await tester.tap(find.text('Monto exacto'));
      await tester.pump();
      expect(
        tester.widget<TextField>(campoEfectivo()).controller!.text,
        '9000',
      );
      expect(find.text(r'Cambio: $0'), findsOneWidget);
    });

    testWidgets('el campo solo admite dígitos y hasta 9', (tester) async {
      await abrir(tester);
      await abrirCobro(tester);
      await escribir(tester, '12ab.-3456789012');
      expect(
        tester.widget<TextField>(campoEfectivo()).controller!.text,
        '123456789',
      );
    });

    testWidgets(
      'si el servidor tiene OTRO precio, se avisa que el total cambió y se cobra con el nuevo',
      (tester) async {
        // La app descargó el arroz a $4.000; el servidor ya lo tiene a $4.500.
        await abrir(
          tester,
          productosDeLaApp: [
            arroz(precio: '4000.00'),
            aceite,
          ],
        );
        expect(find.text(r'Total: $8.000'), findsOneWidget);
        await abrirCobro(tester);

        expect(find.text(r'$9.000'), findsOneWidget);
        expect(
          find.textContaining(
            r'El total cambió al actualizar los precios: antes era $8.000',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'si no se pueden verificar los precios NO se deja cobrar; «Reintentar» lo intenta de nuevo',
      (tester) async {
        await abrir(
          tester,
          catalogoDelServidor: const RespuestaFalsa.falloDeRed(
            DioExceptionType.connectionError,
          ),
        );
        await abrirCobro(tester);

        expect(
          find.textContaining('No se pudo verificar los precios'),
          findsOneWidget,
        );
        expect(campoEfectivo(), findsNothing);
        expect(
          find.widgetWithText(ElevatedButton, 'Confirmar cobro'),
          findsNothing,
        );

        servidor.programar(
          'GET',
          '/api/productos',
          RespuestaFalsa.deEjemplo('13_C1_lista_de_productos'),
        );
        await tester.tap(find.widgetWithText(ElevatedButton, 'Reintentar'));
        await tester.pumpAndSettle();
        expect(campoEfectivo(), findsOneWidget);
      },
    );

    testWidgets(
      'si al verificar, un producto ya no alcanza (stock 1 de 2), no se deja cobrar y se vuelve al carrito',
      (tester) async {
        await abrir(
          tester,
          catalogoDelServidor: const RespuestaFalsa(200, [
            {
              'id_producto': 1,
              'codigo': 'ARR-001',
              'codigo_barras': null,
              'nombre_producto': 'Arroz Diana 1Kg',
              'categoria': 'Granos',
              'precio': '4500.00',
              'cantidad': 1,
              'estado': 'Disponible',
              'nivel_stock': 'critico',
            },
          ]),
        );
        await abrirCobro(tester);

        expect(
          find.textContaining('algunos productos del carrito cambiaron'),
          findsOneWidget,
        );
        expect(campoEfectivo(), findsNothing);
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Volver al carrito'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Solo hay 1 unidad en stock.'), findsOneWidget);
      },
    );
  });

  group('el desenlace del cobro, en el carrito', () {
    testWidgets(
      'venta registrada: comprobante con el cambio; «Nueva venta» deja el carrito vacío y en la copia no queda nada',
      (tester) async {
        await abrir(tester);
        programarVentaOk();
        await abrirCobro(tester);
        await escribir(tester, '10000');
        await confirmar(tester);

        expect(find.text('Venta registrada'), findsOneWidget);
        expect(find.text('Venta n.º 1'), findsOneWidget);
        expect(find.text(r'$9.000'), findsOneWidget);
        expect(find.text(r'$10.000'), findsOneWidget);
        expect(find.text('Cambio a devolver'), findsOneWidget);
        expect(find.text(r'$1.000'), findsOneWidget);
        expect(find.textContaining('ya estaba registrada'), findsNothing);
        expect(almacenVenta.datos, isEmpty);
        expect(servidor.veces('POST', ruta), 1);

        await tester.tap(find.text('Nueva venta'));
        await tester.pumpAndSettle();
        expect(find.text('El carrito está vacío'), findsOneWidget);
        expect(almacenCarrito.datos['carrito_v1_2_1'], isNull);
      },
    );

    testWidgets(
      'sin red: «sin confirmar», con aviso de no cobrar otra vez, líneas bloqueadas; «Reintentar» recupera la MISMA venta',
      (tester) async {
        await abrir(tester);
        programarSinRed();
        await abrirCobro(tester);
        await escribir(tester, '10000');
        await confirmar(tester);

        expect(find.textContaining('No la cobres otra vez'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(find.text('Cancelar este cobro'), findsOneWidget);
        expect(find.text('Registrando la venta…'), findsNothing);
        // Las líneas siguen a la vista pero no se pueden cambiar.
        expect(find.text('Arroz Diana 1Kg'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
              .onPressed,
          isNull,
        );
        expect(
          find.widgetWithText(FilledButton, 'Cobrar en efectivo'),
          findsNothing,
        );
        expect(find.byTooltip('Vaciar carrito'), findsNothing);
        expect(almacenVenta.datos, isNotEmpty);

        servidor.programar(
          'POST',
          ruta,
          RespuestaFalsa.deEjemplo('18_V2_reintento_misma_clave_200'),
        );
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();

        expect(find.text('Venta registrada'), findsOneWidget);
        expect(find.textContaining('ya estaba registrada'), findsOneWidget);
        final envios = servidor.peticiones.where(
          (p) => p.clave == 'POST $ruta',
        );
        expect(envios.map((p) => p.headers['Idempotency-Key']), [clave, clave]);
        expect(almacenVenta.datos, isEmpty);
      },
    );

    testWidgets(
      '«Cancelar este cobro» advierte del riesgo de duplicar; si se confirma, se puede cobrar otra vez',
      (tester) async {
        await abrir(tester);
        programarSinRed();
        await abrirCobro(tester);
        await escribir(tester, '10000');
        await confirmar(tester);

        await tester.tap(find.text('Cancelar este cobro'));
        await tester.pumpAndSettle();
        expect(find.textContaining('quedará duplicada'), findsOneWidget);

        await tester.tap(find.text('Volver'));
        await tester.pumpAndSettle();
        expect(
          find.text('Reintentar'),
          findsOneWidget,
          reason: 'sigue sin confirmar',
        );

        await tester.tap(find.text('Cancelar este cobro'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancelar el cobro'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(FilledButton, 'Cobrar en efectivo'),
          findsOneWidget,
        );
        expect(almacenVenta.datos, isEmpty);
      },
    );

    testWidgets(
      'un rechazo del servidor se muestra con su mensaje, el carrito sigue y se puede corregir',
      (tester) async {
        await abrir(tester);
        servidor.programar(
          'POST',
          ruta,
          RespuestaFalsa.deEjemplo('20_V2_stock_insuficiente_400'),
        );
        await abrirCobro(tester);
        await escribir(tester, '10000');
        await confirmar(tester);

        expect(
          find.text('Stock insuficiente para el producto: Arroz Diana 1Kg'),
          findsOneWidget,
        );
        expect(find.text('Arroz Diana 1Kg'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Cobrar en efectivo'),
              )
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'al salir del carrito con la venta registrada, la próxima vez empieza limpio',
      (tester) async {
        await abrir(tester, pantalla: const HomeScreen());
        await tester.tap(find.text('Vender'));
        await tester.pumpAndSettle();
        programarVentaOk();
        await abrirCobro(tester);
        await escribir(tester, '10000');
        await confirmar(tester);
        expect(find.text('Venta registrada'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(contenedor(tester).read(cobroProvider).fase, FaseCobro.libre);

        await tester.tap(find.text('Vender'));
        await tester.pumpAndSettle();
        expect(find.text('Venta registrada'), findsNothing);
        expect(find.text('El carrito está vacío'), findsOneWidget);
      },
    );
  });

  group('desde la pantalla de inicio', () {
    testWidgets('una venta sin confirmar se anuncia en el inicio', (
      tester,
    ) async {
      final previa = AlmacenVentaEnMemoria()
        ..datos['venta_pendiente_v1_2_1'] = const VentaPendiente(
          clave: clave,
          items: [ItemVenta(idProducto: 1, cantidad: 2)],
          metodoPago: MetodoPago.efectivo,
          totalCentavos: 900000,
          efectivoRecibido: 10000,
        );
      await abrir(tester, pantalla: const HomeScreen(), ventaPrevia: previa);
      expect(
        find.textContaining('Hay una venta sin confirmar'),
        findsOneWidget,
      );
    });

    testWidgets('sin ventas pendientes no hay aviso', (tester) async {
      await abrir(tester, pantalla: const HomeScreen());
      expect(find.textContaining('sin confirmar'), findsNothing);
    });
  });
}
