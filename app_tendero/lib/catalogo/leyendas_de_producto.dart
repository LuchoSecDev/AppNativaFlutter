import 'estado_vencimiento.dart';
import 'producto.dart';

/// De qué color se pinta una leyenda. La pantalla traduce cada tono a colores; aquí solo se decide cuál es.
enum TonoLeyenda {
  /// Rojo sólido: lo ya vencido, lo más fuerte.
  vencido,

  /// Rojo suave: agotado, por agotarse, vence hoy o en 7 días o menos.
  peligro,

  /// Ámbar: pedir más o vence entre 8 y 30 días.
  aviso,

  /// Verde: suficiente.
  exito,

  /// Azul: sobrestock.
  informativo,

  /// Gris: inactivo.
  neutro,
}

/// Una leyenda del estado de un producto: lo que dice, de qué color y, si la hay, su texto de ayuda (qué pasó y qué
/// conviene hacer).
class Leyenda {
  const Leyenda(this.texto, this.tono, {this.ayuda});

  final String texto;
  final TonoLeyenda tono;
  final String? ayuda;
}

/// Las leyendas del estado de [p], con las MISMAS reglas y palabras que la web del Administrador
/// (`frontend/src/utils/leyendasCatalogo.js` y `ProductTable.jsx` del backend).
///
/// - Un producto inactivo no se ofrece para vender, así que eso manda y es la única leyenda.
/// - Si no, van en este orden: la de stock (Agotado / Por agotarse / Pedir más, o «Suficiente» si no hay nada que
///   decir), «Sobrestock» y la de vencimiento.
/// - «Suficiente» solo sale si NADA la contradice: ni stock bajo, ni sobrestock, ni vencimiento. De algo vencido, por
///   vencer o con exceso de stock no se puede decir que está «suficiente» sin más.
/// - Sin unidades es «Agotado» aunque el nivel del servidor diga otra cosa.
List<Leyenda> leyendasDeProducto(Producto p) {
  if (!p.estaDisponible) {
    return const [Leyenda('Inactivo', TonoLeyenda.neutro)];
  }
  final vencimiento = p.estadoVencimiento;
  final stock = _leyendaDeStock(p);
  return [
    ?stock,
    if (stock == null && !p.sobrestock && vencimiento == null)
      const Leyenda('Suficiente', TonoLeyenda.exito),
    if (p.sobrestock)
      const Leyenda(
        'Sobrestock',
        TonoLeyenda.informativo,
        ayuda: 'Tienes más de lo que vendes: es capital quieto',
      ),
    if (vencimiento != null) _leyendaDeVencimiento(vencimiento),
  ];
}

Leyenda? _leyendaDeStock(Producto p) {
  if (p.agotado) {
    return const Leyenda('Agotado', TonoLeyenda.peligro);
  }
  return switch (p.nivelStock) {
    'agotado' => const Leyenda('Agotado', TonoLeyenda.peligro),
    'critico' => const Leyenda('Por agotarse', TonoLeyenda.peligro),
    'reponer' => const Leyenda('Pedir más', TonoLeyenda.aviso),
    _ => null,
  };
}

Leyenda _leyendaDeVencimiento(EstadoVencimiento e) {
  if (e.tipo == TipoVencimiento.vencido) {
    final atras = e.dias.abs();
    final cuando = atras == 1 ? 'Venció ayer' : 'Venció hace $atras días';
    return Leyenda(
      'Vencido',
      TonoLeyenda.vencido,
      ayuda: '$cuando: retíralo de la venta',
    );
  }
  final texto = switch (e.dias) {
    0 => 'Vence hoy',
    1 => 'Vence mañana',
    _ => 'Vence en ${e.dias} días',
  };
  return Leyenda(
    texto,
    e.tipo == TipoVencimiento.proximo ? TonoLeyenda.aviso : TonoLeyenda.peligro,
    ayuda: e.dias == 0
        ? 'Vence hoy: véndelo hoy o retíralo'
        : '$texto: conviene rematarlo',
  );
}
