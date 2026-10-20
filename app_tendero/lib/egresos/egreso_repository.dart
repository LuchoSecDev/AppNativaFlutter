import 'package:dio/dio.dart';

import '../api/errores_de_api.dart';
import '../api/escritura_idempotente.dart';
import 'egreso_models.dart';

/// Habla con el servidor para registrar un egreso. Como `VentaRepository`, NO lanza excepciones por falla de red: cada
/// desenlace es un [ResultadoEgreso], porque al registrar dinero la diferencia entre «no se hizo» y «no sé si se hizo»
/// decide si se puede reintentar sin duplicar el gasto.
class EgresoRepository {
  EgresoRepository(this._dio);

  final Dio _dio;

  static const _ruta = '/api/caja/egreso';
  static const _claveReutilizada = 'IDEMPOTENCY_KEY_REUSED';

  /// `[K4]` `POST /api/caja/egreso` con la `Idempotency-Key` del egreso.
  ///
  /// Qué significa cada respuesta (contrato `[K4]`):
  ///  - 200: registrado (con `Idempotent-Replayed: true` si ya lo estaba).
  ///  - 400, 403, 413, 422: el servidor rechazó ANTES de registrar nada (sin caja abierta, monto, motivo, tope...). Un
  ///    egreso que falla no consume la clave.
  ///  - 401: no hay sesión; no se registró nada, pero se reintentará con la misma clave al volver a entrar.
  ///  - 429 y 5xx, o no llegar al servidor: no se sabe qué pasó; se reintenta con la MISMA clave.
  Future<ResultadoEgreso> registrar(EgresoPendiente egreso) async {
    try {
      final r = await _dio.post<dynamic>(
        _ruta,
        data: egreso.cuerpoDeLaPeticion(),
        // Se SUMA a las cabeceras que ya pone el cliente (Accept, X-Canal) y el interceptor (X-CSRF-Token).
        options: Options(headers: {'Idempotency-Key': egreso.clave}),
      );
      final registro = leerRegistro(r, 'id_egreso');
      if (registro != null) {
        return EgresoRegistrado(registro.id, repetido: registro.repetida);
      }
      // Un 200 sin `id_egreso` no debería existir. Reintentar con la misma clave devolvería lo mismo, así que no se hace
      // solo: se deja a la decisión de la persona. Nunca se da por registrado algo que no se pudo leer.
      return const EgresoSinConfirmar(
        respuestaInesperada,
        reintentoAutomatico: false,
      );
    } on DioException catch (e) {
      return _desdeElError(e);
    }
  }

  ResultadoEgreso _desdeElError(DioException e) {
    final fallo = clasificarFalloDeEscritura(
      e,
      mensajeSesionCaducada: 'La sesión caducó. Vuelve a entrar y reintenta: el gasto se registra una sola vez.',
    );
    switch (fallo) {
      case FalloSinConfirmar():
        return EgresoSinConfirmar(
          fallo.mensaje,
          reintentoAutomatico: fallo.reintentoAutomatico,
          sesionCaducada: fallo.sesionCaducada,
        );
      case FalloRechazado():
        final datos = fallo.datos;
        final claveReutilizada =
            fallo.estado == 422 &&
            datos is Map<String, dynamic> &&
            datos['code'] == _claveReutilizada;
        // 400 (sin caja, monto, motivo, tope), 403 (permiso o CSRF), 413 y 422: no se registró nada.
        return EgresoRechazado(
          fallo.mensaje ?? 'No se pudo registrar el gasto.',
          claveReutilizada: claveReutilizada,
        );
    }
  }
}
