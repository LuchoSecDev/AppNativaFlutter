import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/auth/session_state.dart';
import 'package:stockpilot/caja/caja_models.dart';
import 'package:stockpilot/caja/caja_providers.dart';
import 'package:stockpilot/egresos/almacen_egreso.dart';
import 'package:stockpilot/egresos/egreso_borrador.dart';
import 'package:stockpilot/egresos/egreso_models.dart';
import 'package:stockpilot/egresos/egreso_providers.dart';
import 'package:stockpilot/egresos/egreso_repository.dart';
import 'package:stockpilot/venta/venta_providers.dart';

import 'carrito_apoyo.dart';
import 'fake_adapter.dart';

/// La clave que se le entrega al primer egreso (y `otra-clave-N` a los siguientes), para comprobar cuál se envía.
const claveDeEgreso = '4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22';

/// Un almacén de egresos pendientes en memoria, con un gancho para simular fallas del disco.
class AlmacenEgresoEnMemoria implements AlmacenEgresoPendiente {
  final Map<String, EgresoPendiente> datos = {};

  /// Si es `true`, leer, guardar y borrar fallan (disco lleno, permisos...).
  bool fallar = false;

  @override
  Future<EgresoPendiente?> leer(String clave) async {
    if (fallar) throw Exception('fallo de lectura simulado');
    return datos[clave];
  }

  @override
  Future<void> guardar(String clave, EgresoPendiente egreso) async {
    if (fallar) throw Exception('fallo de escritura simulado');
    datos[clave] = egreso;
  }

  @override
  Future<void> borrar(String clave) async {
    if (fallar) throw Exception('fallo de borrado simulado');
    datos.remove(clave);
  }
}

/// Una caja ABIERTA fija: lo que se ve no depende del servidor, pero `cargar()` (que se pide tras un rechazo) sí le
/// pregunta, y por eso el entorno programa `GET /api/caja/sesion`.
class CajaAbiertaFija extends CajaNotifier {
  @override
  EstadoCaja build() => const EstadoCaja.abierta(
    SesionCaja(
      idSesion: 1,
      montoApertura: '50000.00',
      fechaApertura: '2026-10-04T15:30:00.000Z',
    ),
  );
}

class CajaCerradaFija extends CajaNotifier {
  @override
  EstadoCaja build() => const EstadoCaja.cerrada();
}

/// Un repositorio que revienta: simula un error de programación dentro del registro.
class RepositorioDeEgresoRoto extends EgresoRepository {
  RepositorioDeEgresoRoto() : super(Dio());

  @override
  Future<ResultadoEgreso> registrar(EgresoPendiente egreso) =>
      throw StateError('error de programación simulado');
}

/// Todo lo que necesitan las pruebas de egresos: un servidor falso con los ejemplos reales, el cliente HTTP REAL, un
/// almacén en memoria y los ganchos de reintento. Se usa igual en las pruebas del estado y en las de pantalla.
class EntornoDeEgresos {
  EntornoDeEgresos({
    this.cajaAbierta = true,
    EstadoSesion? sesionInicial,
    this.esperas = const [],
    this.repositorioRoto = false,
  }) : sesion = SesionFija(sesionInicial ?? sesionActiva()) {
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
    servidor.programar(
      'GET',
      '/api/caja/sesion',
      RespuestaFalsa.deEjemplo('10_K1_caja_abierta'),
    );
  }

  final ServidorFalso servidor = ServidorFalso();
  final AlmacenEgresoEnMemoria almacen = AlmacenEgresoEnMemoria();
  final SesionFija sesion;
  final bool cajaAbierta;
  final List<Duration> esperas;
  final bool repositorioRoto;

  /// Las pausas que el reintento automático pidió (sin esperar de verdad).
  final List<Duration> pausas = [];
  var _llamadasAlGenerador = 0;

  static const ruta = '/api/caja/egreso';

  List<PeticionRegistrada> envios() =>
      servidor.peticiones.where((p) => p.clave == 'POST $ruta').toList();

  List<Override> overrides() => [
    dioProvider.overrideWithValue(
      crearClienteApi(
        baseUrl: 'https://servidor.test',
        cookieJar: CookieJar(),
        adapter: servidor,
      ),
    ),
    sesionProvider.overrideWith(() => sesion),
    cajaProvider.overrideWith(
      () => cajaAbierta ? CajaAbiertaFija() : CajaCerradaFija(),
    ),
    almacenEgresoPendienteProvider.overrideWithValue(almacen),
    generadorDeClaveProvider.overrideWithValue(() {
      _llamadasAlGenerador++;
      return _llamadasAlGenerador == 1
          ? claveDeEgreso
          : 'otra-clave-$_llamadasAlGenerador';
    }),
    esperasDeReintentoProvider.overrideWithValue(esperas),
    pausaDeReintentoProvider.overrideWithValue((d) async => pausas.add(d)),
    if (repositorioRoto)
      egresoRepositoryProvider.overrideWithValue(RepositorioDeEgresoRoto()),
  ];

  /// Un contenedor ya «caliente»: la sesión leída y el estado de egresos listo (sin «cargando»).
  Future<ProviderContainer> contenedor() async {
    final c = ProviderContainer(overrides: overrides());
    c.read(sesionProvider);
    c.listen(egresoProvider, (_, _) {});
    c.listen(borradorDeEgresoProvider, (_, _) {});
    for (var i = 0; i < 400 && c.read(egresoProvider).cargando; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    return c;
  }
}
