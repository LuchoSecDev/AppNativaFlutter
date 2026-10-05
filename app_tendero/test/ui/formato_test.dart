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

    test(
      'un texto raro no se inventa: se devuelve tal cual con el signo \$',
      () {
        expect(formatoPesos('abc'), r'$abc');
        expect(formatoPesos('1.2.3'), r'$1.2.3');
        expect(formatoPesos(''), r'$');
      },
    );

    test('formatoPesosEnteros', () {
      expect(formatoPesosEnteros(50000), r'$50.000');
      expect(formatoPesosEnteros(0), r'$0');
    });
  });

  group('descripcionDeFecha y esDeUnDiaAnterior', () {
    // Fechas construidas en hora LOCAL y pasadas a ISO UTC: así la prueba da lo mismo en cualquier zona horaria.
    String iso(int a, int m, int d, int h, int min) =>
        DateTime(a, m, d, h, min).toUtc().toIso8601String();
    final ahora = DateTime(2026, 10, 4, 18, 0);

    test('el mismo día: «hoy a las HH:MM»', () {
      expect(
        descripcionDeFecha(iso(2026, 10, 4, 15, 27), ahora: ahora),
        'hoy a las 15:27',
      );
      expect(
        esDeUnDiaAnterior(iso(2026, 10, 4, 15, 27), ahora: ahora),
        isFalse,
      );
    });

    test('el día anterior: «ayer a las HH:MM»', () {
      expect(
        descripcionDeFecha(iso(2026, 10, 3, 8, 5), ahora: ahora),
        'ayer a las 08:05',
      );
      expect(esDeUnDiaAnterior(iso(2026, 10, 3, 8, 5), ahora: ahora), isTrue);
    });

    test('antes de ayer: «el DD/MM a las HH:MM»', () {
      expect(
        descripcionDeFecha(iso(2026, 9, 28, 23, 59), ahora: ahora),
        'el 28/09 a las 23:59',
      );
      expect(esDeUnDiaAnterior(iso(2026, 9, 28, 23, 59), ahora: ahora), isTrue);
    });

    test('la medianoche cuenta como otro día aunque pasen pocas horas', () {
      final pasadaLaMedianoche = DateTime(2026, 10, 5, 0, 10);
      expect(
        descripcionDeFecha(iso(2026, 10, 4, 23, 50), ahora: pasadaLaMedianoche),
        'ayer a las 23:50',
      );
    });

    test('un texto que no es fecha: null y no es «de un día anterior»', () {
      expect(descripcionDeFecha('no es fecha', ahora: ahora), isNull);
      expect(esDeUnDiaAnterior('no es fecha', ahora: ahora), isFalse);
    });
  });

  group('horaLocal', () {
    test('devuelve HH:MM de una fecha válida', () {
      expect(
        horaLocal('2026-10-04T15:30:00.000Z'),
        matches(RegExp(r'^\d{2}:\d{2}$')),
      );
    });

    test('devuelve null si no es una fecha', () {
      expect(horaLocal('no es fecha'), isNull);
    });
  });
}
