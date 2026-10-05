import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../auth/session_state.dart';
import '../caja/caja_providers.dart';
import '../carrito/carrito_models.dart';
import '../carrito/carrito_providers.dart';
import '../catalogo/catalogo_providers.dart';
import 'almacen_venta.dart';
import 'clave_de_venta.dart';
import 'venta_models.dart';
import 'venta_repository.dart';

/// Dónde se guarda la venta que se está cobrando. `main()` lo sustituye por el real (`shared_preferences`); las
/// pruebas, por uno en memoria.
final almacenVentaPendienteProvider = Provider<AlmacenVentaPendiente>(
  (ref) => throw UnimplementedError(
    'almacenVentaPendienteProvider se sustituye en main()',
  ),
);

final ventaRepositoryProvider = Provider<VentaRepository>(
  (ref) => VentaRepository(ref.watch(dioProvider)),
);

/// De dónde sale la `Idempotency-Key` de cada venta. Es un provider para que las pruebas puedan fijarla.
final generadorDeClaveProvider = Provider<String Function()>(
  (ref) => generarUuidV4,
);

/// Cuánto se espera antes de cada reintento automático tras un tiempo agotado o un error del servidor: 2 s y luego
/// 5 s (contrato [V2]). Si tras eso sigue sin respuesta, decide el Tendero.
final esperasDeReintentoProvider = Provider<List<Duration>>(
  (ref) => const [Duration(seconds: 2), Duration(seconds: 5)],
);

/// La pausa entre reintentos. Es un provider para que las pruebas no esperen de verdad.
final pausaDeReintentoProvider = Provider<Future<void> Function(Duration)>(
  (ref) =>
      (duracion) => Future<void>.delayed(duracion),
);

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

final cobroProvider = NotifierProvider<CobroNotifier, EstadoCobro>(
  CobroNotifier.new,
);

class CobroNotifier extends Notifier<EstadoCobro> {
  VentaRepository get _repo => ref.read(ventaRepositoryProvider);
  AlmacenVentaPendiente get _almacen => ref.read(almacenVentaPendienteProvider);

  /// Se incrementa cada vez que cambia la sesión: una respuesta tardía de la cuenta anterior se descarta (en el
  /// celular queda la venta pendiente de esa cuenta, y se reintenta al volver a entrar con ella).
  int _generacion = 0;

  /// Dónde se guarda la venta pendiente de ESTA persona en ESTA tienda.
  String? _clave;

  bool _obsoleto(int generacion) => generacion != _generacion || !ref.mounted;

  @override
  EstadoCobro build() {
    final sesion = ref.watch(
      sesionProvider.select((e) => (e.fase, e.info?.userId, e.info?.tiendaId)),
    );
    final (fase, userId, tiendaId) = sesion;
    _generacion++;

    if (fase == FaseSesion.activa && userId != null && tiendaId != null) {
      _clave = 'venta_pendiente_v1_${userId}_$tiendaId';
      Future.microtask(_recuperarPendiente);
      return const EstadoCobro(cargando: true);
    }
    _clave = null;
    return const EstadoCobro();
  }

  /// Al entrar: si quedó una venta a medias (la app se cerró o la sesión caducó al cobrar), se muestra como «sin
  /// confirmar». NO se reenvía sola: antes la persona tiene que verla.
  Future<void> _recuperarPendiente() async {
    final g = _generacion;
    final clave = _clave;
    if (clave == null) {
      return;
    }
    VentaPendiente? pendiente;
    try {
      pendiente = await _almacen.leer(clave);
    } on Object {
      pendiente = null;
    }
    if (_obsoleto(g)) {
      return;
    }
    state = pendiente == null
        ? const EstadoCobro()
        : EstadoCobro(
            fase: FaseCobro.sinConfirmar,
            venta: pendiente,
            mensaje: 'Quedó una venta sin confirmar. Reintenta para saber si se registró; no la cobres otra vez.',
          );
  }

  // ───────────────────────── acciones que llaman las pantallas ─────────────────────────

