import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/auth/ui/auth_gate.dart';

import '../../support/fake_adapter.dart';

/// Pruebas de las pantallas: simulan a una persona escribiendo y tocando botones, con un servidor falso que
/// responde con los ejemplos reales del backend. No necesitan celular ni internet.
void main() {
  late ServidorFalso servidor;

  /// Arranca la app con el servidor falso. [programar] agrega las respuestas de cada prueba.
  Future<void> abrirApp(WidgetTester tester, void Function(ServidorFalso s) programar) async {
    servidor = ServidorFalso();
    servidor.programar('GET', '/api/csrf-token', RespuestaFalsa.deEjemplo('04_S1_csrf_token'));
    programar(servidor);
    final caducidad = StreamController<void>.broadcast();
    addTearDown(caducidad.close);
    final dio = crearClienteApi(
      baseUrl: 'https://servidor.test',
      cookieJar: CookieJar(),
      adapter: servidor,
      onSessionExpired: () => caducidad.add(null),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        sesionCaducadaProvider.overrideWithValue(caducidad.stream),
      ],
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pumpAndSettle();
  }

  void sinSesionAlAbrir(ServidorFalso s) =>
      s.programar('GET', '/api/session-info', const RespuestaFalsa(401, {'success': false, 'error': 'Sesión no iniciada'}));

  Finder campo(int posicion) => find.byType(TextFormField).at(posicion);

  Future<void> escribirYEntrar(WidgetTester tester, {String usuario = 'tendero_ejemplo', String clave = 'x'}) async {
    await tester.enterText(campo(0), usuario);
    await tester.enterText(campo(1), clave);
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
  }

  testWidgets('al abrir: muestra «Conectando…» y, sin sesión guardada, pasa al login', (tester) async {
    servidor = ServidorFalso();
    servidor.programar('GET', '/api/session-info', const RespuestaFalsa(401, {'error': 'x'}));
    final caducidad = StreamController<void>.broadcast();
    addTearDown(caducidad.close);
    final dio = crearClienteApi(baseUrl: 'https://servidor.test', cookieJar: CookieJar(), adapter: servidor);
    await tester.pumpWidget(ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio), sesionCaducadaProvider.overrideWithValue(caducidad.stream)],
      child: const MaterialApp(home: AuthGate()),
    ));
    expect(find.text('Conectando…'), findsOneWidget); // primer cuadro, antes de que responda el servidor
    await tester.pumpAndSettle();
    expect(find.text('Inicia sesión'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
  });

  testWidgets('con una sesión vigente al abrir, entra directo a la pantalla de inicio', (tester) async {
    await abrirApp(tester, (s) => s.programar('GET', '/api/session-info', RespuestaFalsa.deEjemplo('05_S4_session_info')));
    expect(find.text('Hola, Carlos Pérez'), findsOneWidget);
    expect(find.text('Inicia sesión'), findsNothing);
  });

  group('login', () {
    testWidgets('si faltan campos, avisa y NO envía nada al servidor', (tester) async {
      await abrirApp(tester, sinSesionAlAbrir);
      await tester.tap(find.text('Ingresar'));
      await tester.pumpAndSettle();
      expect(find.text('Escribe tu usuario o correo'), findsOneWidget);
      expect(find.text('Escribe tu contraseña'), findsOneWidget);
      expect(servidor.veces('POST', '/api/login'), 0);
    });

    testWidgets('la contraseña está oculta y el ojo la muestra', (tester) async {
      await abrirApp(tester, sinSesionAlAbrir);
      bool oculta() => tester.widget<TextField>(find.byType(TextField).at(1)).obscureText;
      expect(oculta(), isTrue);
      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pump();
      expect(oculta(), isFalse);
    });

    testWidgets('credenciales correctas: llega a la pantalla de inicio con el nombre y la tienda', (tester) async {
      await abrirApp(tester, (s) {
        sinSesionAlAbrir(s);
        s.programar('POST', '/api/login', RespuestaFalsa.deEjemplo('02_S2_login_ok'));
        s.programar('GET', '/api/session-info', RespuestaFalsa.deEjemplo('05_S4_session_info'));
      });
      await escribirYEntrar(tester);
      expect(find.text('Hola, Carlos Pérez'), findsOneWidget);
      expect(find.textContaining('Tienda La Esperanza'), findsOneWidget);
      expect(servidor.peticiones.firstWhere((p) => p.clave == 'POST /api/login').cuerpo,
          {'login': 'tendero_ejemplo', 'password': 'x'});
    });

    testWidgets('clave incorrecta: muestra el mensaje y se queda en el login', (tester) async {
      await abrirApp(tester, (s) {
        sinSesionAlAbrir(s);
        s.programar('POST', '/api/login', RespuestaFalsa.deEjemplo('01_S2_login_clave_incorrecta'));
      });
      await escribirYEntrar(tester, clave: 'mala');
      expect(find.text('Usuario/correo o contraseña incorrectos'), findsOneWidget);
      expect(find.text('Inicia sesión'), findsOneWidget);
    });

    testWidgets('sin conexión: muestra un mensaje claro', (tester) async {
      await abrirApp(tester, (s) {
        sinSesionAlAbrir(s);
        s.programar('POST', '/api/login', const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError));
      });
      await escribirYEntrar(tester);
      expect(find.textContaining('No hay conexión con el servidor'), findsOneWidget);
    });

    testWidgets('ya hay otra sesión (409): pregunta; «Cancelar» la oculta', (tester) async {
      await abrirApp(tester, (s) {
        sinSesionAlAbrir(s);
        s.programar('POST', '/api/login', RespuestaFalsa.deEjemplo('03_S2_login_sesion_activa_409'));
      });
      await escribirYEntrar(tester);
      expect(find.textContaining('ya tiene una sesión abierta'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ya tiene una sesión abierta'), findsNothing);
    });

    testWidgets('ya hay otra sesión (409): «Cerrar la otra sesión» entra y envía force', (tester) async {
      await abrirApp(tester, (s) {
        sinSesionAlAbrir(s);
        s.programar('POST', '/api/login', RespuestaFalsa.deEjemplo('03_S2_login_sesion_activa_409'));
      });
      await escribirYEntrar(tester);
      servidor.programar('POST', '/api/login', RespuestaFalsa.deEjemplo('02_S2_login_ok'));
      servidor.programar('GET', '/api/session-info', RespuestaFalsa.deEjemplo('05_S4_session_info'));
      await tester.tap(find.text('Cerrar la otra sesión'));
      await tester.pumpAndSettle();
      expect(find.text('Hola, Carlos Pérez'), findsOneWidget);
      expect(servidor.peticiones.where((p) => p.clave == 'POST /api/login').last.cuerpo['force'], isTrue);
    });

    testWidgets('la prueba de conexión (solo depuración) muestra la respuesta del servidor', (tester) async {
      await abrirApp(tester, sinSesionAlAbrir);
      expect(find.text('Solo depuración'), findsOneWidget);
      await tester.tap(find.text('Probar conexión con el servidor'));
      await tester.pumpAndSettle();
      expect(find.textContaining('El servidor respondió (código 200)'), findsOneWidget);
    });
  });

  group('segundo factor', () {
    Future<void> hastaElCodigo(WidgetTester tester) async {
      await abrirApp(tester, (s) {
        sinSesionAlAbrir(s);
        s.programar('POST', '/api/login', RespuestaFalsa.deEjemplo('40_S2_login_con_segundo_factor'));
      });
      await escribirYEntrar(tester, usuario: 'dueno_ejemplo');
      expect(find.text('Código de verificación'), findsOneWidget);
    }

    bool botonVerificarActivo(WidgetTester tester) =>
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Verificar')).onPressed != null;

    testWidgets('el botón «Verificar» solo se activa con 6 dígitos y el campo solo admite números', (tester) async {
      await hastaElCodigo(tester);
      expect(botonVerificarActivo(tester), isFalse);
      await tester.enterText(find.byType(TextField), '12ab34');
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '1234'); // las letras se descartan
      expect(botonVerificarActivo(tester), isFalse);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      expect(botonVerificarActivo(tester), isTrue);
    });

    testWidgets('código correcto: entra a la pantalla de inicio', (tester) async {
      await hastaElCodigo(tester);
      servidor.programar('POST', '/api/2fa/verify', RespuestaFalsa.deEjemplo('43_S3_verificar_codigo_ok'));
      servidor.programar('GET', '/api/session-info', RespuestaFalsa.deEjemplo('44_S4_session_info_administrador'));
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.tap(find.text('Verificar'));
      await tester.pumpAndSettle();
      expect(find.text('Hola, Marta Gómez'), findsOneWidget);
    });

    testWidgets('código incorrecto: muestra el mensaje y permite reintentar', (tester) async {
      await hastaElCodigo(tester);
      servidor.programar('POST', '/api/2fa/verify', RespuestaFalsa.deEjemplo('42_S3_codigo_incorrecto_401'));
      await tester.enterText(find.byType(TextField), '000000');
      await tester.pump();
      await tester.tap(find.text('Verificar'));
      await tester.pumpAndSettle();
      expect(find.text('Código inválido o ha expirado.'), findsOneWidget);
      expect(find.text('Código de verificación'), findsOneWidget);
    });

    testWidgets('«Volver al inicio de sesión» cierra la sesión a medias y regresa al login', (tester) async {
      await hastaElCodigo(tester);
      servidor.programar('POST', '/api/logout', RespuestaFalsa.deEjemplo('28_S5_logout'));
      await tester.tap(find.text('Volver al inicio de sesión'));
      await tester.pumpAndSettle();
      expect(find.text('Inicia sesión'), findsOneWidget);
      expect(servidor.veces('POST', '/api/logout'), 1);
    });
  });

  group('primer cambio de contraseña', () {
    Future<void> hastaElCambio(WidgetTester tester) async {
      await abrirApp(tester, (s) {
        sinSesionAlAbrir(s);
        s.programar('POST', '/api/login', RespuestaFalsa.deEjemplo('50_S2_login_con_clave_temporal'));
      });
      await escribirYEntrar(tester);
      expect(find.text('Elige tu contraseña'), findsOneWidget);
    }

    testWidgets('valida: mínimo 8 caracteres y que coincidan; no envía nada si hay errores', (tester) async {
      await hastaElCambio(tester);
      await tester.enterText(campo(0), 'corta');
      await tester.enterText(campo(1), 'otra');
      await tester.tap(find.text('Guardar contraseña'));
      await tester.pumpAndSettle();
      expect(find.text('Debe tener al menos 8 caracteres'), findsOneWidget);
      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
      expect(servidor.veces('PUT', '/api/perfil/first-password'), 0);
    });

    testWidgets('con una contraseña válida la guarda y entra a la pantalla de inicio', (tester) async {
      await hastaElCambio(tester);
      servidor.programar('PUT', '/api/perfil/first-password', RespuestaFalsa.deEjemplo('51_S7_primer_cambio_de_contrasena'));
      servidor.programar('GET', '/api/session-info', RespuestaFalsa.deEjemplo('05_S4_session_info'));
      await tester.enterText(campo(0), 'NuevaClave2026!');
      await tester.enterText(campo(1), 'NuevaClave2026!');
      await tester.tap(find.text('Guardar contraseña'));
      await tester.pumpAndSettle();
      expect(find.text('Hola, Carlos Pérez'), findsOneWidget);
      expect(servidor.peticiones.last.clave, 'GET /api/session-info');
    });

    testWidgets('si el servidor la rechaza, muestra su mensaje y se queda en la pantalla', (tester) async {
      await hastaElCambio(tester);
      servidor.programar(
        'PUT',
        '/api/perfil/first-password',
        const RespuestaFalsa(400, {'success': false, 'error': 'La nueva contraseña no puede ser igual a la temporal.'}),
      );
      await tester.enterText(campo(0), 'LaMismaClave1');
      await tester.enterText(campo(1), 'LaMismaClave1');
      await tester.tap(find.text('Guardar contraseña'));
      await tester.pumpAndSettle();
      expect(find.text('La nueva contraseña no puede ser igual a la temporal.'), findsOneWidget);
      expect(find.text('Elige tu contraseña'), findsOneWidget);
    });
  });

  group('con la sesión activa', () {
    Future<void> hastaElInicio(WidgetTester tester) => abrirApp(
        tester, (s) => s.programar('GET', '/api/session-info', RespuestaFalsa.deEjemplo('05_S4_session_info')));

    testWidgets('«Cerrar sesión» vuelve al login y avisa al servidor', (tester) async {
      await hastaElInicio(tester);
      servidor.programar('POST', '/api/logout', RespuestaFalsa.deEjemplo('28_S5_logout'));
      await tester.tap(find.byTooltip('Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('Inicia sesión'), findsOneWidget);
      expect(servidor.veces('POST', '/api/logout'), 1);
    });

    testWidgets('si el servidor dice que la sesión caducó (401), vuelve al login con un aviso', (tester) async {
      await hastaElInicio(tester);
      servidor.programar('GET', '/api/caja/sesion', RespuestaFalsa.deEjemplo('29_S6_sin_sesion_401'));
      final contenedor = ProviderScope.containerOf(tester.element(find.byType(AuthGate)));
      // En una prueba de pantallas el reloj es simulado: un `await` directo sobre la red no avanzaría nunca. Se
      // lanza la petición (que fallará con 401) y `pumpAndSettle` hace correr el tiempo hasta que todo termina.
      var fallo = false;
      contenedor.read(dioProvider).get<dynamic>('/api/caja/sesion').then<void>((_) {}, onError: (Object _) => fallo = true);
      await tester.pumpAndSettle();
      expect(fallo, isTrue);
      expect(find.text('Inicia sesión'), findsOneWidget);
      expect(find.text('Tu sesión terminó. Inicia sesión de nuevo.'), findsOneWidget);
    });
  });
}
