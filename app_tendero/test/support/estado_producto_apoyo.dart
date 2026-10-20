import 'dart:convert';
import 'dart:io';

import 'package:stockpilot/catalogo/estado_vencimiento.dart';
import 'package:stockpilot/catalogo/producto.dart';

/// El `body` de un ejemplo de `test/fixtures/api` (los reales se copian del backend; el `13b` está FABRICADO).
Object? cuerpoDeEjemplo(String ejemplo) {
  final texto = File('test/fixtures/api/$ejemplo.json').readAsStringSync();
  final json = jsonDecode(texto) as Map<String, dynamic>;
  return (json['respuesta'] as Map<String, dynamic>)['body'];
}

/// Los productos de un ejemplo de `[C1]` (el cuerpo es una lista).
List<Producto> productosDeEjemplo(String ejemplo) => [
  for (final p in cuerpoDeEjemplo(ejemplo)! as List)
    Producto.desdeJson(p as Map<String, dynamic>),
];

/// Un producto con el estado que se quiera, para probar las reglas sin depender de un ejemplo.
Producto productoConEstado(
  String nombre, {
  int id = 1,
  int cantidad = 5,
  String precio = '1000.00',
  String estado = 'Disponible',
  String nivelStock = 'ok',
  EstadoVencimiento? vence,
  bool sobrestock = false,
}) => Producto(
  id: id,
  codigo: 'P-$id',
  codigoBarras: null,
  nombre: nombre,
  categoria: 'General',
  precio: precio,
  cantidad: cantidad,
  estado: estado,
  nivelStock: nivelStock,
  estadoVencimiento: vence,
  sobrestock: sobrestock,
);

EstadoVencimiento vencimiento(TipoVencimiento tipo, int dias) =>
    EstadoVencimiento(tipo: tipo, dias: dias);
