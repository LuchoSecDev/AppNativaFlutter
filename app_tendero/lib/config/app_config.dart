/// Configuración de la app que NO puede ir escrita en el código.
///
/// El repositorio es público, así que la dirección del servidor se entrega al compilar:
///
///     flutter run --dart-define=API_BASE_URL=https://mi-servidor.example.com
///
/// `String.fromEnvironment` lee ese valor en el momento de compilar. Si no se entrega, queda vacío.
class AppConfig {
  const AppConfig._();

  /// Dirección base del servidor, sin barra final. Ejemplo: `https://mi-servidor.example.com`.
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Falla con un mensaje claro si se olvidó `--dart-define=API_BASE_URL=...`, en vez de dejar que la app
  /// intente conectarse a una dirección vacía y muestre un error confuso.
  static void validar() {
    if (apiBaseUrl.isEmpty) {
      throw StateError(
        'Falta la dirección del servidor. Ejecuta con: '
        'flutter run --dart-define=API_BASE_URL=https://...',
      );
    }
  }
}
