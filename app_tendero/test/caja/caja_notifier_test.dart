import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/auth/session_state.dart';
import 'package:stockpilot/caja/caja_providers.dart';

import '../support/fake_adapter.dart';

/// Pruebas del estado de la caja con el cliente HTTP REAL y un servidor falso con los ejemplos del backend.
void main() {
  late ServidorFalso servidor;
  late StreamController<void> caducidad;
  late ProviderContainer contenedor;

  setUp(() {
    servidor = ServidorFalso();
    caducidad = StreamController<void>.broadcast();
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
    final dio = crearClienteApi(
      baseUrl: 'https://servidor.test',
      cookieJar: CookieJar(),
      adapter: servidor,
      onSessionExpired: () => caducidad.add(null),
    );
    contenedor = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(dio),
        sesionCaducadaProvider.overrideWithValue(caducidad.stream),
      ],
    );
    addTearDown(() {
      contenedor.dispose();
      caducidad.close();
    });
  });

  CajaNotifier caja() => contenedor.read(cajaProvider.notifier);
  EstadoCaja estado() => contenedor.read(cajaProvider);

  Future<T> esperarQue<T>(T Function() leer, bool Function(T) condicion) async {
    for (var i = 0; i < 200; i++) {
      final actual = leer();
      if (condicion(actual)) return actual;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw TimeoutException(
      'La condición nunca se cumplió; el estado quedó en ${leer()}',
    );
  }

  /// Deja la sesión «activa» (como si el usuario ya hubiera entrado) y espera a que la caja termine de cargar.
  Future<void> conSesionActiva() async {
    servidor.programar(
      'GET',
      '/api/session-info',
      RespuestaFalsa.deEjemplo('05_S4_session_info'),
    );
    contenedor.read(sesionProvider);
    await esperarQue(
      () => contenedor.read(sesionProvider),
      (e) => e.fase == FaseSesion.activa,
    );
  }

  Future<void> hastaQueCargue() async {
    contenedor.listen(
      cajaProvider,
      (_, _) {},
    ); // mantiene vivo el estado de la caja
    await esperarQue(
      estado,
      (e) => e.fase != FaseCaja.cargando && !e.trabajando,
    );
  }

  group('al iniciar', () {
    test('sin sesión no consulta la caja', () async {
      servidor.programar(
        'GET',
        '/api/session-info',
        const RespuestaFalsa(401, {'error': 'x'}),
      );
      contenedor.read(cajaProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(servidor.veces('GET', '/api/caja/sesion'), 0);
    });

    test(
      'con sesión y sin caja abierta: «cerrada» y NO se puede vender',
      () async {
        servidor.programar(
          'GET',
          '/api/caja/sesion',
          RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'),
        );
        await conSesionActiva();
        await hastaQueCargue();
        expect(estado().fase, FaseCaja.cerrada);
        expect(contenedor.read(puedeVenderProvider), isFalse);
      },
    );

    test(
      'con la caja ya abierta: «abierta», con su sesión, y SÍ se puede vender',
      () async {
        servidor.programar(
          'GET',
          '/api/caja/sesion',
          RespuestaFalsa.deEjemplo('10_K1_caja_abierta'),
        );
        await conSesionActiva();
        await hastaQueCargue();
        expect(estado().fase, FaseCaja.abierta);
        expect(estado().sesion!.idSesion, 1);
        expect(contenedor.read(puedeVenderProvider), isTrue);
      },
    );

    test('si no se puede consultar: «error» con un mensaje, y «cargar» permite reintentar', () async {
      servidor.programar(
        'GET',
        '/api/caja/sesion',
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      servidor.programar(
        'GET',
        '/api/caja/sesion',
        RespuestaFalsa.deEjemplo('10_K1_caja_abierta'),
      );
      await conSesionActiva();
      await hastaQueCargue();
      expect(estado().fase, FaseCaja.error);
      expect(estado().mensaje, contains('conexión'));
      expect(contenedor.read(puedeVenderProvider), isFalse);

      await caja().cargar();
      expect(estado().fase, FaseCaja.abierta);
    });
  });

  group('abrir la caja', () {
    Future<void> conCajaCerrada() async {
      servidor.programar(
        'GET',
        '/api/caja/sesion',
        RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'),
      );
      await conSesionActiva();
      await hastaQueCargue();
    }

    test(
      'éxito: envía el monto, vuelve a consultar al servidor y queda «abierta»',
      () async {
        await conCajaCerrada();
        servidor.programar(
          'POST',
          '/api/caja/abrir',
          RespuestaFalsa.deEjemplo('09_K2_abrir_caja'),
        );
        servidor.programar(
          'GET',
          '/api/caja/sesion',
          RespuestaFalsa.deEjemplo('10_K1_caja_abierta'),
        );
        await caja().abrir(50000);
        expect(estado().fase, FaseCaja.abierta);
        expect(
          estado().sesion!.montoApertura,
          '50000.00',
        ); // lo que guardó el servidor
        expect(
          servidor.peticiones
              .where((p) => p.clave == 'POST /api/caja/abrir')
              .single
              .cuerpo,
          {'monto_apertura': 50000},
        );
      },
    );

    test(
      'monto rechazado por el servidor: sigue «cerrada» con su mensaje',
      () async {
        await conCajaCerrada();
        servidor.programar(
          'POST',
          '/api/caja/abrir',
          const RespuestaFalsa(400, {
            'error': 'El monto de apertura no es válido.',
          }),
        );
        await caja().abrir(1);
        expect(estado().fase, FaseCaja.cerrada);
        expect(estado().mensaje, 'El monto de apertura no es válido.');
        expect(estado().trabajando, isFalse);
      },
    );

    test('«ya tenías una caja abierta» (p. ej. abierta desde la web): muestra esa caja con un aviso', () async {
      await conCajaCerrada();
      servidor.programar(
        'POST',
        '/api/caja/abrir',
        const RespuestaFalsa(400, {
          'error': 'Ya tienes una sesión de caja abierta.',
        }),
      );
      servidor.programar(
        'GET',
        '/api/caja/sesion',
        RespuestaFalsa.deEjemplo('10_K1_caja_abierta'),
      );
      await caja().abrir(1000);
      expect(estado().fase, FaseCaja.abierta);
      expect(estado().mensaje, contains('Ya tenías una caja abierta'));
    });

    test('se perdió la respuesta pero el servidor SÍ la abrió: se consulta y queda «abierta», sin reintentar el POST', () async {
      await conCajaCerrada();
      servidor.programar(
        'POST',
        '/api/caja/abrir',
        const RespuestaFalsa.falloDeRed(DioExceptionType.receiveTimeout),
      );
      servidor.programar(
        'GET',
        '/api/caja/sesion',
        RespuestaFalsa.deEjemplo('10_K1_caja_abierta'),
      );
      await caja().abrir(50000);
      expect(estado().fase, FaseCaja.abierta);
      expect(
        servidor.veces('POST', '/api/caja/abrir'),
        1,
      ); // no se reintentó a ciegas
    });

    test(
      'falló y la caja NO se abrió: sigue «cerrada» con el mensaje de la falla',
      () async {
        await conCajaCerrada();
        servidor.programar(
          'POST',
          '/api/caja/abrir',
          const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
        );
        servidor.programar(
          'GET',
          '/api/caja/sesion',
          RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'),
        );
        await caja().abrir(50000);
        expect(estado().fase, FaseCaja.cerrada);
        expect(estado().mensaje, contains('conexión'));
      },
    );

    test('un segundo toque mientras espera NO envía otra apertura', () async {
      await conCajaCerrada();
      servidor.programar(
        'POST',
        '/api/caja/abrir',
        RespuestaFalsa.deEjemplo('09_K2_abrir_caja'),
      );
      servidor.programar(
        'GET',
        '/api/caja/sesion',
        RespuestaFalsa.deEjemplo('10_K1_caja_abierta'),
      );
      await Future.wait([caja().abrir(50000), caja().abrir(50000)]);
      expect(servidor.veces('POST', '/api/caja/abrir'), 1);
    });

    test('abrir cuando ya está abierta no hace nada', () async {
      servidor.programar(
        'GET',
        '/api/caja/sesion',
        RespuestaFalsa.deEjemplo('10_K1_caja_abierta'),
      );
      await conSesionActiva();
      await hastaQueCargue();
      await caja().abrir(1000);
      expect(servidor.veces('POST', '/api/caja/abrir'), 0);
    });
  });

  group('cambio de cuenta', () {
    test('al cerrar sesión la caja se reinicia: no queda a la vista la de la cuenta anterior', () async {
      servidor.programar(
        'GET',
        '/api/caja/sesion',
        RespuestaFalsa.deEjemplo('10_K1_caja_abierta'),
      );
      await conSesionActiva();
      await hastaQueCargue();
      expect(estado().fase, FaseCaja.abierta);

      servidor.programar(
        'POST',
        '/api/logout',
        RespuestaFalsa.deEjemplo('28_S5_logout'),
      );
      await contenedor.read(sesionProvider.notifier).cerrarSesion();
      await esperarQue(estado, (e) => e.fase == FaseCaja.cargando);
      expect(contenedor.read(puedeVenderProvider), isFalse);
      expect(estado().sesion, isNull);
    });

    test('una respuesta TARDÍA de la sesión anterior se descarta y no aparece en la cuenta nueva', () async {
      final llega = Completer<void>();
      servidor.programar(
        'GET',
        '/api/session-info',
        RespuestaFalsa.deEjemplo('05_S4_session_info'),
      );
      // La consulta de la caja de la cuenta A queda en el aire...
      servidor.programar(
        'GET',
        '/api/caja/sesion',
        RespuestaFalsa.demorada(200, const {
          'active': true,
          'session': {
            'id_sesion': 99,
            'monto_apertura': '1.00',
            'fecha_apertura': '2026-10-04T15:30:00.000Z',
            'estado': 'Abierta',
          },
        }, llega.future),
      );
      contenedor.read(sesionProvider);
      contenedor.listen(cajaProvider, (_, _) {});
      await esperarQue(
        () => contenedor.read(sesionProvider),
        (e) => e.fase == FaseSesion.activa,
      );
      await esperarQue(
        () => servidor.veces('GET', '/api/caja/sesion'),
        (n) => n == 1,
      );

      // ...la cuenta A cierra sesión mientras tanto...
      servidor.programar(
        'POST',
        '/api/logout',
        RespuestaFalsa.deEjemplo('28_S5_logout'),
      );
      await contenedor.read(sesionProvider.notifier).cerrarSesion();
      expect(contenedor.read(sesionProvider).fase, FaseSesion.sinSesion);

      // ...y la respuesta de A llega TARDE.
      llega.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(estado().fase, isNot(FaseCaja.abierta));
      expect(estado().sesion, isNull);
      expect(contenedor.read(puedeVenderProvider), isFalse);
    });
  });
}
