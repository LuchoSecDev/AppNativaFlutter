import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'egreso_models.dart';

/// Dónde se guarda en el celular el egreso que se está registrando, para poder reintentarlo con la MISMA clave si la
/// app se cierra o la sesión caduca antes de saber si el servidor lo registró. Es una interfaz para sustituirla en pruebas.
abstract class AlmacenEgresoPendiente {
  /// El egreso guardado bajo [clave], o `null` si no hay (o lo guardado está dañado).
  Future<EgresoPendiente?> leer(String clave);

  Future<void> guardar(String clave, EgresoPendiente egreso);

  Future<void> borrar(String clave);
}

/// El almacén real: `shared_preferences`.
class AlmacenEgresoPendienteLocal implements AlmacenEgresoPendiente {
  AlmacenEgresoPendienteLocal(this._preferencias);

  final SharedPreferences _preferencias;

  @override
  Future<EgresoPendiente?> leer(String clave) async {
    final texto = _preferencias.getString(clave);
    if (texto == null || texto.isEmpty) return null;
    try {
      return EgresoPendiente.desdeJson(jsonDecode(texto));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> guardar(String clave, EgresoPendiente egreso) async {
    await _preferencias.setString(clave, jsonEncode(egreso.aJson()));
  }

  @override
  Future<void> borrar(String clave) async {
    await _preferencias.remove(clave);
  }
}
