/// Qué tan cerca está de vencer un producto, tal como lo calcula el servidor (`estado_vencimiento` en `[C1]` y `[C2]`).
enum TipoVencimiento {
  /// Ya venció (`dias` negativos).
  vencido,

  /// Vence hoy (`dias` = 0): todavía se vende.
  hoy,

  /// De 1 a 7 días.
  critico,

  /// De 8 a 30 días.
  proximo,
}

/// El vencimiento de un producto: de qué tipo y a cuántos días de calendario (negativo = ya venció). El servidor manda
/// `null` si el producto no tiene fecha o si faltan más de 30 días.
class EstadoVencimiento {
  const EstadoVencimiento({required this.tipo, required this.dias});

  final TipoVencimiento tipo;
  final int dias;

  /// `null` si no hay vencimiento (campo ausente o `null`) o si no tiene la forma esperada: un tipo que la app no
  /// conoce o `dias` ilegible se ignora en vez de romper la lista de productos. En ese caso el servidor sigue siendo
  /// quien decide al vender.
  static EstadoVencimiento? desdeJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final dias = json['dias'];
    if (dias is! num) {
      return null;
    }
    for (final tipo in TipoVencimiento.values) {
      if (tipo.name == json['tipo']) {
        return EstadoVencimiento(tipo: tipo, dias: dias.toInt());
      }
    }
    return null;
  }
}
