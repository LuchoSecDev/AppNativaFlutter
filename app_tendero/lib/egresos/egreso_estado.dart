import 'egreso_models.dart';

enum FaseEgreso {
  /// No hay un gasto en curso: se puede registrar uno.
  libre,

  /// Se está enviando al servidor (o esperando para reintentar).
  enviando,

  /// No se sabe si el servidor registró el gasto. Solo se puede REINTENTAR (misma clave) o descartar con aviso.
  sinConfirmar,

  /// El gasto quedó registrado (pendiente de aprobación del Administrador).
  registrado,

  /// El servidor lo rechazó, o la app lo frenó antes de enviarlo: no se registró nada y se puede corregir.
  rechazado,
}

/// Lo que la app sabe del registro de un egreso en este momento. Inmutable.
class EstadoEgreso {
  const EstadoEgreso({
    this.fase = FaseEgreso.libre,
    this.cargando = false,
    this.egreso,
    this.mensaje,
    this.idEgreso,
    this.repetido = false,
    this.intento = 0,
    this.sesionCaducada = false,
  });

  final FaseEgreso fase;

  /// `true` mientras se lee del celular si quedó un gasto a medias.
  final bool cargando;

  /// El gasto en curso, sin confirmar o ya registrado.
  final EgresoPendiente? egreso;

  /// Un error o aviso para mostrar, en español.
  final String? mensaje;

  /// El número del gasto (solo en [FaseEgreso.registrado]).
  final int? idEgreso;

  /// `true` si el servidor devolvió un gasto que ya estaba registrado (un reintento que no duplicó nada).
  final bool repetido;

  /// Cuántas veces se ha enviado este gasto (1 = el primer envío).
  final int intento;

  final bool sesionCaducada;

  /// Mientras hay un gasto sin resolver el formulario NO se puede tocar: el reintento debe enviar exactamente lo mismo
  /// que la primera vez, y el gasto se registra una sola vez.
  bool get bloqueaElFormulario =>
      cargando ||
      fase == FaseEgreso.enviando ||
      fase == FaseEgreso.sinConfirmar;
}
