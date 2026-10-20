import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/ui/avisos.dart';
import 'package:stockpilot/ui/retroalimentacion.dart';

import '../support/vibracion_apoyo.dart';

/// La vibración: qué se pide, cuándo y cuántas veces.
void main() {
  group('vibrar', () {
    testWidgets('cada intensidad pide la vibración de Flutter que le toca', (
      tester,
    ) async {
      final llamadas = registrarVibraciones(tester);
      vibrar(Intensidad.suave);
      vibrar(Intensidad.media);
      vibrar(Intensidad.fuerte);
      await tester.pump();
      expect(llamadas, [vibracionSuave, vibracionMedia, vibracionFuerte]);
    });
  });

  group('los avisos vibran según su tipo', () {
    Future<void> abrir(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  for (final tipo in TipoAviso.values)
                    TextButton(
                      onPressed: () => mostrarAviso(
                        context,
                        'Aviso ${tipo.name}',
                        tipo: tipo,
                      ),
                      child: Text('mostrar ${tipo.name}'),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    const esperado = {
      'exito': vibracionSuave,
      'aviso': vibracionMedia,
      'error': vibracionFuerte,
    };
    for (final e in esperado.entries) {
      testWidgets('${e.key}: vibra ${e.value} una sola vez', (tester) async {
        final llamadas = registrarVibraciones(tester);
        await abrir(tester);
        await tester.tap(find.text('mostrar ${e.key}'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(llamadas, [e.value]);
      });
    }

    testWidgets('dos avisos seguidos vibran dos veces, una por cada uno', (
      tester,
    ) async {
      final llamadas = registrarVibraciones(tester);
      await abrir(tester);
      await tester.tap(find.text('mostrar exito'));
      await tester.pump();
      await tester.tap(find.text('mostrar error'));
      await tester.pump();
      expect(llamadas, [vibracionSuave, vibracionFuerte]);
    });

    testWidgets('el aviso sigue mostrándose aunque la vibración falle', (
      tester,
    ) async {
      // Sin ningún oyente de la vibración (como un celular sin motor): el aviso se ve igual.
      await abrir(tester);
      await tester.tap(find.text('mostrar error'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Aviso error'), findsOneWidget);
    });
  });

  group('VibrarAlAparecer', () {
    testWidgets('vibra una vez al aparecer y no al redibujarse el padre', (
      tester,
    ) async {
      final llamadas = registrarVibraciones(tester);
      late StateSetter redibujar;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              redibujar = setState;
              return const VibrarAlAparecer(
                intensidad: Intensidad.media,
                child: Text('comprobante'),
              );
            },
          ),
        ),
      );
      expect(llamadas, [vibracionMedia]);
      redibujar(() {});
      await tester.pump();
      redibujar(() {});
      await tester.pump();
      expect(llamadas, [
        vibracionMedia,
      ], reason: 'redibujar no vuelve a vibrar');
      expect(find.text('comprobante'), findsOneWidget);
    });

    testWidgets('si se quita y se vuelve a poner, vibra otra vez', (
      tester,
    ) async {
      final llamadas = registrarVibraciones(tester);
      late StateSetter redibujar;
      var visible = true;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              redibujar = setState;
              return visible
                  ? const VibrarAlAparecer(
                      intensidad: Intensidad.fuerte,
                      child: Text('rechazo'),
                    )
                  : const SizedBox();
            },
          ),
        ),
      );
      expect(llamadas, [vibracionFuerte]);
      redibujar(() => visible = false);
      await tester.pump();
      redibujar(() => visible = true);
      await tester.pump();
      expect(llamadas, [vibracionFuerte, vibracionFuerte]);
    });
  });
}
