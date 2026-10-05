import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stockpilot/auth/session_state.dart';
import 'package:stockpilot/carrito/almacen_carrito.dart';
import 'package:stockpilot/carrito/carrito_models.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/catalogo/catalogo_providers.dart';

import '../support/carrito_apoyo.dart';

void main() {
  group('AlmacenCarritoLocal (shared_preferences)', () {
    late AlmacenCarritoLocal almacen;

    Future<void> preparar([Map<String, Object> inicial = const {}]) async {
      SharedPreferences.setMockInitialValues(inicial);
      almacen = AlmacenCarritoLocal(await SharedPreferences.getInstance());
    }

    test('guarda y lee las líneas, sin perder nada', () async {
      await preparar();
      const lineas = [
        LineaCarrito(idProducto: 1, nombre: 'Arroz Diana 1Kg', cantidad: 2),
        LineaCarrito(idProducto: 5, nombre: 'Café «Sello» Rojo', cantidad: 1),
      ];
      await almacen.guardar('k', lineas);
      final leidas = await almacen.leer('k');
      expect(leidas.map((l) => l.aJson()), lineas.map((l) => l.aJson()));
    });

    test('sin nada guardado devuelve una lista vacía', () async {
      await preparar();
      expect(await almacen.leer('k'), isEmpty);
    });

    test('guardar una lista vacía borra lo guardado', () async {
      await preparar();
      await almacen.guardar('k', const [
        LineaCarrito(idProducto: 1, nombre: 'A', cantidad: 1),
      ]);
      await almacen.guardar('k', const []);
      expect(await almacen.leer('k'), isEmpty);
    });

    test(
      'un texto dañado se ignora (carrito vacío) en vez de romper la app',
      () async {
        await preparar({'k': '{esto no es json'});
        expect(await almacen.leer('k'), isEmpty);
      },
    );

    test('un JSON válido pero con otra forma se ignora', () async {
      await preparar({'k': '{"id": 1}'});
      expect(await almacen.leer('k'), isEmpty);
    });

    test('las líneas dañadas se omiten y las buenas se conservan', () async {
      await preparar({
        'k': '[{"id":1,"nombre":"Bueno","cantidad":2},{"id":"x"},{"id":2,"cantidad":0},{"id":3,"cantidad":-1},"basura",null,{"id":4,"cantidad":1}]',
      });
      final leidas = await almacen.leer('k');
      expect(leidas.map((l) => l.idProducto), [1, 4]);
      expect(leidas.first.cantidad, 2);
    });

    test('carritos de claves distintas no se mezclan', () async {
      await preparar();
      await almacen.guardar('a', const [
        LineaCarrito(idProducto: 1, nombre: 'A', cantidad: 1),
      ]);
      await almacen.guardar('b', const [
        LineaCarrito(idProducto: 2, nombre: 'B', cantidad: 3),
      ]);
      expect((await almacen.leer('a')).single.idProducto, 1);
      expect((await almacen.leer('b')).single.cantidad, 3);
    });
  });

  group('CarritoNotifier', () {
    late AlmacenEnMemoria almacen;
    late ProviderContainer c;
    late SesionFija sesion;
    late CatalogoFijo catalogo;

    final arroz = producto(
      1,
      'Arroz Diana 1Kg',
      precio: '4500.00',
      cantidad: 10,
    );
    final aceite = producto(
      2,
      'Aceite Gourmet 1L',
      precio: '12000.00',
      cantidad: 5,
    );

    void armar({List<dynamic>? productos, AlmacenEnMemoria? con}) {
      almacen = con ?? AlmacenEnMemoria();
      final a = armarContenedor(
        almacen: almacen,
        productos: [arroz, aceite, ...?productos?.cast()],
      );
      c = a.contenedor;
      sesion = a.sesion;
      catalogo = a.catalogo;
      addTearDown(c.dispose);
    }

    CarritoNotifier carrito() => c.read(carritoProvider.notifier);
    EstadoCarrito estado() => c.read(carritoProvider);

    /// Lee el carrito (lo que dispara la carga) y espera a que termine de cargar.
    Future<void> cargado() async {
      c.listen(carritoProvider, (_, _) {});
      for (var i = 0; i < 100 && estado().cargando; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(estado().cargando, isFalse);
    }

    test('arranca «cargando» y termina con el carrito vacío si no había nada guardado', () async {
      armar();
      expect(estado().cargando, isTrue);
      await cargado();
      expect(estado().lineas, isEmpty);
    });

    test('recupera lo que había guardado para ESTA persona y tienda', () async {
      final previo = AlmacenEnMemoria()
        ..datos['carrito_v1_2_1'] = const [
          LineaCarrito(idProducto: 1, nombre: 'Arroz Diana 1Kg', cantidad: 3),
        ];
      armar(con: previo);
      await cargado();
      expect(estado().lineas.single.cantidad, 3);
    });

    test('agregar un producto nuevo pone 1 unidad; el mismo producto suma de a una', () async {
      armar();
      await cargado();
      expect(carrito().agregar(arroz), ResultadoAgregar.agregado);
      expect(estado().lineas.single.cantidad, 1);
      expect(carrito().agregar(arroz), ResultadoAgregar.agregado);
      expect(estado().lineas.single.cantidad, 2);
      expect(estado().lineas, hasLength(1));
    });

    test('cada cambio se guarda en el celular', () async {
      armar();
      await cargado();
      carrito().agregar(arroz);
      carrito().agregar(aceite);
      await Future<void>.delayed(Duration.zero);
      expect(almacen.datos['carrito_v1_2_1']!.map((l) => l.idProducto), [1, 2]);
    });

    test('sobrevive a un «reinicio» de la app: un contenedor nuevo con el mismo almacén lo recupera', () async {
      armar();
      await cargado();
      carrito().agregar(arroz);
      carrito().agregar(arroz);
      await Future<void>.delayed(Duration.zero);

      final conservado = almacen;
      c.dispose();
      armar(con: conservado);
      await cargado();
      expect(estado().lineas.single.idProducto, 1);
      expect(estado().lineas.single.cantidad, 2);
    });

    group('reglas al agregar', () {
      test('un producto agotado no se agrega', () async {
        armar();
        await cargado();
        expect(
          carrito().agregar(producto(9, 'Agotado', cantidad: 0)),
          ResultadoAgregar.agotado,
        );
        expect(estado().lineas, isEmpty);
      });

      test('un producto inactivo no se agrega', () async {
        armar();
        await cargado();
        expect(
          carrito().agregar(producto(9, 'Viejo', estado: 'Inactivo')),
          ResultadoAgregar.noDisponible,
        );
      });

      test(
        'un producto sin precio (0, vacío o ilegible) no se agrega',
        () async {
          armar();
          await cargado();
          for (final precio in ['0.00', '0', '', 'abc', '-5.00']) {
            expect(
              carrito().agregar(producto(9, 'Sin precio', precio: precio)),
              ResultadoAgregar.sinPrecio,
              reason: 'precio "$precio"',
            );
          }
          expect(estado().lineas, isEmpty);
        },
      );

      test('no se pasa de las unidades en stock', () async {
        armar();
        await cargado();
        final dos = producto(9, 'Solo dos', cantidad: 2);
        expect(carrito().agregar(dos), ResultadoAgregar.agregado);
        expect(carrito().agregar(dos), ResultadoAgregar.agregado);
        expect(carrito().agregar(dos), ResultadoAgregar.limiteDeStock);
        expect(estado().lineas.single.cantidad, 2);
      });

      test(
        'mientras el carrito se está leyendo del celular no deja agregar',
        () async {
          armar();
          c.listen(carritoProvider, (_, _) {});
          expect(estado().cargando, isTrue);
          expect(carrito().agregar(arroz), ResultadoAgregar.cargando);
        },
      );
    });

    group('cambiar el carrito', () {
      test(
        'incrementar respeta el stock; decrementar nunca baja de 1',
        () async {
          armar();
          await cargado();
          final tres = producto(9, 'Tres', cantidad: 3);
          catalogo.poner(EstadoCatalogo.listo([arroz, aceite, tres]));
          carrito().agregar(tres);

          expect(carrito().incrementar(9), ResultadoAgregar.agregado);
          expect(carrito().incrementar(9), ResultadoAgregar.agregado);
          expect(estado().lineas.single.cantidad, 3);
          expect(carrito().incrementar(9), ResultadoAgregar.limiteDeStock);

          carrito().decrementar(9);
          carrito().decrementar(9);
          expect(estado().lineas.single.cantidad, 1);
          carrito().decrementar(9); // con 1 no hace nada
          expect(estado().lineas.single.cantidad, 1);
        },
      );

      test('quitar saca solo ese producto; vaciar lo deja sin nada y lo borra del celular', () async {
        armar();
        await cargado();
        carrito().agregar(arroz);
        carrito().agregar(aceite);
        carrito().quitar(1);
        expect(estado().lineas.map((l) => l.idProducto), [2]);
        carrito().vaciar();
        await Future<void>.delayed(Duration.zero);
        expect(estado().lineas, isEmpty);
        expect(almacen.datos.containsKey('carrito_v1_2_1'), isFalse);
      });
    });

    group('cuentas y sesión', () {
      test(
        'otra persona en el mismo celular NO ve el carrito de la anterior',
        () async {
          armar();
          await cargado();
          carrito().agregar(arroz);
          await Future<void>.delayed(Duration.zero);

          sesion.poner(
            sesionActiva(userId: 3),
          ); // entra otro usuario de la misma tienda
          await cargado();
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(estado().lineas, isEmpty);
          // ...y el de la primera persona sigue guardado intacto.
          expect(almacen.datos['carrito_v1_2_1']!.single.idProducto, 1);
        },
      );

      test('otra tienda tampoco comparte carrito', () async {
        armar();
        await cargado();
        carrito().agregar(arroz);
        await Future<void>.delayed(Duration.zero);
        sesion.poner(sesionActiva(tiendaId: 2));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(estado().lineas, isEmpty);
      });

      test('si la sesión caduca, el carrito deja de verse pero NO se borra: al volver a entrar se recupera', () async {
        armar();
        await cargado();
        carrito().agregar(arroz);
        carrito().agregar(arroz);
        await Future<void>.delayed(Duration.zero);

        sesion.poner(
          const EstadoSesion.sinSesion(mensaje: 'Tu sesión terminó.'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(estado().lineas, isEmpty);
        expect(estado().cargando, isFalse);
        expect(
          carrito().agregar(arroz),
          ResultadoAgregar.cargando,
        ); // sin sesión no se agrega
        expect(almacen.datos['carrito_v1_2_1']!.single.cantidad, 2);

        sesion.poner(sesionActiva()); // la MISMA persona vuelve a entrar
        await cargado();
        expect(estado().lineas.single.cantidad, 2);
      });

      test('una lectura TARDÍA de la cuenta anterior se descarta', () async {
        final previo = AlmacenEnMemoria()
          ..datos['carrito_v1_2_1'] = const [
            LineaCarrito(idProducto: 1, nombre: 'De la cuenta A', cantidad: 5),
          ]
          ..lecturaDemorada = Completer<void>();
        armar(con: previo);
        c.listen(carritoProvider, (_, _) {});
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(previo.lecturas, 1); // la lectura de A quedó en el aire

        sesion.poner(const EstadoSesion.sinSesion()); // A sale
        await Future<void>.delayed(Duration.zero);
        previo.lecturaDemorada!
            .complete(); // ...y la respuesta de A llega tarde
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(estado().lineas, isEmpty);
      });
    });

    group('fallas del almacenamiento del celular', () {
      test(
        'si no se puede LEER, se sigue con un carrito vacío y se puede vender',
        () async {
          armar(con: AlmacenEnMemoria()..fallar = true);
          await cargado();
          expect(estado().lineas, isEmpty);
          expect(carrito().agregar(arroz), ResultadoAgregar.agregado);
        },
      );

      test('si no se puede GUARDAR, el carrito sigue funcionando en memoria sin lanzar errores', () async {
        armar();
        await cargado();
        almacen.fallar = true;
        expect(carrito().agregar(arroz), ResultadoAgregar.agregado);
        await Future<void>.delayed(Duration.zero);
        expect(estado().lineas.single.cantidad, 1);
      });
    });
  });

  group('resumenCarritoProvider (precios del catálogo y total exacto)', () {
    late AlmacenEnMemoria almacen;
    late ProviderContainer c;
    late CatalogoFijo catalogo;

    void armar(List<dynamic> productos, List<LineaCarrito> lineas) {
      almacen = AlmacenEnMemoria()..datos['carrito_v1_2_1'] = lineas;
      final a = armarContenedor(almacen: almacen, productos: productos.cast());
      c = a.contenedor;
      catalogo = a.catalogo;
      addTearDown(c.dispose);
    }

    Future<ResumenCarrito> resumen() async {
      c.listen(carritoProvider, (_, _) {});
      for (var i = 0; i < 100 && c.read(carritoProvider).cargando; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      return c.read(resumenCarritoProvider);
    }

    const l = LineaCarrito.new;

    test(
      'el total es EXACTO: 3 × \$3.333,33 + 1 × \$12.000,00 = \$21.999,99',
      () async {
        armar(
          [
            producto(1, 'A', precio: '3333.33'),
            producto(2, 'B', precio: '12000.00'),
          ],
          [
            l(idProducto: 1, nombre: 'A', cantidad: 3),
            l(idProducto: 2, nombre: 'B', cantidad: 1),
          ],
        );
        final r = await resumen();
        expect(r.totalCentavos, 2199999);
        expect(r.unidades, 4);
        expect(r.sePuedeCobrar, isTrue);
        expect(r.lineas.first.subtotalCentavos, 999999);
      },
    );

    test('un carrito vacío no se puede cobrar', () async {
      armar([producto(1, 'A')], []);
      final r = await resumen();
      expect(r.estaVacio, isTrue);
      expect(r.sePuedeCobrar, isFalse);
      expect(r.totalCentavos, 0);
    });

    test('si el PRECIO cambia en el catálogo, el total cambia solo (nunca se cobra con un precio viejo)', () async {
      armar(
        [producto(1, 'A', precio: '1000.00')],
        [l(idProducto: 1, nombre: 'A', cantidad: 2)],
      );
      expect((await resumen()).totalCentavos, 200000);
      catalogo.poner(
        EstadoCatalogo.listo([producto(1, 'A', precio: '1500.00')]),
      );
      expect(c.read(resumenCarritoProvider).totalCentavos, 300000);
    });

    test('si baja el STOCK por debajo de lo que hay en el carrito: «sin stock suficiente» y no se puede cobrar', () async {
      armar(
        [producto(1, 'A', cantidad: 10)],
        [l(idProducto: 1, nombre: 'A', cantidad: 5)],
      );
      expect((await resumen()).sePuedeCobrar, isTrue);
      catalogo.poner(EstadoCatalogo.listo([producto(1, 'A', cantidad: 3)]));
      final r = c.read(resumenCarritoProvider);
      expect(r.lineas.single.problema, ProblemaLinea.sinStockSuficiente);
      expect(
        r.lineas.single.mensajeDelProblema,
        'Solo hay 3 unidades en stock.',
      );
      expect(r.sePuedeCobrar, isFalse);
    });

    test('un producto que ya no está en el catálogo es un problema', () async {
      armar(
        [producto(2, 'Otro')],
        [l(idProducto: 1, nombre: 'Desaparecido', cantidad: 1)],
      );
      final r = await resumen();
      expect(r.lineas.single.problema, ProblemaLinea.noEstaEnElCatalogo);
      expect(
        r.lineas.single.nombre,
        'Desaparecido',
      ); // se muestra con el nombre guardado
    });

    test('un producto desactivado es un problema', () async {
      armar(
        [producto(1, 'A', estado: 'Inactivo')],
        [l(idProducto: 1, nombre: 'A', cantidad: 1)],
      );
      expect((await resumen()).lineas.single.problema, ProblemaLinea.inactivo);
    });

    test('un producto cuyo precio quedó en 0 es un problema (sinPrecio) y no suma al total', () async {
      armar(
        [producto(1, 'A', precio: '0.00')],
        [l(idProducto: 1, nombre: 'A', cantidad: 2)],
      );
      final r = await resumen();
      expect(r.lineas.single.problema, ProblemaLinea.sinPrecio);
      expect(r.sePuedeCobrar, isFalse);
    });

    test('mientras el catálogo NO está descargado no se acusa a nadie: «esperando el catálogo», sin cobrar', () async {
      armar([], [l(idProducto: 1, nombre: 'A', cantidad: 1)]);
      catalogo.poner(const EstadoCatalogo.cargando());
      final r = await resumen();
      expect(r.lineas.single.problema, ProblemaLinea.esperandoCatalogo);
      expect(r.sePuedeCobrar, isFalse);
    });
  });
}
