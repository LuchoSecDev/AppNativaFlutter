// Aritmética de dinero sin números decimales.
//
// Los importes de la API llegan como TEXTO con dos decimales (`"12000.00"`). Con `double`, sumar o multiplicar
// introduce errores de redondeo (0.1 + 0.2 != 0.3), inaceptables en un total que el cliente va a pagar. Aquí todo
// se hace con ENTEROS de centavos: 12.000,00 pesos son 1.200.000 centavos, y sumar y multiplicar enteros es exacto.

/// Convierte un importe en texto (`"12000.00"`, `"4500.5"`, `"150"`) a centavos: `1200000`, `450050`, `15000`.
/// Devuelve `null` si no es un importe válido (negativo, con letras, con más de dos decimales...), en vez de
/// inventar una cifra.
int? centavosDeImporte(String importe) {
  final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(importe.trim());
  if (m == null) {
    return null;
  }
  final enteros = int.parse(m.group(1)!);
  final decimales = (m.group(2) ?? '').padRight(2, '0');
  return enteros * 100 + int.parse(decimales);
}

/// Lo inverso: `1200000` -> `"12000.00"`. Solo para valores no negativos.
String importeDeCentavos(int centavos) {
  assert(centavos >= 0, 'importeDeCentavos solo admite valores no negativos');
  final enteros = centavos ~/ 100;
  final decimales = (centavos % 100).toString().padLeft(2, '0');
  return '$enteros.$decimales';
}
