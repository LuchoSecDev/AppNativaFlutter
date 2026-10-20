import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/egresos/egreso_reglas.dart';

/// Las reglas que la app comprueba antes de enviar un gasto (el servidor igual decide).
void main() {
  group('motivoEsValido', () {
    test(
      '5 caracteres es el mínimo, sin contar espacios al principio ni al final',
      () {
        expect(motivoEsValido('abcde'), isTrue);
        expect(motivoEsValido('  abcde  '), isTrue);
        expect(motivoEsValido('abcd'), isFalse);
        expect(motivoEsValido('  abcd  '), isFalse);
        expect(motivoEsValido('     '), isFalse);
        expect(motivoEsValido(''), isFalse);
      },
    );

    test('los espacios de en medio sí cuentan', () {
      expect(motivoEsValido('a b c'), isTrue);
    });
  });

  group('topeEnCentavos', () {
    test('para el Tendero es el tope del servidor, en centavos', () {
      expect(
        topeEnCentavos(rol: 'Tendero', limiteEgresoTendero: '150000.00'),
        15000000,
      );
      expect(
        topeEnCentavos(rol: 'Tendero', limiteEgresoTendero: '150000.50'),
        15000050,
      );
    });

    test('para otros roles no hay tope', () {
      expect(
        topeEnCentavos(rol: 'Administrador', limiteEgresoTendero: '150000.00'),
        isNull,
      );
      expect(topeEnCentavos(rol: '', limiteEgresoTendero: '150000.00'), isNull);
    });

    test('un tope en 0, vacío o ilegible no frena (decide el servidor)', () {
      for (final raro in ['0.00', '0', '', 'abc', '-5.00', '1.234']) {
        expect(
          topeEnCentavos(rol: 'Tendero', limiteEgresoTendero: raro),
          isNull,
          reason: '"$raro"',
        );
      }
    });
  });

  group('motivoParaNoRegistrar', () {
    String? regla({
      bool caja = true,
      int monto = 10000,
      String motivo = 'Bolsas y hielo',
      String rol = 'Tendero',
      String tope = '150000.00',
    }) => motivoParaNoRegistrar(
      cajaAbierta: caja,
      montoPesos: monto,
      motivo: motivo,
      rol: rol,
      limiteEgresoTendero: tope,
    );

    test('un gasto normal pasa', () => expect(regla(), isNull));

    test('el monto IGUAL al tope pasa y un peso más no', () {
      expect(regla(monto: 150000), isNull);
      expect(regla(monto: 150001), contains(r'$150.000'));
    });

    test('un tope con centavos: 150000 pesos pasan, 150001 no', () {
      expect(regla(monto: 150000, tope: '150000.50'), isNull);
      expect(regla(monto: 150001, tope: '150000.50'), isNotNull);
    });

    test(
      'el orden de los motivos: caja, luego monto, luego motivo, luego tope',
      () {
        expect(regla(caja: false, monto: 0, motivo: ''), contains('caja'));
        expect(regla(monto: 0, motivo: ''), contains('monto'));
        expect(regla(motivo: ''), contains('motivo'));
        expect(regla(monto: 999999999), contains('Por seguridad'));
      },
    );

    test('cada mensaje es entendible y en español', () {
      expect(
        regla(caja: false),
        'No hay una caja abierta. Abre la caja para registrar gastos.',
      );
      expect(regla(monto: 0), 'El monto debe ser mayor a 0.');
      expect(
        regla(motivo: 'abc'),
        'Escribe el motivo del gasto (mínimo 5 caracteres).',
      );
    });
  });
}
