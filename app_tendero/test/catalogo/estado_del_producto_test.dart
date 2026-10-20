import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/catalogo/estado_vencimiento.dart';
import 'package:stockpilot/catalogo/leyendas_de_producto.dart';
import 'package:stockpilot/catalogo/producto.dart';

import '../support/estado_producto_apoyo.dart';

/// Lo que se lee del servidor sobre el estado de un producto (`estado_vencimiento` y `sobrestock`, contrato [C1] y
/// [C2]). Las leyendas que salen de ahí se prueban en `leyendas_de_producto_test.dart`.
void main() {
  group('lo que se lee del servidor', () {
    test('el ejemplo REAL de [C1]: sin vencimiento y sin sobrestock', () {
      final lista = productosDeEjemplo('13_C1_lista_de_productos');
      expect(lista, isNotEmpty);
      for (final p in lista) {
        expect(p.estadoVencimiento, isNull);
        expect(p.sobrestock, isFalse);
      }
    });

    test('el ejemplo REAL de [C2] (escáner) también trae el campo', () {
      final cuerpo =
          cuerpoDeEjemplo('11_C2_producto_por_codigo_de_barras')! as Map;
      final p = Producto.desdeJson(cuerpo['data'] as Map<String, dynamic>);
      expect(p.estadoVencimiento, isNull);
      expect(p.sobrestock, isFalse);
    });

    test('FABRICADO: los cuatro tipos de vencimiento y el sobrestock', () {
      final porNombre = {
        for (final p in productosDeEjemplo(
          '13b_C1_FABRICADO_estados_de_producto',
        ))
          p.nombre: p,
      };
      EstadoVencimiento? e(String n) => porNombre[n]!.estadoVencimiento;
      expect(e('Yogur natural 1L')?.tipo, TipoVencimiento.vencido);
      expect(e('Yogur natural 1L')?.dias, -3);
      expect(e('Leche entera 1L')?.tipo, TipoVencimiento.hoy);
      expect(e('Leche entera 1L')?.dias, 0);
      expect(e('Pan tajado')?.tipo, TipoVencimiento.critico);
      expect(e('Pan tajado')?.dias, 3);
      expect(e('Atún en lata')?.tipo, TipoVencimiento.proximo);
      expect(e('Atún en lata')?.dias, 20);
      expect(porNombre['Arroz Diana 50Kg']!.sobrestock, isTrue);
      expect(porNombre['Arroz Diana 50Kg']!.estadoVencimiento, isNull);
    });

    test(
      'sin los campos (respuesta de antes del cambio) todo sigue como hoy',
      () {
        final p = Producto.desdeJson({
          'id_producto': 1,
          'nombre_producto': 'Arroz',
          'precio': '1000.00',
          'cantidad': 3,
          'estado': 'Disponible',
          'nivel_stock': 'ok',
        });
        expect(p.estadoVencimiento, isNull);
        expect(p.sobrestock, isFalse);
        expect(leyendasDeProducto(p).map((l) => l.texto), ['Suficiente']);
      },
    );

    test('una forma rara se ignora en vez de romper la lista', () {
      for (final raro in <Object?>[
        'vencido',
        42,
        <String, Object?>{},
        {'tipo': 'otro_tipo_nuevo', 'dias': 1},
        {'tipo': 'vencido'},
        {'tipo': 'vencido', 'dias': 'tres'},
      ]) {
        final p = Producto.desdeJson({
          'id_producto': 1,
          'nombre_producto': 'Arroz',
          'cantidad': 3,
          'estado_vencimiento': raro,
          'sobrestock': 'si',
        });
        expect(p.estadoVencimiento, isNull, reason: '$raro');
        expect(p.sobrestock, isFalse, reason: '$raro');
      }
    });
  });

  group('vencido con unidades (lo que el servidor se niega a vender)', () {
    test('solo lo ya vencido Y con unidades', () {
      final vencido = vencimiento(TipoVencimiento.vencido, -1);
      expect(productoConEstado('A', vence: vencido).vencidoConUnidades, isTrue);
      expect(
        productoConEstado('A', cantidad: 0, vence: vencido).vencidoConUnidades,
        isFalse,
      );
      for (final t in [
        TipoVencimiento.hoy,
        TipoVencimiento.critico,
        TipoVencimiento.proximo,
      ]) {
        expect(
          productoConEstado('A', vence: vencimiento(t, 2)).vencidoConUnidades,
          isFalse,
        );
      }
      expect(productoConEstado('A').vencidoConUnidades, isFalse);
    });
  });
}
