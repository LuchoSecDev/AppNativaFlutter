import 'package:flutter/material.dart';

import '../../ui/colores.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../../venta/venta_providers.dart';

/// Mientras la venta viaja al servidor (y mientras se reintenta con pausas). No tiene botones: no se debe cobrar dos
/// veces ni cambiar el carrito.
class CobroEnviando extends StatelessWidget {
  const CobroEnviando({super.key, required this.cobro});

  final EstadoCobro cobro;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text(
              'Registrando la venta…',
              style: TextStyle(fontSize: 18, color: Colores.tinta),
            ),
            if (cobro.intento > 1) ...[
              const SizedBox(height: 4),
              Text(
                'Intento ${cobro.intento}',
                style: const TextStyle(fontSize: 13, color: Colores.tinta),
              ),
            ],
            if (cobro.mensaje != null) ...[
              const SizedBox(height: 12),
              CuadroDeMensaje(cobro.mensaje!, esError: false),
            ],
          ],
        ),
      ),
    );
  }
}
