import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/colores.dart';
import '../egreso_estado.dart';
import '../egreso_providers.dart';
import 'comprobante_de_egreso.dart';
import 'formulario_de_egreso.dart';
import 'gasto_sin_confirmar.dart';

/// Registrar un gasto de caja chica. Según en qué punto esté el registro muestra el formulario, «registrando…», el
/// gasto sin confirmar o el comprobante. Esta pantalla solo dibuja: lo que se decide vive en [EgresoNotifier].
class RegistrarEgresoScreen extends ConsumerWidget {
  const RegistrarEgresoScreen({super.key});

  /// Un resultado (comprobante o rechazo) ya se vio: al salir, el siguiente gasto empieza limpio.
  void _cerrarResultado(WidgetRef ref) =>
      ref.read(egresoProvider.notifier).aceptarResultado();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(egresoProvider);

    return PopScope(
      onPopInvokedWithResult: (volvio, _) {
        if (volvio) _cerrarResultado(ref);
      },
      child: Scaffold(
        backgroundColor: Colores.papel,
        appBar: AppBar(title: const Text('Registrar gasto')),
        body: SafeArea(
          child: switch (estado.fase) {
            _ when estado.cargando => const Center(
              child: CircularProgressIndicator(),
            ),
            FaseEgreso.libre => const FormularioDeEgreso(),
            FaseEgreso.rechazado => FormularioDeEgreso(rechazo: estado.mensaje),
            FaseEgreso.enviando => _Registrando(mensaje: estado.mensaje),
            FaseEgreso.sinConfirmar => GastoSinConfirmar(estado: estado),
            FaseEgreso.registrado => ComprobanteDeEgreso(
              estado: estado,
              alTerminar: () {
                _cerrarResultado(ref);
                Navigator.of(context).pop();
              },
            ),
          },
        ),
      ),
    );
  }
}

class _Registrando extends StatelessWidget {
  const _Registrando({this.mensaje});

  final String? mensaje;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text(
            'Registrando el gasto…',
            style: TextStyle(fontSize: 16, color: Colores.tinta),
          ),
          if (mensaje != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                mensaje!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colores.tinta),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
