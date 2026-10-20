import 'venta_models.dart';

enum FaseCobro {
  /// No hay venta en curso: se puede cobrar el carrito.
  libre,

  /// Se está enviando al servidor (o esperando para reintentar).
  enviando,

  /// No se sabe si el servidor registró la venta. Solo se puede REINTENTAR (misma clave) o descartar con aviso.
  sinConfirmar,

  /// La venta quedó registrada. El carrito ya se vació.
  registrada,

  /// El servidor la rechazó sin registrar nada: se puede corregir el carrito y volver a cobrar.
  rechazada,
}

/// Lo que la app sabe del cobro en este momento. Inmutable.
class EstadoCobro {
  const EstadoCobro({
    this.fase = FaseCobro.libre,
    this.cargando = false,
    this.venta,
    this.mensaje,
    this.idVenta,
    this.repetida = false,
    this.intento = 0,
    this.sesionCaducada = false,
  });

  final FaseCobro fase;

  /// `true` mientras se lee del celular si quedó una venta a medias.
  final bool cargando;

  /// La venta en curso, sin confirmar o ya registrada.
  final VentaPendiente? venta;

  /// Un error o aviso para mostrar, en español.
  final String? mensaje;

  /// El número de la venta (solo en [FaseCobro.registrada]).
  final int? idVenta;

  /// `true` si el servidor devolvió una venta que ya estaba registrada (un reintento que no duplicó nada).
  final bool repetida;

  /// Cuántas veces se ha enviado esta venta (1 = el primer envío).
  final int intento;

  final bool sesionCaducada;

  /// Mientras hay un cobro sin resolver el carrito NO se puede tocar: el reintento debe enviar exactamente lo mismo
  /// que la primera vez, y la venta se registra una sola vez. También mientras aún no se sabe si quedó una a medias.
  bool get bloqueaElCarrito =>
      cargando || fase == FaseCobro.enviando || fase == FaseCobro.sinConfirmar;
}
