import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../auth/session_state.dart';
import '../caja/caja_providers.dart';
// Las tres piezas son genéricas (clave, esperas y pausa de reintento); viven en venta/ solo por historia.
import '../venta/venta_providers.dart'
    show
        esperasDeReintentoProvider,
        generadorDeClaveProvider,
        pausaDeReintentoProvider;
import 'almacen_egreso.dart';
import 'egreso_borrador.dart';
import 'egreso_estado.dart';
import 'egreso_models.dart';
import 'egreso_reglas.dart';
import 'egreso_repository.dart';

/// Dónde se guarda el egreso que se está registrando. `main()` lo sustituye por el real (`shared_preferences`); las
/// pruebas, por uno en memoria.
final almacenEgresoPendienteProvider = Provider<AlmacenEgresoPendiente>(
  (ref) => throw UnimplementedError(
    'almacenEgresoPendienteProvider se sustituye en main()',
  ),
);

final egresoRepositoryProvider = Provider<EgresoRepository>(
  (ref) => EgresoRepository(ref.watch(dioProvider)),
);

final egresoProvider = NotifierProvider<EgresoNotifier, EstadoEgreso>(
  EgresoNotifier.new,
);

/// Registra gastos de caja chica sin duplicarlos: guarda el gasto con su clave ANTES de enviarlo, lo reenvía con la
/// MISMA clave si no se sabe cómo terminó, y descarta las respuestas de una sesión anterior.
class EgresoNotifier extends Notifier<EstadoEgreso> {
  EgresoRepository get _repo => ref.read(egresoRepositoryProvider);
  AlmacenEgresoPendiente get _almacen =>
      ref.read(almacenEgresoPendienteProvider);

  /// Se incrementa cada vez que cambia la sesión: una respuesta tardía de la cuenta anterior se descarta (en el
  /// celular queda el gasto pendiente de esa cuenta, y se reintenta al volver a entrar con ella).
  int _generacion = 0;

  /// Dónde se guarda el gasto pendiente de ESTA persona en ESTA tienda.
  String? _clave;

  bool _obsoleto(int generacion) => generacion != _generacion || !ref.mounted;

  @override
  EstadoEgreso build() {
    final (fase, userId, tiendaId) = ref.watch(
      sesionProvider.select((e) => (e.fase, e.info?.userId, e.info?.tiendaId)),
    );
    _generacion++;

    if (fase == FaseSesion.activa && userId != null && tiendaId != null) {
      _clave = 'egreso_pendiente_v1_${userId}_$tiendaId';
      Future.microtask(_recuperarPendiente);
      return const EstadoEgreso(cargando: true);
    }
    _clave = null;
    return const EstadoEgreso();
  }

  /// Al entrar: si quedó un gasto a medias (la app se cerró o la sesión caducó al registrarlo), se muestra como «sin
  /// confirmar». NO se reenvía solo: antes la persona tiene que verlo.
  Future<void> _recuperarPendiente() async {
    final g = _generacion;
    final clave = _clave;
    if (clave == null) return;
    EgresoPendiente? pendiente;
    try {
      pendiente = await _almacen.leer(clave);
    } on Object {
      pendiente = null;
    }
    if (_obsoleto(g)) return;
    state = pendiente == null
        ? const EstadoEgreso()
        : EstadoEgreso(
            fase: FaseEgreso.sinConfirmar,
            egreso: pendiente,
            mensaje: 'Quedó un gasto sin confirmar. Reintenta para saber si se registró; no lo registres otra vez.',
          );
  }

  // ───────────────────────── acciones que llaman las pantallas ─────────────────────────

  /// Registra un gasto: lo guarda en el celular y lo envía. El resultado queda en el estado. [montoPesos] son pesos
  /// enteros.
  Future<void> registrar({
    required int montoPesos,
    required String motivo,
    required CategoriaEgreso categoria,
  }) async {
    final puede =
        !state.cargando &&
        _clave != null &&
        // El estado es el seguro contra el doble toque: al empezar pasa de inmediato a «enviando».
        (state.fase == FaseEgreso.libre || state.fase == FaseEgreso.rechazado);
    if (!puede) return;

    final info = ref.read(sesionProvider).info;
    final rechazo = motivoParaNoRegistrar(
      cajaAbierta: ref.read(puedeVenderProvider),
      montoPesos: montoPesos,
      motivo: motivo,
      rol: info?.rol ?? '',
      limiteEgresoTendero: info?.limiteEgresoTendero ?? '',
    );
    if (rechazo != null) {
      state = EstadoEgreso(fase: FaseEgreso.rechazado, mensaje: rechazo);
      return;
    }

    final egreso = EgresoPendiente(
      clave: ref.read(generadorDeClaveProvider)(),
      montoPesos: montoPesos,
      motivo: motivo.trim(),
      categoria: categoria,
    );
    final g = _generacion;
    final clave = _clave!;
    state = EstadoEgreso(fase: FaseEgreso.enviando, egreso: egreso, intento: 1);
    try {
      // Primero se guarda y DESPUÉS se envía: si la app muere a mitad del envío, al volver se sabe que había un gasto
      // y se reintenta con la misma clave. Si guardar falla, se registra igual (sin esa protección).
      await _almacen.guardar(clave, egreso);
    } on Object {
      // sin copia en el celular
    }
    if (_obsoleto(g)) return;
    await _enviar(g, clave, egreso);
  }

