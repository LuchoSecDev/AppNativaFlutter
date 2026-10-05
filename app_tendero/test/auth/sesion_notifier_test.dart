import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/auth/session_state.dart';

import '../support/fake_adapter.dart';

/// Pruebas del estado de la sesión: cada camino que puede seguir el usuario, usando el cliente HTTP REAL y un
/// servidor falso con los ejemplos reales del backend.
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

  SesionNotifier sesion() => contenedor.read(sesionProvider.notifier);

  /// Espera (hasta 1 s) a que el estado cumpla la condición. Los pasos son asíncronos, así que hay que esperar.
  Future<EstadoSesion> esperarQue(bool Function(EstadoSesion) condicion) async {
    for (var i = 0; i < 200; i++) {
      final actual = contenedor.read(sesionProvider);
      if (condicion(actual)) return actual;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw TimeoutException(
      'El estado nunca cumplió la condición; quedó en ${contenedor.read(sesionProvider).fase}',
    );
  }

  Future<EstadoSesion> arrancarSinSesion() async {
    servidor.programar(
      'GET',
      '/api/session-info',
      const RespuestaFalsa(401, {
        'success': false,
        'error': 'Sesión no iniciada',
      }),
    );
    contenedor.read(
      sesionProvider,
    ); // primer uso: ejecuta build() y la comprobación de arranque
    return esperarQue((e) => e.fase != FaseSesion.iniciando);
  }

  group('al abrir la app', () {
    test('empieza en «iniciando» y, si no hay sesión (401), pasa a «sinSesion» sin mensaje de error', () async {
      servidor.programar(
        'GET',
        '/api/session-info',
        const RespuestaFalsa(401, {
          'success': false,
          'error': 'Sesión no iniciada',
        }),
      );
      expect(contenedor.read(sesionProvider).fase, FaseSesion.iniciando);
      final e = await esperarQue((e) => e.fase != FaseSesion.iniciando);
      expect(e.fase, FaseSesion.sinSesion);
      expect(e.mensaje, isNull);
    });

    test('con la cookie todavía vigente, entra directo a «activa» con los datos de la tienda', () async {
      servidor.programar(
        'GET',
        '/api/session-info',
        RespuestaFalsa.deEjemplo('05_S4_session_info'),
      );
      contenedor.read(sesionProvider);
      final e = await esperarQue((e) => e.fase != FaseSesion.iniciando);
      expect(e.fase, FaseSesion.activa);
      expect(e.info!.tiendaNombre, 'Tienda La Esperanza');
    });

    test('si la cuenta aún debía cambiar su contraseña temporal, vuelve a pedir el cambio', () async {
      servidor.programar(
        'GET',
        '/api/session-info',
        const RespuestaFalsa(200, {
          'success': true,
          'userId': 2,
          'tiendaId': 1,
          'tiendaNombre': 'T',
          'limiteEgresoTendero': '150000.00',
          'rol': 'Tendero',
          'nombres': 'Carlos',
          'cambioClaveForzoso': true,
          'needs2FASetup': false,
          'is2FAEnabled': false,
        }),
      );
      contenedor.read(sesionProvider);
      final e = await esperarQue((e) => e.fase != FaseSesion.iniciando);
      expect(e.fase, FaseSesion.cambioClave);
    });

    test('con el servidor sin respuesta, pasa a «sinSesion» con un mensaje para reintentar', () async {
      servidor.programar(
        'GET',
        '/api/session-info',
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      contenedor.read(sesionProvider);
      final e = await esperarQue((e) => e.fase != FaseSesion.iniciando);
      expect(e.fase, FaseSesion.sinSesion);
      expect(e.mensaje, contains('conexión'));
    });
  });

  group('inicio de sesión', () {
    test(
      'credenciales correctas: pasa por «trabajando» y termina en «activa»',
      () async {
        await arrancarSinSesion();
        final historial = <EstadoSesion>[];
        contenedor.listen(sesionProvider, (_, nuevo) => historial.add(nuevo));
        servidor.programar(
          'POST',
          '/api/login',
          RespuestaFalsa.deEjemplo('02_S2_login_ok'),
        );
        servidor.programar(
          'GET',
          '/api/session-info',
          RespuestaFalsa.deEjemplo('05_S4_session_info'),
        );

        await sesion().iniciarSesion('tendero_ejemplo', 'x');

        expect(
          historial.first.trabajando,
          isTrue,
        ); // mientras espera al servidor
        final fin = contenedor.read(sesionProvider);
        expect(fin.fase, FaseSesion.activa);
        expect(fin.trabajando, isFalse);
        expect(fin.info!.nombres, 'Carlos Pérez');
      },
    );

    test('un segundo toque mientras espera al servidor NO envía otro login (evita un 409 provocado por uno mismo)', () async {
      await arrancarSinSesion();
      servidor.programar(
        'POST',
        '/api/login',
        RespuestaFalsa.deEjemplo('02_S2_login_ok'),
      );
      servidor.programar(
        'GET',
        '/api/session-info',
        RespuestaFalsa.deEjemplo('05_S4_session_info'),
      );
      final primero = sesion().iniciarSesion('a', 'b');
      final segundo = sesion().iniciarSesion(
        'a',
        'b',
      ); // sin esperar: simula el doble toque
      await Future.wait([primero, segundo]);
      expect(servidor.veces('POST', '/api/login'), 1);
      expect(contenedor.read(sesionProvider).fase, FaseSesion.activa);
    });

    test(
      'clave incorrecta: se queda en «sinSesion» con el mensaje del servidor',
      () async {
        await arrancarSinSesion();
        servidor.programar(
          'POST',
          '/api/login',
          RespuestaFalsa.deEjemplo('01_S2_login_clave_incorrecta'),
        );
        await sesion().iniciarSesion('a', 'mala');
        final e = contenedor.read(sesionProvider);
        expect(e.fase, FaseSesion.sinSesion);
        expect(e.mensaje, 'Usuario/correo o contraseña incorrectos');
        expect(e.trabajando, isFalse);
      },
    );

    test('sin conexión: «sinSesion» con un mensaje, sin quedarse «trabajando» para siempre', () async {
      await arrancarSinSesion();
      servidor.programar(
        'POST',
        '/api/login',
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      await sesion().iniciarSesion('a', 'b');
      final e = contenedor.read(sesionProvider);
      expect(e.fase, FaseSesion.sinSesion);
      expect(e.trabajando, isFalse);
      expect(e.mensaje, contains('conexión'));
    });

    test('ya hay otra sesión (409): pide confirmar; al confirmar con «forzar» entra', () async {
      await arrancarSinSesion();
      servidor.programar(
        'POST',
        '/api/login',
        RespuestaFalsa.deEjemplo('03_S2_login_sesion_activa_409'),
      );
      await sesion().iniciarSesion('a', 'b');
      expect(contenedor.read(sesionProvider).pideForzar, isTrue);

      servidor.programar(
        'POST',
        '/api/login',
        RespuestaFalsa.deEjemplo('02_S2_login_ok'),
      );
      servidor.programar(
        'GET',
        '/api/session-info',
        RespuestaFalsa.deEjemplo('05_S4_session_info'),
      );
      await sesion().iniciarSesion('a', 'b', forzar: true);
      expect(contenedor.read(sesionProvider).fase, FaseSesion.activa);
      expect(
        servidor.peticiones
            .where((p) => p.clave == 'POST /api/login')
            .last
            .cuerpo['force'],
        isTrue,
      );
    });
  });

  group('segundo factor', () {
    test('el login pide el código; un código incorrecto deja reintentar; el correcto entra', () async {
      await arrancarSinSesion();
      servidor.programar(
        'POST',
        '/api/login',
        RespuestaFalsa.deEjemplo('40_S2_login_con_segundo_factor'),
      );
      await sesion().iniciarSesion('a', 'b');
      expect(contenedor.read(sesionProvider).fase, FaseSesion.codigo2FA);

      servidor.programar(
        'POST',
        '/api/2fa/verify',
        RespuestaFalsa.deEjemplo('42_S3_codigo_incorrecto_401'),
      );
      await sesion().verificarCodigo('000000');
      var e = contenedor.read(sesionProvider);
      expect(e.fase, FaseSesion.codigo2FA);
      expect(e.mensaje, 'Código inválido o ha expirado.');

      servidor.programar(
        'POST',
        '/api/2fa/verify',
        RespuestaFalsa.deEjemplo('43_S3_verificar_codigo_ok'),
      );
      servidor.programar(
        'GET',
        '/api/session-info',
        RespuestaFalsa.deEjemplo('44_S4_session_info_administrador'),
      );
      await sesion().verificarCodigo('123456');
      e = contenedor.read(sesionProvider);
      expect(e.fase, FaseSesion.activa);
      expect(e.info!.rol, 'Administrador');
    });

    test('un Administrador sin segundo factor configurado NO entra: se cierra la sesión y se le avisa', () async {
      await arrancarSinSesion();
      servidor.programar(
        'POST',
        '/api/login',
        const RespuestaFalsa(200, {
          'success': true,
          'user': {
            'nombres': 'Marta',
            'rol': 'Administrador',
            'cambioClaveForzoso': false,
            'needs2FASetup': true,
          },
        }),
      );
      servidor.programar(
        'POST',
        '/api/logout',
        RespuestaFalsa.deEjemplo('28_S5_logout'),
      );
      await sesion().iniciarSesion('a', 'b');
      final e = contenedor.read(sesionProvider);
      expect(e.fase, FaseSesion.sinSesion);
      expect(e.mensaje, contains('segundo factor'));
      expect(servidor.veces('POST', '/api/logout'), 1);
    });
  });

  group('primer cambio de contraseña', () {
    test('una cuenta nueva pasa a «cambioClave»; una clave rechazada deja corregir; una válida entra', () async {
      await arrancarSinSesion();
      servidor.programar(
        'POST',
        '/api/login',
        RespuestaFalsa.deEjemplo('50_S2_login_con_clave_temporal'),
      );
      await sesion().iniciarSesion('a', 'b');
      expect(contenedor.read(sesionProvider).fase, FaseSesion.cambioClave);
      expect(contenedor.read(sesionProvider).usuario!.nombres, isNotEmpty);

      servidor.programar(
        'PUT',
        '/api/perfil/first-password',
        const RespuestaFalsa(400, {'success': false, 'error': 'Muy corta'}),
      );
      await sesion().cambiarClaveInicial('corta');
      var e = contenedor.read(sesionProvider);
      expect(e.fase, FaseSesion.cambioClave);
      expect(e.mensaje, 'Muy corta');
      expect(e.usuario, isNotNull); // no se pierde quién es

      servidor.programar(
        'PUT',
        '/api/perfil/first-password',
        RespuestaFalsa.deEjemplo('51_S7_primer_cambio_de_contrasena'),
      );
      servidor.programar(
        'GET',
        '/api/session-info',
        RespuestaFalsa.deEjemplo('05_S4_session_info'),
      );
      await sesion().cambiarClaveInicial('NuevaClave2026!');
      e = contenedor.read(sesionProvider);
      expect(e.fase, FaseSesion.activa);
    });
  });

  group('cerrar sesión y sesión caducada', () {
    Future<void> iniciarSesionActiva() async {
      await arrancarSinSesion();
      servidor.programar(
        'POST',
        '/api/login',
        RespuestaFalsa.deEjemplo('02_S2_login_ok'),
      );
      servidor.programar(
        'GET',
        '/api/session-info',
        RespuestaFalsa.deEjemplo('05_S4_session_info'),
      );
      await sesion().iniciarSesion('a', 'b');
      expect(contenedor.read(sesionProvider).fase, FaseSesion.activa);
    }

    test('cerrarSesion avisa al servidor y vuelve al login', () async {
      await iniciarSesionActiva();
      servidor.programar(
        'POST',
        '/api/logout',
        RespuestaFalsa.deEjemplo('28_S5_logout'),
      );
      await sesion().cerrarSesion();
      expect(contenedor.read(sesionProvider).fase, FaseSesion.sinSesion);
      expect(servidor.veces('POST', '/api/logout'), 1);
    });

    test('un 401 real en una petición normal (sesión caducada) devuelve al login con un aviso', () async {
      await iniciarSesionActiva();
      servidor.programar(
        'GET',
        '/api/caja/sesion',
        RespuestaFalsa.deEjemplo('29_S6_sin_sesion_401'),
      );
      await expectLater(
        contenedor.read(dioProvider).get<dynamic>('/api/caja/sesion'),
        throwsA(isA<DioException>()),
      );
      final e = await esperarQue((e) => e.fase == FaseSesion.sinSesion);
      expect(e.mensaje, 'Tu sesión terminó. Inicia sesión de nuevo.');
    });

    test('el aviso de caducidad NO pisa la pantalla de login (si todavía no hay sesión no pasa nada)', () async {
      await arrancarSinSesion();
      caducidad.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final e = contenedor.read(sesionProvider);
      expect(e.fase, FaseSesion.sinSesion);
      expect(e.mensaje, isNull);
    });
  });
}
