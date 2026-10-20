import 'package:flutter/material.dart';

import '../../ui/colores.dart';
import '../../ui/retroalimentacion.dart';
import '../egreso_estado.dart';
import 'resumen_del_gasto.dart';

/// El comprobante de un gasto ya registrado. Vibra una vez al aparecer. El gasto queda pendiente de aprobación del
/// Administrador (contrato `[K4]`): la persona no lo aprueba ni lo rechaza.
class ComprobanteDeEgreso extends StatelessWidget {
  const ComprobanteDeEgreso({
    super.key,
    required this.estado,
    required this.alTerminar,
  });

  final EstadoEgreso estado;
  final VoidCallback alTerminar;

  @override
  Widget build(BuildContext context) {
    final egreso = estado.egreso;
    return VibrarAlAparecer(
      intensidad: Intensidad.media,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.check_circle, size: 64, color: Colores.exito),
                const SizedBox(height: 12),
                const Text(
                  'Gasto registrado',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colores.tinta,
                  ),
                ),
                Text(
                  'Gasto n.º ${estado.idEgreso}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colores.tinta),
                ),
                const SizedBox(height: 16),
                if (egreso != null) ResumenDelGasto(egreso: egreso),
                const SizedBox(height: 12),
                const Text(
                  'Queda pendiente de aprobación del Administrador.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colores.tinta),
                ),
                if (estado.repetido) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Este gasto ya estaba registrado: se recuperó sin registrarlo otra vez.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colores.tinta, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(onPressed: alTerminar, child: const Text('Listo')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
