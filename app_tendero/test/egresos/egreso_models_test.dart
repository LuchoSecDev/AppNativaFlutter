import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/clave_de_idempotencia.dart';
import 'package:stockpilot/egresos/egreso_models.dart';

/// Los datos de un egreso: categorías, el cuerpo de la petición y lo que se guarda en el celular.
void main() {
  const clave = '4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22';

  group('la clave de idempotencia', () {
    test('acepta lo que acepta el servidor: 8 a 100 letras, números, guion o guion bajo', () {
      expect(esClaveDeIdempotenciaValida(clave), isTrue);
      expect(esClaveDeIdempotenciaValida('abcdefgh'), isTrue); // 8, el mínimo
      expect(esClaveDeIdempotenciaValida('a' * 100), isTrue); // 100, el máximo
      expect(esClaveDeIdempotenciaValida('con_guion_bajo-y-guion'), isTrue);
    });

    test('rechaza lo que el servidor rechazaría', () {
      expect(esClaveDeIdempotenciaValida('abcdefg'), isFalse); // 7
      expect(esClaveDeIdempotenciaValida('a' * 101), isFalse);
      expect(esClaveDeIdempotenciaValida(''), isFalse);
      expect(esClaveDeIdempotenciaValida('con espacio 123'), isFalse);
      expect(esClaveDeIdempotenciaValida('con.punto.12345'), isFalse);
      expect(esClaveDeIdempotenciaValida('tildé-12345678'), isFalse);
      expect(esClaveDeIdempotenciaValida('abcdefgh\n'), isFalse);
    });
  });

  group('CategoriaEgreso', () {
    test('son las seis de la web, con su escritura exacta', () {
      expect(CategoriaEgreso.values.map((c) => c.valorApi), [
        'Proveedor menor',
        'Insumos / Bolsas',
        'Transporte',
        'Limpieza',
        'Servicios',
        'Otro',
      ]);
    });

    test('se reconoce por su texto exacto y nada más', () {
      expect(
        CategoriaEgreso.desdeApi('Transporte'),
        CategoriaEgreso.transporte,
      );
      expect(CategoriaEgreso.desdeApi('Otro'), CategoriaEgreso.otro);
      expect(CategoriaEgreso.desdeApi('transporte'), isNull);
      expect(CategoriaEgreso.desdeApi('Inventada'), isNull);
      expect(CategoriaEgreso.desdeApi(null), isNull);
      expect(CategoriaEgreso.desdeApi(3), isNull);
    });
  });

  group('EgresoPendiente', () {
    const egreso = EgresoPendiente(
      clave: clave,
      montoPesos: 10000,
      motivo: 'Bolsas y hielo',
      categoria: CategoriaEgreso.otro,
    );

    test('el cuerpo de la petición sigue el contrato: monto en PESOS enteros, motivo y categoría', () {
      expect(egreso.cuerpoDeLaPeticion(), {
        'monto': 10000,
        'motivo': 'Bolsas y hielo',
        'categoria': 'Otro',
      });
    });

    test('el cuerpo no lleva foto (D1: el egreso va sin foto)', () {
      expect(egreso.cuerpoDeLaPeticion().containsKey('foto_soporte'), isFalse);
    });

    test('guardado y leído queda igual (la clave y la carga no cambian)', () {
      final leido = EgresoPendiente.desdeJson(egreso.aJson())!;
      expect(leido.clave, clave);
      expect(leido.montoPesos, 10000);
      expect(leido.motivo, 'Bolsas y hielo');
      expect(leido.categoria, CategoriaEgreso.otro);
      expect(leido.cuerpoDeLaPeticion(), egreso.cuerpoDeLaPeticion());
    });

    test('lo guardado dañado o de otra forma se descarta (null), no se inventa un egreso', () {
      final bueno = egreso.aJson();
      expect(EgresoPendiente.desdeJson(null), isNull);
      expect(EgresoPendiente.desdeJson('texto'), isNull);
      expect(EgresoPendiente.desdeJson({...bueno, 'clave': 'corta'}), isNull);
      expect(EgresoPendiente.desdeJson({...bueno, 'clave': 5}), isNull);
      expect(EgresoPendiente.desdeJson({...bueno, 'monto_pesos': 0}), isNull);
      expect(EgresoPendiente.desdeJson({...bueno, 'monto_pesos': -5}), isNull);
      expect(
        EgresoPendiente.desdeJson({...bueno, 'monto_pesos': '10000'}),
        isNull,
      );
      expect(
        EgresoPendiente.desdeJson({...bueno, 'monto_pesos': 10.5}),
        isNull,
      );
      expect(EgresoPendiente.desdeJson({...bueno, 'motivo': null}), isNull);
      expect(EgresoPendiente.desdeJson({...bueno, 'motivo': 7}), isNull);
      expect(
        EgresoPendiente.desdeJson({...bueno, 'categoria': 'Inventada'}),
        isNull,
      );
      expect(EgresoPendiente.desdeJson({...bueno, 'categoria': null}), isNull);
    });
  });
}
