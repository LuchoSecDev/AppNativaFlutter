import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../clientes/cliente.dart';
import '../../clientes/clientes_providers.dart';
import '../../ui/colores.dart';
import '../../ui/piezas_de_pantalla.dart';
import 'fiado_formato.dart';

/// Buscador y lista de los clientes de la tienda.
class ElegirCliente extends ConsumerWidget {
  const ElegirCliente({
    super.key,
    required this.controladorBusqueda,
    required this.avisoDeTotal,
    required this.alElegir,
  });

  final TextEditingController controladorBusqueda;
  final String? avisoDeTotal;
  final ValueChanged<Cliente> alElegir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(clientesProvider);

    return Column(
      children: [
        if (avisoDeTotal != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: CuadroDeMensaje(avisoDeTotal!, esError: false),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: controladorBusqueda,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar cliente por nombre',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: controladorBusqueda.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Borrar la búsqueda',
                      onPressed: controladorBusqueda.clear,
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: switch (estado.fase) {
            FaseClientes.cargando => const Center(
              child: CircularProgressIndicator(),
            ),
            FaseClientes.error => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CuadroDeMensaje(
                      estado.mensajeError ??
                          'No se pudo cargar la lista de clientes.',
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(clientesProvider.notifier).cargar(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
            FaseClientes.listo => ListaDeClientes(
              consulta: controladorBusqueda.text,
              alElegir: alElegir,
            ),
          },
        ),
      ],
    );
  }
}

class ListaDeClientes extends ConsumerWidget {
  const ListaDeClientes({
    super.key,
    required this.consulta,
    required this.alElegir,
  });

  final String consulta;
  final ValueChanged<Cliente> alElegir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientes = ref.watch(clientesFiltradosProvider(consulta));

    if (clientes.isEmpty) {
      final hayClientes = ref.watch(clientesProvider).clientes.isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            hayClientes ? 'No se encontraron clientes con ese nombre.' : 'Esta tienda todavía no tiene clientes. El Administrador los registra desde la web.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colores.tinta),
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: clientes.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = clientes[i];
        final cupo = c.sinTope
            ? 'sin tope'
            : 'cupo ${pesosDeCentavos(c.limiteCreditoCentavos)}';
        return ListTile(
          title: Text(
            c.nombre,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'Debe ${pesosDeCentavos(c.saldoPendienteCentavos)} · $cupo',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => alElegir(c),
        );
      },
    );
  }
}
