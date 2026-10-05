import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'carrito_models.dart';

/// Dónde se guarda el carrito en el celular, para no perderlo si la app se cierra o la sesión caduca a mitad de una
/// venta. Es una interfaz para poder sustituirla en las pruebas.
abstract class AlmacenCarrito {
  /// Lee las líneas guardadas bajo [clave]; lista vacía si no hay nada (o si lo guardado está dañado).
  Future<List<LineaCarrito>> leer(String clave);

  /// Guarda las líneas bajo [clave]; con una lista vacía borra lo guardado.
  Future<void> guardar(String clave, List<LineaCarrito> lineas);
}

/// El almacén real: `shared_preferences`, que guarda pares clave-texto en el celular.
class AlmacenCarritoLocal implements AlmacenCarrito {
  AlmacenCarritoLocal(this._preferencias);

  final SharedPreferences _preferencias;

  @override
  Future<List<LineaCarrito>> leer(String clave) async {
    final texto = _preferencias.getString(clave);
    if (texto == null || texto.isEmpty) {
      return const [];
    }
    try {
      final datos = jsonDecode(texto);
      if (datos is! List) {
        return const [];
      }
      // `?valor` agrega el elemento solo si no es nulo: las líneas dañadas (desdeJson devuelve null) se omiten.
      return [for (final d in datos) ?LineaCarrito.desdeJson(d)];
    } on FormatException {
      return const []; // texto dañado: se empieza con un carrito vacío en vez de fallar
    }
  }

  @override
  Future<void> guardar(String clave, List<LineaCarrito> lineas) async {
    if (lineas.isEmpty) {
      await _preferencias.remove(clave);
      return;
    }
    await _preferencias.setString(
      clave,
      jsonEncode([for (final l in lineas) l.aJson()]),
    );
  }
}
