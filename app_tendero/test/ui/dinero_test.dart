import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/ui/dinero.dart';
import 'package:stockpilot/ui/formato.dart';

void main() {
  group('centavosDeImporte', () {
    test('convierte importes con dos decimales, con uno o sin decimales', () {
      expect(centavosDeImporte('12000.00'), 1200000);
      expect(centavosDeImporte('4500.5'), 450050);
      expect(centavosDeImporte('150'), 15000);
      expect(centavosDeImporte('0.05'), 5);
      expect(centavosDeImporte('0'), 0);
      expect(centavosDeImporte(' 100.00 '), 10000);
    });

    test('importes inválidos devuelven null, no una cifra inventada', () {
      for (final malo in ['', 'abc', '-5.00', '1.234', '1,50', '1.2.3', '12 000', r'$100', '1e5']) {
        expect(centavosDeImporte(malo), isNull, reason: 'importe: "$malo"');
      }
    });
  });

  group('importeDeCentavos', () {
    test('formatea con dos decimales', () {
      expect(importeDeCentavos(1200000), '12000.00');
      expect(importeDeCentavos(450050), '4500.50');
      expect(importeDeCentavos(5), '0.05');
      expect(importeDeCentavos(0), '0.00');
    });

    test('ida y vuelta sin pérdida', () {
      for (final texto in ['12000.00', '4500.50', '0.05', '999999999.99']) {
        expect(importeDeCentavos(centavosDeImporte(texto)!), texto);
      }
    });
  });

  group('por qué no se usa double', () {
    test('sumar centavos enteros es exacto donde el double falla', () {
      expect(0.1 + 0.2 == 0.3, isFalse); // el problema que se evita
      expect(centavosDeImporte('0.10')! + centavosDeImporte('0.20')!, centavosDeImporte('0.30'));
    });

    test('3 unidades de 3.333,33 dan exactamente 9.999,99', () {
      final unitario = centavosDeImporte('3333.33')!;
      expect(importeDeCentavos(unitario * 3), '9999.99');
      expect(formatoPesos(importeDeCentavos(unitario * 3)), r'$9.999,99');
    });
  });
}
