import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/catalogo/buscar_productos.dart';
import 'package:stockpilot/catalogo/producto.dart';

Producto p(
  String nombre, {
  int id = 1,
  String codigo = 'X-1',
  String? barras,
  String categoria = 'General',
  String estado = 'Disponible',
  int cantidad = 5,
}) => Producto(
  id: id,
  codigo: codigo,
  codigoBarras: barras,
  nombre: nombre,
  categoria: categoria,
  precio: '1000.00',
  cantidad: cantidad,
  estado: estado,
  nivelStock: 'ok',
);

List<String> nombres(List<Producto> r) => r.map((e) => e.nombre).toList();

void main() {
  group('normalizarTexto', () {
    test('quita tildes, pasa a minúsculas y ordena los espacios', () {
      expect(normalizarTexto('  CAFÉ   Molido  '), 'cafe molido');
      expect(normalizarTexto('Piñata'), 'pinata');
      expect(normalizarTexto('Ñandú Üñ'), 'nandu un');
    });
  });

  group('buscarProductos', () {
    final catalogo = [
      p(
        'Arroz Diana 1Kg',
        id: 1,
        codigo: 'ARR-001',
        barras: '7701234000011',
        categoria: 'Granos',
      ),
      p('Aceite Gourmet 1L', id: 2, codigo: 'ACE-001', categoria: 'Aceites'),
      p(
        'Café Sello Rojo 250g',
        id: 3,
        codigo: 'CAF-001',
        barras: '7709990000012',
        categoria: 'Bebidas',
      ),
      p('Arroz Roa 500g', id: 4, codigo: 'ARR-002', categoria: 'Granos'),
      p('Cuaderno 100 hojas', id: 5, codigo: 'PAP-001', categoria: 'Papelería'),
    ];

    test('sin texto devuelve todos, ordenados por nombre', () {
      expect(nombres(buscarProductos(catalogo, '')), [
        'Aceite Gourmet 1L',
        'Arroz Diana 1Kg',
        'Arroz Roa 500g',
        'Café Sello Rojo 250g',
        'Cuaderno 100 hojas',
      ]);
      expect(nombres(buscarProductos(catalogo, '   ')).length, 5);
    });

    test('no distingue mayúsculas ni tildes, en ninguno de los dos lados', () {
      expect(nombres(buscarProductos(catalogo, 'cafe')), [
        'Café Sello Rojo 250g',
      ]);
      expect(nombres(buscarProductos(catalogo, 'CAFÉ')), [
        'Café Sello Rojo 250g',
      ]);
      expect(nombres(buscarProductos(catalogo, 'papeleria')), [
        'Cuaderno 100 hojas',
      ]); // por categoría
    });

    test('varias palabras: todas deben aparecer, en cualquier orden', () {
      expect(nombres(buscarProductos(catalogo, 'aceite 1l')), [
        'Aceite Gourmet 1L',
      ]);
      expect(nombres(buscarProductos(catalogo, '1l aceite')), [
        'Aceite Gourmet 1L',
      ]);
      expect(buscarProductos(catalogo, 'arroz aceite'), isEmpty);
    });

    test('encuentra por código interno y por código de barras', () {
      expect(nombres(buscarProductos(catalogo, 'ARR-002')), ['Arroz Roa 500g']);
      expect(nombres(buscarProductos(catalogo, '7701234000011')), [
        'Arroz Diana 1Kg',
      ]);
      expect(nombres(buscarProductos(catalogo, '77099')), [
        'Café Sello Rojo 250g',
      ]); // parte del código
    });

    test('orden: coincidencia exacta de código, luego los que EMPIEZAN, luego los que contienen', () {
      final lista = [
        p('Salsa de arroz', id: 1, codigo: 'S-1'),
        p('Arroz Diana', id: 2, codigo: 'A-1'),
        p('Harina', id: 3, codigo: 'arroz'), // un código que ES «arroz»
        p('Bolsa para arroz', id: 4, codigo: 'B-1'),
      ];
      expect(nombres(buscarProductos(lista, 'arroz')), [
        'Harina',
        'Arroz Diana',
        'Bolsa para arroz',
        'Salsa de arroz',
      ]);
    });

    test('un texto sin coincidencias devuelve una lista vacía', () {
      expect(buscarProductos(catalogo, 'zzzz'), isEmpty);
    });

    test('los productos inactivos no se ofrecen, salvo que se pida', () {
      final lista = [p('Activo', id: 1), p('Viejo', id: 2, estado: 'Inactivo')];
      expect(nombres(buscarProductos(lista, '')), ['Activo']);
      expect(nombres(buscarProductos(lista, 'viejo')), isEmpty);
      expect(nombres(buscarProductos(lista, 'viejo', incluirInactivos: true)), [
        'Viejo',
      ]);
    });

    test('productos sin código de barras no rompen la búsqueda', () {
      expect(nombres(buscarProductos([p('Sin barras')], 'sin')), [
        'Sin barras',
      ]);
    });

    test(
      'los productos agotados SÍ aparecen (se ven, pero no se podrán agregar)',
      () {
        expect(
          nombres(buscarProductos([p('Agotado', cantidad: 0)], 'agotado')),
          ['Agotado'],
        );
      },
    );
  });
}
