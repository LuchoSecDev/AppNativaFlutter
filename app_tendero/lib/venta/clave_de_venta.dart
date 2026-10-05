import 'dart:math';

/// Un UUID versión 4 (aleatorio), por ejemplo `4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22`. Es la `Idempotency-Key` de cada
/// venta: 36 caracteres de letras, números y guiones, que el servidor acepta (contrato [V2]).
///
/// Se usa un generador criptográfico (`Random.secure`) para que dos ventas, aunque sean de dos celulares distintos,
/// no puedan coincidir por casualidad. [azar] solo se pasa en las pruebas.
String generarUuidV4([Random? azar]) {
  final r = azar ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // los 4 bits de «versión» valen 4
  b[8] = (b[8] & 0x3f) | 0x80; // los 2 bits de «variante» del estándar RFC 4122
  String h(int desde, int hasta) => [
    for (var i = desde; i < hasta; i++) b[i].toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
}
