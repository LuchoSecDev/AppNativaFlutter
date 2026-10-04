import 'dart:convert';

import 'package:dio/dio.dart';

/// Aplica en UN solo lugar las reglas de sesión del contrato de la API (secciones 1 y 2 y [S6]), para que
/// ninguna pantalla tenga que repetirlas ni pueda olvidarlas.
///
/// Un «interceptor» es código que Dio ejecuta en cada petición: puede modificarla antes de enviarla
/// ([onRequest]), mirar la respuesta ([onResponse]) o reaccionar a un error ([onError]).
///
/// Reglas que implementa:
///  1. Toda ESCRITURA (POST, PUT, PATCH, DELETE) lleva la cabecera `X-CSRF-Token`. El token se pide una vez a
///     `GET /api/csrf-token` y se reutiliza mientras dure la sesión.
///  2. `POST /api/login` NO lleva token: el login regenera la sesión y un token pedido antes dejaría de valer.
///     Por eso, tras un login (o un logout) exitoso, el token guardado se descarta y se pide otro después.
///  3. Si el servidor responde `403` con `code: CSRF_INVALID`, se pide un token nuevo y se repite la petición
///     UNA sola vez (el servidor rechazó antes de procesar nada, así que repetir es seguro).
///  4. Un `401` en cualquier ruta protegida significa «sesión caducada o reemplazada»: se avisa con
///     [onSessionExpired] para volver al login. Se exceptúan `/api/login` y `/api/2fa/verify`, donde un 401
///     solo quiere decir «credenciales o código incorrectos».
class SessionInterceptor extends Interceptor {
  SessionInterceptor({
    required this.dio,
    required this.tokenDio,
    this.onSessionExpired,
  });

  /// El cliente principal. Se usa para REPETIR una petición (regla 3).
  final Dio dio;

  /// Un cliente aparte, SIN este interceptor, para pedir el token. Si pidiera el token con [dio], la petición
  /// del token pasaría por este mismo interceptor y se generaría un ciclo.
  final Dio tokenDio;

  /// Se llama cuando el servidor dice que ya no hay sesión (regla 4).
  final void Function()? onSessionExpired;

  static const _metodosDeEscritura = {'POST', 'PUT', 'PATCH', 'DELETE'};
  static const _rutaLogin = '/api/login';
  static const _rutasQueCambianLaSesion = {'/api/login', '/api/logout'};
  static const _rutasDondeElUnauthorizedEsNormal = {'/api/login', '/api/2fa/verify'};
  static const _marcaDeReintento = 'csrfReintentado';

  /// Marca para una petición cuyo 401 es esperable y NO significa «sesión caducada». Ejemplo: al abrir la app se
  /// pregunta si todavía hay sesión; un 401 ahí solo quiere decir «no hay», y no debe disparar el aviso.
  /// Uso: `Options(extra: {SessionInterceptor.sinAvisoDeCaducidad: true})`.
  static const sinAvisoDeCaducidad = 'sinAvisoDeCaducidad';

  /// El token guardado. `?` significa «puede ser nulo»: al inicio no hay ninguno.
  String? _csrfToken;

  /// Si dos escrituras salen a la vez y todavía no hay token, solo UNA lo pide y la otra espera el mismo.
  Future<String>? _pedidoEnCurso;

  Future<String> _obtenerToken() {
    final guardado = _csrfToken;
    if (guardado != null) return Future.value(guardado);
    return _pedidoEnCurso ??= _pedirToken().whenComplete(() => _pedidoEnCurso = null);
  }

  Future<String> _pedirToken() async {
    final respuesta = await tokenDio.get<dynamic>('/api/csrf-token');
    final datos = _comoMapa(respuesta.data);
    final token = datos?['csrfToken'];
    if (token is! String || token.isEmpty) {
      throw DioException(
        requestOptions: respuesta.requestOptions,
        response: respuesta,
        message: 'El servidor no devolvió un token CSRF válido.',
      );
    }
    _csrfToken = token;
    return token;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final esEscritura = _metodosDeEscritura.contains(options.method.toUpperCase());
    if (!esEscritura || options.uri.path == _rutaLogin) {
      handler.next(options);
      return;
    }
    try {
      options.headers['X-CSRF-Token'] = await _obtenerToken();
      handler.next(options);
    } on DioException catch (e) {
      // No se pudo conseguir el token (sin red, servidor dormido...): la petición original falla con ese error.
      handler.reject(DioException(requestOptions: options, error: e, response: e.response, type: e.type, message: e.message));
    }
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (_rutasQueCambianLaSesion.contains(response.requestOptions.uri.path)) {
      _csrfToken = null; // la sesión cambió: el token anterior ya no sirve
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final estado = err.response?.statusCode;
    final ruta = err.requestOptions.uri.path;

    // Regla 3: CSRF inválido -> pedir otro token y repetir UNA vez.
    final cuerpo = _comoMapa(err.response?.data);
    final yaSeReintento = err.requestOptions.extra[_marcaDeReintento] == true;
    if (estado == 403 && cuerpo?['code'] == 'CSRF_INVALID' && !yaSeReintento) {
      _csrfToken = null;
      err.requestOptions.extra[_marcaDeReintento] = true;
      try {
        // `fetch` vuelve a pasar por onRequest, que pedirá el token nuevo y lo pondrá en la cabecera.
        final repetida = await dio.fetch<dynamic>(err.requestOptions);
        handler.resolve(repetida);
      } on DioException catch (e) {
        handler.next(e);
      }
      return;
    }

    // Regla 4: sesión caducada o reemplazada.
    final avisarSiCaduco = err.requestOptions.extra[sinAvisoDeCaducidad] != true;
    if (estado == 401 && avisarSiCaduco && !_rutasDondeElUnauthorizedEsNormal.contains(ruta)) {
      _csrfToken = null;
      onSessionExpired?.call();
    }
    handler.next(err);
  }

  /// Dio ya convierte el JSON en un mapa cuando el servidor lo declara; si llegó como texto, se convierte aquí.
  Map<String, dynamic>? _comoMapa(dynamic datos) {
    if (datos is Map<String, dynamic>) return datos;
    if (datos is String && datos.isNotEmpty) {
      try {
        final decodificado = jsonDecode(datos);
        if (decodificado is Map<String, dynamic>) return decodificado;
      } on FormatException {
        return null;
      }
    }
    return null;
  }
}
