import 'package:flutter/material.dart';

import '../../ui/colores.dart';
import '../leyendas_de_producto.dart';

/// La píldora de color de una [Leyenda] del estado de un producto. La usan la lista de productos y la ficha, para que
/// digan lo mismo y con los mismos colores.
///
/// Con [conTooltip], mantener presionada la píldora muestra la ayuda de la web («Venció hace 3 días: retíralo de la
/// venta»); la ficha ya escribe la ayuda a la vista y la pide sin él.
class PildoraDeLeyenda extends StatelessWidget {
  const PildoraDeLeyenda(this.leyenda, {super.key, this.conTooltip = true});

  final Leyenda leyenda;
  final bool conTooltip;

  /// Fondo y letra de cada tono: el vencido es rojo sólido; los demás, un fondo suave con la letra del mismo color.
  static (Color fondo, Color letra) coloresDe(TonoLeyenda tono) =>
      switch (tono) {
        TonoLeyenda.vencido => (Colores.peligro, Colors.white),
        TonoLeyenda.peligro => (Colores.peligroSuave, Colores.peligro),
        TonoLeyenda.aviso => (Colores.avisoSuave, Colores.aviso),
        TonoLeyenda.exito => (
          Colores.exito.withValues(alpha: 0.12),
          Colores.exito,
        ),
        TonoLeyenda.informativo => (
          Colores.azul.withValues(alpha: 0.10),
          Colores.azul,
        ),
        TonoLeyenda.neutro => (Colors.grey.shade200, Colors.grey.shade700),
      };

  @override
  Widget build(BuildContext context) {
    final (fondo, letra) = coloresDe(leyenda.tono);
    final pildora = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        leyenda.texto,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: letra,
        ),
      ),
    );
    final ayuda = leyenda.ayuda;
    return conTooltip && ayuda != null
        ? Tooltip(message: ayuda, child: pildora)
        : pildora;
  }
}
