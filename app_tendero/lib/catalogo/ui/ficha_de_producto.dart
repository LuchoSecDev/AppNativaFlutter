import 'package:flutter/material.dart';

import '../../ui/colores.dart';
import '../../ui/formato.dart';
import '../producto.dart';

/// Muestra los datos de un producto en una ficha centrada y flotante (no pegada al pie de la pantalla).
///
/// Se cierra con la X, con «Cerrar» o tocando fuera de ella. Solo consulta: no cambia nada del producto.
Future<void> mostrarFichaDeProducto(BuildContext context, Producto producto) =>
    showDialog<void>(
      context: context,
      builder: (_) => FichaDeProducto(producto: producto),
    );

/// La etiqueta del estado del stock de [p]: qué dice y de qué color es.
///
/// Un producto inactivo no se ofrece para vender, así que eso manda sobre su stock. Después, lo agotado se decide por
/// las unidades (no solo por lo que diga `nivelStock`), y lo demás sale del nivel que calcula el servidor.
({String texto, Color color}) estadoDeStock(Producto p) {
  if (!p.estaDisponible) {
    return (texto: 'Inactivo', color: Colors.grey.shade700);
  }
  if (p.agotado) return (texto: 'Agotado', color: Colores.peligro);
  return switch (p.nivelStock) {
    'agotado' => (texto: 'Agotado', color: Colores.peligro),
    'critico' => (texto: 'Stock crítico', color: Colores.peligro),
    'reponer' => (texto: 'Por reponer', color: Colores.aviso),
    _ => (texto: 'Disponible', color: Colores.exito),
  };
}

class FichaDeProducto extends StatelessWidget {
  const FichaDeProducto({super.key, required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context) {
    final p = producto;
    final estado = estadoDeStock(p);
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
                        _Etiqueta(texto: estado.texto, color: estado.color),
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

/// La píldora de color con el estado del stock.
class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color,
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
