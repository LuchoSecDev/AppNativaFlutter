import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'venta_models.dart';

/// Dónde se guarda en el celular la venta que se está cobrando, para poder reintentarla con la MISMA clave si la app
/// se cierra o la sesión caduca antes de saber si el servidor la registró. Es una interfaz para sustituirla en pruebas.
abstract class AlmacenVentaPendiente {
  /// La venta guardada bajo [clave], o `null` si no hay (o lo guardado está dañado).
  Future<VentaPendiente?> leer(String clave);

  Future<void> guardar(String clave, VentaPendiente venta);

  Future<void> borrar(String clave);
}

/// El almacén real: `shared_preferences`.
class AlmacenVentaPendienteLocal implements AlmacenVentaPendiente {
  AlmacenVentaPendienteLocal(this._preferencias);

  final SharedPreferences _preferencias;

  @override
  Future<VentaPendiente?> leer(String clave) async {
    final texto = _preferencias.getString(clave);
    if (texto == null || texto.isEmpty) {
      return null;
    }
    try {
      return VentaPendiente.desdeJson(jsonDecode(texto));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> guardar(String clave, VentaPendiente venta) async {
    await _preferencias.setString(clave, jsonEncode(venta.aJson()));
  }

  @override
  Future<void> borrar(String clave) async {
    await _preferencias.remove(clave);
  }
}
