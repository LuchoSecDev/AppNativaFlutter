import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_models.dart';
import 'package:stockpilot/auth/auth_repository.dart';

import '../support/fake_adapter.dart';

/// Pruebas de la capa que habla con la API de sesión. Las respuestas salen de los ejemplos reales del backend.
void main() {
  late ServidorFalso servidor;
  late AuthRepository repo;
  late int vecesQueCaduco;

  setUp(() {
    servidor = ServidorFalso();
    vecesQueCaduco = 0;
    repo = AuthRepository(
      crearClienteApi(
        baseUrl: 'https://servidor.test',
        cookieJar: CookieJar(),
        adapter: servidor,
        onSessionExpired: () => vecesQueCaduco++,
      ),
    );
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
  });

  group('login [S2]', () {
    test('credenciales correctas: LoginExitoso con el usuario; envía login y password, sin "force"', () async {
      servidor.programar(
        'POST',
        '/api/login',
        RespuestaFalsa.deEjemplo('02_S2_login_ok'),
      );
      final r = await repo.login(usuario: 'tendero_ejemplo', password: 'x');
      expect(r, isA<LoginExitoso>());
      final u = (r as LoginExitoso).usuario;
      expect(u.nombres, 'Carlos Pérez');
      expect(u.rol, 'Tendero');
      expect(u.cambioClaveForzoso, isFalse);
      expect(servidor.peticiones.single.cuerpo, {
        'login': 'tendero_ejemplo',
        'password': 'x',
      });
    });

    test(
      'con segundo factor: LoginRequiere2FA (todavía no hay sesión)',
      () async {
        servidor.programar(
          'POST',
          '/api/login',
          RespuestaFalsa.deEjemplo('40_S2_login_con_segundo_factor'),
        );
        expect(
          await repo.login(usuario: 'a', password: 'b'),
          isA<LoginRequiere2FA>(),
        );
      },
    );

    test('primer inicio de una cuenta nueva: el usuario trae cambioClaveForzoso = true', () async {
      servidor.programar(
        'POST',
        '/api/login',
        RespuestaFalsa.deEjemplo('50_S2_login_con_clave_temporal'),
      );
      final r = await repo.login(usuario: 'a', password: 'b');
      expect((r as LoginExitoso).usuario.cambioClaveForzoso, isTrue);
    });

    test(
      'clave incorrecta (401): LoginRechazado con el mensaje del servidor',
      () async {
        servidor.programar(
          'POST',
          '/api/login',
          RespuestaFalsa.deEjemplo('01_S2_login_clave_incorrecta'),
        );
        final r = await repo.login(usuario: 'a', password: 'mala');
        expect(r, isA<LoginRechazado>());
        expect(
          (r as LoginRechazado).mensaje,
          'Usuario/correo o contraseña incorrectos',
        );
        expect(vecesQueCaduco, 0);
      },
    );

    test('ya hay una sesión (409 SESSION_ACTIVE): LoginSesionActiva; con forzar envía "force": true', () async {
      servidor.programar(
        'POST',
        '/api/login',
        RespuestaFalsa.deEjemplo('03_S2_login_sesion_activa_409'),
      );
      expect(
        await repo.login(usuario: 'a', password: 'b'),
        isA<LoginSesionActiva>(),
      );
      await repo.login(usuario: 'a', password: 'b', forzar: true);
      expect(servidor.peticiones.last.cuerpo, {
        'login': 'a',
        'password': 'b',
        'force': true,
      });
    });

    test('demasiados intentos (429): LoginRechazado con el mensaje', () async {
      servidor.programar(
        'POST',
        '/api/login',
        const RespuestaFalsa(429, {
          'success': false,
          'error': 'Demasiados intentos.',
        }),
      );
      final r = await repo.login(usuario: 'a', password: 'b');
      expect((r as LoginRechazado).mensaje, 'Demasiados intentos.');
    });

    test(
      'sin conexión: lanza ErrorDeApi con un mensaje para el usuario',
      () async {
        servidor.programar(
          'POST',
          '/api/login',
          const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
        );
        await expectLater(
          repo.login(usuario: 'a', password: 'b'),
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

    test('tiempo agotado: ErrorDeApi que explica que el servidor puede estar despertando', () async {
      servidor.programar(
        'POST',
        '/api/login',
        const RespuestaFalsa.falloDeRed(DioExceptionType.receiveTimeout),
      );
      await expectLater(
        repo.login(usuario: 'a', password: 'b'),
        throwsA(
          isA<ErrorDeApi>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('dormido'),
          ),
        ),
      );
    });

    test('error del servidor (500): ErrorDeApi', () async {
      servidor.programar(
        'POST',
        '/api/login',
        const RespuestaFalsa(500, {'success': false, 'error': 'Error'}),
      );
      await expectLater(
        repo.login(usuario: 'a', password: 'b'),
        throwsA(isA<ErrorDeApi>()),
      );
    });
  });

  group('segundo factor [S3]', () {
    test('código correcto: VerificacionExitosa; envía {token: código} con el token CSRF', () async {
      servidor.programar(
        'POST',
        '/api/2fa/verify',
        RespuestaFalsa.deEjemplo('43_S3_verificar_codigo_ok'),
      );
      final r = await repo.verificarCodigo2FA('123456');
      expect((r as VerificacionExitosa).usuario.rol, 'Administrador');
      final p = servidor.peticiones.last;
      expect(p.cuerpo, {'token': '123456'});
      expect(p.headers['X-CSRF-Token'], isNotEmpty);
    });

    test('código incorrecto (401): VerificacionRechazada con el mensaje, y NO cuenta como sesión caducada', () async {
      servidor.programar(
        'POST',
        '/api/2fa/verify',
        RespuestaFalsa.deEjemplo('42_S3_codigo_incorrecto_401'),
      );
      final r = await repo.verificarCodigo2FA('000000');
      expect(
        (r as VerificacionRechazada).mensaje,
        'Código inválido o ha expirado.',
      );
      expect(vecesQueCaduco, 0);
    });
  });

  group('primer cambio de contraseña [S7]', () {
    test('éxito: CambioClaveExitoso; envía {newPassword}', () async {
      servidor.programar(
        'PUT',
        '/api/perfil/first-password',
        RespuestaFalsa.deEjemplo('51_S7_primer_cambio_de_contrasena'),
      );
      expect(
        await repo.cambiarClaveInicial('NuevaClave2026!'),
        isA<CambioClaveExitoso>(),
      );
      expect(servidor.peticiones.last.cuerpo, {
        'newPassword': 'NuevaClave2026!',
      });
      expect(servidor.peticiones.last.headers['X-CSRF-Token'], isNotEmpty);
    });

    test(
      'contraseña rechazada (400): CambioClaveRechazado con el mensaje',
      () async {
        servidor.programar(
          'PUT',
          '/api/perfil/first-password',
          const RespuestaFalsa(400, {
            'success': false,
            'error': 'La contraseña debe tener al menos 8 caracteres',
          }),
        );
        final r = await repo.cambiarClaveInicial('corta');
        expect(
          (r as CambioClaveRechazado).mensaje,
          'La contraseña debe tener al menos 8 caracteres',
        );
      },
    );
  });

  group('información de la sesión [S4]', () {
    test(
      'infoDeSesion: lee tienda, rol y el tope de egresos (como TEXTO)',
      () async {
        servidor.programar(
          'GET',
          '/api/session-info',
          RespuestaFalsa.deEjemplo('05_S4_session_info'),
        );
        final info = await repo.infoDeSesion();
        expect(info.tiendaNombre, 'Tienda La Esperanza');
        expect(info.rol, 'Tendero');
        expect(info.limiteEgresoTendero, '150000.00');
        expect(info.limiteEgresoTendero, isA<String>());
      },
    );

    test(
      'restaurarSesion con cookie vigente: devuelve la información',
      () async {
        servidor.programar(
          'GET',
          '/api/session-info',
          RespuestaFalsa.deEjemplo('44_S4_session_info_administrador'),
        );
        final info = await repo.restaurarSesion();
        expect(info!.nombres, 'Marta Gómez');
        expect(info.is2FAEnabled, isTrue);
      },
    );

    test('restaurarSesion sin sesión (401): devuelve null y NO avisa de sesión caducada', () async {
      servidor.programar(
        'GET',
        '/api/session-info',
        const RespuestaFalsa(401, {
          'success': false,
          'error': 'Sesión no iniciada',
        }),
      );
      expect(await repo.restaurarSesion(), isNull);
      expect(vecesQueCaduco, 0);
    });

    test(
      'restaurarSesion con el servidor caído (500): lanza ErrorDeApi',
      () async {
        servidor.programar(
          'GET',
          '/api/session-info',
          const RespuestaFalsa(500, {'error': 'x'}),
        );
        await expectLater(repo.restaurarSesion(), throwsA(isA<ErrorDeApi>()));
      },
    );
  });

  group('cerrar sesión [S5] y prueba de conexión', () {
    test('cerrarSesion envía POST /api/logout con token CSRF', () async {
      servidor.programar(
        'POST',
        '/api/logout',
        RespuestaFalsa.deEjemplo('28_S5_logout'),
      );
      await repo.cerrarSesion();
      expect(servidor.veces('POST', '/api/logout'), 1);
      expect(servidor.peticiones.last.headers['X-CSRF-Token'], isNotEmpty);
    });

    test('cerrarSesion NO lanza error si no hay red (el usuario sale de todos modos)', () async {
      servidor.programar(
        'POST',
        '/api/logout',
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      await repo.cerrarSesion(); // si lanzara, la prueba fallaría
    });

    test(
      'probarConexion: con el servidor respondiendo da el estado 200',
      () async {
        final r = await repo.probarConexion();
        expect(r.llego, isTrue);
        expect(r.estado, 200);
      },
    );

    test(
      'probarConexion: sin red da un mensaje de error y llego = false',
      () async {
        final sinRed = AuthRepository(
          crearClienteApi(
            baseUrl: 'https://servidor.test',
            cookieJar: CookieJar(),
            adapter: ServidorFalso()
              ..programar(
                'GET',
                '/api/csrf-token',
                const RespuestaFalsa.falloDeRed(
                  DioExceptionType.connectionError,
                ),
              ),
          ),
        );
        final r = await sinRed.probarConexion();
        expect(r.llego, isFalse);
        expect(r.error, contains('conexión'));
      },
    );
  });
}
