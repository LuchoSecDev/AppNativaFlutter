import 'producto.dart';

/// Pasa un texto a una forma comparable: minúsculas, sin tildes ni diéresis, sin espacios repetidos. Así «Café»,
/// «cafe» y «CAFÉ» se encuentran entre sí, y quien escribe sin tildes (lo normal en un celular) no queda fuera.
String normalizarTexto(String texto) {
  const origen = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const destino = 'aaaaaeeeeiiiiooooouuuunc';
  final buffer = StringBuffer();
  for (final caracter in texto.toLowerCase().split('')) {
    final posicion = origen.indexOf(caracter);
    buffer.write(posicion >= 0 ? destino[posicion] : caracter);
  }
  return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Busca en el catálogo por lo que escribe el usuario. Se hace en el celular, sobre la lista ya descargada, porque
/// la API entrega todos los productos de la tienda sin paginar.
///
/// - Cada palabra escrita tiene que aparecer en algún lugar (nombre, categoría, código o código de barras), en
///   cualquier orden: «aceite 1l» encuentra «Aceite Gourmet 1L».
/// - Primero van los que coinciden exactamente con un código; luego los que EMPIEZAN con lo escrito; luego los que
///   lo contienen en el nombre; y al final los que solo coinciden por otro campo. Dentro de cada grupo, por nombre.
/// - Sin texto, devuelve todos ordenados por nombre.
/// - Los productos inactivos no se ofrecen (no se pueden vender), salvo que [incluirInactivos] sea `true`.
List<Producto> buscarProductos(
  List<Producto> productos,
  String consulta, {
  bool incluirInactivos = false,
}) {
  final candidatos = incluirInactivos
      ? productos
      : productos.where((p) => p.estaDisponible);
  final q = normalizarTexto(consulta);

  if (q.isEmpty) {
    return candidatos.toList()..sort(
      (a, b) => normalizarTexto(a.nombre).compareTo(normalizarTexto(b.nombre)),
    );
  }

  final palabras = q.split(' ');
  final encontrados = <({Producto producto, int grupo, String nombre})>[];

  for (final p in candidatos) {
    final nombre = normalizarTexto(p.nombre);
    final codigo = normalizarTexto(p.codigo);
    final barras = normalizarTexto(p.codigoBarras ?? '');
    final todo = '$nombre ${normalizarTexto(p.categoria)} $codigo $barras';
    if (!palabras.every(todo.contains)) {
      continue;
    }
    final int grupo;
    if (codigo == q || (barras.isNotEmpty && barras == q)) {
      grupo = 0;
    } else if (nombre.startsWith(q)) {
      grupo = 1;
    } else if (nombre.contains(q)) {
      grupo = 2;
    } else {
      grupo = 3;
    }
    encontrados.add((producto: p, grupo: grupo, nombre: nombre));
  }

  encontrados.sort((a, b) {
    final porGrupo = a.grupo.compareTo(b.grupo);
    return porGrupo != 0 ? porGrupo : a.nombre.compareTo(b.nombre);
  });
  return [for (final e in encontrados) e.producto];
}
