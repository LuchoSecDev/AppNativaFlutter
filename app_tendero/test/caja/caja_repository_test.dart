import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/api/errores_de_api.dart';
import 'package:stockpilot/caja/caja_models.dart';
import 'package:stockpilot/caja/caja_repository.dart';

import '../support/fake_adapter.dart';

/// Pruebas de la capa que habla con la API de la caja ([K1] y [K2]), con los ejemplos reales del backend.
void main() {
  late ServidorFalso servidor;
  late CajaRepository repo;

  setUp(() {
    servidor = ServidorFalso();
    repo = CajaRepository(
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

  group('consultarSesion [K1]', () {
    test('sin caja abierta devuelve null', () async {
      servidor.programar(
        'GET',
        '/api/caja/sesion',
        RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'),
      );
      expect(await repo.consultarSesion(), isNull);
    });

    test(
      'con caja abierta devuelve la sesión; el monto sigue siendo TEXTO',
      () async {
        servidor.programar(
          'GET',
          '/api/caja/sesion',
          RespuestaFalsa.deEjemplo('10_K1_caja_abierta'),
        );
        final sesion = await repo.consultarSesion();
        expect(sesion!.idSesion, 1);
        expect(sesion.montoApertura, '50000.00');
        expect(sesion.montoApertura, isA<String>());
        expect(sesion.fechaApertura, isNotEmpty);
      },
    );

    test('con el servidor caído (500) lanza ErrorDeApi', () async {
      servidor.programar(
        'GET',
        '/api/caja/sesion',
        const RespuestaFalsa(500, {'error': 'x'}),
      );
      await expectLater(repo.consultarSesion(), throwsA(isA<ErrorDeApi>()));
    });

    test(
      'sin conexión lanza ErrorDeApi con un mensaje para el usuario',
      () async {
        servidor.programar(
          'GET',
          '/api/caja/sesion',
          const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
        );
        await expectLater(
          repo.consultarSesion(),
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

    test('una respuesta con forma rara lanza ErrorDeApi, no un error de programación', () async {
      servidor.programar(
        'GET',
        '/api/caja/sesion',
        const RespuestaFalsa(200, {'active': true}),
      );
      await expectLater(repo.consultarSesion(), throwsA(isA<ErrorDeApi>()));
    });
  });

  group('abrir [K2]', () {
    test(
      'éxito: CajaAbierta; envía el monto como NÚMERO y con el token CSRF',
      () async {
        servidor.programar(
          'POST',
          '/api/caja/abrir',
          RespuestaFalsa.deEjemplo('09_K2_abrir_caja'),
        );
        expect(await repo.abrir(50000), isA<CajaAbierta>());
        final p = servidor.peticiones.last;
        expect(p.cuerpo, {'monto_apertura': 50000});
        expect(p.cuerpo['monto_apertura'], isA<int>());
        expect(p.headers['X-CSRF-Token'], isNotEmpty);
      },
    );

    test('el 0 es un monto válido y se envía tal cual', () async {
      servidor.programar(
        'POST',
        '/api/caja/abrir',
        RespuestaFalsa.deEjemplo('09_K2_abrir_caja'),
      );
      await repo.abrir(0);
      expect(servidor.peticiones.last.cuerpo, {'monto_apertura': 0});
    });

    test('«Ya tienes una sesión de caja abierta» (400): CajaRechazada con yaEstabaAbierta', () async {
      servidor.programar(
        'POST',
        '/api/caja/abrir',
        const RespuestaFalsa(400, {
          'error': 'Ya tienes una sesión de caja abierta.',
        }),
      );
      final r = await repo.abrir(1000);
      expect(r, isA<CajaRechazada>());
      expect((r as CajaRechazada).yaEstabaAbierta, isTrue);
    });

    test('monto no válido (400): CajaRechazada con el mensaje, sin yaEstabaAbierta', () async {
      servidor.programar(
        'POST',
        '/api/caja/abrir',
        const RespuestaFalsa(400, {
          'error': 'El monto de apertura no es válido.',
        }),
      );
      final r = await repo.abrir(1000) as CajaRechazada;
      expect(r.mensaje, 'El monto de apertura no es válido.');
      expect(r.yaEstabaAbierta, isFalse);
    });

    test(
      'sin conexión lanza ErrorDeApi (NO se sabe si el servidor la abrió)',
      () async {
        servidor.programar(
          'POST',
          '/api/caja/abrir',
          const RespuestaFalsa.falloDeRed(DioExceptionType.receiveTimeout),
        );
        await expectLater(repo.abrir(1000), throwsA(isA<ErrorDeApi>()));
      },
    );
  });
}
