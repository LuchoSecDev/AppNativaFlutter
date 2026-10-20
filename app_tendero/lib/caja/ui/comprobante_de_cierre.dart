import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/colores.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../../ui/retroalimentacion.dart';
import '../cierre_providers.dart';
import 'desglose_del_arqueo.dart';
import 'desglose_por_metodo.dart';
import 'tarjeta_de_diferencia.dart';

/// El comprobante: la caja quedó cerrada, con el arqueo final.
class ComprobanteDeCierre extends ConsumerWidget {
  const ComprobanteDeCierre({super.key, required this.cierre});

  final EstadoCierre cierre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arqueo = cierre.arqueoFinal;
    return VibrarAlAparecer(
      intensidad: Intensidad.media,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.lock, size: 56, color: Colores.exito),
          const SizedBox(height: 8),
          const Text(
            'Caja cerrada',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colores.tinta,
            ),
          ),
          if (cierre.cambio) ...[
            const SizedBox(height: 12),
            const CuadroDeMensaje(
              'Mientras revisabas se registró un movimiento: este es el arqueo FINAL, distinto al que viste.',
              esError: false,
            ),
          ],
          if (arqueo != null) ...[
            const SizedBox(height: 16),
            DesgloseDelArqueo(arqueo: arqueo),
            const SizedBox(height: 16),
            TarjetaDeDiferencia(arqueo: arqueo),
            DesglosePorMetodo(arqueo: arqueo),
          ],
          if (cierre.mensaje != null) ...[
            const SizedBox(height: 12),
            CuadroDeMensaje(cierre.mensaje!, esError: false),
          ],
          const SizedBox(height: 24),
          BotonPrincipal(
            texto: 'Volver al inicio',
            alPulsar: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
