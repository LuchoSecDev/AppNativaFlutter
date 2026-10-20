import 'package:flutter/material.dart';

import '../../ui/colores.dart';
import '../../ui/formato.dart';
import '../leyendas_de_producto.dart';
import '../producto.dart';
import 'pildora_de_leyenda.dart';

/// Muestra los datos de un producto en una ficha centrada y flotante (no pegada al pie de la pantalla).
///
/// Se cierra con la X, con «Cerrar» o tocando fuera de ella. Solo consulta: no cambia nada del producto.
Future<void> mostrarFichaDeProducto(BuildContext context, Producto producto) =>
    showDialog<void>(
      context: context,
      builder: (_) => FichaDeProducto(producto: producto),
    );

class FichaDeProducto extends StatelessWidget {
  const FichaDeProducto({super.key, required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context) {
    final p = producto;
    final leyendas = leyendasDeProducto(p);
    final unidades = '${p.cantidad} ${p.cantidad == 1 ? 'unidad' : 'unidades'}';

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 12, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        p.nombre,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colores.tinta,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      formatoPesos(p.precio),
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: Colores.azul,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final l in leyendas)
                          PildoraDeLeyenda(l, conTooltip: false),
                        Text(
                          unidades,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colores.tinta,
                          ),
                        ),
                      ],
                    ),
                    // La ayuda de cada leyenda, a la vista: qué pasó y qué conviene hacer.
                    for (final l in leyendas)
                      if (l.ayuda != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            l.ayuda!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    if (p.categoria.isNotEmpty)
                      _Dato(
                        icono: Icons.category_outlined,
                        titulo: 'Categoría',
                        valor: p.categoria,
                      ),
                    if (p.codigo.isNotEmpty)
                      _Dato(
                        icono: Icons.tag,
                        titulo: 'Código',
                        valor: p.codigo,
                      ),
                    _Dato(
                      icono: Icons.qr_code_2,
                      titulo: 'Código de barras',
                      valor: p.codigoBarras ?? 'Sin asociar',
                      apagado: p.codigoBarras == null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una fila de la ficha: ícono, qué dato es y su valor.
class _Dato extends StatelessWidget {
  const _Dato({
    required this.icono,
    required this.titulo,
    required this.valor,
    this.apagado = false,
  });

  final IconData icono;
  final String titulo;
  final String valor;

  /// Para lo que falta (por ejemplo, un código de barras sin asociar): se lee, pero sin llamar la atención.
  final bool apagado;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icono, size: 22, color: Colors.black45),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                Text(
                  valor,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: apagado ? Colors.black45 : Colores.tinta,
                    fontStyle: apagado ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
