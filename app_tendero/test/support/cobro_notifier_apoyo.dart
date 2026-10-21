import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/auth/session_state.dart';
import 'package:stockpilot/caja/caja_models.dart';
import 'package:stockpilot/caja/caja_providers.dart';
import 'package:stockpilot/carrito/carrito_models.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/catalogo/catalogo_providers.dart';
import 'package:stockpilot/venta/venta_models.dart';
import 'package:stockpilot/venta/venta_providers.dart';
import 'package:stockpilot/venta/venta_repository.dart';

import 'carrito_apoyo.dart';
import 'fake_adapter.dart';

/// La clave de idempotencia que el generador falso entrega a la PRIMERA venta de cada prueba.
const claveDeVenta = '4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22';

/// La ruta del cobro (`[V2]`).
const rutaDeVenta = '/api/registrar-venta-carrito';

/// Dónde se guarda la venta pendiente de la persona de la sesión de prueba (usuario 2, tienda 1).
const claveDelAlmacenDeVenta = 'venta_pendiente_v1_2_1';

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

class _CajaCerradaFija extends CajaNotifier {
  @override
  EstadoCaja build() => const EstadoCaja.cerrada();
}

/// Un repositorio que revienta: simula un error de programación dentro del cobro.
class RepositorioRoto extends VentaRepository {
  RepositorioRoto() : super(Dio());

  @override
  Future<ResultadoVenta> registrar(VentaPendiente venta) =>
      throw StateError('error de programación simulado');
}

/// Entrega la clave esperada la primera vez y claves distintas después.
String Function() generadorDeUnaSolaClave() {
  var llamadas = 0;
  return () => llamadas++ == 0 ? claveDeVenta : 'otra-clave-$llamadas';
}

final arroz = producto(1, 'Arroz Diana 1Kg', precio: '4500.00', cantidad: 10);
final aceite = producto(
  2,
  'Aceite Gourmet 1L',
  precio: '12000.00',
  cantidad: 5,
);

Future<T> esperarQue<T>(T Function() leer, bool Function(T) condicion) async {
  for (var i = 0; i < 400; i++) {
    final actual = leer();
    if (condicion(actual)) {
      return actual;
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  throw TimeoutException('La condición nunca se cumplió: ${leer()}');
}

/// El cobro con el cliente HTTP REAL y un servidor falso con los ejemplos reales del backend. Cada archivo de pruebas
/// crea el suyo; [armar] lo deja listo en cada prueba.
class BancoDelNotificador {
  late ServidorFalso servidor;
  late StreamController<void> caducidad;
  late AlmacenEnMemoria almacenCarrito;
  late AlmacenVentaEnMemoria almacenVenta;
  late List<Duration> pausas;
  late ProviderContainer c;
  late SesionFija sesion;

  EstadoCobro cobro() => c.read(cobroProvider);
  CobroNotifier notificador() => c.read(cobroProvider.notifier);
  List<PeticionRegistrada> envios() =>
      servidor.peticiones.where((p) => p.clave == 'POST $rutaDeVenta').toList();

  /// Arma el entorno. [cajaAbierta] decide si hay caja abierta; [esperas] los reintentos automáticos.
  Future<void> armar({
    EstadoSesion? sesionInicial,
    bool cajaAbierta = true,
    List<Duration>? esperas,
    List<Override> extra = const [],
    AlmacenVentaEnMemoria? almacenPrevio,
    List<LineaCarrito>? lineasGuardadas,
    String Function()? generador,
  }) async {
    servidor = ServidorFalso();
    caducidad = StreamController<void>.broadcast();
    almacenCarrito = AlmacenEnMemoria();
    if (lineasGuardadas != null) {
      almacenCarrito.datos['carrito_v1_2_1'] = lineasGuardadas;
    }
    almacenVenta = almacenPrevio ?? AlmacenVentaEnMemoria();
    pausas = [];
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
    servidor.programar(
      'GET',
      '/api/caja/sesion',
      RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'),
    );
    final dio = crearClienteApi(
      baseUrl: 'https://servidor.test',
      cookieJar: CookieJar(),
      adapter: servidor,
      onSessionExpired: () => caducidad.add(null),
    );
    sesion = SesionFija(sesionInicial ?? sesionActiva());
    c = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(dio),
        sesionCaducadaProvider.overrideWithValue(caducidad.stream),
        sesionProvider.overrideWith(() => sesion),
        catalogoProvider.overrideWith(
          () => CatalogoFijo(EstadoCatalogo.listo([arroz, aceite])),
        ),
        cajaProvider.overrideWith(
          () => cajaAbierta ? _CajaAbiertaFija() : _CajaCerradaFija(),
        ),
        almacenCarritoProvider.overrideWithValue(almacenCarrito),
        almacenVentaPendienteProvider.overrideWithValue(almacenVenta),
        // La primera clave es la esperada; si el código pidiera OTRA (por ejemplo, al reintentar), saldría distinta y
        // las pruebas que comparan la clave de cada envío lo detectarían.
        generadorDeClaveProvider.overrideWithValue(
          generador ?? generadorDeUnaSolaClave(),
        ),
        pausaDeReintentoProvider.overrideWithValue((d) async => pausas.add(d)),
        if (esperas != null)
          esperasDeReintentoProvider.overrideWithValue(esperas),
        ...extra,
      ],
    );
    addTearDown(() {
      c.dispose();
      caducidad.close();
    });
    c.listen(carritoProvider, (_, _) {});
    c.listen(cobroProvider, (_, _) {});
    await esperarQue(
      () => (c.read(carritoProvider).cargando, cobro().cargando),
      (e) => !e.$1 && !e.$2,
    );
  }

  /// Carrito con 2 arroces ($9.000), como en el ejemplo 17 del backend.
  void llenarCarrito() {
    c.read(carritoProvider.notifier).agregar(arroz);
    c.read(carritoProvider.notifier).agregar(arroz);
  }
}
