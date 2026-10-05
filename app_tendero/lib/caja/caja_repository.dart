import 'package:dio/dio.dart';

import '../api/errores_de_api.dart';
import 'caja_models.dart';

/// Habla con el servidor para todo lo de la caja. Igual que `AuthRepository`: un resultado esperable se
/// DEVUELVE como valor; solo las fallas de red o del servidor se lanzan como [ErrorDeApi].
class CajaRepository {
  CajaRepository(this._dio);

  final Dio _dio;

  /// [K1] `GET /api/caja/sesion`. Devuelve la sesión abierta de ESTE vendedor, o `null` si no tiene caja abierta.
  /// (La caja es por vendedor: la que abrió el Administrador no cuenta.)
  Future<SesionCaja?> consultarSesion() async {
    try {
      final r = await _dio.get<dynamic>('/api/caja/sesion');
      final cuerpo = _mapa(r.data);
      if (cuerpo['active'] != true) return null;
      final sesion = cuerpo['session'];
      if (sesion is! Map<String, dynamic>) {
        throw const ErrorDeApi(respuestaInesperada);
      }
      return SesionCaja.desdeJson(sesion);
    } on DioException catch (e) {
      throw ErrorDeApi(mensajeDeFalla(e));
    }
  }

  /// [K2] `POST /api/caja/abrir` con el efectivo inicial, en pesos enteros (el 0 es válido).
  ///
  /// El servidor no tiene idempotencia aquí, pero tampoco hace falta: abrir es atómico por vendedor, así que una
  /// segunda apertura simultánea solo recibe «Ya tienes una sesión de caja abierta» y no duplica nada.
  Future<ResultadoAbrirCaja> abrir(int montoApertura) async {
    try {
      await _dio.post<dynamic>(
        '/api/caja/abrir',
        data: {'monto_apertura': montoApertura},
      );
      return const CajaAbierta();
    } on DioException catch (e) {
      if (e.response?.statusCode == 400) {
        final mensaje =
            mensajeDelServidor(e.response?.data) ?? 'No se pudo abrir la caja.';
        return CajaRechazada(
          mensaje,
          yaEstabaAbierta: mensaje.contains(
            'Ya tienes una sesión de caja abierta',
          ),
        );
      }
      throw ErrorDeApi(mensajeDeFalla(e));
    }
  }

  // ───────────────────────── utilidades ─────────────────────────

  Map<String, dynamic> _mapa(dynamic datos) {
    if (datos is Map<String, dynamic>) return datos;
    throw const ErrorDeApi(respuestaInesperada);
  }
}
