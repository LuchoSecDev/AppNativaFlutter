import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/catalogo/estado_vencimiento.dart';
import 'package:stockpilot/catalogo/leyendas_de_producto.dart';
import 'package:stockpilot/catalogo/producto.dart';

import '../support/estado_producto_apoyo.dart';

/// Las leyendas del estado de un producto, con las MISMAS reglas que la web
/// (`frontend/src/utils/leyendasCatalogo.js` y `ProductTable.jsx` del backend).
void main() {
  Producto p({
    int cantidad = 5,
    String estado = 'Disponible',
    String nivelStock = 'ok',
    EstadoVencimiento? vence,
    bool sobrestock = false,
  }) => productoConEstado(
    'A',
    cantidad: cantidad,
    estado: estado,
    nivelStock: nivelStock,
    vence: vence,
    sobrestock: sobrestock,
  );

  /// «texto|tono» de cada leyenda, en el orden en que se muestran.
  List<String> resumen(Producto producto) => [
    for (final l in leyendasDeProducto(producto)) '${l.texto}|${l.tono.name}',
  ];

  String? ayudaDe(Producto producto) =>
      leyendasDeProducto(producto).single.ayuda;

  group('stock', () {
    test('Suficiente: disponible, nivel ok, sin vencimiento ni sobrestock', () {
      expect(resumen(p()), ['Suficiente|exito']);
    });

    test(
      'un nivel que la app no conoce se lee como suficiente, no como alarma',
      () {
        expect(resumen(p(nivelStock: 'raro')), ['Suficiente|exito']);
      },
    );

    test('los niveles que calcula el servidor', () {
      expect(resumen(p(cantidad: 0, nivelStock: 'agotado')), [
        'Agotado|peligro',
      ]);
      expect(resumen(p(nivelStock: 'critico')), ['Por agotarse|peligro']);
      expect(resumen(p(nivelStock: 'reponer')), ['Pedir más|aviso']);
    });

    test(
      'sin unidades es «Agotado» aunque el nivel diga ok, y nunca «Suficiente»',
      () {
        expect(resumen(p(cantidad: 0)), ['Agotado|peligro']);
      },
    );

    test('Sobrestock lleva su ayuda y quita el «Suficiente»', () {
      final l = leyendasDeProducto(p(sobrestock: true));
      expect([for (final x in l) x.texto], ['Sobrestock']);
      expect(l.single.tono, TonoLeyenda.informativo);
      expect(l.single.ayuda, 'Tienes más de lo que vendes: es capital quieto');
    });
  });

  group('vencimiento', () {
    test('vencido: rojo sólido, y la ayuda dice hace cuánto', () {
      final v = p(vence: vencimiento(TipoVencimiento.vencido, -3));
      expect(resumen(v), ['Vencido|vencido']);
      expect(ayudaDe(v), 'Venció hace 3 días: retíralo de la venta');
    });

    test('vencido ayer dice «Venció ayer»', () {
      final v = p(vence: vencimiento(TipoVencimiento.vencido, -1));
      expect(ayudaDe(v), 'Venció ayer: retíralo de la venta');
    });

    test('vence hoy, mañana y en N días: rojo suave hasta 7 días', () {
      final hoy = p(vence: vencimiento(TipoVencimiento.hoy, 0));
      expect(resumen(hoy), ['Vence hoy|peligro']);
      expect(ayudaDe(hoy), 'Vence hoy: véndelo hoy o retíralo');
      final manana = p(vence: vencimiento(TipoVencimiento.critico, 1));
      expect(resumen(manana), ['Vence mañana|peligro']);
      expect(ayudaDe(manana), 'Vence mañana: conviene rematarlo');
      final siete = p(vence: vencimiento(TipoVencimiento.critico, 7));
      expect(resumen(siete), ['Vence en 7 días|peligro']);
      expect(ayudaDe(siete), 'Vence en 7 días: conviene rematarlo');
    });

    test('de 8 a 30 días es ámbar', () {
      expect(resumen(p(vence: vencimiento(TipoVencimiento.proximo, 8))), [
        'Vence en 8 días|aviso',
      ]);
      expect(resumen(p(vence: vencimiento(TipoVencimiento.proximo, 30))), [
        'Vence en 30 días|aviso',
      ]);
    });
  });

  group('varias a la vez', () {
    test('en el orden de la web: stock, sobrestock, vencimiento', () {
      final v = p(
        nivelStock: 'reponer',
        sobrestock: true,
        vence: vencimiento(TipoVencimiento.proximo, 20),
      );
      expect(resumen(v), [
        'Pedir más|aviso',
        'Sobrestock|informativo',
        'Vence en 20 días|aviso',
      ]);
    });

    test('agotado y vencido a la vez: las dos', () {
      final v = p(
        cantidad: 0,
        nivelStock: 'agotado',
        vence: vencimiento(TipoVencimiento.vencido, -2),
      );
      expect(resumen(v), ['Agotado|peligro', 'Vencido|vencido']);
    });

    test(
      'un producto inactivo solo dice «Inactivo», sin importar lo demás',
      () {
        final v = p(
          estado: 'Inactivo',
          nivelStock: 'critico',
          sobrestock: true,
          vence: vencimiento(TipoVencimiento.vencido, -5),
        );
        expect(resumen(v), ['Inactivo|neutro']);
      },
    );

    test('FABRICADO: cada producto de la lista de ejemplo', () {
      final porNombre = {
        for (final x in productosDeEjemplo(
          '13b_C1_FABRICADO_estados_de_producto',
        ))
          x.nombre: resumen(x),
      };
      expect(porNombre, {
        'Yogur natural 1L': ['Vencido|vencido'],
        'Leche entera 1L': ['Vence hoy|peligro'],
        'Pan tajado': ['Vence en 3 días|peligro'],
        'Atún en lata': ['Vence en 20 días|aviso'],
        'Arroz Diana 50Kg': ['Sobrestock|informativo'],
        'Galletas de soda': ['Inactivo|neutro'],
      });
    });
  });
}
