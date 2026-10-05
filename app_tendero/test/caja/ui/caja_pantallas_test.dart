import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/auth/ui/auth_gate.dart';
import 'package:stockpilot/ui/reloj.dart';

import '../../support/fake_adapter.dart';

/// Pruebas de las pantallas de la caja: simulan a una persona tocando y escribiendo, con un servidor falso que
/// responde con los ejemplos reales del backend.
void main() {
  late ServidorFalso servidor;

  /// Abre la app con una sesión ya iniciada (cookie vigente) y las respuestas de la caja que programe cada prueba.
  Future<void> abrirInicio(
    WidgetTester tester,
    void Function(ServidorFalso s) programarCaja, {
    bool esperar = true,
    DateTime? ahora,
  }) async {
    servidor = ServidorFalso();
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
    programarCaja(servidor);
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
          // El reloj se fija: «hoy» o «ayer» dependen del día en que se mira. La caja del ejemplo se abrió el
          // 4-oct-2026 a las 15:30 UTC; por defecto «ahora» es una hora después de esa apertura.
          ahoraProvider.overrideWithValue(
            ahora ?? DateTime.parse('2026-10-04T16:30:00.000Z').toLocal(),
          ),
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    if (esperar) await tester.pumpAndSettle();
  }

  void cajaCerrada(ServidorFalso s) => s.programar(
    'GET',
    '/api/caja/sesion',
    RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'),
  );
  void cajaAbierta(ServidorFalso s) => s.programar(
    'GET',
    '/api/caja/sesion',
    RespuestaFalsa.deEjemplo('10_K1_caja_abierta'),
  );

  /// El botón «Vender» de la pantalla de inicio (es un FilledButton con ícono: se busca por su texto).
  FilledButton botonVender(WidgetTester tester) => tester.widget<FilledButton>(
    find.ancestor(
      of: find.text('Vender'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    ),
  );

  group('pantalla de inicio', () {
    testWidgets(
      'con la caja cerrada: lo dice, ofrece abrirla y el botón «Vender» está bloqueado',
      (tester) async {
        await abrirInicio(tester, cajaCerrada);
        expect(find.text('Caja cerrada'), findsOneWidget);
        expect(find.text('Abrir caja'), findsOneWidget);
        expect(find.text('Abre la caja para vender.'), findsOneWidget);
        expect(botonVender(tester).onPressed, isNull);
      },
    );

    testWidgets(
      'con la caja abierta: muestra el efectivo inicial y «Vender» está activo',
      (tester) async {
        await abrirInicio(tester, cajaAbierta);
        expect(find.text('Caja abierta'), findsOneWidget);
        expect(find.text(r'Efectivo inicial: $50.000'), findsOneWidget);
        expect(find.textContaining('Abierta hoy a las'), findsOneWidget);
        expect(find.textContaining('día anterior'), findsNothing);
        expect(find.text('Abrir caja'), findsNothing);
        expect(botonVender(tester).onPressed, isNotNull);
        await tester.tap(find.text('Vender'));
        await tester.pump();
        expect(
          find.text('La pantalla de venta llega en el siguiente paso.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'una caja que quedó abierta de un día anterior lo dice con la fecha y avisa que hay que cerrarla',
      (tester) async {
        // Tres días después de la apertura: es la caja «olvidada» que no debe leerse como la de hoy.
        await abrirInicio(
          tester,
          cajaAbierta,
          ahora: DateTime.parse('2026-10-07T16:30:00.000Z').toLocal(),
        );
        expect(find.text('Caja abierta'), findsOneWidget);
        expect(find.textContaining('Abierta el 04/10 a las'), findsOneWidget);
        expect(find.textContaining('Abierta hoy'), findsNothing);
        expect(
          find.textContaining('Esta caja se abrió en un día anterior'),
          findsOneWidget,
        );
        expect(
          botonVender(tester).onPressed,
          isNotNull,
        ); // el aviso no bloquea: lo decide la persona
      },
    );

    testWidgets(
      'mientras consulta muestra «Consultando la caja…» y «Vender» bloqueado',
      (tester) async {
        final llega = Completer<void>();
        await abrirInicio(
          tester,
          (s) => s.programar(
            'GET',
            '/api/caja/sesion',
            RespuestaFalsa.demorada(200, const {'active': false}, llega.future),
          ),
          esperar: false,
        );
        // Avanza cuadro a cuadro (sin pumpAndSettle, que no termina con una ruedita girando) hasta ver el estado.
        for (
          var i = 0;
          i < 30 && find.text('Consultando la caja…').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(find.text('Consultando la caja…'), findsOneWidget);
        expect(botonVender(tester).onPressed, isNull);
        llega.complete();
        await tester.pumpAndSettle();
        expect(find.text('Caja cerrada'), findsOneWidget);
      },
    );

    testWidgets(
      'si no se puede consultar: muestra el error y «Reintentar» vuelve a consultar',
      (tester) async {
        await abrirInicio(tester, (s) {
          s.programar(
            'GET',
            '/api/caja/sesion',
            const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
          );
          cajaAbierta(s);
        });
        expect(
          find.textContaining('No hay conexión con el servidor'),
          findsOneWidget,
        );
        expect(botonVender(tester).onPressed, isNull);
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
        expect(find.text('Caja abierta'), findsOneWidget);
      },
    );
  });

  group('abrir la caja', () {
    Finder botonAbrir() => find.widgetWithText(ElevatedButton, 'Abrir caja');

    Future<void> irAAbrir(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Abrir caja'));
      await tester.pumpAndSettle();
      expect(find.text('Efectivo inicial'), findsOneWidget);
    }

    testWidgets('sin escribir nada avisa y no envía', (tester) async {
      await abrirInicio(tester, cajaCerrada);
      await irAAbrir(tester);
      await tester.tap(botonAbrir());
      await tester.pumpAndSettle();
      expect(find.text('Escribe el efectivo inicial'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(servidor.veces('POST', '/api/caja/abrir'), 0);
    });

    testWidgets('el campo solo admite dígitos y hasta 9', (tester) async {
      await abrirInicio(tester, cajaCerrada);
      await irAAbrir(tester);
      await tester.enterText(find.byType(TextFormField), '5a0b');
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '50',
      );
      await tester.enterText(find.byType(TextFormField), '1234567890');
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '123456789',
      );
    });

    testWidgets('pide confirmar el monto; «Corregir» no envía nada', (
      tester,
    ) async {
      await abrirInicio(tester, cajaCerrada);
      await irAAbrir(tester);
      await tester.enterText(find.byType(TextFormField), '50000');
      await tester.tap(botonAbrir());
      await tester.pumpAndSettle();
      expect(
        find.text(r'Vas a abrir la caja con $50.000. ¿Es correcto?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Corregir'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(servidor.veces('POST', '/api/caja/abrir'), 0);
    });

    testWidgets(
      'confirmando: abre la caja, vuelve al inicio y desbloquea «Vender»',
      (tester) async {
        await abrirInicio(tester, (s) {
          cajaCerrada(s);
          cajaAbierta(s);
          s.programar(
            'POST',
            '/api/caja/abrir',
            RespuestaFalsa.deEjemplo('09_K2_abrir_caja'),
          );
        });
        await irAAbrir(tester);
        await tester.enterText(find.byType(TextFormField), '50000');
        await tester.tap(botonAbrir());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sí, abrir'));
        await tester.pumpAndSettle();

        expect(
          servidor.peticiones
              .where((p) => p.clave == 'POST /api/caja/abrir')
              .single
              .cuerpo,
          {'monto_apertura': 50000},
        );
        expect(find.text('Efectivo inicial'), findsNothing); // volvió al inicio
        expect(find.text('Caja abierta'), findsOneWidget);
        expect(find.text(r'Efectivo inicial: $50.000'), findsOneWidget);
        expect(botonVender(tester).onPressed, isNotNull);
      },
    );

    testWidgets('se puede abrir con 0', (tester) async {
      await abrirInicio(tester, (s) {
        cajaCerrada(s);
        cajaAbierta(s);
        s.programar(
          'POST',
          '/api/caja/abrir',
          RespuestaFalsa.deEjemplo('09_K2_abrir_caja'),
        );
      });
      await irAAbrir(tester);
      await tester.enterText(find.byType(TextFormField), '0');
      await tester.tap(botonAbrir());
      await tester.pumpAndSettle();
      expect(
        find.text(r'Vas a abrir la caja con $0. ¿Es correcto?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Sí, abrir'));
      await tester.pumpAndSettle();
      expect(
        servidor.peticiones
            .where((p) => p.clave == 'POST /api/caja/abrir')
            .single
            .cuerpo,
        {'monto_apertura': 0},
      );
    });

    testWidgets(
      'si el servidor rechaza el monto: muestra su mensaje y se queda en la pantalla',
      (tester) async {
        await abrirInicio(tester, (s) {
          cajaCerrada(s);
          s.programar(
            'POST',
            '/api/caja/abrir',
            const RespuestaFalsa(400, {
              'error': 'El monto de apertura no es válido.',
            }),
          );
        });
        await irAAbrir(tester);
        await tester.enterText(find.byType(TextFormField), '100');
        await tester.tap(botonAbrir());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sí, abrir'));
        await tester.pumpAndSettle();
        expect(find.text('El monto de apertura no es válido.'), findsWidgets);
        expect(
          find.text('Efectivo inicial'),
          findsOneWidget,
        ); // sigue en la pantalla de apertura
      },
    );
  });
}
