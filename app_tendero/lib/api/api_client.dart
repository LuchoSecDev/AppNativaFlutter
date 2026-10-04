import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'session_interceptor.dart';

/// Tiempo máximo de espera. El servidor gratuito se duerme tras 15 minutos sin tráfico y la primera petición
/// puede tardar cerca de un minuto en recibir respuesta (contrato, sección 1): por eso 70 segundos.
const Duration esperaMaximaDelServidor = Duration(seconds: 70);

/// Crea el cliente HTTP con el que la app habla con el servidor.
///
///  - [baseUrl]: dirección del servidor (ver `AppConfig`).
///  - [cookieJar]: dónde se guarda la cookie de sesión. En la app real, el persistente
///    (`crearCookieJarPersistente`); en las pruebas, uno en memoria (`CookieJar()`).
///  - [onSessionExpired]: qué hacer cuando el servidor dice que ya no hay sesión (volver al login).
///  - [adapter]: solo para pruebas; permite sustituir la red real por respuestas simuladas.
Dio crearClienteApi({
  required String baseUrl,
  required CookieJar cookieJar,
  void Function()? onSessionExpired,
  HttpClientAdapter? adapter,
}) {
  Dio nuevoCliente() {
    final cliente = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: esperaMaximaDelServidor,
      sendTimeout: esperaMaximaDelServidor,
      receiveTimeout: esperaMaximaDelServidor,
      headers: {
        // Sin esta cabecera, una petición sin sesión recibe una redirección HTML en vez de un 401 en JSON.
        'Accept': 'application/json',
        // Canal de la sesión. El contrato lo exige en el login y lo ignora en las demás peticiones, así que se
        // manda siempre: es imposible olvidarlo.
        'X-Canal': 'app',
      },
    ));
    if (adapter != null) cliente.httpClientAdapter = adapter;
    cliente.interceptors.add(CookieManager(cookieJar)); // guarda y reenvía la cookie de sesión
    return cliente;
  }

  final tokenDio = nuevoCliente(); // solo pide el token CSRF
  final dio = nuevoCliente(); // el que usa el resto de la app
  dio.interceptors.add(SessionInterceptor(dio: dio, tokenDio: tokenDio, onSessionExpired: onSessionExpired));
  return dio;
}
