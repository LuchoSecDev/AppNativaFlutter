import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/actualizacion/actualizacion_repository.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/api/errores_de_api.dart';

import '../support/fake_adapter.dart';

/// La capa que habla con `[U1]` y `[U2]`, con los ejemplos reales del backend.
void main() {
  late ServidorFalso servidor;
  late ActualizacionRepository repo;

  setUp(() {
    servidor = ServidorFalso();
    repo = ActualizacionRepository(
      crearClienteApi(
        baseUrl: 'https://servidor.test',
        cookieJar: CookieJar(),
        adapter: servidor,
      ),
    );
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
  });

  group('consultarVersion [U1]', () {
    test('devuelve la versión publicada y pide GET /api/app/version', () async {
      servidor.programar(
        'GET',
        '/api/app/version',
        RespuestaFalsa.deEjemplo('37_U1_version_disponible'),
      );
      final v = await repo.consultarVersion();
      expect(v!.versionCode, 3);
      expect(v.minVersionCode, 2);
      expect(servidor.veces('GET', '/api/app/version'), 1);
    });

    test('«disponible: false» devuelve null', () async {
      servidor.programar(
        'GET',
        '/api/app/version',
        RespuestaFalsa.deEjemplo('36_U1_version_sin_configurar'),
      );
      expect(await repo.consultarVersion(), isNull);
    });

    test(
      'una respuesta que no se entiende devuelve null (no inventa una versión)',
      () async {
        servidor.programar(
          'GET',
          '/api/app/version',
          const RespuestaFalsa(200, {'disponible': true, 'versionCode': 'x'}),
        );
        expect(await repo.consultarVersion(), isNull);
      },
    );

    test('con el servidor caído (500) lanza ErrorDeApi', () async {
      servidor.programar(
        'GET',
        '/api/app/version',
        const RespuestaFalsa(500, {'error': 'x'}),
      );
      await expectLater(repo.consultarVersion(), throwsA(isA<ErrorDeApi>()));
    });

    test(
      'sin conexión lanza ErrorDeApi con un mensaje para el usuario',
      () async {
        servidor.programar(
          'GET',
          '/api/app/version',
          const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
        );
        await expectLater(
          repo.consultarVersion(),
          throwsA(
            isA<ErrorDeApi>().having(
              (e) => e.mensaje,
              'mensaje',
              contains('conexión'),
            ),
          ),
        );
      },
    );
  });

  group('pedirDescarga [U2]', () {
    test('devuelve la descarga y pide GET /api/app/descarga', () async {
      servidor.programar(
        'GET',
        '/api/app/descarga',
        RespuestaFalsa.deEjemplo('39_U2_descarga_ok'),
      );
      final r = await repo.pedirDescarga();
      expect(r, isA<DescargaLista>());
      final d = (r as DescargaLista).descarga;
      expect(d.enlace.scheme, 'https');
      expect(d.sha256, hasLength(64));
      expect(servidor.veces('GET', '/api/app/descarga'), 1);
    });

    test('404 (no hay descarga configurada) es esperable: se devuelve, no se lanza', () async {
      servidor.programar(
        'GET',
        '/api/app/descarga',
        const RespuestaFalsa(404, {
          'success': false,
          'error': 'No hay una versión disponible para descargar.',
        }),
      );
      expect(await repo.pedirDescarga(), isA<DescargaNoDisponible>());
    });

    test(
      'sin sesión (401) lanza ErrorDeApi: la dirección no es pública',
      () async {
        servidor.programar(
          'GET',
          '/api/app/descarga',
          RespuestaFalsa.deEjemplo('38_U2_descarga_sin_sesion_401'),
        );
        await expectLater(repo.pedirDescarga(), throwsA(isA<ErrorDeApi>()));
      },
    );

    test(
      'una dirección que no es https NUNCA se entrega: respuesta inesperada',
      () async {
        servidor.programar(
          'GET',
          '/api/app/descarga',
          RespuestaFalsa(200, {
            'versionCode': 3,
            'versionName': '1.0.2',
            'url': 'http://descargas.ejemplo.test/a.apk',
            'sha256': 'a' * 64,
          }),
        );
        await expectLater(
          repo.pedirDescarga(),
          throwsA(
            isA<ErrorDeApi>().having(
              (e) => e.mensaje,
              'mensaje',
              respuestaInesperada,
            ),
          ),
        );
      },
    );

    test('una descarga sin huella válida tampoco se entrega', () async {
      servidor.programar(
        'GET',
        '/api/app/descarga',
        RespuestaFalsa(200, {
          'versionCode': 3,
          'url': 'https://descargas.ejemplo.test/a.apk',
          'sha256': 'no-es-una-huella',
        }),
      );
      await expectLater(repo.pedirDescarga(), throwsA(isA<ErrorDeApi>()));
    });

    test('con el servidor caído (500) lanza ErrorDeApi', () async {
      servidor.programar(
        'GET',
        '/api/app/descarga',
        const RespuestaFalsa(500, {'error': 'x'}),
      );
      await expectLater(repo.pedirDescarga(), throwsA(isA<ErrorDeApi>()));
    });
  });
}
