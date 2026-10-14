/// La versión de la app que está instalada en este celular.
///
/// [codigo] es el `versionCode` de Android (el número después del `+` de `version:` en `pubspec.yaml`); es el que se
/// compara con el del servidor. [nombre] es solo para mostrarlo («1.0.0»).
class VersionInstalada {
  const VersionInstalada({required this.codigo, required this.nombre});

  final int codigo;
  final String nombre;
}

/// [U1] `GET /api/app/version`: la última versión publicada de la app y la mínima que todavía funciona.
class VersionPublicada {
  const VersionPublicada({
    required this.versionCode,
    required this.versionName,
    required this.minVersionCode,
    this.notas = '',
  });

  final int versionCode;
  final String versionName;

  /// La versión más vieja que todavía puede usarse con el servidor. Si la instalada es menor, hay que actualizar.
  final int minVersionCode;

  /// Qué cambió, en una frase (puede venir vacío).
  final String notas;

  /// `null` si todavía no se publicó ninguna versión (`disponible: false`) o si la respuesta no tiene la forma esperada.
  /// Ante una respuesta rara NO se inventa nada: sin información, la app sigue funcionando como siempre.
  static VersionPublicada? desdeJson(dynamic json) {
    if (json is! Map<String, dynamic> || json['disponible'] != true) {
      return null;
    }
    final codigo = json['versionCode'];
    final minima = json['minVersionCode'];
    if (codigo is! int || codigo < 1 || minima is! int || minima < 1) {
      return null;
    }
    final nombre = json['versionName'];
    final notas = json['notas'];
    return VersionPublicada(
      versionCode: codigo,
      versionName: nombre is String && nombre.isNotEmpty ? nombre : '$codigo',
      minVersionCode: minima,
      notas: notas is String ? notas : '',
    );
  }
}

/// [U2] `GET /api/app/descarga` (solo con sesión): de dónde bajar el APK de la última versión.
class DescargaApp {
  const DescargaApp({
    required this.versionCode,
    required this.versionName,
    required this.url,
    required this.sha256,
    this.bytes,
  });

  final int versionCode;
  final String versionName;

  /// Siempre `https`. La dirección es privada: no se escribe en ningún repositorio ni se muestra en pantalla.
  final String url;

  /// Huella SHA-256 del APK, 64 caracteres hexadecimales en minúsculas. En esta fase el APK lo baja el navegador, así
  /// que la app todavía no la verifica; Android sí exige que la firma sea la misma al instalar una actualización.
  final String sha256;
  final int? bytes;

  Uri get enlace => Uri.parse(url);

  static final RegExp _huella = RegExp(r'^[0-9a-f]{64}$');

  /// `null` si falta algo o si la dirección no es una dirección `https` sin usuario ni clave incrustados.
  static DescargaApp? desdeJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final codigo = json['versionCode'];
    final url = json['url'];
    final huella = json['sha256'];
    if (codigo is! int || url is! String || huella is! String) return null;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final huellaMinuscula = huella.toLowerCase();
    if (!_huella.hasMatch(huellaMinuscula)) return null;
    final nombre = json['versionName'];
    final bytes = json['bytes'];
    return DescargaApp(
      versionCode: codigo,
      versionName: nombre is String && nombre.isNotEmpty ? nombre : '$codigo',
      url: url,
      sha256: huellaMinuscula,
      bytes: bytes is int && bytes > 0 ? bytes : null,
    );
  }
}
