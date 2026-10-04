import 'package:dio/dio.dart';

import '../api/errores_de_api.dart';
import '../api/session_interceptor.dart';
import 'auth_models.dart';

/// Habla con el servidor para todo lo de la sesión. Es el ÚNICO lugar que conoce las rutas y las respuestas de
/// la API de sesión: las pantallas y el estado nunca llaman a Dio directamente.
///
/// Convención: un resultado «esperable» (clave incorrecta, código vencido, ya hay otra sesión) se DEVUELVE como
/// un valor; solo las fallas de red o del servidor se lanzan como [ErrorDeApi].
class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  /// [S2] `POST /api/login`. Con [forzar] cierra la otra sesión de la app de la misma cuenta (solo Tendero).
  Future<ResultadoLogin> login({
    required String usuario,
    required String password,
    bool forzar = false,
  }) async {
    try {
      final r = await _dio.post<dynamic>(
        '/api/login',
        data: {
          'login': usuario,
          'password': password,
          if (forzar) 'force': true,
        },
      );
      final cuerpo = _mapa(r.data);
      if (cuerpo['require2FA'] == true) return const LoginRequiere2FA();
      final user = cuerpo['user'];
      if (user is Map<String, dynamic>) {
        return LoginExitoso(UsuarioSesion.desdeJson(user));
      }
      throw const ErrorDeApi(respuestaInesperada);
    } on DioException catch (e) {
      final estado = e.response?.statusCode;
      final cuerpo = _mapaONulo(e.response?.data);
      if (estado == 409 && cuerpo?['code'] == 'SESSION_ACTIVE') {
        return const LoginSesionActiva();
      }
      if (estado == 400 || estado == 401 || estado == 429) {
        return LoginRechazado(
          mensajeDelServidor(cuerpo) ?? 'No se pudo iniciar sesión.',
        );
      }
      throw ErrorDeApi(mensajeDeFalla(e));
    }
  }

  /// [S3] `POST /api/2fa/verify`: completa el login con el código de 6 dígitos.
  Future<ResultadoVerificacion> verificarCodigo2FA(String codigo) async {
    try {
      final r = await _dio.post<dynamic>(
        '/api/2fa/verify',
        data: {'token': codigo},
      );
      final user = _mapa(r.data)['user'];
      if (user is Map<String, dynamic>) {
        return VerificacionExitosa(UsuarioSesion.desdeJson(user));
      }
      throw const ErrorDeApi(respuestaInesperada);
    } on DioException catch (e) {
      final estado = e.response?.statusCode;
      if (estado == 400 || estado == 401 || estado == 429) {
        return VerificacionRechazada(
          mensajeDelServidor(_mapaONulo(e.response?.data)) ??
              'Código incorrecto.',
        );
      }
      throw ErrorDeApi(mensajeDeFalla(e));
    }
  }

  /// [S7] `PUT /api/perfil/first-password`: la contraseña definitiva de una cuenta nueva.
  Future<ResultadoCambioClave> cambiarClaveInicial(String nuevaClave) async {
    try {
      await _dio.put<dynamic>(
        '/api/perfil/first-password',
        data: {'newPassword': nuevaClave},
      );
      return const CambioClaveExitoso();
    } on DioException catch (e) {
      final estado = e.response?.statusCode;
      if (estado == 400) {
        return CambioClaveRechazado(
          mensajeDelServidor(_mapaONulo(e.response?.data)) ??
              'No se pudo cambiar la contraseña.',
        );
      }
      throw ErrorDeApi(mensajeDeFalla(e));
    }
  }

  /// [S4] `GET /api/session-info` justo después de iniciar sesión. Si no hay sesión, lanza [ErrorDeApi].
  Future<InfoSesion> infoDeSesion() async {
    try {
      final r = await _dio.get<dynamic>('/api/session-info');
      return InfoSesion.desdeJson(_mapa(r.data));
    } on DioException catch (e) {
      throw ErrorDeApi(mensajeDeFalla(e));
    }
  }

  /// Al abrir la app: ¿la cookie guardada todavía vale? Devuelve la sesión, o `null` si no hay (un 401 aquí es
  /// lo normal si caducó o nunca se inició, así que no se toma como «sesión caducada»).
  Future<InfoSesion?> restaurarSesion() async {
    try {
      final r = await _dio.get<dynamic>(
        '/api/session-info',
        options: Options(extra: {SessionInterceptor.sinAvisoDeCaducidad: true}),
      );
      return InfoSesion.desdeJson(_mapa(r.data));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return null;
      throw ErrorDeApi(mensajeDeFalla(e));
    }
  }

  /// [S5] `POST /api/logout`. Si falla (sin red), da igual: el usuario quiere salir y la app sale de todos modos.
  Future<void> cerrarSesion() async {
    try {
      await _dio.post<dynamic>('/api/logout', data: <String, dynamic>{});
    } on DioException {
      // Sin red o sesión ya inválida: no hay nada que hacer.
    }
  }

  /// Solo para depuración: ¿llega la app al servidor? No necesita sesión ni credenciales.
  Future<ResultadoConexion> probarConexion() async {
    final reloj = Stopwatch()..start();
    try {
      final r = await _dio.get<dynamic>('/api/csrf-token');
      return ResultadoConexion(duracion: reloj.elapsed, estado: r.statusCode);
    } on DioException catch (e) {
      if (e.response != null) {
        return ResultadoConexion(
          duracion: reloj.elapsed,
          estado: e.response!.statusCode,
        );
      }
      return ResultadoConexion(
        duracion: reloj.elapsed,
        error: mensajeDeFalla(e),
      );
    }
  }

  // ───────────────────────── utilidades ─────────────────────────

  Map<String, dynamic> _mapa(dynamic datos) {
    final mapa = _mapaONulo(datos);
    if (mapa == null) throw const ErrorDeApi(respuestaInesperada);
    return mapa;
  }

  Map<String, dynamic>? _mapaONulo(dynamic datos) =>
      datos is Map<String, dynamic> ? datos : null;
}
