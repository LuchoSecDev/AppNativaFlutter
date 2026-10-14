import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/actualizacion/actualizacion_models.dart';
import 'package:stockpilot/actualizacion/actualizacion_providers.dart';
import 'package:stockpilot/actualizacion/estado_de_version.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/auth/session_state.dart';

import '../support/fake_adapter.dart';

/// El estado de las actualizaciones con el cliente HTTP REAL, un servidor falso con los ejemplos del backend, una versión
/// instalada que se fija en cada prueba y un «navegador» falso que solo anota qué enlace le pidieron abrir.
void main() {
  late ServidorFalso servidor;
  late StreamController<void> caducidad;
  late List<Uri> abiertos;
  late Future<bool> Function(Uri) comoSeAbre;
  late int? instalada;
  late ProviderContainer contenedor;

  setUp(() {
    servidor = ServidorFalso();
    caducidad = StreamController<void>.broadcast();
    abiertos = [];
    comoSeAbre = (enlace) async {
      abiertos.add(enlace);
      return true;
    };
    instalada = 2;
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
        lectorDeVersionInstaladaProvider.overrideWithValue(
          () async => instalada == null
              ? null
              : VersionInstalada(codigo: instalada!, nombre: '1.0.$instalada'),
        ),
        abridorDeEnlacesProvider.overrideWithValue(
          (enlace) => comoSeAbre(enlace),
        ),
      ],
    );
    addTearDown(() {
      contenedor.dispose();
      caducidad.close();
    });
  });

  EstadoActualizacion estado() => contenedor.read(actualizacionProvider);
  ActualizacionNotifier notificador() =>
      contenedor.read(actualizacionProvider.notifier);

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

  /// Deja la sesión «activa» y mantiene vivo el estado de las actualizaciones (arranca la consulta).
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
    contenedor.listen(actualizacionProvider, (_, _) {});
  }

  /// Espera a que la consulta de versión termine (haya cambiado el estado o no).
  Future<void> hastaQueConsulte() async {
    await esperarQue(
      () => servidor.veces('GET', '/api/app/version'),
      (n) => n >= 1,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }

  void versionPublicada() => servidor.programar(
    'GET',
    '/api/app/version',
    RespuestaFalsa.deEjemplo('37_U1_version_disponible'),
  ); // última 3, mínima 2

  group('al consultar la versión [U1]', () {
    test('instalada menor que la mínima: obligatoria', () async {
      instalada = 1;
      versionPublicada();
      await conSesionActiva();
      await esperarQue(
        estado,
        (e) => e.nivel == NivelDeActualizacion.obligatoria,
      );
      expect(estado().publicada!.versionCode, 3);
    });

    test('instalada entre la mínima y la última: opcional', () async {
      instalada = 2;
      versionPublicada();
      await conSesionActiva();
      await esperarQue(estado, (e) => e.nivel == NivelDeActualizacion.opcional);
      expect(estado().avisoDescartado, isFalse);
    });

    test('instalada igual a la última: al día', () async {
      instalada = 3;
      versionPublicada();
      await conSesionActiva();
      await hastaQueConsulte();
      expect(estado().nivel, NivelDeActualizacion.alDia);
    });

    test('todavía no se publicó ninguna versión: al día', () async {
      servidor.programar(
        'GET',
        '/api/app/version',
        RespuestaFalsa.deEjemplo('36_U1_version_sin_configurar'),
      );
      await conSesionActiva();
      await hastaQueConsulte();
      expect(estado().nivel, NivelDeActualizacion.alDia);
      expect(estado().publicada, isNull);
    });

    test('sin saber la versión instalada ni siquiera consulta: no hay con qué comparar', () async {
      instalada = null;
      await conSesionActiva();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(servidor.veces('GET', '/api/app/version'), 0);
      expect(estado().nivel, NivelDeActualizacion.alDia);
    });

    test(
      'con el servidor caído (500) NO bloquea la app: queda al día',
      () async {
        instalada = 1; // aunque fuera una versión vieja, sin poder consultar no se bloquea
        servidor.programar(
          'GET',
          '/api/app/version',
          const RespuestaFalsa(500, {'error': 'x'}),
        );
        await conSesionActiva();
        await hastaQueConsulte();
        expect(estado().nivel, NivelDeActualizacion.alDia);
      },
    );

    test('sin conexión NO bloquea la app', () async {
      instalada = 1;
      servidor.programar(
        'GET',
        '/api/app/version',
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      await conSesionActiva();
      await hastaQueConsulte();
      expect(estado().nivel, NivelDeActualizacion.alDia);
    });

    test('sin sesión no consulta nada', () async {
      servidor.programar(
        'GET',
        '/api/session-info',
        const RespuestaFalsa(401, {'error': 'x'}),
      );
      contenedor.read(sesionProvider);
      contenedor.listen(actualizacionProvider, (_, _) {});
      await esperarQue(
        () => contenedor.read(sesionProvider),
        (e) => e.fase == FaseSesion.sinSesion,
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(servidor.veces('GET', '/api/app/version'), 0);
    });

    test('una respuesta que llega TARDE, cuando la sesión ya se perdió, no se muestra en la cuenta siguiente', () async {
      instalada = 1;
      final llega = Completer<void>();
      servidor.programar(
        'GET',
        '/api/app/version',
        RespuestaFalsa.demorada(
          200,
          RespuestaFalsa.deEjemplo('37_U1_version_disponible').cuerpo,
          llega.future,
        ),
      );
      await conSesionActiva();
      await esperarQue(
        () => servidor.veces('GET', '/api/app/version'),
        (n) => n >= 1,
      );
      caducidad.add(null); // el servidor dice «ya no hay sesión»
      await esperarQue(
        () => contenedor.read(sesionProvider),
        (e) => e.fase == FaseSesion.sinSesion,
      );
      llega.complete();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(estado().nivel, NivelDeActualizacion.alDia);
      expect(estado().publicada, isNull);
    });
  });

  group('«Ahora no»', () {
    test(
      'descartar el aviso lo marca como descartado y no cambia el nivel',
      () async {
        versionPublicada();
        await conSesionActiva();
        await esperarQue(
          estado,
          (e) => e.nivel == NivelDeActualizacion.opcional,
        );
        notificador().descartarAviso();
        expect(estado().avisoDescartado, isTrue);
        expect(estado().nivel, NivelDeActualizacion.opcional);
      },
    );
  });

  group('descargar [U2]', () {
    Future<void> conActualizacionOpcional() async {
      versionPublicada();
      await conSesionActiva();
      await esperarQue(estado, (e) => e.nivel == NivelDeActualizacion.opcional);
    }

    test(
      'abre en el navegador la dirección https que dio el servidor',
      () async {
        await conActualizacionOpcional();
        servidor.programar(
          'GET',
          '/api/app/descarga',
          RespuestaFalsa.deEjemplo('39_U2_descarga_ok'),
        );
        await notificador().descargar();
        expect(abiertos, [
          Uri.parse('https://descargas.ejemplo.test/stockpilot-1.0.2.apk'),
        ]);
        expect(estado().abriendo, isFalse);
        expect(estado().mensaje, isNull);
      },
    );

    test(
      'un segundo toque mientras se espera no pide la descarga otra vez',
      () async {
        await conActualizacionOpcional();
        final llega = Completer<void>();
        servidor.programar(
          'GET',
          '/api/app/descarga',
          RespuestaFalsa.demorada(
            200,
            RespuestaFalsa.deEjemplo('39_U2_descarga_ok').cuerpo,
            llega.future,
          ),
        );
        final primero = notificador().descargar();
        await esperarQue(estado, (e) => e.abriendo);
        await notificador().descargar(); // segundo toque
        llega.complete();
        await primero;
        expect(servidor.veces('GET', '/api/app/descarga'), 1);
        expect(abiertos, hasLength(1));
      },
    );

    test(
      'todavía no hay descarga (404): un mensaje, no se abre nada',
      () async {
        await conActualizacionOpcional();
        servidor.programar(
          'GET',
          '/api/app/descarga',
          const RespuestaFalsa(404, {'success': false, 'error': 'x'}),
        );
        await notificador().descargar();
        expect(abiertos, isEmpty);
        expect(estado().mensaje, contains('Todavía no hay una versión'));
        expect(estado().abriendo, isFalse);
      },
    );

    test(
      'con el servidor caído: un mensaje para el usuario, no se abre nada',
      () async {
        await conActualizacionOpcional();
        servidor.programar(
          'GET',
          '/api/app/descarga',
          const RespuestaFalsa(500, {'error': 'x'}),
        );
        await notificador().descargar();
        expect(abiertos, isEmpty);
        expect(estado().mensaje, isNotNull);
        expect(estado().abriendo, isFalse);
      },
    );

    test('si el celular no pudo abrir el enlace, se avisa', () async {
      await conActualizacionOpcional();
      comoSeAbre = (_) async => false;
      servidor.programar(
        'GET',
        '/api/app/descarga',
        RespuestaFalsa.deEjemplo('39_U2_descarga_ok'),
      );
      await notificador().descargar();
      expect(estado().mensaje, contains('No se pudo abrir la descarga'));
      expect(estado().abriendo, isFalse);
    });

    test(
      'si abrir el enlace lanza una excepción, tampoco se cae: se avisa',
      () async {
        await conActualizacionOpcional();
        comoSeAbre = (_) async => throw StateError('sin navegador');
        servidor.programar(
          'GET',
          '/api/app/descarga',
          RespuestaFalsa.deEjemplo('39_U2_descarga_ok'),
        );
        await notificador().descargar();
        expect(estado().mensaje, contains('No se pudo abrir la descarga'));
        expect(estado().abriendo, isFalse);
      },
    );

    test('un intento nuevo borra el mensaje del anterior', () async {
      await conActualizacionOpcional();
      servidor.programar(
        'GET',
        '/api/app/descarga',
        const RespuestaFalsa(500, {'error': 'x'}),
      );
      servidor.programar(
        'GET',
        '/api/app/descarga',
        RespuestaFalsa.deEjemplo('39_U2_descarga_ok'),
      );
      await notificador().descargar();
      expect(estado().mensaje, isNotNull);
      await notificador().descargar();
      expect(estado().mensaje, isNull);
      expect(abiertos, hasLength(1));
    });
  });
}
