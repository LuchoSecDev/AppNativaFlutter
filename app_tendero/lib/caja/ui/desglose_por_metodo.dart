import 'package:flutter/material.dart';

import '../../ui/colores.dart';
import '../../ui/dinero.dart';
import '../../ui/formato.dart';
import '../caja_models.dart';

/// Lo vendido en el turno, separado por método de pago: es el desglose de auditoría. Solo el efectivo entra al cajón; el
/// resto se muestra aparte, marcado, para que se vea que no se olvidó. No se dibuja si el servidor no lo envió.
class DesglosePorMetodo extends StatelessWidget {
  const DesglosePorMetodo({super.key, required this.arqueo});

  final ArqueoCaja arqueo;

  @override
  Widget build(BuildContext context) {
    if (arqueo.ventasPorMetodo.isEmpty && arqueo.abonosPorMetodo.isEmpty) {
      return const SizedBox.shrink(); // un servidor anterior al desglose
    }
    final ventas = arqueo.ventasPorMetodo.where((m) => m.tieneMovimiento);
    final abonos = arqueo.abonosPorMetodo.where((m) => m.tieneMovimiento);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Lo vendido en el turno, por método de pago',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colores.tinta,
            ),
          ),
          const SizedBox(height: 6),
          if (ventas.isEmpty)
            const Text(
              'Sin ventas en este turno.',
              style: TextStyle(fontSize: 13, color: Colores.tinta),
            )
          else
            for (final m in ventas) LineaDeMetodo(m, unidad: 'venta'),
          if (abonos.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Abonos de clientes',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colores.tinta,
              ),
            ),
            const SizedBox(height: 6),
            for (final m in abonos) LineaDeMetodo(m, unidad: 'abono'),
          ],
        ],
      ),
    );
  }
}

class LineaDeMetodo extends StatelessWidget {
  const LineaDeMetodo(this.movimiento, {super.key, required this.unidad});

  final MovimientoPorMetodo movimiento;
  final String unidad;

  @override
  Widget build(BuildContext context) {
    final cantidad = movimiento.cantidad;
    final detalle =
        '$cantidad ${cantidad == 1 ? unidad : '${unidad}s'}${movimiento.entraAlCajon ? '' : ' · no entra al cajón'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: movimiento.etiqueta,
                    style: const TextStyle(fontSize: 13, color: Colores.tinta),
                  ),
                  TextSpan(
                    text: ' · $detalle',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          Text(
            formatoPesos(importeDeCentavos(movimiento.totalCentavos)),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colores.tinta,
            ),
          ),
        ],
      ),
    );
  }
}
