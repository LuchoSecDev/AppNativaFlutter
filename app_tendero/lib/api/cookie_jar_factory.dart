import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';

/// Crea el «cajón de cookies» que SOBREVIVE a cerrar la app.
///
/// El servidor identifica al Tendero con una cookie de sesión (`connect.sid`). Si la app la guardara solo en
/// memoria, el Tendero tendría que iniciar sesión cada vez que cierra la app. `PersistCookieJar` la guarda en
/// archivos dentro de la carpeta privada de la app.
///
/// La sesión del servidor caduca a los 30 minutos sin actividad; guardar la cookie no la alarga, solo evita
/// perderla al cerrar la app dentro de ese plazo.
Future<CookieJar> crearCookieJarPersistente() async {
  final carpeta = await getApplicationDocumentsDirectory();
  final sep = Platform.pathSeparator;
  return PersistCookieJar(storage: FileStorage('${carpeta.path}$sep.cookies$sep'));
}
