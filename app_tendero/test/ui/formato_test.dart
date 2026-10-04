import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/ui/formato.dart';

void main() {
  group('formatoPesos', () {
    test('agrupa los miles con punto y quita los ".00"', () {
      expect(formatoPesos('50000.00'), r'$50.000');
      expect(formatoPesos('150000.00'), r'$150.000');
      expect(formatoPesos('1234567.00'), r'$1.234.567');
      expect(formatoPesos('999.00'), r'$999');
      expect(formatoPesos('0.00'), r'$0');
    });

    test('muestra los centavos con coma solo si existen', () {
      expect(formatoPesos('4500.50'), r'$4.500,50');
      expect(formatoPesos('0.05'), r'$0,05');
    });

    test('acepta importes sin decimales', () {
      expect(formatoPesos('50000'), r'$50.000');
    });

    test('importes negativos (la diferencia de un arqueo)', () {
      expect(formatoPesos('-2500.00'), r'-$2.500');
    });

    test('un texto raro no se inventa: se devuelve tal cual con el signo \$', () {
      expect(formatoPesos('abc'), r'$abc');
      expect(formatoPesos('1.2.3'), r'$1.2.3');
      expect(formatoPesos(''), r'$');
    });

    test('formatoPesosEnteros', () {
      expect(formatoPesosEnteros(50000), r'$50.000');
      expect(formatoPesosEnteros(0), r'$0');
    });
  });

  group('horaLocal', () {
    test('devuelve HH:MM de una fecha válida', () {
      expect(horaLocal('2026-10-04T15:30:00.000Z'), matches(RegExp(r'^\d{2}:\d{2}$')));
    });

    test('devuelve null si no es una fecha', () {
      expect(horaLocal('no es fecha'), isNull);
    });
  });
}
