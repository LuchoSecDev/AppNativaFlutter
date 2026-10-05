import 'package:dio/dio.dart';

import '../api/errores_de_api.dart';
import 'venta_models.dart';

/// Habla con el servidor para cobrar. A diferencia de los otros repositorios, NO lanza excepciones por falla de red:
/// cada desenlace posible es un [ResultadoVenta], porque al cobrar la diferencia entre «no se hizo» y «no sé si se
/// hizo» decide si se puede reintentar sin duplicar la venta.
class VentaRepository {
  VentaRepository(this._dio);

  final Dio _dio;

  /// [V2] `POST /api/registrar-venta-carrito` con la `Idempotency-Key` de la venta.
  ///
  /// Qué significa cada respuesta (contrato [V2] y [S6]):
  ///  - 200: registrada (con `Idempotent-Replayed: true` si ya lo estaba).
  ///  - 400, 403, 404, 422: el servidor rechazó ANTES de registrar nada. En 403 es porque no hay caja abierta.
  ///  - 401: no hay sesión; no se registró nada, pero se reintentará con la misma clave al volver a entrar.
  ///  - 429 y 5xx, o no llegar al servidor: no se sabe qué pasó; se reintenta con la MISMA clave.
  Future<ResultadoVenta> registrar(VentaPendiente venta) async {
    try {
      final r = await _dio.post<dynamic>(
        '/api/registrar-venta-carrito',
        data: venta.cuerpoDeLaPeticion(),
        // Se SUMA a las cabeceras que ya pone el cliente (Accept, X-Canal) y el interceptor (X-CSRF-Token).
        options: Options(headers: {'Idempotency-Key': venta.clave}),
      );
      final cuerpo = r.data;
      if (cuerpo is Map<String, dynamic> &&
          cuerpo['success'] == true &&
          cuerpo['id_venta'] is int) {
        return VentaRegistrada(
          cuerpo['id_venta'] as int,
          repetida: r.headers.value('idempotent-replayed') == 'true',
        );
      }
      // Un 200 sin `id_venta` no debería existir. Reintentar con la misma clave devolvería lo mismo, así que no
      // se hace solo: se deja a la decisión del Tendero.
      return const VentaSinConfirmar(
        respuestaInesperada,
        reintentoAutomatico: false,
      );
    } on DioException catch (e) {
      return _desdeElError(e);
    }
  }

  ResultadoVenta _desdeElError(DioException e) {
    final estado = e.response?.statusCode;
    if (estado == null) {
      // Sin respuesta: tiempo agotado, sin red... El servidor pudo haber registrado la venta.
      return VentaSinConfirmar(mensajeDeFalla(e));
    }
    final mensaje = mensajeDelServidor(e.response?.data);
    if (estado == 401) {
      return const VentaSinConfirmar(
        'La sesión caducó. Vuelve a entrar y reintenta: la venta se registra una sola vez.',
        reintentoAutomatico: false,
        sesionCaducada: true,
      );
    }
    if (estado == 429) {
      return VentaSinConfirmar(
        mensaje ?? 'Demasiadas peticiones. Espera un momento y reintenta.',
        reintentoAutomatico: false,
      );
    }
    if (estado >= 500) {
      return VentaSinConfirmar(mensajeDeFalla(e));
    }
    if (estado == 403) {
      // El 403 de «sin caja abierta» no trae `code`; el del token CSRF sí (y ya se reintentó una vez).
      final datos = e.response?.data;
      final esDeCsrf =
          datos is Map<String, dynamic> && datos['code'] == 'CSRF_INVALID';
      return VentaRechazada(
        mensaje ?? 'No tienes permiso para registrar esta venta.',
        cajaCerrada: !esDeCsrf,
      );
    }
    // 400 (stock, método de pago, cupo...), 404 (producto o cliente) y 422 (clave reutilizada): no se registró nada.
    return VentaRechazada(mensaje ?? 'No se pudo registrar la venta.');
  }
}
