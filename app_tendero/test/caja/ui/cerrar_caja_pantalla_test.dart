import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/caja/ui/cerrar_caja_screen.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/home_screen.dart';
import 'package:stockpilot/venta/venta_providers.dart';

import '../../support/carrito_apoyo.dart';
import '../../support/fake_adapter.dart';

/// La pantalla de cerrar la caja (contar → ver la diferencia → confirmar o recontar), con el cliente HTTP REAL y un
/// servidor falso con los ejemplos reales del backend.
void main() {
  const arqueo = '/api/caja/arqueo-previo';
  const cerrar = '/api/caja/cerrar';

  late ServidorFalso servidor;

  RespuestaFalsa arqueoCon({
    required int declarado,
    int esperado = 49000,
    int ventas = 9000,
    bool alCerrar = false,
  }) => RespuestaFalsa(200, {
    'success': true,
    if (alCerrar) 'message': 'Caja cerrada exitosamente (Arqueo completo)',
    'arqueo': {
      'monto_apertura': 50000,
      'ventas_efectivo': ventas,
      'abonos_efectivo': 0,
      'egresos': 10000,
      'monto_cierre_calculado': esperado,
      'monto_cierre_declarado': declarado,
      'diferencia': declarado - esperado,
    },
  });

  void programarCajaCerrada() => servidor.programar(
    'GET',
    '/api/caja/sesion',
    RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'),
  );

  Future<void> abrir(
    WidgetTester tester, {
    Widget pantalla = const CerrarCajaScreen(),
    bool cajaAbierta = true,
    List<RespuestaFalsa>? respuestasDeCaja,
  }) async {
    // Una pantalla alta, como un celular: el paso 2 es largo y la prueba no desplaza.
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    servidor = ServidorFalso();
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
    servidor.programar(
      'GET',
      '/api/productos',
      RespuestaFalsa.deEjemplo('13_C1_lista_de_productos'),
    );
    // La pantalla del cierre no consulta la caja al abrirse: la primera respuesta se gasta cuando ocurra la primera
    // consulta, así que las pruebas que la necesitan fijan el orden con [respuestasDeCaja].
    for (final r
        in respuestasDeCaja ??
            [
              RespuestaFalsa.deEjemplo(
                cajaAbierta ? '10_K1_caja_abierta' : '07_K1_caja_sin_abrir',
              ),
            ]) {
      servidor.programar('GET', '/api/caja/sesion', r);
    }
    final dio = crearClienteApi(
      baseUrl: 'https://servidor.test',
      cookieJar: CookieJar(),
      adapter: servidor,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          sesionProvider.overrideWith(() => SesionFija(sesionActiva())),
          almacenCarritoProvider.overrideWithValue(AlmacenEnMemoria()),
          almacenVentaPendienteProvider.overrideWithValue(
            AlmacenVentaEnMemoria(),
          ),
        ],
        child: MaterialApp(home: pantalla),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder campo() => find.widgetWithText(TextField, 'Efectivo contado');

  Future<void> contar(WidgetTester tester, String pesos) async {
    await tester.enterText(campo(), pesos);
    await tester.pump();
  }

  Future<void> verArqueo(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, 'Ver arqueo'));
    await tester.pumpAndSettle();
  }

  Future<void> hastaRevisar(WidgetTester tester) async {
    servidor.programar(
      'POST',
      arqueo,
      RespuestaFalsa.deEjemplo('30_K5_arqueo_previo'),
    );
    await contar(tester, '57500');
    await verArqueo(tester);
    expect(find.text('Revisar arqueo'), findsOneWidget);
  }

  group('paso 1: contar', () {
    testWidgets(
      'el campo solo admite dígitos y hasta 9; sin escribir nada pide el monto y NO consulta',
      (tester) async {
        await abrir(tester);
        await contar(tester, '12ab.-3456789012');
        expect(tester.widget<TextField>(campo()).controller!.text, '123456789');

        await contar(tester, '');
        await verArqueo(tester);
        expect(
          find.text(
            'Escribe cuánto contaste en el cajón (0 si no hay efectivo).',
          ),
          findsOneWidget,
        );
        expect(servidor.veces('POST', arqueo), 0);
      },
    );

    testWidgets('el 0 es un monto válido (cajón vacío)', (tester) async {
      await abrir(tester);
      servidor.programar('POST', arqueo, arqueoCon(declarado: 0));
      await contar(tester, '0');
      await verArqueo(tester);
      expect(find.text('Revisar arqueo'), findsOneWidget);
      expect(find.text('Falta'), findsOneWidget);
      expect(find.text(r'Faltan $49.000 en el cajón.'), findsOneWidget);
    });

    testWidgets(
      'monto rechazado por el servidor: muestra su mensaje y se queda en el paso 1',
      (tester) async {
        await abrir(tester);
        servidor.programar(
          'POST',
          arqueo,
          RespuestaFalsa.deEjemplo('31_K5_monto_invalido_400'),
        );
        await contar(tester, '1');
        await verArqueo(tester);
        expect(
          find.text('El monto de cierre declarado no es válido.'),
          findsOneWidget,
        );
        expect(find.text('Ver arqueo'), findsOneWidget);
      },
    );

    testWidgets('sin conexión: mensaje claro y se puede reintentar', (
      tester,
    ) async {
      await abrir(tester);
      servidor.programar(
        'POST',
        arqueo,
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      await contar(tester, '57500');
      await verArqueo(tester);
      expect(find.textContaining('No hay conexión'), findsOneWidget);
      expect(servidor.veces('POST', cerrar), 0);

      servidor.programar(
        'POST',
        arqueo,
        RespuestaFalsa.deEjemplo('30_K5_arqueo_previo'),
      );
      await verArqueo(tester);
      expect(find.text('Revisar arqueo'), findsOneWidget);
    });
  });

  group('paso 2: ver la diferencia', () {
    testWidgets(
      'muestra de dónde sale lo que debería haber, lo contado y la diferencia; NO cierra la caja',
      (tester) async {
        await abrir(tester);
        await hastaRevisar(tester);

        expect(find.text('Fondo inicial'), findsOneWidget);
        expect(find.text(r'$50.000'), findsOneWidget);
        expect(find.text('+ Ventas en efectivo'), findsOneWidget);
        // $9.000 sale dos veces: en la cuenta del cajón y en la línea «Efectivo» del desglose por método.
        expect(find.text(r'$9.000'), findsNWidgets(2));
        expect(find.text('+ Abonos en efectivo'), findsOneWidget);
        expect(find.text('− Egresos (gastos)'), findsOneWidget);
        expect(find.text(r'$10.000'), findsOneWidget);
        expect(find.text('Debería haber'), findsOneWidget);
        expect(find.text(r'$49.000'), findsOneWidget);
        expect(find.text('Tú contaste'), findsOneWidget);
        expect(find.text(r'$57.500'), findsOneWidget);
        expect(find.text('Sobra'), findsOneWidget);
        expect(find.text(r'Hay $8.500 de más en el cajón.'), findsOneWidget);
        expect(
          find.textContaining('Solo el efectivo entra al cajón'),
          findsOneWidget,
        );
        expect(servidor.veces('POST', cerrar), 0);
      },
    );

    testWidgets(
      '«Cuadra» cuando coincide, «Falta» cuando falta (con el monto sin signo menos)',
      (tester) async {
        await abrir(tester);
        servidor.programar('POST', arqueo, arqueoCon(declarado: 49000));
        await contar(tester, '49000');
        await verArqueo(tester);
        expect(find.text('Cuadra'), findsOneWidget);

        await tester.tap(find.widgetWithText(OutlinedButton, 'Recontar'));
        await tester.pumpAndSettle();
        servidor.programar('POST', arqueo, arqueoCon(declarado: 40000));
        await contar(tester, '40000');
        await verArqueo(tester);
        expect(find.text('Falta'), findsOneWidget);
        expect(find.text(r'Faltan $9.000 en el cajón.'), findsOneWidget);
      },
    );

    testWidgets('«Recontar» vuelve al campo con lo escrito, sin cerrar nada', (
      tester,
    ) async {
      await abrir(tester);
      await hastaRevisar(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Recontar'));
      await tester.pumpAndSettle();

      expect(find.text('Cerrar caja'), findsOneWidget);
      expect(tester.widget<TextField>(campo()).controller!.text, '57500');
      expect(servidor.veces('POST', cerrar), 0);
    });
  });

  group('desglose por método de pago (auditoría)', () {
    // Un turno con efectivo, tarjeta, un fiado y abonos (uno en efectivo, otro por transferencia).
    const unTurnoVariado = RespuestaFalsa(200, {
      'success': true,
      'arqueo': {
        'monto_apertura': 50000,
        'ventas_efectivo': 13500,
        'abonos_efectivo': 2000,
        'egresos': 10000,
        'monto_cierre_calculado': 55500,
        'monto_cierre_declarado': 55500,
        'diferencia': 0,
        'ventas_por_metodo': {
          'Efectivo': {'cantidad': 2, 'total': 13500},
          'Tarjeta': {'cantidad': 1, 'total': 4500},
          'Transferencia': {'cantidad': 0, 'total': 0},
          'Fiado': {'cantidad': 1, 'total': 4500},
          'Otro': {'cantidad': 0, 'total': 0},
        },
        'abonos_por_metodo': {
          'Efectivo': {'cantidad': 1, 'total': 2000},
          'Tarjeta': {'cantidad': 0, 'total': 0},
          'Transferencia': {'cantidad': 1, 'total': 3000},
          'Otro': {'cantidad': 0, 'total': 0},
        },
      },
    });

    testWidgets(
      'el paso 2 separa lo vendido por método y marca lo que NO entra al cajón (tarjeta, transferencia, fiado)',
      (tester) async {
        await abrir(tester);
        servidor.programar('POST', arqueo, unTurnoVariado);
        await contar(tester, '55500');
        await verArqueo(tester);

        expect(
          find.text('Lo vendido en el turno, por método de pago'),
          findsOneWidget,
        );
        expect(find.textContaining('Efectivo · 2 ventas'), findsOneWidget);
        expect(
          find.textContaining('Tarjeta · 1 venta · no entra al cajón'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Fiado (crédito) · 1 venta · no entra al cajón'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Transferencia ·'),
          findsOneWidget,
          reason: 'solo el de los abonos: no hubo ventas por transferencia',
        );
        expect(
          find.textContaining('Otro método'),
          findsNothing,
          reason: 'sin movimiento no se muestra',
        );
        expect(
          find.text(r'$13.500'),
          findsNWidgets(2),
        ); // la cuenta del cajón y la línea de efectivo
        expect(find.text(r'$4.500'), findsNWidgets(2)); // tarjeta y fiado
        expect(find.text('Abonos de clientes'), findsOneWidget);
        expect(
          find.textContaining('Transferencia · 1 abono · no entra al cajón'),
          findsOneWidget,
        );
        expect(find.text(r'$3.000'), findsOneWidget);
      },
    );

    testWidgets('el comprobante del cierre también lo muestra', (tester) async {
      await abrir(tester);
      servidor.programar('POST', arqueo, unTurnoVariado);
      await contar(tester, '55500');
      await verArqueo(tester);
      programarCajaCerrada();
      servidor.programar('POST', cerrar, unTurnoVariado);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar cierre'));
      await tester.pumpAndSettle();

      expect(
        find.text('Lo vendido en el turno, por método de pago'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Tarjeta · 1 venta · no entra al cajón'),
        findsOneWidget,
      );
    });

    testWidgets('un turno sin ventas lo dice (no deja el bloque vacío)', (
      tester,
    ) async {
      await abrir(tester);
      servidor.programar(
        'POST',
        arqueo,
        const RespuestaFalsa(200, {
          'success': true,
          'arqueo': {
            'monto_apertura': 50000,
            'ventas_efectivo': 0,
            'abonos_efectivo': 0,
            'egresos': 0,
            'monto_cierre_calculado': 50000,
            'monto_cierre_declarado': 50000,
            'diferencia': 0,
            'ventas_por_metodo': {
              'Efectivo': {'cantidad': 0, 'total': 0},
              'Tarjeta': {'cantidad': 0, 'total': 0},
              'Transferencia': {'cantidad': 0, 'total': 0},
              'Fiado': {'cantidad': 0, 'total': 0},
              'Otro': {'cantidad': 0, 'total': 0},
            },
            'abonos_por_metodo': {
              'Efectivo': {'cantidad': 0, 'total': 0},
            },
          },
        }),
      );
      await contar(tester, '50000');
      await verArqueo(tester);
      expect(find.text('Sin ventas en este turno.'), findsOneWidget);
      expect(find.text('Abonos de clientes'), findsNothing);
    });

    testWidgets(
      'con un servidor anterior al desglose (sin esos campos) el arqueo se ve igual y no aparece el bloque',
      (tester) async {
        await abrir(tester);
        servidor.programar(
          'POST',
          arqueo,
          const RespuestaFalsa(200, {
            'success': true,
            'arqueo': {
              'monto_apertura': 50000,
              'ventas_efectivo': 9000,
              'abonos_efectivo': 0,
              'egresos': 10000,
              'monto_cierre_calculado': 49000,
              'monto_cierre_declarado': 57500,
              'diferencia': 8500,
            },
          }),
        );
        await contar(tester, '57500');
        await verArqueo(tester);
        expect(find.text('Revisar arqueo'), findsOneWidget);
        expect(find.text('Debería haber'), findsOneWidget);
        expect(
          find.text('Lo vendido en el turno, por método de pago'),
          findsNothing,
        );
      },
    );
  });

  group('paso 3: confirmar', () {
    testWidgets(
      '«Confirmar cierre»: comprobante con el arqueo final; «Volver al inicio» sale',
      (tester) async {
        await abrir(tester, pantalla: const _Inicio());
        await tester.tap(find.text('Abrir cierre'));
        await tester.pumpAndSettle();
        await hastaRevisar(tester);

        programarCajaCerrada();
        servidor.programar(
          'POST',
          cerrar,
          RespuestaFalsa.deEjemplo('27_K3_cerrar_caja'),
        );
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Confirmar cierre'),
        );
        await tester.pumpAndSettle();

        expect(find.text('Caja cerrada'), findsWidgets);
        expect(find.text('Sobra'), findsOneWidget);
        expect(find.text(r'$57.500'), findsOneWidget);
        expect(find.textContaining('Mientras revisabas'), findsNothing);
        expect(servidor.veces('POST', cerrar), 1);
        expect(
          servidor.peticiones
              .firstWhere((p) => p.clave == 'POST $cerrar')
              .cuerpo,
          {'monto_cierre_declarado': 57500},
        );

        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Volver al inicio'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Abrir cierre'), findsOneWidget);
      },
    );

    testWidgets(
      'si cambió algo mientras revisaba, muestra el arqueo FINAL y lo avisa',
      (tester) async {
        await abrir(tester);
        await hastaRevisar(tester);
        programarCajaCerrada();
        servidor.programar(
          'POST',
          cerrar,
          arqueoCon(
            declarado: 57500,
            esperado: 53500,
            ventas: 13500,
            alCerrar: true,
          ),
        );
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Confirmar cierre'),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Mientras revisabas se registró un movimiento'),
          findsOneWidget,
        );
        expect(find.text(r'$53.500'), findsOneWidget);
        expect(find.text(r'Hay $4.000 de más en el cajón.'), findsOneWidget);
      },
    );

    testWidgets(
      'si se perdió la respuesta y la caja SÍ se cerró: lo dice (sin arqueo) y no vuelve a enviar el cierre',
      (tester) async {
        // La consulta que sigue al fallo del cierre encuentra la caja ya cerrada.
        await abrir(
          tester,
          respuestasDeCaja: [RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir')],
        );
        await hastaRevisar(tester);
        servidor.programar(
          'POST',
          cerrar,
          const RespuestaFalsa.falloDeRed(DioExceptionType.receiveTimeout),
        );
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Confirmar cierre'),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('La caja se cerró, pero no llegó el resumen'),
          findsOneWidget,
        );
        expect(servidor.veces('POST', cerrar), 1);
      },
    );

    testWidgets(
      'si no se sabe si se cerró: solo ofrece «Comprobar» (nunca cerrar de nuevo)',
      (tester) async {
        // Ni el cierre ni la primera consulta de la caja llegan; la segunda («Comprobar») sí, y dice «cerrada».
        await abrir(
          tester,
          respuestasDeCaja: [
            const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
            RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'),
          ],
        );
        await hastaRevisar(tester);
        servidor.programar(
          'POST',
          cerrar,
          const RespuestaFalsa.falloDeRed(DioExceptionType.receiveTimeout),
        );
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Confirmar cierre'),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('no la cierres otra vez'), findsOneWidget);
        expect(
          find.widgetWithText(ElevatedButton, 'Confirmar cierre'),
          findsNothing,
        );

        await tester.tap(find.widgetWithText(ElevatedButton, 'Comprobar'));
        await tester.pumpAndSettle();
        expect(find.textContaining('La caja se cerró'), findsOneWidget);
        expect(servidor.veces('POST', cerrar), 1);
      },
    );
  });

  group('salir y volver a entrar', () {
    testWidgets(
      'salir a media revisión y volver a entrar empieza de cero (paso 1, campo vacío)',
      (tester) async {
        await abrir(tester, pantalla: const _Inicio());
        await tester.tap(find.text('Abrir cierre'));
        await tester.pumpAndSettle();
        await hastaRevisar(tester);

        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Abrir cierre'));
        await tester.pumpAndSettle();

        expect(find.text('Ver arqueo'), findsOneWidget);
        expect(find.text('Revisar arqueo'), findsNothing);
        expect(tester.widget<TextField>(campo()).controller!.text, isEmpty);
      },
    );
  });

  group('salir mientras se calcula', () {
    testWidgets(
      'si se sale mientras se pide el arqueo y la respuesta llega después, al volver a entrar se empieza de cero',
      (tester) async {
        await abrir(tester, pantalla: const _Inicio());
        await tester.tap(find.text('Abrir cierre'));
        await tester.pumpAndSettle();

        final llega = Completer<void>();
        servidor.programar(
          'POST',
          arqueo,
          RespuestaFalsa.demorada(
            200,
            arqueoCon(declarado: 57500).cuerpo,
            llega.future,
          ),
        );
        await contar(tester, '57500');
        await tester.tap(find.widgetWithText(ElevatedButton, 'Ver arqueo'));
        await tester.pump();

        // El Tendero sale con el botón «atrás» del sistema mientras espera.
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
        llega.complete();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Abrir cierre'));
        await tester.pumpAndSettle();
        expect(find.text('Ver arqueo'), findsOneWidget);
        expect(find.text('Revisar arqueo'), findsNothing);
        expect(tester.widget<TextField>(campo()).controller!.text, isEmpty);
      },
    );
  });

  group('desde el inicio', () {
    testWidgets(
      'con la caja abierta hay un botón «Cerrar caja» que abre la pantalla del cierre',
      (tester) async {
        await abrir(tester, pantalla: const HomeScreen());
        expect(
          find.widgetWithText(OutlinedButton, 'Cerrar caja'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(OutlinedButton, 'Cerrar caja'));
        await tester.pumpAndSettle();
        expect(campo(), findsOneWidget);
        expect(find.text('Ver arqueo'), findsOneWidget);
      },
    );

    testWidgets('con la caja cerrada no hay botón de cerrarla', (tester) async {
      await abrir(tester, pantalla: const HomeScreen(), cajaAbierta: false);
      expect(find.widgetWithText(OutlinedButton, 'Cerrar caja'), findsNothing);
    });

    testWidgets(
      'tras cerrar, el inicio muestra «Caja cerrada» y bloquea Vender',
      (tester) async {
        await abrir(tester, pantalla: const HomeScreen());
        await tester.tap(find.widgetWithText(OutlinedButton, 'Cerrar caja'));
        await tester.pumpAndSettle();
        await hastaRevisar(tester);
        programarCajaCerrada();
        servidor.programar(
          'POST',
          cerrar,
          RespuestaFalsa.deEjemplo('27_K3_cerrar_caja'),
        );
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Confirmar cierre'),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Volver al inicio'),
        );
        await tester.pumpAndSettle();

        expect(find.text('Caja cerrada'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Vender'))
              .onPressed,
          isNull,
        );
      },
    );
  });
}

/// Una pantalla de inicio mínima para abrir el cierre y poder volver.
class _Inicio extends StatelessWidget {
  const _Inicio();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CerrarCajaScreen()),
        ),
        child: const Text('Abrir cierre'),
      ),
    ),
  );
}
