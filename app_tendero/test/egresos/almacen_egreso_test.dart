import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stockpilot/egresos/almacen_egreso.dart';
import 'package:stockpilot/egresos/egreso_models.dart';

/// El almacén real de los egresos pendientes (`shared_preferences`), contra uno vacío y contra lo dañado.
void main() {
  const clave = 'egreso_pendiente_v1_2_1';
  const egreso = EgresoPendiente(
    clave: '4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22',
    montoPesos: 10000,
    motivo: 'Bolsas y hielo',
    categoria: CategoriaEgreso.otro,
  );

  Future<AlmacenEgresoPendienteLocal> almacen([
    Map<String, Object> inicial = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(inicial);
    return AlmacenEgresoPendienteLocal(await SharedPreferences.getInstance());
  }

  test('sin nada guardado devuelve null', () async {
    expect(await (await almacen()).leer(clave), isNull);
  });

  test('lo guardado se lee igual, con su clave de idempotencia', () async {
    final a = await almacen();
    await a.guardar(clave, egreso);
    final leido = await a.leer(clave);
    expect(leido?.clave, egreso.clave);
    expect(leido?.montoPesos, 10000);
    expect(leido?.motivo, 'Bolsas y hielo');
    expect(leido?.categoria, CategoriaEgreso.otro);
  });

  test('borrar lo deja vacío', () async {
    final a = await almacen();
    await a.guardar(clave, egreso);
    await a.borrar(clave);
    expect(await a.leer(clave), isNull);
  });

  test('cada cuenta y tienda tiene lo suyo', () async {
    final a = await almacen();
    await a.guardar(clave, egreso);
    expect(await a.leer('egreso_pendiente_v1_9_9'), isNull);
  });

  test(
    'lo dañado se descarta (null) en vez de lanzar: texto que no es JSON',
    () async {
      final a = await almacen({clave: 'esto no es json'});
      expect(await a.leer(clave), isNull);
    },
  );

  test(
    'lo dañado se descarta (null): JSON válido pero de otra forma',
    () async {
      final a = await almacen({clave: '{"clave":"corta","monto_pesos":0}'});
      expect(await a.leer(clave), isNull);
    },
  );

  test('un texto vacío es como no haber guardado nada', () async {
    final a = await almacen({clave: ''});
    expect(await a.leer(clave), isNull);
  });
}
