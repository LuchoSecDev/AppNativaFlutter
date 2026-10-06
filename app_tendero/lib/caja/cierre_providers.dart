import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/errores_de_api.dart';
import '../auth/auth_providers.dart';
import '../venta/venta_providers.dart';
import 'caja_models.dart';
import 'caja_providers.dart';

/// En qué punto está el cierre de caja. Son tres tiempos (decisión del 5-oct-2026): contar y declarar, VER la
/// diferencia (y poder recontar) y confirmar.
enum FaseCierre {
  /// El Tendero cuenta el cajón y escribe el total.
  contando,

  /// Se está pidiendo el arqueo ([K5]); no cierra nada.
  calculando,

  /// Ve cuánto debería haber y la diferencia: puede recontar o confirmar.
  revisando,

  /// Se está cerrando la caja ([K3]).
  cerrando,

  /// La caja quedó cerrada (con el arqueo final, o sin él si no llegó).
  cerrada,

  /// No se sabe si la caja se cerró (se perdió la respuesta y tampoco se pudo consultar). Solo se puede COMPROBAR:
  /// cerrar no se repite a ciegas.
  sinConfirmar,
}

/// Lo que la app sabe del cierre en este momento. Inmutable.
class EstadoCierre {
  const EstadoCierre({
    this.fase = FaseCierre.contando,
    this.declaradoPesos,
    this.arqueoPrevio,
    this.arqueoFinal,
    this.mensaje,
    this.cambio = false,
  });

  final FaseCierre fase;

  /// Lo que el Tendero contó, en pesos enteros (se conserva al recontar).
  final int? declaradoPesos;

  /// El arqueo que vio al revisar ([K5]).
  final ArqueoCaja? arqueoPrevio;

  /// El arqueo del cierre real ([K3]), solo en [FaseCierre.cerrada].
  final ArqueoCaja? arqueoFinal;

  /// Un error o aviso para mostrar, en español.
  final String? mensaje;

  /// `true` si el arqueo final no coincide con el que vio al revisar: entre una cosa y otra se registró algo.
  final bool cambio;

  bool get enCurso =>
      fase == FaseCierre.calculando || fase == FaseCierre.cerrando;
}

final cierreProvider = NotifierProvider<CierreNotifier, EstadoCierre>(
  CierreNotifier.new,
);

class CierreNotifier extends Notifier<EstadoCierre> {
  /// Igual que en la caja y el carrito: una respuesta tardía de una sesión anterior se descarta.
  int _generacion = 0;

  bool _obsoleto(int generacion) => generacion != _generacion || !ref.mounted;

  @override
  EstadoCierre build() {
    ref.watch(sesionProvider.select((e) => (e.fase, e.info?.userId)));
    _generacion++;
    return const EstadoCierre();
  }

  /// Al entrar a la pantalla: empieza de cero, salvo que haya algo en curso (se perdería su resultado).
  void iniciar() {
    if (!state.enCurso && state.fase != FaseCierre.sinConfirmar) {
      state = const EstadoCierre();
    }
  }

  /// Paso 1 → 2. Con lo contado ([declaradoPesos]) pide el arqueo SIN cerrar nada. Es de solo lectura: si falla la
  /// red se puede repetir.
  Future<void> verArqueo(int declaradoPesos) async {
    if (state.fase != FaseCierre.contando) {
      return;
    }
    final bloqueo = _motivoParaNoCerrar();
    if (bloqueo != null) {
      state = EstadoCierre(declaradoPesos: declaradoPesos, mensaje: bloqueo);
      return;
    }
    final g = _generacion;
    state = EstadoCierre(
      fase: FaseCierre.calculando,
      declaradoPesos: declaradoPesos,
    );
    try {
      final resultado = await ref
          .read(cajaRepositoryProvider)
          .verArqueo(declaradoPesos);
      if (_obsoleto(g)) {
        return;
      }
      switch (resultado) {
        case ArqueoCalculado(:final arqueo):
          state = EstadoCierre(
            fase: FaseCierre.revisando,
            declaradoPesos: declaradoPesos,
            arqueoPrevio: arqueo,
          );
        case ArqueoRechazado(:final mensaje, :final sinCajaAbierta):
          if (sinCajaAbierta) {
            // La caja ya no está abierta (se cerró en la web): se actualiza lo que muestra el inicio.
            await ref.read(cajaProvider.notifier).cargar();
          }
          if (_obsoleto(g)) {
            return;
          }
          state = EstadoCierre(
            declaradoPesos: declaradoPesos,
            mensaje: mensaje,
          );
      }
    } on ErrorDeApi catch (e) {
      if (_obsoleto(g)) {
        return;
      }
      state = EstadoCierre(declaradoPesos: declaradoPesos, mensaje: e.mensaje);
    }
  }

  /// Paso 2 → 1: volver a contar. Lo escrito se conserva para corregirlo.
  void recontar() {
    if (state.fase != FaseCierre.revisando) {
      return;
    }
    state = EstadoCierre(declaradoPesos: state.declaradoPesos);
  }

