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

    test(
      'un código ya confirmado no se vuelve a confirmar hasta hacer reset',
      () {
        final s = ScanStabilizer();
        for (var i = 0; i < 2; i++) {
          s.register('AAA');
        }
        expect(s.register('AAA'), 'AAA');
        expect(s.register('AAA'), isNull);
        expect(s.register('AAA'), isNull);
      },
    );

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
      expect(
        () => ScanStabilizer(requiredReads: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // Escaneo continuo (vender): tras agregar un producto la cámara sigue apuntándole un momento. Sin esta regla, el
  // mismo código se confirmaría otra vez a las 3 lecturas y se vendería una unidad de más sin que nadie lo note.
  group('ScanStabilizer con silencioParaRepetir (escaneo continuo)', () {
    final t0 = DateTime(2026, 10, 5, 10);
    DateTime en(int milisegundos) =>
        t0.add(Duration(milliseconds: milisegundos));

    ScanStabilizer continuo() =>
        ScanStabilizer(silencioParaRepetir: const Duration(milliseconds: 1500));

    String? leerTres(ScanStabilizer s, String code, int desdeMs) {
      String? r;
      for (var i = 0; i < 3; i++) {
        r = s.register(code, ahora: en(desdeMs + i * 100));
      }
      return r;
    }

    test('mientras el código siga a la vista, NO se confirma otra vez', () {
      final s = continuo();
      expect(leerTres(s, 'AAA', 0), 'AAA');
      // La cámara sigue viendo el mismo producto durante 10 segundos, una lectura cada 100 ms.
      for (var ms = 300; ms < 10000; ms += 100) {
        expect(
          s.register('AAA', ahora: en(ms)),
          isNull,
          reason: 'a los $ms ms',
        );
      }
    });

    test('si el código desaparece más del silencio y vuelve, sí se confirma de nuevo', () {
      final s = continuo();
      expect(leerTres(s, 'AAA', 0), 'AAA');
      // Última vez visto: 200 ms. Vuelve a los 1.800 ms (1.600 ms sin verlo): se vuelve a armar.
      expect(leerTres(s, 'AAA', 1800), 'AAA');
    });

    test('si desaparece menos del silencio, sigue bloqueado (temblor de la cámara)', () {
      final s = continuo();
      expect(leerTres(s, 'AAA', 0), 'AAA');
      // Última vez visto: 200 ms. Vuelve a los 1.000 ms (800 ms sin verlo): todavía no.
      expect(leerTres(s, 'AAA', 1000), isNull);
    });

    test('otro producto distinto se confirma de inmediato', () {
      final s = continuo();
      expect(leerTres(s, 'AAA', 0), 'AAA');
      expect(leerTres(s, 'BBB', 300), 'BBB');
    });

    test('A, luego B y luego A otra vez: A se vuelve a confirmar (ya no es el último)', () {
      final s = continuo();
      expect(leerTres(s, 'AAA', 0), 'AAA');
      expect(leerTres(s, 'BBB', 300), 'BBB');
      expect(leerTres(s, 'AAA', 700), 'AAA');
    });

    test('notarVisto mantiene el bloqueo mientras se procesa (en pausa) el mismo código', () {
      final s = continuo();
      expect(leerTres(s, 'AAA', 0), 'AAA');
      // Se consulta al servidor 3 segundos con la cámara todavía apuntando al producto: la lectura sigue viéndose.
      for (var ms = 300; ms < 3000; ms += 100) {
        s.notarVisto('AAA', ahora: en(ms));
      }
      expect(leerTres(s, 'AAA', 3000), isNull);
    });

    test('notarVisto de otro código no desbloquea el confirmado', () {
      final s = continuo();
      expect(leerTres(s, 'AAA', 0), 'AAA');
      s.notarVisto('BBB', ahora: en(5000));
      expect(s.register('AAA', ahora: en(5100)), isNull);
    });

    test('reset permite volver a leer el mismo código al instante (tras un error o «cancelar»)', () {
      final s = continuo();
      expect(leerTres(s, 'AAA', 0), 'AAA');
      s.reset();
      expect(leerTres(s, 'AAA', 400), 'AAA');
    });

    test(
      'leer en pausa no confirma nada (ni un código distinto, que se perdería)',
      () {
        final s = continuo();
        expect(leerTres(s, 'AAA', 0), 'AAA');
        for (var i = 0; i < 3; i++) {
          expect(
            s.leer('BBB', pausado: true, ahora: en(300 + i * 100)),
            isNull,
          );
        }
        // Al reanudar, BBB empieza desde cero: necesita sus 3 lecturas, y se confirma.
        expect(s.leer('BBB', pausado: false, ahora: en(700)), isNull);
        expect(s.leer('BBB', pausado: false, ahora: en(800)), isNull);
        expect(s.leer('BBB', pausado: false, ahora: en(900)), 'BBB');
      },
    );

    test('sin silencioParaRepetir (la pantalla de diagnóstico) nada cambia: solo se repite tras reset', () {
      final s = ScanStabilizer();
      for (var i = 0; i < 3; i++) {
        s.register('AAA', ahora: en(i * 100));
      }
      for (var ms = 5000; ms < 5400; ms += 100) {
        expect(s.register('AAA', ahora: en(ms)), isNull);
      }
    });
  });
}
