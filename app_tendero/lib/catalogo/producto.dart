/// Un producto del catálogo de la tienda (`GET /api/productos`, contrato [C1]).
///
/// Solo se guardan los campos que la app usa. Un Tendero NO recibe el costo de compra ni la clasificación ABC
/// (datos del margen del negocio): el servidor no se los manda.
class Producto {
  const Producto({
    required this.id,
    required this.codigo,
    required this.codigoBarras,
    required this.nombre,
    required this.categoria,
    required this.precio,
    required this.cantidad,
    required this.estado,
    required this.nivelStock,
  });

  final int id;

  /// Código interno (SKU) del producto. El escáner también lo reconoce.
  final String codigo;

  /// Código de barras comercial; `null` si el producto todavía no lo tiene asociado.
  final String? codigoBarras;

  final String nombre;
  final String categoria;

  /// Precio de venta. Llega como TEXTO con dos decimales (`"12000.00"`): para mostrarlo se usa `formatoPesos` y
  /// para hacer cuentas, un tipo decimal; nunca se suma texto.
  final String precio;

  /// Unidades en stock (siempre enteras).
  final int cantidad;

  /// `Disponible` o `Inactivo`.
  final String estado;

  /// `agotado`, `critico`, `reponer` u `ok`.
  final String nivelStock;

  /// Un producto inactivo no se ofrece para vender.
  bool get estaDisponible => estado == 'Disponible';

  bool get agotado => cantidad <= 0;

  factory Producto.desdeJson(Map<String, dynamic> json) {
    final barras = json['codigo_barras'];
    return Producto(
      id: (json['id_producto'] as num?)?.toInt() ?? 0,
      codigo: json['codigo']?.toString() ?? '',
      codigoBarras: barras == null || barras.toString().isEmpty
          ? null
          : barras.toString(),
      nombre: json['nombre_producto'] as String? ?? '',
      categoria: json['categoria'] as String? ?? '',
      precio: json['precio']?.toString() ?? '0.00',
      cantidad: (json['cantidad'] as num?)?.toInt() ?? 0,
      estado: json['estado'] as String? ?? 'Disponible',
      nivelStock: json['nivel_stock'] as String? ?? 'ok',
    );
  }
}
