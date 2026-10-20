import 'package:flutter/material.dart';

import '../../ui/colores.dart';
import '../../ui/formato.dart';
import '../egreso_models.dart';

/// Lo que se va a registrar (o se registró): monto, categoría y motivo. Lo comparten el comprobante y la pantalla de «gasto
/// sin confirmar», para que la persona vea exactamente qué gasto es.
class ResumenDelGasto extends StatelessWidget {
  const ResumenDelGasto({super.key, required this.egreso});

  final EgresoPendiente egreso;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Renglon(
          'Monto',
          formatoPesosEnteros(egreso.montoPesos),
          destacado: true,
        ),
        _Renglon('Categoría', egreso.categoria.valorApi),
        _Renglon('Motivo', egreso.motivo),
      ],
    );
  }
}

class _Renglon extends StatelessWidget {
  const _Renglon(this.etiqueta, this.valor, {this.destacado = false});

  final String etiqueta;
  final String valor;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(etiqueta, style: const TextStyle(color: Colores.tinta)),
          ),
          Expanded(
            child: Text(
              valor,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: destacado ? FontWeight.w800 : FontWeight.w600,
                fontSize: destacado ? 18 : 15,
                color: Colores.tinta,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
