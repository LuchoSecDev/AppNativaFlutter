import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/scan_stabilizer.dart';

void main() {
  group('ScanStabilizer', () {
    test('confirma un código al leerlo 3 veces seguidas, no antes', () {
      final s = ScanStabilizer();
      expect(s.register('7701234000011'), isNull);
      expect(s.register('7701234000011'), isNull);
      expect(s.register('7701234000011'), '7701234000011');
    });

    test('un código distinto reinicia la cuenta', () {
      final s = ScanStabilizer();
      s.register('AAA');
      s.register('AAA');
      expect(s.register('BBB'), isNull); // reinicia: BBB lleva 1 lectura
      expect(s.register('AAA'), isNull); // AAA vuelve a empezar desde 1
      expect(s.register('AAA'), isNull);
      expect(s.register('AAA'), 'AAA');
    });

    test('un código ya confirmado no se vuelve a confirmar hasta hacer reset', () {
      final s = ScanStabilizer();
      for (var i = 0; i < 2; i++) {
        s.register('AAA');
      }
      expect(s.register('AAA'), 'AAA');
      expect(s.register('AAA'), isNull);
      expect(s.register('AAA'), isNull);
    });

    test('tras reset se puede confirmar de nuevo el mismo código («Escanear otro»)', () {
      final s = ScanStabilizer();
      for (var i = 0; i < 3; i++) {
        s.register('AAA');
      }
      s.reset();
      expect(s.register('AAA'), isNull);
      expect(s.register('AAA'), isNull);
      expect(s.register('AAA'), 'AAA');
    });

    test('el número de lecturas es configurable', () {
      final s = ScanStabilizer(requiredReads: 1);
      expect(s.register('AAA'), 'AAA');
    });

    test('requiredReads debe ser mayor que 0', () {
      expect(() => ScanStabilizer(requiredReads: 0), throwsA(isA<AssertionError>()));
    });
  });
}
