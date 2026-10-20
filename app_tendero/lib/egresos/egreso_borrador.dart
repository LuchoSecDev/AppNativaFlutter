import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'egreso_models.dart';

/// Lo que la persona ya escribió en el formulario de gasto. Se conserva si sale de la pantalla y vuelve, y se borra al
/// registrar el gasto o al cambiar de sesión.
class BorradorDeEgreso {
  const BorradorDeEgreso({this.monto = '', this.motivo = '', this.categoria});

  /// Solo dígitos, tal como se escribe (pesos enteros).
  final String monto;
  final String motivo;

  /// `null` hasta que se elige: no se preselecciona, para no registrar un gasto por inercia.
  final CategoriaEgreso? categoria;
}

final borradorDeEgresoProvider =
    NotifierProvider<BorradorNotifier, BorradorDeEgreso>(BorradorNotifier.new);

class BorradorNotifier extends Notifier<BorradorDeEgreso> {
  @override
  BorradorDeEgreso build() {
    // Cada vez que cambia la sesión (otra cuenta, otra tienda) se empieza en blanco.
    ref.watch(
      sesionProvider.select((s) => (s.fase, s.info?.userId, s.info?.tiendaId)),
    );
    return const BorradorDeEgreso();
  }

  /// Cambia solo los campos que se pasan; los demás quedan como estaban.
  void cambiar({String? monto, String? motivo, CategoriaEgreso? categoria}) {
    state = BorradorDeEgreso(
      monto: monto ?? state.monto,
      motivo: motivo ?? state.motivo,
      categoria: categoria ?? state.categoria,
    );
  }

  void limpiar() => state = const BorradorDeEgreso();
}
