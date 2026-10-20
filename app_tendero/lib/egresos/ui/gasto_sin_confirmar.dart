import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/piezas_de_pantalla.dart';
import '../../ui/retroalimentacion.dart';
import '../egreso_estado.dart';
import '../egreso_providers.dart';
import 'resumen_del_gasto.dart';

/// Cuando NO se sabe si el servidor registró el gasto. Solo se puede REINTENTAR (con la misma clave: si ya estaba, no lo
/// duplica) o cancelar con una advertencia. Nunca se ofrece «registrar de nuevo».
class GastoSinConfirmar extends ConsumerWidget {
  const GastoSinConfirmar({super.key, required this.estado});

  final EstadoEgreso estado;

  Future<void> _confirmarCancelar(BuildContext context, WidgetRef ref) async {
    final cancelar = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('¿Cancelar este gasto?'),
        content: const Text(
          'Si el servidor SÍ lo había registrado, registrarlo otra vez lo duplicaría. Cancela solo si estás seguro de que no se registró.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Volver'),
          ),
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Cancelar el gasto'),
          ),
        ],
      ),
    );
    if (cancelar == true) {
      await ref.read(egresoProvider.notifier).descartarSinConfirmar();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final egreso = estado.egreso;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VibrarAlAparecer(
                intensidad: Intensidad.media,
                child: CuadroDeMensaje(
                  '${estado.mensaje ?? 'No se pudo confirmar el gasto.'} No lo registres otra vez: puede que ya esté registrado.',
                ),
              ),
              const SizedBox(height: 16),
              if (egreso != null) ResumenDelGasto(egreso: egreso),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => ref.read(egresoProvider.notifier).reintentar(),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => _confirmarCancelar(context, ref),
                child: const Text('Cancelar este gasto'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
