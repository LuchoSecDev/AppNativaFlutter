import '../catalogo/producto.dart';

/// Una línea del carrito tal como se GUARDA en el celular: solo qué producto y cuántas unidades.
///
/// A propósito NO se guarda el precio ni el stock: se leen del catálogo cada vez que se muestra el carrito, así que
/// un cambio de precio o de stock se refleja solo y nunca se cobra con un dato viejo. El nombre se guarda únicamente
/// para poder mostrar la línea si el catálogo todavía no se ha descargado.
class LineaCarrito {
  const LineaCarrito({
    required this.idProducto,
    required this.nombre,
    required this.cantidad,
  });

  final int idProducto;
  final String nombre;
  final int cantidad;

  LineaCarrito conCantidad(int nueva) =>
      LineaCarrito(idProducto: idProducto, nombre: nombre, cantidad: nueva);

  Map<String, dynamic> aJson() => {
    'id': idProducto,
    'nombre': nombre,
    'cantidad': cantidad,
  };

  /// `null` si el dato guardado no tiene la forma esperada (por ejemplo, de una versión vieja o dañado): se ignora
  /// en vez de romper la app.
  static LineaCarrito? desdeJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final cantidad = json['cantidad'];
    if (id is! int || cantidad is! int || cantidad < 1) {
      return null;
    }
    return LineaCarrito(
      idProducto: id,
      nombre: json['nombre'] is String ? json['nombre'] as String : '',
      cantidad: cantidad,
    );
  }
}

/// Por qué una línea del carrito no se puede cobrar tal como está.
enum ProblemaLinea {
  ninguno,

  /// El catálogo todavía no se descargó: no se puede saber el precio ni el stock.
  esperandoCatalogo,

  /// El producto ya no está en el catálogo de la tienda.
  noEstaEnElCatalogo,

  /// El producto fue desactivado.
  inactivo,

  /// Hay menos unidades en stock que las del carrito.
  sinStockSuficiente,

  /// El producto no tiene precio (o es 0): vender algo a $0 casi siempre es un error de datos.
  sinPrecio,
}

/// Una línea del carrito junto con los datos ACTUALES del catálogo.
class LineaDetallada {
  const LineaDetallada({
    required this.linea,
    required this.producto,
    required this.precioUnitarioCentavos,
    required this.problema,
  });

  final LineaCarrito linea;

  /// El producto del catálogo, o `null` si no se encuentra (o el catálogo aún no llega).
  final Producto? producto;

  /// Precio de una unidad en centavos; `null` si no se pudo determinar.
  final int? precioUnitarioCentavos;

  final ProblemaLinea problema;

  String get nombre => producto?.nombre ?? linea.nombre;

  /// Precio de la línea (precio × unidades), en centavos; `null` si no se conoce el precio.
  int? get subtotalCentavos => precioUnitarioCentavos == null
      ? null
      : precioUnitarioCentavos! * linea.cantidad;

  bool get tieneProblema => problema != ProblemaLinea.ninguno;

  /// El texto que se le muestra al usuario, o `null` si no hay problema.
  String? get mensajeDelProblema => switch (problema) {
    ProblemaLinea.ninguno => null,
    ProblemaLinea.esperandoCatalogo => 'Esperando los datos del catálogo…',
    ProblemaLinea.noEstaEnElCatalogo =>
      'Este producto ya no está en el catálogo.',
    ProblemaLinea.inactivo => 'Este producto está inactivo.',
    ProblemaLinea.sinStockSuficiente =>
      'Solo hay ${producto?.cantidad ?? 0} ${producto?.cantidad == 1 ? 'unidad' : 'unidades'} en stock.',
    ProblemaLinea.sinPrecio =>
      'Este producto no tiene precio. Pide al administrador que se lo asigne.',
  };
}

/// El carrito completo, ya con precios y total.
class ResumenCarrito {
  const ResumenCarrito({required this.lineas});

  final List<LineaDetallada> lineas;

  bool get estaVacio => lineas.isEmpty;

  /// Total de unidades (no de líneas).
  int get unidades => lineas.fold(0, (suma, l) => suma + l.linea.cantidad);

  /// Suma de los subtotales conocidos, en centavos. Exacta: son enteros.
  int get totalCentavos =>
      lineas.fold(0, (suma, l) => suma + (l.subtotalCentavos ?? 0));

  bool get hayProblemas => lineas.any((l) => l.tieneProblema);

  /// Hay algo para cobrar y todo está en orden.
  bool get sePuedeCobrar => !estaVacio && !hayProblemas;
}

/// Qué pasó al intentar agregar un producto al carrito.
enum ResultadoAgregar {
  agregado,
  agotado,
  noDisponible,
  sinPrecio,

  /// Ya hay en el carrito todas las unidades que hay en stock.
  limiteDeStock,

  /// El carrito todavía se está leyendo del almacenamiento del celular.
  cargando,

  /// Hay un cobro en curso o sin confirmar: el carrito no se puede cambiar hasta resolverlo.
  ventaEnCurso,
}

/// Qué decirle al usuario cuando no se pudo agregar un producto al carrito. `null` si se agregó. Lo usan el carrito
/// y el escáner de venta, para que digan lo mismo.
String? mensajeDeAgregar(ResultadoAgregar r, Producto p) => switch (r) {
  ResultadoAgregar.agregado => null,
  ResultadoAgregar.agotado => '«${p.nombre}» está agotado.',
  ResultadoAgregar.noDisponible => '«${p.nombre}» está inactivo.',
  ResultadoAgregar.sinPrecio =>
    '«${p.nombre}» no tiene precio. Pide al administrador que se lo asigne.',
  ResultadoAgregar.limiteDeStock =>
    'Ya agregaste todas las unidades que hay de «${p.nombre}».',
  ResultadoAgregar.cargando => 'Un momento: se está preparando el carrito.',
  ResultadoAgregar.ventaEnCurso =>
    'Hay un cobro en curso: no se puede cambiar el carrito hasta resolverlo.',
};
