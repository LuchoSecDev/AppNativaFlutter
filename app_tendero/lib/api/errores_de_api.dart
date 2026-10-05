import 'package:dio/dio.dart';

/// Falla de red o del servidor (sin conexión, tiempo agotado, error 5xx...). Lleva un mensaje listo para
/// mostrarle al usuario, en español y sin detalles técnicos.
///
/// Los resultados «esperables» (clave incorrecta, caja ya abierta...) NO son [ErrorDeApi]: los repositorios los
/// devuelven como valores. Esto es solo para lo inesperado.
class ErrorDeApi implements Exception {
  const ErrorDeApi(this.mensaje);

  final String mensaje;

  @override
  String toString() => 'ErrorDeApi($mensaje)';
}

/// El mensaje de un error del servidor: viene en `error` (o, a veces, en `message`). `null` si no hay.
String? mensajeDelServidor(dynamic cuerpo) {
  if (cuerpo is! Map<String, dynamic>) return null;
  final texto = cuerpo['error'] ?? cuerpo['message'];
  return texto is String && texto.isNotEmpty ? texto : null;
}

/// Mensaje para el usuario según el tipo de falla de red o del servidor.
String mensajeDeFalla(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'El servidor tardó demasiado en responder. Si estaba dormido, espera un momento e inténtalo otra vez.';
    case DioExceptionType.connectionError:
      return 'No hay conexión con el servidor. Revisa tu internet.';
    default:
      break;
  }
  final estado = e.response?.statusCode ?? 0;
  if (estado >= 500) {
    return 'El servidor tuvo un problema. Inténtalo de nuevo en un momento.';
  }
  return 'No se pudo completar la operación. Inténtalo de nuevo.';
}

/// Texto estándar para una respuesta que no tiene la forma esperada.
const String respuestaInesperada =
    'El servidor respondió algo inesperado. Inténtalo de nuevo.';
