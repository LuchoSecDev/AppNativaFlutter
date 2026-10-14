import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/actualizacion/actualizacion_models.dart';
import 'package:stockpilot/actualizacion/actualizacion_providers.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/auth/ui/auth_gate.dart';
import 'package:stockpilot/ui/reloj.dart';

import '../../support/fake_adapter.dart';

/// Las pantallas de actualización, tal como las ve una persona: la app entera (`AuthGate`) con una sesión ya iniciada, un
/// servidor falso con los ejemplos reales y un «navegador» falso que solo anota qué enlace le pidieron abrir.
void main() {
  late ServidorFalso servidor;
  late List<Uri> abiertos;

  /// Abre la app con la sesión iniciada. [instalada]: el `versionCode` instalado (`null` = no se pudo leer). La última
  /// versión publicada del ejemplo es la 3 y la mínima la 2.
  Future<void> abrirApp(
    WidgetTester tester, {
    required int? instalada,
    bool publicada = true,
  }) async {
    servidor = ServidorFalso();
    abiertos = [];
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
    servidor.programar(
      'GET',
      '/api/session-info',
      RespuestaFalsa.deEjemplo('05_S4_session_info'),
    );
    servidor.programar(
      'GET',
      '/api/caja/sesion',
      RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'),
    );
    servidor.programar(
      'GET',
      '/api/app/version',
      RespuestaFalsa.deEjemplo(
        publicada ? '37_U1_version_disponible' : '36_U1_version_sin_configurar',
      ),
    );
    servidor.programar(
      'GET',
      '/api/app/descarga',
      RespuestaFalsa.deEjemplo('39_U2_descarga_ok'),
    );
    servidor.programar(
      'POST',
      '/api/logout',
      RespuestaFalsa.deEjemplo('28_S5_logout'),
    );
    final caducidad = StreamController<void>.broadcast();
    addTearDown(caducidad.close);
    final dio = crearClienteApi(
      baseUrl: 'https://servidor.test',
      cookieJar: CookieJar(),
      adapter: servidor,
      onSessionExpired: () => caducidad.add(null),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          sesionCaducadaProvider.overrideWithValue(caducidad.stream),
          ahoraProvider.overrideWithValue(
            DateTime.parse('2026-10-04T16:30:00.000Z').toLocal(),
          ),
          lectorDeVersionInstaladaProvider.overrideWithValue(
            () async => instalada == null
                ? null
                : VersionInstalada(codigo: instalada, nombre: '1.0.0'),
          ),
          abridorDeEnlacesProvider.overrideWithValue((enlace) async {
            abiertos.add(enlace);
            return true;
          }),
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('versión nueva, pero la instalada todavía sirve (opcional)', () {
    testWidgets(
      'el inicio avisa con el nombre y las notas, y se puede seguir trabajando',
      (tester) async {
        await abrirApp(tester, instalada: 2);
        expect(
          find.text('Hay una versión nueva de StockPilot (1.0.2).'),
          findsOneWidget,
        );
        expect(find.text('Corrige el escáner con poca luz.'), findsOneWidget);
        expect(find.text('Vender'), findsOneWidget); // el inicio sigue ahí
        expect(find.text('Hay que actualizar la app'), findsNothing);
      },
    );

    testWidgets('«Ahora no» quita el aviso y deja el inicio', (tester) async {
      await abrirApp(tester, instalada: 2);
      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hay una versión nueva'), findsNothing);
      expect(find.text('Vender'), findsOneWidget);
    });

    testWidgets(
      '«Descargar» abre en el navegador la dirección que dio el servidor',
      (tester) async {
        await abrirApp(tester, instalada: 2);
        await tester.tap(find.text('Descargar'));
        await tester.pumpAndSettle();
        expect(abiertos, [
          Uri.parse('https://descargas.ejemplo.test/stockpilot-1.0.2.apk'),
        ]);
        expect(servidor.veces('GET', '/api/app/descarga'), 1);
      },
    );
  });

  group(
    'la versión instalada ya no funciona con el servidor (obligatoria)',
    () {
      testWidgets(
        'se muestra la pantalla de actualizar EN LUGAR del inicio: no se puede vender',
        (tester) async {
          await abrirApp(tester, instalada: 1);
          expect(find.text('Hay que actualizar la app'), findsOneWidget);
          expect(find.textContaining('Descarga la 1.0.2'), findsOneWidget);
          expect(find.text('Descargar la versión nueva'), findsOneWidget);
          expect(find.text('Vender'), findsNothing);
          expect(find.text('Consultar productos'), findsNothing);
        },
      );

      testWidgets(
        '«Descargar la versión nueva» abre la dirección en el navegador',
        (tester) async {
          await abrirApp(tester, instalada: 1);
          await tester.tap(find.text('Descargar la versión nueva'));
          await tester.pumpAndSettle();
          expect(abiertos, [
            Uri.parse('https://descargas.ejemplo.test/stockpilot-1.0.2.apk'),
          ]);
        },
      );

      testWidgets('«Cerrar sesión» sigue disponible y lleva al login', (
        tester,
      ) async {
        await abrirApp(tester, instalada: 1);
        await tester.tap(find.text('Cerrar sesión'));
        await tester.pumpAndSettle();
        expect(find.text('Ingresar'), findsOneWidget);
        expect(find.text('Hay que actualizar la app'), findsNothing);
      });
    },
  );

  group('cuando no hay nada que avisar', () {
    testWidgets(
      'la instalada es la última: ni aviso ni pantalla de actualizar',
      (tester) async {
        await abrirApp(tester, instalada: 3);
        expect(find.textContaining('Hay una versión nueva'), findsNothing);
        expect(find.text('Hay que actualizar la app'), findsNothing);
        expect(find.text('Vender'), findsOneWidget);
      },
    );

    testWidgets('todavía no se publicó ninguna versión: todo normal', (
      tester,
    ) async {
      await abrirApp(tester, instalada: 1, publicada: false);
      expect(find.textContaining('Hay una versión nueva'), findsNothing);
      expect(find.text('Hay que actualizar la app'), findsNothing);
      expect(find.text('Vender'), findsOneWidget);
    });

    testWidgets(
      'si no se puede leer la versión instalada ni se consulta ni se molesta',
      (tester) async {
        await abrirApp(tester, instalada: null);
        expect(servidor.veces('GET', '/api/app/version'), 0);
        expect(find.textContaining('Hay una versión nueva'), findsNothing);
        expect(find.text('Hay que actualizar la app'), findsNothing);
        expect(find.text('Vender'), findsOneWidget);
        expect(find.textContaining('StockPilot 1.0.0'), findsNothing);
      },
    );
  });

  group('versión instalada al pie del inicio', () {
    testWidgets(
      'muestra el nombre y el código, para comprobar en un celular real',
      (tester) async {
        await abrirApp(tester, instalada: 3);
        await tester.scrollUntilVisible(
          find.text('StockPilot 1.0.0 (3)'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('StockPilot 1.0.0 (3)'), findsOneWidget);
      },
    );
  });
}