  /// Cobra el carrito: guarda la venta en el celular y la envía. El resultado queda en el estado.
  ///
  /// [efectivoRecibido] son pesos enteros y es obligatorio para [MetodoPago.efectivo]. La app valida que alcance para
  /// cubrir el total, pero quien decide es el servidor (que, hoy, no lo comprueba).
  Future<void> cobrar({
    required MetodoPago metodo,
    int? efectivoRecibido,
  }) async {
    final puede =
        !state.cargando &&
        _clave != null &&
        // El estado es el seguro contra el doble toque: al empezar a cobrar pasa de inmediato a «enviando».
        (state.fase == FaseCobro.libre || state.fase == FaseCobro.rechazada);
    if (!puede) {
      return;
    }
    final resumen = ref.read(resumenCarritoProvider);
    final rechazo = _motivoParaNoCobrar(resumen, metodo, efectivoRecibido);
    if (rechazo != null) {
      state = EstadoCobro(fase: FaseCobro.rechazada, mensaje: rechazo);
      return;
    }

    final venta = VentaPendiente(
      clave: ref.read(generadorDeClaveProvider)(),
      items: [
        for (final l in resumen.lineas)
          ItemVenta(idProducto: l.linea.idProducto, cantidad: l.linea.cantidad),
      ],
      metodoPago: metodo,
      totalCentavos: resumen.totalCentavos,
      efectivoRecibido: efectivoRecibido,
    );
    final g = _generacion;
    final clave = _clave!;
    state = EstadoCobro(fase: FaseCobro.enviando, venta: venta, intento: 1);
    try {
      // Primero se guarda y DESPUÉS se envía: si la app muere a mitad del envío, al volver se sabe que había una
      // venta y se reintenta con la misma clave. Si guardar falla, se vende igual (sin esa protección).
      await _almacen.guardar(clave, venta);
    } on Object {
      // sin copia en el celular
    }
    if (_obsoleto(g)) {
      return;
    }
    await _enviar(g, clave, venta);
  }

  /// Reintenta una venta sin confirmar con la MISMA clave y la misma carga: si el servidor ya la había registrado,
  /// devuelve esa misma venta (`repetida`) y no cobra de nuevo.
  Future<void> reintentar() async {
    final venta = state.venta;
    final clave = _clave;
    if (state.fase != FaseCobro.sinConfirmar ||
        venta == null ||
        clave == null) {
      return;
    }
    await _enviar(_generacion, clave, venta);
  }

  /// Renuncia a una venta sin confirmar. Es lo único que permite volver a cobrar el carrito con otra clave, y por eso
  /// la pantalla lo pide con una advertencia: si el servidor SÍ la había registrado, cobrar de nuevo la duplicaría.
  Future<void> descartarSinConfirmar() async {
    final clave = _clave;
    if (state.fase != FaseCobro.sinConfirmar || clave == null) {
      return;
    }
    state = const EstadoCobro();
    try {
      await _almacen.borrar(clave);
    } on Object {
      // si no se pudo borrar, al volver a entrar se mostrará de nuevo como sin confirmar
    }
  }

  /// Cierra el resultado (venta registrada o error) y deja todo listo para la siguiente venta.
  void aceptarResultado() {
    if (state.fase == FaseCobro.registrada ||
        state.fase == FaseCobro.rechazada) {
      state = const EstadoCobro();
    }
  }

  // ───────────────────────── pasos internos ─────────────────────────

  String? _motivoParaNoCobrar(
    ResumenCarrito resumen,
    MetodoPago metodo,
    int? efectivoRecibido,
  ) {
    if (!ref.read(puedeVenderProvider)) {
      return 'No hay una caja abierta. Abre la caja para vender.';
    }
    if (!resumen.sePuedeCobrar) {
      return 'El carrito tiene productos con problemas. Revísalos antes de cobrar.';
    }
    if (metodo == MetodoPago.efectivo) {
      if (efectivoRecibido == null ||
          efectivoRecibido <= 0 ||
          efectivoRecibido * 100 < resumen.totalCentavos) {
        return 'El efectivo recibido no alcanza para cubrir el total.';
      }
    }
    return null;
  }

