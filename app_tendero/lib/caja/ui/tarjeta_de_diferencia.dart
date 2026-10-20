import 'package:flutter/material.dart';

import '../../ui/colores.dart';
import '../caja_models.dart';

/// «Cuadra», «Sobra» o «Falta», con su color.
class TarjetaDeDiferencia extends StatelessWidget {
  const TarjetaDeDiferencia({super.key, required this.arqueo});

  final ArqueoCaja arqueo;

  @override
  Widget build(BuildContext context) {
    final (fondo, color) = switch (arqueo.tipo) {
      TipoDiferencia.cuadra => (const Color(0xFFDDF3E9), Colores.exito),
      TipoDiferencia.sobra => (Colores.avisoSuave, Colores.aviso),
      TipoDiferencia.falta => (Colores.peligroSuave, Colores.peligro),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            arqueo.tituloDeLaDiferencia,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            arqueo.detalleDeLaDiferencia,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
