import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/colores.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../actualizacion_providers.dart';
import '../estado_de_version.dart';

/// Aviso en el inicio cuando hay una versión nueva pero la instalada todavía sirve. Se puede descartar («Ahora no»);
/// vuelve a salir la próxima vez que se inicie sesión. No se muestra si no hay nada que avisar.
class AvisoDeVersionNueva extends ConsumerWidget {
  const AvisoDeVersionNueva({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(actualizacionProvider);
    if (estado.nivel != NivelDeActualizacion.opcional ||
        estado.avisoDescartado) {
      return const SizedBox.shrink();
    }
    final nombre = estado.publicada?.versionName ?? '';
    final notas = estado.publicada?.notas ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colores.azul),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nombre.isEmpty
                  ? 'Hay una versión nueva de StockPilot.'
                  : 'Hay una versión nueva de StockPilot ($nombre).',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colores.tinta,
              ),
            ),
            if (notas.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                notas,
                style: const TextStyle(fontSize: 13, color: Colores.tinta),
              ),
            ],
            if (estado.mensaje != null) ...[
              const SizedBox(height: 8),
              CuadroDeMensaje(estado.mensaje!),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: estado.abriendo
                      ? null
                      : () => ref
                            .read(actualizacionProvider.notifier)
                            .descartarAviso(),
                  child: const Text('Ahora no'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: estado.abriendo
                      ? null
                      : () => ref
                            .read(actualizacionProvider.notifier)
                            .descargar(),
                  child: estado.abriendo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Descargar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// «StockPilot 1.0.0 (1)» al pie del inicio: sirve para saber qué versión hay instalada (y para comprobar en un celular
/// real que el número que se compara con el servidor es el esperado). No se muestra si no se pudo leer.
class EtiquetaDeVersion extends ConsumerWidget {
  const EtiquetaDeVersion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(versionInstaladaProvider).value;
    if (version == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Text(
        'StockPilot ${version.nombre} (${version.codigo})',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: Colores.tinta),
      ),
    );
  }
}