  /// Envía la venta y, si no se sabe cómo terminó por un fallo pasajero, la reintenta con pausas. Siempre la MISMA
  /// [venta] (misma clave, mismo cuerpo).
  Future<void> _enviar(int g, String clave, VentaPendiente venta) async {
    final esperas = ref.read(esperasDeReintentoProvider);
    var intento = 0;
    try {
      while (true) {
        intento++;
        state = EstadoCobro(
          fase: FaseCobro.enviando,
          venta: venta,
          intento: intento,
          mensaje: state.fase == FaseCobro.enviando ? state.mensaje : null,
        );
        final resultado = await _repo.registrar(venta);
        if (_obsoleto(g)) {
          return;
        }
        switch (resultado) {
          case VentaRegistrada():
            await _alRegistrarse(g, clave, venta, resultado);
            return;
          case VentaRechazada():
            await _alRechazarse(g, clave, resultado);
            return;
          case VentaSinConfirmar():
            if (resultado.reintentoAutomatico && intento <= esperas.length) {
              state = EstadoCobro(
                fase: FaseCobro.enviando,
                venta: venta,
                intento: intento,
                mensaje: '${resultado.mensaje} Reintentando…',
              );
              await ref.read(pausaDeReintentoProvider)(esperas[intento - 1]);
              if (_obsoleto(g)) {
                return;
              }
              continue;
            }
            state = EstadoCobro(
              fase: FaseCobro.sinConfirmar,
              venta: venta,
              intento: intento,
              mensaje: resultado.mensaje,
              sesionCaducada: resultado.sesionCaducada,
            );
            return;
        }
      }
    } on Object {
      // Un error de programación: no se silencia (se relanza para que quede registrado), pero la pantalla no se
      // queda girando para siempre y la venta, que pudo registrarse, no se da por fallida.
      if (!_obsoleto(g)) {
        state = EstadoCobro(
          fase: FaseCobro.sinConfirmar,
          venta: venta,
          intento: intento,
          mensaje: 'Ocurrió un error inesperado. Reintenta para saber si la venta se registró.',
        );
      }
      rethrow;
    }
  }

  Future<void> _alRegistrarse(
    int g,
    String clave,
    VentaPendiente venta,
    VentaRegistrada r,
  ) async {
    state = EstadoCobro(
      fase: FaseCobro.registrada,
      venta: venta,
      idVenta: r.idVenta,
      repetida: r.repetida,
      intento: state.intento,
    );
    // Primero el carrito y después la venta pendiente: si la app muere entre los dos pasos, lo que sobra es la venta
    // pendiente, que al reintentarse devuelve la misma venta. Al revés, quedaría el carrito ya vendido listo para
    // cobrarse otra vez.
    ref.read(carritoProvider.notifier).vaciar();
    try {
      await _almacen.borrar(clave);
    } on Object {
      // si no se pudo borrar, el reintento posterior devuelve la misma venta y no la duplica
    }
    // El stock cambió en el servidor: se actualiza la lista (sin esperar) para no mostrar existencias viejas.
    if (!_obsoleto(g)) {
      unawaited(ref.read(catalogoProvider.notifier).cargar());
    }
  }

  Future<void> _alRechazarse(int g, String clave, VentaRechazada r) async {
    state = EstadoCobro(fase: FaseCobro.rechazada, mensaje: r.mensaje);
    try {
      await _almacen.borrar(
        clave,
      ); // el servidor no registró nada: no hay nada que reintentar
    } on Object {
      // si no se pudo borrar, al volver a entrar se mostrará como sin confirmar y un reintento dará el mismo rechazo
    }
    if (_obsoleto(g)) {
      return;
    }
    // Para que lo que se ve coincida con la realidad: una caja cerrada o un stock que cambió.
    if (r.cajaCerrada) {
      unawaited(ref.read(cajaProvider.notifier).cargar());
    } else {
      unawaited(ref.read(catalogoProvider.notifier).cargar());
    }
  }
}
