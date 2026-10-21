import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Dónde se guarda en el celular lo que se está registrando (una venta, un gasto), para poder reintentarlo con la MISMA
/// clave si la app se cierra o la sesión caduca antes de saber si el servidor lo registró. Es una interfaz para
/// sustituirla en pruebas.
abstract class AlmacenPendiente<T> {
  /// Lo guardado bajo [clave], o `null` si no hay (o lo guardado está dañado).
  Future<T?> leer(String clave);

  Future<void> guardar(String clave, T pendiente);

  Future<void> borrar(String clave);
}

/// El almacén real: `shared_preferences`, con el pendiente guardado como texto JSON. [desdeJson] devuelve `null` si lo
/// leído no tiene la forma esperada (por ejemplo, de una versión vieja de la app): se ignora en vez de romper.
class AlmacenPendienteLocal<T> implements AlmacenPendiente<T> {
  AlmacenPendienteLocal(
    this.preferencias, {
    required this.desdeJson,
    required this.aJson,
  });

  final SharedPreferences preferencias;

  /// Devuelve `null` si lo leído no tiene la forma esperada.
  final T? Function(Object? json) desdeJson;
  final Map<String, dynamic> Function(T pendiente) aJson;

  @override
  Future<T?> leer(String clave) async {
    final texto = preferencias.getString(clave);
    if (texto == null || texto.isEmpty) {
      return null;
    }
    try {
      return desdeJson(jsonDecode(texto));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> guardar(String clave, T pendiente) async {
    await preferencias.setString(clave, jsonEncode(aJson(pendiente)));
  }

  @override
  Future<void> borrar(String clave) async {
    await preferencias.remove(clave);
  }
}
