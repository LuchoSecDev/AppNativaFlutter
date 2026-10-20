import 'package:flutter/material.dart';

import '../../ui/colores.dart';
import '../../ui/dinero.dart';
import '../../ui/formato.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../../ui/retroalimentacion.dart';
import '../../venta/venta_providers.dart';
import '../carrito_models.dart';
import 'botones_para_agregar.dart';

class PieDelCarrito extends StatelessWidget {
  const PieDelCarrito({
    super.key,
    required this.resumen,
    required this.cobro,
    required this.puedeVender,
    required this.alEscanear,
    required this.alBuscar,
    required this.alCobrar,
    required this.alReintentar,
    required this.alDescartar,
  });

  final ResumenCarrito resumen;
  final EstadoCobro cobro;
  final bool puedeVender;
  final VoidCallback alEscanear;
  final VoidCallback alBuscar;
  final VoidCallback alCobrar;
  final VoidCallback alReintentar;
  final VoidCallback alDescartar;

  @override
  Widget build(BuildContext context) {
    final sinConfirmar = cobro.fase == FaseCobro.sinConfirmar;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${resumen.unidades} ${resumen.unidades == 1 ? 'unidad' : 'unidades'}',
                style: const TextStyle(color: Colores.tinta),
              ),
              Text(
                'Total: ${formatoPesos(importeDeCentavos(resumen.totalCentavos))}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colores.tinta,
                ),
              ),
            ],
          ),
          if (sinConfirmar) ...[
            const SizedBox(height: 12),
            VibrarAlAparecer(
              intensidad: Intensidad.media,
              child: CuadroDeMensaje(
                '${cobro.mensaje ?? 'No se pudo confirmar la venta.'} No la cobres otra vez: puede que ya esté registrada.',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: alReintentar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: alDescartar,
              child: const Text('Cancelar este cobro'),
            ),
          ] else ...[
            if (cobro.fase == FaseCobro.rechazada && cobro.mensaje != null) ...[
              const SizedBox(height: 8),
              VibrarAlAparecer(
                intensidad: Intensidad.fuerte,
                child: CuadroDeMensaje(cobro.mensaje!),
              ),
            ],
            if (resumen.hayProblemas) ...[
              const SizedBox(height: 8),
              const CuadroDeMensaje(
                'Revisa los productos marcados en rojo antes de cobrar.',
              ),
            ],
            const SizedBox(height: 12),
            BotonesParaAgregar(
              puedeVender: puedeVender,
              alEscanear: alEscanear,
              alBuscar: alBuscar,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: resumen.sePuedeCobrar && puedeVender ? alCobrar : null,
              child: const Text('Cobrar...'),
            ),
            if (!puedeVender) ...[
              const SizedBox(height: 4),
              const Text(
                'Abre la caja para cobrar y escanear.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colores.tinta),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
