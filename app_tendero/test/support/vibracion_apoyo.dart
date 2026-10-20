import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los tipos de vibración que Flutter manda al sistema (`HapticFeedbackType.*`).
const vibracionSuave = 'HapticFeedbackType.lightImpact';
const vibracionMedia = 'HapticFeedbackType.mediumImpact';
const vibracionFuerte = 'HapticFeedbackType.heavyImpact';

/// Escucha las vibraciones que pide la app y las devuelve en orden. Sin celular no se puede SENTIR la vibración, pero sí
/// comprobar que se pidió la correcta, en el momento correcto y una sola vez.
List<String> registrarVibraciones(WidgetTester tester) {
  final llamadas = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        llamadas.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return llamadas;
}
