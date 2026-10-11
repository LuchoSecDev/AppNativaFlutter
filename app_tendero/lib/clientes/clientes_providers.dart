import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/errores_de_api.dart';
import '../auth/auth_providers.dart';
import '../auth/session_state.dart';
import 'cliente.dart';
import 'clientes_repository.dart';

final clientesRepositoryProvider = Provider<ClientesRepository>(
  (ref) => ClientesRepository(ref.watch(dioProvider)),
);

enum FaseClientes { cargando, listo, error }

/// Lo que la app sabe de los clientes (para fiar) en este momento. Inmutable.
class EstadoClientes {
  const EstadoClientes({
    this.fase = FaseClientes.cargando,
    this.clientes = const [],
    this.mensajeError,
  });

  final FaseClientes fase;
  final List<Cliente> clientes;

  /// Qué decirle al usuario si [fase] es [FaseClientes.error].
  final String? mensajeError;
}

/// Los clientes de la tienda de quien tiene la sesión abierta.
///
/// No se descargan al iniciar sesión: solo quien fía los necesita, y sus saldos cambian entre venta y venta. La
/// pantalla de fiado llama a [ClientesNotifier.cargar] cada vez que se abre, para no ofrecer un saldo viejo.
final clientesProvider = NotifierProvider<ClientesNotifier, EstadoClientes>(
  ClientesNotifier.new,
);

class ClientesNotifier extends Notifier<EstadoClientes> {
  /// Cambia con la sesión: una respuesta de otra sesión (otro usuario, otra tienda) se descarta, para no mostrar
  /// los clientes de una tienda a quien entró después.
  int _generacion = 0;

  bool _obsoleto(int generacion) => generacion != _generacion || !ref.mounted;

  @override
  EstadoClientes build() {
    ref.watch(sesionProvider.select((s) => s.fase));
    _generacion++;
    return const EstadoClientes();
  }

  Future<void> cargar() async {
    if (ref.read(sesionProvider).fase != FaseSesion.activa) return;
    final g = _generacion;
    state = const EstadoClientes(fase: FaseClientes.cargando);
    try {
      final clientes = await ref
          .read(clientesRepositoryProvider)
          .obtenerClientes();
      if (_obsoleto(g)) return;
      state = EstadoClientes(fase: FaseClientes.listo, clientes: clientes);
    } on ErrorDeApi catch (e) {
      if (_obsoleto(g)) return;
      state = EstadoClientes(fase: FaseClientes.error, mensajeError: e.mensaje);
    }
  }
}

/// Los clientes cuyo nombre contiene [consulta] (sin distinguir mayúsculas). Con la consulta vacía, todos.
final clientesFiltradosProvider = Provider.family<List<Cliente>, String>((
  ref,
  consulta,
) {
  final clientes = ref.watch(clientesProvider).clientes;
  final buscado = consulta.trim().toLowerCase();
  if (buscado.isEmpty) return clientes;
  return clientes
      .where((c) => c.nombre.toLowerCase().contains(buscado))
      .toList();
});