  /// Paso 2 → cierre. Se cierra con el MISMO monto que el Tendero vio en el arqueo.
  ///
  /// El cierre no tiene idempotencia: si no llega la respuesta NO se reintenta; se consulta la caja ([K1]) para saber
  /// si se cerró.
  Future<void> confirmar() async {
    if (state.fase != FaseCierre.revisando) {
      return;
    }
    final declarado = state.declaradoPesos;
    final previo = state.arqueoPrevio;
    if (declarado == null) {
      return;
    }
    final bloqueo = _motivoParaNoCerrar();
    if (bloqueo != null) {
      state = EstadoCierre(
        fase: FaseCierre.revisando,
        declaradoPesos: declarado,
        arqueoPrevio: previo,
        mensaje: bloqueo,
      );
      return;
    }
    final g = _generacion;
    state = EstadoCierre(
      fase: FaseCierre.cerrando,
      declaradoPesos: declarado,
      arqueoPrevio: previo,
    );
    try {
      final resultado = await ref
          .read(cajaRepositoryProvider)
          .cerrar(declarado);
      if (_obsoleto(g)) {
        return;
      }
      switch (resultado) {
        case CierreExitoso(:final arqueo):
          await _alCerrarse(g, previo: previo, arqueo: arqueo);
        case CierreRechazado(:final mensaje, :final sinCajaAbierta):
          if (sinCajaAbierta) {
            await ref.read(cajaProvider.notifier).cargar();
            if (_obsoleto(g)) {
              return;
            }
            state = const EstadoCierre(
              fase: FaseCierre.cerrada,
              mensaje: 'La caja ya estaba cerrada (por ejemplo, se cerró desde la web).',
            );
          } else {
            state = EstadoCierre(declaradoPesos: declarado, mensaje: mensaje);
          }
      }
    } on ErrorDeApi catch (e) {
      if (_obsoleto(g)) {
        return;
      }
      await _comprobarSiSeCerro(
        g,
        declarado: declarado,
        previo: previo,
        motivo: e.mensaje,
      );
    }
  }

  /// Desde «sin confirmar»: vuelve a consultar la caja para saber si el cierre llegó a hacerse.
  Future<void> comprobar() async {
    if (state.fase != FaseCierre.sinConfirmar) {
      return;
    }
    await _comprobarSiSeCerro(
      _generacion,
      declarado: state.declaradoPesos,
      previo: state.arqueoPrevio,
      motivo: null,
    );
  }

  // ───────────────────────── pasos internos ─────────────────────────

  /// No se cierra la caja con una venta a medias: su reintento se registraría después del cierre y el efectivo no
  /// cuadraría. También mientras se está cobrando.
  String? _motivoParaNoCerrar() {
    final fase = ref.read(cobroProvider).fase;
    if (fase == FaseCobro.sinConfirmar || fase == FaseCobro.enviando) {
      return 'Hay una venta sin confirmar. Resuélvela (reintentarla) antes de cerrar la caja.';
    }
    return null;
  }

  Future<void> _alCerrarse(
    int g, {
    required ArqueoCaja? previo,
    required ArqueoCaja? arqueo,
  }) async {
    // El inicio debe mostrar «Caja cerrada» y bloquear Vender.
    await ref.read(cajaProvider.notifier).cargar();
    if (_obsoleto(g)) {
      return;
    }
    state = EstadoCierre(
      fase: FaseCierre.cerrada,
      arqueoPrevio: previo,
      arqueoFinal: arqueo,
      cambio:
          previo != null && arqueo != null && !arqueo.mismasCifrasQue(previo),
      mensaje: arqueo == null
          ? 'La caja se cerró, pero no llegó el resumen del arqueo. Puedes verlo en la web.'
          : null,
    );
  }

  Future<void> _comprobarSiSeCerro(
    int g, {
    required int? declarado,
    required ArqueoCaja? previo,
    required String? motivo,
  }) async {
    try {
      final sesion = await ref.read(cajaRepositoryProvider).consultarSesion();
      if (_obsoleto(g)) {
        return;
      }
      if (sesion == null) {
        // Sí se cerró: lo que se perdió fue la respuesta.
        await ref.read(cajaProvider.notifier).cargar();
        if (_obsoleto(g)) {
          return;
        }
        state = EstadoCierre(
          fase: FaseCierre.cerrada,
          arqueoPrevio: previo,
          mensaje: 'La caja se cerró, pero no llegó el resumen del arqueo. Puedes verlo en la web.',
        );
      } else {
        // Sigue abierta: no se cerró. Se puede confirmar de nuevo.
        state = EstadoCierre(
          fase: FaseCierre.revisando,
          declaradoPesos: declarado,
          arqueoPrevio: previo,
          mensaje:
              'No se pudo cerrar la caja${motivo == null ? '.' : ': $motivo'} La caja sigue abierta; inténtalo de nuevo.',
        );
      }
    } on ErrorDeApi catch (e) {
      if (_obsoleto(g)) {
        return;
      }
      state = EstadoCierre(
        fase: FaseCierre.sinConfirmar,
        declaradoPesos: declarado,
        arqueoPrevio: previo,
        mensaje:
            'No sabemos si la caja se cerró (${e.mensaje}) Revisa tu conexión y toca «Comprobar»; no la cierres otra vez.',
      );
    }
  }
}
