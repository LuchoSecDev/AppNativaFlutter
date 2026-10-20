import 'package:flutter/material.dart';

import '../../ui/colores.dart';
import '../../ui/dinero.dart';
import '../../ui/formato.dart';
import '../caja_models.dart';

/// De dónde sale lo que debería haber: fondo inicial, ventas, abonos y egresos, y el total contado.
class DesgloseDelArqueo extends StatelessWidget {
  const DesgloseDelArqueo({super.key, required this.arqueo});

  final ArqueoCaja arqueo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          _Renglon('Fondo inicial', arqueo.aperturaCentavos),
          _Renglon('+ Ventas en efectivo', arqueo.ventasEfectivoCentavos),
          _Renglon('+ Abonos en efectivo', arqueo.abonosEfectivoCentavos),
          _Renglon('− Egresos (gastos)', arqueo.egresosCentavos),
          const Divider(height: 20),
          _Renglon('Debería haber', arqueo.esperadoCentavos, destacado: true),
          _Renglon('Tú contaste', arqueo.declaradoCentavos, destacado: true),
        ],
      ),
    );
  }
}

class _Renglon extends StatelessWidget {
  const _Renglon(this.etiqueta, this.centavos, {this.destacado = false});

  final String etiqueta;
  final int centavos;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      fontSize: destacado ? 16 : 14,
      fontWeight: destacado ? FontWeight.w800 : FontWeight.w500,
      color: Colores.tinta,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: estilo),
          Text(formatoPesos(importeDeCentavos(centavos)), style: estilo),
        ],
      ),
    );
  }
}
