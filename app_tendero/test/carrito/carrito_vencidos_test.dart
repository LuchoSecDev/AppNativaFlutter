import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/carrito/carrito_models.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/catalogo/catalogo_providers.dart';
import 'package:stockpilot/catalogo/estado_vencimiento.dart';
import 'package:stockpilot/catalogo/producto.dart';

import '../support/carrito_apoyo.dart';
import '../support/estado_producto_apoyo.dart';

/// El servidor rechaza TODO el carrito si trae un producto vencido con unidades (400 `PRODUCTO_VENCIDO`, ejemplo real
/// 45) o uno que no está disponible (400 `PRODUCTO_NO_DISPONIBLE`, ejemplo real 46). La app no lo deja ni agregar.
/// Lo que vence HOY todavía se vende.
void main() {
  late ProviderContainer c;
  late CatalogoFijo catalogo;

  Producto vencido({
    int id = 9,
    int cantidad = 4,
    String estado = 'Disponible',
  }) => productoConEstado(
    'Yogur natural 1L',
    id: id,
    cantidad: cantidad,
    estado: estado,
    vence: vencimiento(TipoVencimiento.vencido, -3),
  );

  Future<void> armar(
    List<Producto> productos, {
    List<LineaCarrito> lineas = const [],
  }) async {
    final almacen = AlmacenEnMemoria()..datos['carrito_v1_2_1'] = lineas;
    final a = armarContenedor(almacen: almacen, productos: productos);
    c = a.contenedor;
    catalogo = a.catalogo;
    addTearDown(c.dispose);
    c.listen(carritoProvider, (_, _) {});
    for (var i = 0; i < 100 && c.read(carritoProvider).cargando; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  CarritoNotifier carrito() => c.read(carritoProvider.notifier);
  ResumenCarrito resumen() => c.read(resumenCarritoProvider);

  group('al agregar', () {
    test('un producto vencido con unidades no se agrega', () async {
      await armar([]);
      expect(carrito().agregar(vencido()), ResultadoAgregar.vencido);
      expect(c.read(carritoProvider).lineas, isEmpty);
    });

    test('lo que vence hoy, en días o en un mes SÍ se agrega', () async {
      await armar([]);
      final casos = {
        1: vencimiento(TipoVencimiento.hoy, 0),
        2: vencimiento(TipoVencimiento.critico, 3),
        3: vencimiento(TipoVencimiento.proximo, 20),
      };
      for (final e in casos.entries) {
        expect(
          carrito().agregar(
            productoConEstado('P${e.key}', id: e.key, vence: e.value),
          ),
          ResultadoAgregar.agregado,
          reason: e.value.tipo.name,
        );
      }
      expect(c.read(carritoProvider).lineas, hasLength(3));
    });

    test('vencido SIN unidades es un agotado, no un vencido (igual que el servidor)', () async {
      await armar([]);
      expect(carrito().agregar(vencido(cantidad: 0)), ResultadoAgregar.agotado);
    });

    test('un producto no disponible gana sobre el vencimiento', () async {
      await armar([]);
      expect(
        carrito().agregar(vencido(estado: 'Inactivo')),
        ResultadoAgregar.noDisponible,
      );
    });

    test('el mensaje dice el nombre y que no se puede vender', () {
      expect(
        mensajeDeAgregar(ResultadoAgregar.vencido, vencido()),
        '«Yogur natural 1L» está vencido y no se puede vender.',
      );
    });

    test(
      'sumar una unidad a una línea cuyo producto ya venció tampoco deja',
      () async {
        final ok = productoConEstado('Yogur natural 1L', id: 9, cantidad: 4);
        await armar(
          [ok],
          lineas: [
            const LineaCarrito(idProducto: 9, nombre: 'Yogur', cantidad: 1),
          ],
        );
        expect(carrito().incrementar(9), ResultadoAgregar.agregado);
        catalogo.poner(EstadoCatalogo.listo([vencido()]));
        expect(carrito().incrementar(9), ResultadoAgregar.vencido);
        expect(c.read(carritoProvider).lineas.single.cantidad, 2);
      },
    );
  });

  group('lo que ya estaba en el carrito cuando el producto venció', () {
    const linea = LineaCarrito(idProducto: 9, nombre: 'Yogur', cantidad: 2);

    test('la línea queda con el problema «vencido» y no se puede cobrar', () async {
      await armar([vencido()], lineas: [linea]);
      final l = resumen().lineas.single;
      expect(l.problema, ProblemaLinea.vencido);
      expect(
        l.mensajeDelProblema,
        'Este producto está vencido y no se puede vender. Quítalo del carrito.',
      );
      expect(resumen().sePuedeCobrar, isFalse);
    });

    test('quitarla deja cobrar el resto', () async {
      final bueno = productoConEstado('Pan', id: 1);
      await armar(
        [vencido(), bueno],
        lineas: [
          linea,
          const LineaCarrito(idProducto: 1, nombre: 'Pan', cantidad: 1),
        ],
      );
      expect(resumen().sePuedeCobrar, isFalse);
      carrito().quitar(9);
      expect(resumen().sePuedeCobrar, isTrue);
    });

    test('lo que vence hoy se puede cobrar', () async {
      final hoy = productoConEstado(
        'Leche',
        id: 9,
        vence: vencimiento(TipoVencimiento.hoy, 0),
      );
      await armar([hoy], lineas: [linea]);
      expect(resumen().lineas.single.problema, ProblemaLinea.ninguno);
      expect(resumen().sePuedeCobrar, isTrue);
    });

    test(
      'inactivo manda sobre vencido; vencido manda sobre el stock',
      () async {
        await armar([vencido(estado: 'Inactivo')], lineas: [linea]);
        expect(resumen().lineas.single.problema, ProblemaLinea.inactivo);
        catalogo.poner(EstadoCatalogo.listo([vencido(cantidad: 1)]));
        expect(resumen().lineas.single.problema, ProblemaLinea.vencido);
      },
    );

    test(
      'si el producto se repone con fecha nueva, el problema desaparece solo',
      () async {
        await armar([vencido()], lineas: [linea]);
        expect(resumen().sePuedeCobrar, isFalse);
        catalogo.poner(
          EstadoCatalogo.listo([
            productoConEstado('Yogur natural 1L', id: 9, cantidad: 4),
          ]),
        );
        expect(resumen().sePuedeCobrar, isTrue);
      },
    );
  });
}
