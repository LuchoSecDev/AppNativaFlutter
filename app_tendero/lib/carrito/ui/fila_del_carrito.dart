import 'package:flutter/material.dart';

import '../../ui/colores.dart';
import '../../ui/dinero.dart';
import '../../ui/formato.dart';
import '../carrito_models.dart';

class FilaDelCarrito extends StatelessWidget {
  const FilaDelCarrito({
    super.key,
    required this.detalle,
    required this.bloqueado,
    required this.alMas,
    required this.alMenos,
    required this.alQuitar,
  });

  final LineaDetallada detalle;

  /// `true` mientras se cobra: las líneas se ven pero no se pueden cambiar.
  final bool bloqueado;
  final VoidCallback alMas;
  final VoidCallback alMenos;
  final VoidCallback alQuitar;

  @override
  Widget build(BuildContext context) {
    final unitario = detalle.precioUnitarioCentavos;
    final subtotal = detalle.subtotalCentavos;
    final problema = detalle.mensajeDelProblema;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  detalle.nombre,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colores.tinta,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Quitar ${detalle.nombre}',
                icon: const Icon(Icons.delete_outline),
                onPressed: bloqueado ? null : alQuitar,
              ),
            ],
          ),
          Row(
            children: [
              IconButton.outlined(
                tooltip: 'Menos',
                icon: const Icon(Icons.remove),
                onPressed: !bloqueado && detalle.linea.cantidad > 1
                    ? alMenos
                    : null,
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${detalle.linea.cantidad}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton.outlined(
                tooltip: 'Más',
                icon: const Icon(Icons.add),
                onPressed: bloqueado ? null : alMas,
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    subtotal == null
                        ? '—'
                        : formatoPesos(importeDeCentavos(subtotal)),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (unitario != null)
                    Text(
                      '${formatoPesos(importeDeCentavos(unitario))} c/u',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colores.tinta,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          if (problema != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Text(
                problema,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colores.peligro,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
