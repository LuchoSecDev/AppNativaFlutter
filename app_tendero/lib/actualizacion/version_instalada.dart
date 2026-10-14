import 'package:package_info_plus/package_info_plus.dart';

import 'actualizacion_models.dart';

/// Lee del sistema qué versión de la app está instalada.
///
/// `PackageInfo.buildNumber` es el `versionCode` de Android (lo que va después del `+` en `pubspec.yaml`) y `version` es el
/// nombre («1.0.0»). Si algo falla (no hay plugin, como en las pruebas, o el número no es un entero) devuelve `null`:
/// sin saber qué versión hay instalada no se puede comparar, y entonces la app NO bloquea ni avisa nada.
Future<VersionInstalada?> leerVersionInstaladaDelSistema() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final codigo = int.tryParse(info.buildNumber);
    if (codigo == null || codigo < 1) return null;
    return VersionInstalada(codigo: codigo, nombre: info.version);
  } catch (_) {
    return null;
  }
}
