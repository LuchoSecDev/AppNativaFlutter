import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';

import '../support/fake_adapter.dart';

/// Pruebas de las reglas de sesión del contrato (docs del backend, secciones 1 y 2 y [S6]).
/// Corren sin servidor: las respuestas salen de los ejemplos reales de `test/fixtures/api`.
void main() {
  late ServidorFalso servidor;
  late Dio dio;
  late int vecesQueCaduco;

  setUp(() {
    servidor = ServidorFalso();
    vecesQueCaduco = 0;
    dio = crearClienteApi(
      baseUrl: 'https://servidor.test',
      cookieJar: CookieJar(), // en memoria: en la app real es el persistente
      adapter: servidor,
      onSessionExpired: () => vecesQueCaduco++,
    );
    servidor.programar('GET', '/api/csrf-token', RespuestaFalsa.deEjemplo('04_S1_csrf_token'));
  });

  Future<Response<dynamic>> abrirCaja() => dio.post<dynamic>('/api/caja/abrir', data: {'monto_apertura': 50000});

  group('Cabeceras y configuración', () {
    test('toda petición lleva Accept: application/json y X-Canal: app', () async {
      servidor.programar('GET', '/api/caja/sesion', RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'));
      await dio.get<dynamic>('/api/caja/sesion');
      final p = servidor.peticiones.single;
      expect(p.headers['Accept'], 'application/json');
      expect(p.headers['X-Canal'], 'app');
    });

    test('la espera máxima es de al menos 60 s (el servidor gratuito tarda ~1 min en despertar)', () {
      expect(dio.options.connectTimeout!.inSeconds, greaterThanOrEqualTo(60));
      expect(dio.options.receiveTimeout!.inSeconds, greaterThanOrEqualTo(60));
    });
  });

  group('Token CSRF', () {
    test('una lectura (GET) NO pide ni lleva token', () async {
      servidor.programar('GET', '/api/caja/sesion', RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'));
      await dio.get<dynamic>('/api/caja/sesion');
      expect(servidor.veces('GET', '/api/csrf-token'), 0);
      expect(servidor.peticiones.single.headers.containsKey('X-CSRF-Token'), isFalse);
    });

    test('una escritura pide el token primero y lo envía en X-CSRF-Token', () async {
      servidor.programar('POST', '/api/caja/abrir', RespuestaFalsa.deEjemplo('09_K2_abrir_caja'));
      final r = await abrirCaja();
      expect(r.statusCode, 200);
      expect(servidor.peticiones.map((p) => p.clave), ['GET /api/csrf-token', 'POST /api/caja/abrir']);
      expect(servidor.peticiones.last.headers['X-CSRF-Token'], isNotEmpty);
    });

    test('el token se reutiliza: dos escrituras seguidas piden el token UNA vez', () async {
      servidor.programar('POST', '/api/caja/abrir', RespuestaFalsa.deEjemplo('09_K2_abrir_caja'));
      await abrirCaja();
      await abrirCaja();
      expect(servidor.veces('GET', '/api/csrf-token'), 1);
    });

    test('dos escrituras simultáneas sin token también lo piden UNA sola vez', () async {
      servidor.programar('POST', '/api/caja/abrir', RespuestaFalsa.deEjemplo('09_K2_abrir_caja'));
      await Future.wait([abrirCaja(), abrirCaja()]);
      expect(servidor.veces('GET', '/api/csrf-token'), 1);
      expect(servidor.veces('POST', '/api/caja/abrir'), 2);
    });

    test('el login NO lleva token ni lo pide antes (el login regenera la sesión)', () async {
      servidor.programar('POST', '/api/login', RespuestaFalsa.deEjemplo('02_S2_login_ok'));
      await dio.post<dynamic>('/api/login', data: {'login': 'x', 'password': 'y'});
      expect(servidor.veces('GET', '/api/csrf-token'), 0);
      expect(servidor.peticiones.single.headers.containsKey('X-CSRF-Token'), isFalse);
    });

    test('tras un login exitoso se descarta el token y se pide uno nuevo en la siguiente escritura', () async {
      servidor.programar('POST', '/api/caja/abrir', RespuestaFalsa.deEjemplo('09_K2_abrir_caja'));
      servidor.programar('POST', '/api/login', RespuestaFalsa.deEjemplo('02_S2_login_ok'));
      await abrirCaja(); // pide el token #1
      await dio.post<dynamic>('/api/login', data: {'login': 'x', 'password': 'y'});
      await abrirCaja(); // el token #1 ya no sirve: pide el #2
      expect(servidor.veces('GET', '/api/csrf-token'), 2);
    });
  });

  group('Reintento por CSRF inválido (403 con code CSRF_INVALID)', () {
    test('pide otro token y repite la petición UNA vez; si ahora sale bien, devuelve ese resultado', () async {
      servidor.programar('POST', '/api/caja/abrir', RespuestaFalsa.deEjemplo('06_S6_escritura_sin_csrf_403'));
      servidor.programar('POST', '/api/caja/abrir', RespuestaFalsa.deEjemplo('09_K2_abrir_caja'));
      final r = await abrirCaja();
      expect(r.statusCode, 200);
      expect(servidor.peticiones.map((p) => p.clave), [
        'GET /api/csrf-token',
        'POST /api/caja/abrir', // rechazada: 403
        'GET /api/csrf-token', // token nuevo
        'POST /api/caja/abrir', // repetida: 200
      ]);
    });

    test('si el servidor vuelve a rechazar, NO se reintenta una segunda vez (sin bucles)', () async {
      servidor.programar('POST', '/api/caja/abrir', RespuestaFalsa.deEjemplo('06_S6_escritura_sin_csrf_403'));
      await expectLater(
        abrirCaja(),
        throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'estado', 403)),
      );
      expect(servidor.veces('POST', '/api/caja/abrir'), 2); // el original + UN reintento
    });

    test('un 403 de permisos (sin code CSRF_INVALID) NO se reintenta', () async {
      servidor.programar(
        'POST',
        '/api/caja/abrir',
        const RespuestaFalsa(403, {'error': 'Se requieren permisos de administrador'}),
      );
      await expectLater(abrirCaja(), throwsA(isA<DioException>()));
      expect(servidor.veces('POST', '/api/caja/abrir'), 1);
    });
  });

  group('Sesión caducada (401)', () {
    test('un 401 en una ruta protegida avisa para volver al login', () async {
      servidor.programar('GET', '/api/caja/sesion', RespuestaFalsa.deEjemplo('29_S6_sin_sesion_401'));
      await expectLater(dio.get<dynamic>('/api/caja/sesion'), throwsA(isA<DioException>()));
      expect(vecesQueCaduco, 1);
    });

    test('un 401 en el login (clave incorrecta) NO se toma como sesión caducada', () async {
      servidor.programar('POST', '/api/login', RespuestaFalsa.deEjemplo('01_S2_login_clave_incorrecta'));
      await expectLater(
        dio.post<dynamic>('/api/login', data: {'login': 'x', 'password': 'mala'}),
        throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'estado', 401)),
      );
      expect(vecesQueCaduco, 0);
    });

    test('un 401 en la verificación del código 2FA (código incorrecto) tampoco', () async {
      servidor.programar('POST', '/api/2fa/verify', const RespuestaFalsa(401, {'success': false, 'error': 'Código inválido o ha expirado.'}));
      await expectLater(dio.post<dynamic>('/api/2fa/verify', data: {'token': '000000'}), throwsA(isA<DioException>()));
      expect(vecesQueCaduco, 0);
    });

    test('el 409 SESSION_ACTIVE del login llega a quien llamó, para ofrecer «cerrar la otra sesión»', () async {
      servidor.programar('POST', '/api/login', RespuestaFalsa.deEjemplo('03_S2_login_sesion_activa_409'));
      await expectLater(
        dio.post<dynamic>('/api/login', data: {'login': 'x', 'password': 'y'}),
        throwsA(isA<DioException>().having((e) => e.response?.data['code'], 'code', 'SESSION_ACTIVE')),
      );
      expect(vecesQueCaduco, 0);
    });
  });

  group('Cookie de sesión', () {
    test('la cookie que entrega el login se reenvía en las siguientes peticiones', () async {
      servidor.programar(
        'POST',
        '/api/login',
        const RespuestaFalsa(200, {'success': true}, headers: {
          'set-cookie': ['connect.sid=abc123; Path=/; HttpOnly'],
        }),
      );
      servidor.programar('GET', '/api/caja/sesion', RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'));
      await dio.post<dynamic>('/api/login', data: {'login': 'x', 'password': 'y'});
      await dio.get<dynamic>('/api/caja/sesion');
      expect(servidor.peticiones.last.headers['cookie'], contains('connect.sid=abc123'));
    });
  });
}
