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
import 'package:stockpilot/venta/venta_providers.dart';

import 'carrito_apoyo.dart';
import 'fake_adapter.dart';

/// La clave de idempotencia que el generador falso entrega a la PRIMERA venta de cada prueba.
const claveDeCobro = '4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22';

/// La ruta del cobro (`[V2]`).
const rutaDeCobro = '/api/registrar-venta-carrito';

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

Finder campoEfectivo() => find.widgetWithText(TextField, 'Efectivo recibido');

Future<void> abrirCobro(
  WidgetTester tester, {
  String metodo = 'Efectivo',
}) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Cobrar...'));
  await tester.pumpAndSettle();
  // La hoja «¿Cómo vas a cobrar?» ofrece los cuatro métodos; por defecto se elige el efectivo.
  await tester.tap(find.widgetWithText(InkWell, metodo));
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

/// Las pantallas del cobro con el cliente HTTP REAL y un servidor falso con los ejemplos reales del backend. Cada
/// archivo de pruebas crea el suyo; [abrir] lo deja listo (y vuelve a crear el servidor y los almacenes) en cada prueba.
class BancoDeCobro {
  late ServidorFalso servidor;
  late AlmacenEnMemoria almacenCarrito;
  late AlmacenVentaEnMemoria almacenVenta;
  int llamadasAlGenerador = 0;

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
    RespuestaFalsa? clientesDelServidor,
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
    servidor.programar(
      'GET',
      '/api/clientes',
      clientesDelServidor ?? RespuestaFalsa.deEjemplo('16_V1_clientes'),
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
                ? claveDeCobro
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

  void programarVentaOk() => servidor.programar(
    'POST',
    rutaDeCobro,
    RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
  );

  void programarSinRed() => servidor.programar(
    'POST',
    rutaDeCobro,
    const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
  );
}
