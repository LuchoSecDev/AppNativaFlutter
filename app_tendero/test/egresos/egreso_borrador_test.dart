import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/auth/session_state.dart';
import 'package:stockpilot/egresos/egreso_borrador.dart';
import 'package:stockpilot/egresos/egreso_models.dart';
import 'package:stockpilot/egresos/egreso_providers.dart';

import '../support/carrito_apoyo.dart';
import '../support/egreso_apoyo.dart';
import '../support/fake_adapter.dart';

/// Lo que la persona ya escribió en el formulario: se conserva si sale de la pantalla y vuelve.
void main() {
  late EntornoDeEgresos e;
  late ProviderContainer c;

  setUp(() async {
    e = EntornoDeEgresos();
    c = await e.contenedor();
    addTearDown(c.dispose);
  });

  BorradorDeEgreso borrador() => c.read(borradorDeEgresoProvider);
  BorradorNotifier notificador() => c.read(borradorDeEgresoProvider.notifier);

  test('empieza vacío y sin categoría elegida (no se preselecciona: se elige a propósito)', () {
    expect(borrador().monto, '');
    expect(borrador().motivo, '');
    expect(borrador().categoria, isNull);
  });

  test('cada campo se guarda sin pisar a los demás', () {
    notificador().cambiar(monto: '12000');
    notificador().cambiar(motivo: 'Bolsas');
    notificador().cambiar(categoria: CategoriaEgreso.limpieza);
    expect(borrador().monto, '12000');
    expect(borrador().motivo, 'Bolsas');
    expect(borrador().categoria, CategoriaEgreso.limpieza);
  });

  test('limpiar lo deja todo vacío, incluida la categoría', () {
    notificador().cambiar(
      monto: '12000',
      motivo: 'Bolsas',
      categoria: CategoriaEgreso.otro,
    );
    notificador().limpiar();
    expect(borrador().monto, '');
    expect(borrador().motivo, '');
    expect(borrador().categoria, isNull);
  });

  test('al cambiar la sesión se borra: la cuenta nueva no ve lo que escribió la anterior', () {
    notificador().cambiar(
      monto: '12000',
      motivo: 'Bolsas',
      categoria: CategoriaEgreso.otro,
    );
    e.sesion.poner(const EstadoSesion.sinSesion());
    e.sesion.poner(sesionActiva(userId: 9, tiendaId: 2));
    expect(borrador().monto, '');
    expect(borrador().motivo, '');
    expect(borrador().categoria, isNull);
  });

  test(
    'registrar con éxito lo limpia (el siguiente gasto empieza en blanco)',
    () async {
      e.servidor.programar(
        'POST',
        EntornoDeEgresos.ruta,
        RespuestaFalsa.deEjemplo('24_K4_egreso_ok'),
      );
      notificador().cambiar(
        monto: '10000',
        motivo: 'Bolsas y hielo',
        categoria: CategoriaEgreso.otro,
      );
      await c
          .read(egresoProvider.notifier)
          .registrar(
            montoPesos: 10000,
            motivo: 'Bolsas y hielo',
            categoria: CategoriaEgreso.otro,
          );
      expect(borrador().monto, '');
    },
  );
}
