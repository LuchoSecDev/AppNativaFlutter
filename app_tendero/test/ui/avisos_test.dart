import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/ui/avisos.dart';
import 'package:stockpilot/ui/colores.dart';

/// Los avisos flotantes: cómo se ven, cuánto duran y cómo se cierran.
void main() {
  /// Una pantalla con un botón por tipo de aviso y un botón «Cobrar» debajo (lo que el aviso podría tapar).
  Future<void> abrir(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                for (final tipo in TipoAviso.values)
                  TextButton(
                    onPressed: () =>
                        mostrarAviso(context, 'Aviso ${tipo.name}', tipo: tipo),
                    child: Text('mostrar ${tipo.name}'),
                  ),
                TextButton(
                  onPressed: () => mostrarAviso(
                    context,
                    'Otro aviso',
                    tipo: TipoAviso.exito,
                  ),
                  child: const Text('mostrar otro'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Avanza el reloj en pasos de 100 ms. Un solo `pump` largo es engañoso: el temporizador del aviso nace cuando
  /// termina su animación de entrada, y con un salto grande ese momento cae al final del salto.
  Future<void> avanzar(WidgetTester tester, Duration total) async {
    for (
      var t = Duration.zero;
      t < total;
      t += const Duration(milliseconds: 100)
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mostrar(WidgetTester tester, String tipo) async {
    await tester.tap(find.text('mostrar $tipo'));
    await tester.pump(); // aparece
    await tester.pump(const Duration(milliseconds: 300)); // termina de entrar
  }

  testWidgets('es flotante y redondeado, no una barra pegada al borde', (
    tester,
  ) async {
    await abrir(tester);
    await mostrar(tester, 'exito');
    final barra = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(barra.behavior, SnackBarBehavior.floating);
    expect(barra.margin, isNotNull, reason: 'separado de los bordes');
    expect(barra.shape, isA<RoundedRectangleBorder>());
  });

  testWidgets('cada tipo trae su ícono y su color', (tester) async {
    await abrir(tester);
    const esperado = {
      'exito': (Icons.check_circle_rounded, Colores.exito),
      'aviso': (Icons.warning_amber_rounded, Colores.aviso),
      'error': (Icons.error_rounded, Colores.peligro),
    };
    for (final e in esperado.entries) {
      await mostrar(tester, e.key);
      expect(find.text('Aviso ${e.key}'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byIcon(e.value.$1),
        ),
        findsOneWidget,
        reason: 'ícono de ${e.key}',
      );
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        e.value.$2,
      );
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold)))
          .clearSnackBars();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('un éxito se va solo a los 2 s', (tester) async {
    await abrir(tester);
    await mostrar(tester, 'exito');
    await avanzar(tester, const Duration(milliseconds: 1500));
    expect(find.text('Aviso exito'), findsOneWidget, reason: 'aún a la vista');
    await avanzar(
      tester,
      const Duration(milliseconds: 1000),
    ); // 2,5 s después de entrar
    expect(find.text('Aviso exito'), findsNothing);
  });

  for (final tipo in ['aviso', 'error']) {
    testWidgets('un $tipo dura más: sigue a los 3 s y se va a los 3,5 s', (
      tester,
    ) async {
      await abrir(tester);
      await mostrar(tester, tipo);
      await avanzar(tester, const Duration(milliseconds: 2800)); // 3 s en total
      expect(find.text('Aviso $tipo'), findsOneWidget);
      await avanzar(tester, const Duration(milliseconds: 1000)); // 4 s en total
      expect(find.text('Aviso $tipo'), findsNothing);
    });
  }

  testWidgets('tocarlo en cualquier parte lo cierra al instante', (
    tester,
  ) async {
    await abrir(tester);
    await mostrar(tester, 'error');
    // En el ícono, no en el texto: el toque debe cubrir todo el aviso.
    await tester.tap(find.byIcon(Icons.error_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Aviso error'), findsNothing);
  });

  testWidgets(
    'tocar el borde (el relleno, sin texto ni ícono) también lo cierra',
    (tester) async {
      await abrir(tester);
      await mostrar(tester, 'error');
      final relleno = find.byWidgetPredicate(
        (w) =>
            w is Padding &&
            w.padding ==
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
      // 4 px dentro del borde izquierdo, a media altura: ahí no hay ni texto ni ícono, solo relleno. (No en la
      // esquina: las esquinas redondeadas se recortan y no reciben toques.)
      final area = tester.getRect(relleno);
      await tester.tapAt(Offset(area.left + 4, area.center.dy));
      await tester.pumpAndSettle();
      expect(find.text('Aviso error'), findsNothing);
    },
  );

  testWidgets('deslizarlo hacia un lado también lo cierra', (tester) async {
    await abrir(tester);
    await mostrar(tester, 'error');
    await tester.drag(find.text('Aviso error'), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Aviso error'), findsNothing);
  });

  testWidgets('un aviso nuevo reemplaza al anterior en vez de hacer cola', (
    tester,
  ) async {
    await abrir(tester);
    await mostrar(tester, 'error');
    await tester.tap(find.text('mostrar otro'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Otro aviso'), findsOneWidget);
    expect(find.text('Aviso error'), findsNothing);
    // Y el nuevo dura lo suyo (2 s más las animaciones), no lo del anterior ni lo de los dos sumados.
    await avanzar(tester, const Duration(milliseconds: 3500));
    expect(find.text('Otro aviso'), findsNothing);
  });
}