  /// Reintenta un gasto sin confirmar con la MISMA clave y la misma carga: si el servidor ya lo había registrado,
  /// devuelve ese mismo gasto (`repetido`) y no lo registra de nuevo.
  Future<void> reintentar() async {
    final egreso = state.egreso;
    final clave = _clave;
    if (state.fase != FaseEgreso.sinConfirmar ||
        egreso == null ||
        clave == null) {
      return;
    }
    await _enviar(_generacion, clave, egreso);
  }

  /// Renuncia a un gasto sin confirmar. Es lo único que permite registrar otro con una clave nueva, y por eso la
  /// pantalla lo pide con una advertencia: si el servidor SÍ lo había registrado, registrarlo otra vez lo duplicaría.
  Future<void> descartarSinConfirmar() async {
    final clave = _clave;
    if (state.fase != FaseEgreso.sinConfirmar || clave == null) return;
    state = const EstadoEgreso();
    try {
      await _almacen.borrar(clave);
    } on Object {
      // si no se pudo borrar, al volver a entrar se mostrará de nuevo como sin confirmar
    }
  }

  /// Cierra el resultado (gasto registrado o rechazo) y deja todo listo para el siguiente.
  void aceptarResultado() {
    if (state.fase == FaseEgreso.registrado ||
        state.fase == FaseEgreso.rechazado) {
      state = const EstadoEgreso();
    }
  }

  // ───────────────────────── pasos internos ─────────────────────────

  /// Envía el gasto y, si no se sabe cómo terminó por un fallo pasajero, lo reintenta con pausas. Siempre el MISMO
  /// [egreso] (misma clave, mismo cuerpo).
  Future<void> _enviar(int g, String clave, EgresoPendiente egreso) async {
    final esperas = ref.read(esperasDeReintentoProvider);
    var intento = 0;
    try {
      while (true) {
        intento++;
        state = EstadoEgreso(
          fase: FaseEgreso.enviando,
          egreso: egreso,
          intento: intento,
          mensaje: state.fase == FaseEgreso.enviando ? state.mensaje : null,
        );
        final resultado = await _repo.registrar(egreso);
        if (_obsoleto(g)) return;
        switch (resultado) {
          case EgresoRegistrado():
            await _alRegistrarse(clave, egreso, resultado);
            return;
          case EgresoRechazado():
            await _alRechazarse(g, clave, resultado);
            return;
          case EgresoSinConfirmar():
            if (resultado.reintentoAutomatico && intento <= esperas.length) {
              state = EstadoEgreso(
                fase: FaseEgreso.enviando,
                egreso: egreso,
                intento: intento,
                mensaje: '${resultado.mensaje} Reintentando…',
              );
              await ref.read(pausaDeReintentoProvider)(esperas[intento - 1]);
              if (_obsoleto(g)) return;
              continue;
            }
            state = EstadoEgreso(
              fase: FaseEgreso.sinConfirmar,
              egreso: egreso,
              intento: intento,
              mensaje: resultado.mensaje,
              sesionCaducada: resultado.sesionCaducada,
            );
            return;
        }
      }
    } on Object {
      // Un error de programación: no se silencia (se relanza para que quede registrado), pero la pantalla no se queda
      // girando para siempre y el gasto, que pudo registrarse, no se da por fallido.
      if (!_obsoleto(g)) {
        state = EstadoEgreso(
          fase: FaseEgreso.sinConfirmar,
          egreso: egreso,
          intento: intento,
          mensaje: 'Ocurrió un error inesperado. Reintenta para saber si el gasto se registró.',
        );
      }
      rethrow;
    }
  }

  Future<void> _alRegistrarse(
    String clave,
    EgresoPendiente egreso,
    EgresoRegistrado r,
  ) async {
    state = EstadoEgreso(
      fase: FaseEgreso.registrado,
      egreso: egreso,
      idEgreso: r.idEgreso,
      repetido: r.repetido,
      intento: state.intento,
    );
    ref.read(borradorDeEgresoProvider.notifier).limpiar();
    try {
      await _almacen.borrar(clave);
    } on Object {
      // si no se pudo borrar, el reintento posterior devuelve el mismo gasto y no lo duplica
    }
  }

  Future<void> _alRechazarse(int g, String clave, EgresoRechazado r) async {
    state = EstadoEgreso(fase: FaseEgreso.rechazado, mensaje: r.mensaje);
    try {
      // El servidor no registró nada: no hay nada que reintentar.
      await _almacen.borrar(clave);
    } on Object {
      // si no se pudo borrar, al volver a entrar se mostrará como sin confirmar y un reintento dará el mismo rechazo
    }
    if (_obsoleto(g)) return;
    // Para que lo que se ve coincida con la realidad: pudo ser una caja cerrada desde la web. Se usa `actualizar` y no
    // `cargar`: éste pone la caja en «cargando» y `puedeVender` en falso mientras responde, y un reenvío inmediato
    // (la persona corrige y vuelve a tocar) se frenaría con un falso «no hay una caja abierta».
    unawaited(ref.read(cajaProvider.notifier).actualizar());
  }
}
