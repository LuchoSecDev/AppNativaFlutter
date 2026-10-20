import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/egresos/ui/registrar_egreso_screen.dart';

import 'egreso_apoyo.dart';

/// Abre una pantalla con el cliente HTTP REAL y el servidor falso del [EntornoDeEgresos]. Si [pantalla] es la de
/// registrar, la abre encima de una pantalla de inicio con un botón (como en la app), para poder «volver».
Future<void> abrirPantallaDeEgresos(
  WidgetTester tester,
  EntornoDeEgresos entorno, {
  Widget? pantalla,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: entorno.overrides(),
      child: MaterialApp(home: pantalla ?? const _Inicio()),
    ),
  );
  await tester.pumpAndSettle();
}

ProviderContainer contenedorDe(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

/// Una pantalla de inicio mínima: un botón que abre el registro de gastos, y se puede volver a ella.
class _Inicio extends StatelessWidget {
  const _Inicio();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const RegistrarEgresoScreen(),
          ),
        ),
        child: const Text('Abrir gasto'),
      ),
    ),
  );
}

Future<void> abrirRegistro(WidgetTester tester) async {
  await tester.tap(find.text('Abrir gasto'));
  await tester.pumpAndSettle();
}
