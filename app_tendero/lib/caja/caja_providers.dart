import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/errores_de_api.dart';
import '../auth/auth_providers.dart';
import '../auth/session_state.dart';
import 'caja_models.dart';
import 'caja_repository.dart';

/// En qué punto está la caja del vendedor.
enum FaseCaja {
  /// Consultando al servidor (o todavía no hay sesión que consultar).
  cargando,

  /// No tiene caja abierta: no puede vender.
  cerrada,

  /// Tiene una caja abierta: puede vender.
  abierta,

  /// No se pudo saber (sin conexión, servidor caído...). Se puede reintentar.
  error,
}

/// Lo que la app sabe de la caja en este momento. Inmutable: para cambiarlo se crea otro.
class EstadoCaja {
  const EstadoCaja._({
    required this.fase,
    this.sesion,
    this.mensaje,
    this.trabajando = false,
  });

  const EstadoCaja.cargando() : this._(fase: FaseCaja.cargando);

  const EstadoCaja.cerrada({String? mensaje})
    : this._(fase: FaseCaja.cerrada, mensaje: mensaje);

  /// [aviso]: algo que conviene decirle al usuario aunque la caja esté abierta (por ejemplo, que ya la tenía abierta).
  const EstadoCaja.abierta(SesionCaja sesion, {String? aviso})
    : this._(fase: FaseCaja.abierta, sesion: sesion, mensaje: aviso);

  const EstadoCaja.error(String mensaje)
    : this._(fase: FaseCaja.error, mensaje: mensaje);

  final FaseCaja fase;

  /// La sesión de caja (solo en [FaseCaja.abierta]).
  final SesionCaja? sesion;

  /// Un error o aviso para mostrar, en español.
  final String? mensaje;

  /// `true` mientras se espera la respuesta del servidor a una apertura.
  final bool trabajando;

  /// Solo se puede vender con la caja abierta. El servidor también lo exige (403 sin caja abierta); esto evita que
  /// la app ofrezca vender para que el servidor lo rechace.
  bool get puedeVender => fase == FaseCaja.abierta;

  EstadoCaja enTrabajo() =>
      EstadoCaja._(fase: fase, sesion: sesion, trabajando: true);
}

final cajaRepositoryProvider = Provider<CajaRepository>(
  (ref) => CajaRepository(ref.watch(dioProvider)),
);

/// Estado de la caja de la persona que tiene la sesión abierta.
final cajaProvider = NotifierProvider<CajaNotifier, EstadoCaja>(
  CajaNotifier.new,
);

/// `true` si se puede vender ahora mismo (hay sesión y la caja está abierta).
final puedeVenderProvider = Provider<bool>(
  (ref) => ref.watch(cajaProvider).puedeVender,
);

class CajaNotifier extends Notifier<EstadoCaja> {
  CajaRepository get _repo => ref.read(cajaRepositoryProvider);

  /// Se incrementa cada vez que cambia la sesión. Una respuesta del servidor que llega «tarde», de una sesión
  /// anterior (alguien cerró sesión y entró otra persona), se descarta en vez de mostrarse en la cuenta nueva.
  int _generacion = 0;

  bool _obsoleto(int generacion) => generacion != _generacion || !ref.mounted;

  @override
  EstadoCaja build() {
    // `watch` hace que build() se ejecute DE NUEVO cada vez que cambia la fase de la sesión. Así, al cerrar
    // sesión la caja se reinicia sola y no queda a la vista la de la cuenta anterior.
    final fase = ref.watch(sesionProvider.select((e) => e.fase));
    _generacion++;
    if (fase == FaseSesion.activa) {
      Future.microtask(cargar);
    }
    return const EstadoCaja.cargando();
  }

  // ───────────────────────── acciones que llaman las pantallas ─────────────────────────

  /// [K1] Consulta si el vendedor tiene una caja abierta.
  Future<void> cargar() async {
    final g = _generacion;
    state = const EstadoCaja.cargando();
    await _leerEstado(g);
  }

  /// [K2] Abre la caja con el efectivo inicial, en pesos enteros (el 0 es válido).
  Future<void> abrir(int montoApertura) async {
    // Un segundo toque mientras se espera, o abrir cuando ya está abierta, no hace nada.
    if (state.trabajando || state.fase != FaseCaja.cerrada) {
      return;
    }
    final g = _generacion;
    state = state.enTrabajo();
    try {
      final resultado = await _repo.abrir(montoApertura);
      if (_obsoleto(g)) {
        return;
      }
      switch (resultado) {
        case CajaAbierta():
          await _leerEstado(g); // se muestra lo que el servidor guardó, no lo que escribió el usuario
        case CajaRechazada(yaEstabaAbierta: true):
          await _leerEstado(
            g,
            avisoSiAbierta: 'Ya tenías una caja abierta; se muestra esa.',
          );
        case CajaRechazada(mensaje: final m):
          state = EstadoCaja.cerrada(mensaje: m);
      }
    } on ErrorDeApi catch (e) {
      // La respuesta pudo perderse AUNQUE el servidor sí abriera la caja (contrato: no reintentar a ciegas). Antes de
      // decir que falló, se pregunta cómo quedó.
      if (_obsoleto(g)) {
        return;
      }
      await _leerEstado(g, avisoSiCerrada: e.mensaje);
    }
  }

  // ───────────────────────── pasos internos ─────────────────────────

  Future<void> _leerEstado(
    int g, {
    String? avisoSiAbierta,
    String? avisoSiCerrada,
  }) async {
    try {
      final sesion = await _repo.consultarSesion();
      if (_obsoleto(g)) {
        return;
      }
      state = sesion == null
          ? EstadoCaja.cerrada(mensaje: avisoSiCerrada)
          : EstadoCaja.abierta(sesion, aviso: avisoSiAbierta);
    } on ErrorDeApi catch (e) {
      if (!_obsoleto(g)) {
        state = EstadoCaja.error(e.mensaje);
      }
    } on DioException {
      // Por si algún día se escapa una excepción de Dio sin traducir.
      if (!_obsoleto(g)) {
        state = const EstadoCaja.error(
          'No se pudo consultar la caja. Inténtalo de nuevo.',
        );
      }
    }
  }
}
