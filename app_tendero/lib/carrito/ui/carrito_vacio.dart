import 'package:flutter/material.dart';

import '../../ui/colores.dart';
import 'botones_para_agregar.dart';

class CarritoVacio extends StatelessWidget {
  const CarritoVacio({
    super.key,
    required this.puedeVender,
    required this.alEscanear,
    required this.alBuscar,
  });

  final bool puedeVender;
  final VoidCallback alEscanear;
  final VoidCallback alBuscar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shopping_cart_outlined,
              size: 56,
              color: Colores.tinta,
            ),
            const SizedBox(height: 12),
            const Text(
              'El carrito está vacío',
              style: TextStyle(fontSize: 18, color: Colores.tinta),
            ),
            const SizedBox(height: 16),
            BotonesParaAgregar(
              puedeVender: puedeVender,
              alEscanear: alEscanear,
              alBuscar: alBuscar,
              principal: true,
            ),
            if (!puedeVender) ...[
              const SizedBox(height: 8),
              const Text(
                'Abre la caja para escanear.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colores.tinta),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
