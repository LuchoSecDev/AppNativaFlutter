import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/caja/caja_models.dart';
import 'package:stockpilot/caja/caja_providers.dart';
import 'package:stockpilot/carrito/carrito_models.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/carrito/ui/carrito_screen.dart';
import 'package:stockpilot/catalogo/catalogo_providers.dart';
import 'package:stockpilot/catalogo/producto.dart';
import 'package:stockpilot/home_screen.dart';
import 'package:stockpilot/venta/venta_providers.dart';

import '../../support/carrito_apoyo.dart';

/// Una caja abierta fija, para probar el inicio sin servidor.
class _CajaAbiertaFija extends CajaNotifier {
  @override
  EstadoCaja build() => const EstadoCaja.abierta(
    SesionCaja(
      idSesion: 1,
      montoApertura: '50000.00',
      fechaApertura: '2026-10-04T15:30:00.000Z',
    ),
  );
}

/// Una caja cerrada fija: sin ella el carrito pediría la caja al servidor.
class _CajaCerradaFija extends CajaNotifier {
  @override
  EstadoCaja build() => const EstadoCaja.cerrada();
}

void main() {
  late AlmacenEnMemoria almacen;

  final arroz = producto(1, 'Arroz Diana 1Kg', precio: '4500.00', cantidad: 10);
  final aceite = producto(
    2,
    'Aceite Gourmet 1L',
    precio: '12000.00',
    cantidad: 5,
  );

  /// Abre la pantalla indicada con sesión, catálogo y almacén fijos (sin servidor).
  Future<void> abrir(
    WidgetTester tester, {
    required Widget pantalla,
    List<Producto>? productos,
    List<LineaCarrito> lineas = const [],
    bool conCajaAbierta = false,
  }) async {
    almacen = AlmacenEnMemoria();
    if (lineas.isNotEmpty) {
      almacen.datos['carrito_v1_2_1'] = lineas;
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sesionProvider.overrideWith(() => SesionFija(sesionActiva())),
          catalogoProvider.overrideWith(
            () => CatalogoFijo(
              EstadoCatalogo.listo(productos ?? [arroz, aceite]),
            ),
          ),
          almacenCarritoProvider.overrideWithValue(almacen),
          almacenVentaPendienteProvider.overrideWithValue(
            AlmacenVentaEnMemoria(),
          ),
          cajaProvider.overrideWith(
            () => conCajaAbierta ? _CajaAbiertaFija() : _CajaCerradaFija(),
          ),
        ],
        child: MaterialApp(home: pantalla),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> agregarDesdeBuscador(WidgetTester tester, String nombre) async {
    await tester.tap(find.text('Agregar producto').last);
    await tester.pumpAndSettle();
    expect(find.text('Elegir producto'), findsOneWidget);
    await tester.tap(find.text(nombre));
    await tester.pumpAndSettle();
  }

  Finder boton(String tooltip) => find.byTooltip(tooltip);

  group('el carrito', () {
    testWidgets('vacío: lo dice y ofrece agregar un producto', (tester) async {
      await abrir(tester, pantalla: const CarritoScreen());
      expect(find.text('El carrito está vacío'), findsOneWidget);
      expect(find.text('Agregar producto'), findsOneWidget);
      expect(find.byTooltip('Vaciar carrito'), findsNothing);
    });

    testWidgets(
      'agregar desde el buscador: aparece la línea, el total y el aviso «Agregado»',
      (tester) async {
        await abrir(tester, pantalla: const CarritoScreen());
        await agregarDesdeBuscador(tester, 'Arroz Diana 1Kg');

        expect(find.text('Elegir producto'), findsNothing); // volvió al carrito
        expect(find.text('Arroz Diana 1Kg'), findsOneWidget);
        expect(find.text(r'Total: $4.500'), findsOneWidget);
        expect(find.text('1 unidad'), findsOneWidget);
        expect(find.text('Agregado: Arroz Diana 1Kg'), findsOneWidget);
        await tester.pump(Duration.zero);
        expect(almacen.datos['carrito_v1_2_1']!.single.cantidad, 1);
      },
    );

    testWidgets(
      'el botón «Más» suma una unidad y el total se recalcula; «Menos» resta pero nunca baja de 1',
      (tester) async {
        await abrir(
          tester,
          pantalla: const CarritoScreen(),
          lineas: const [
            LineaCarrito(idProducto: 1, nombre: 'Arroz Diana 1Kg', cantidad: 1),
          ],
        );
        expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove))
              .onPressed,
          isNull,
          reason: 'con 1 unidad no se puede restar',
        );

        await tester.tap(boton('Más'));
        await tester.pumpAndSettle();
        expect(find.text('2'), findsOneWidget);
        expect(find.text(r'Total: $9.000'), findsOneWidget);
        expect(find.text(r'$4.500 c/u'), findsOneWidget);

        await tester.tap(boton('Menos'));
        await tester.pumpAndSettle();
        expect(find.text('1'), findsOneWidget);
        expect(find.text(r'Total: $4.500'), findsOneWidget);
      },
    );

    testWidgets(
      'el total con centavos es exacto: 3 × \$3.333,33 = \$9.999,99',
      (tester) async {
        await abrir(
          tester,
          pantalla: const CarritoScreen(),
          productos: [producto(7, 'Raro', precio: '3333.33')],
          lineas: const [
            LineaCarrito(idProducto: 7, nombre: 'Raro', cantidad: 3),
          ],
        );
        expect(find.text(r'Total: $9.999,99'), findsOneWidget);
      },
    );

    testWidgets('«Más» no pasa del stock y avisa', (tester) async {
      await abrir(
        tester,
        pantalla: const CarritoScreen(),
        productos: [producto(9, 'Solo dos', precio: '1000.00', cantidad: 2)],
        lineas: const [
          LineaCarrito(idProducto: 9, nombre: 'Solo dos', cantidad: 2),
        ],
      );
      await tester.tap(boton('Más'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget); // no subió
      expect(
        find.textContaining('Ya agregaste todas las unidades'),
        findsOneWidget,
      );
    });

    testWidgets(
      'quitar un producto lo saca; si era el último, vuelve al estado vacío',
      (tester) async {
        await abrir(
          tester,
          pantalla: const CarritoScreen(),
          lineas: const [
            LineaCarrito(idProducto: 1, nombre: 'Arroz Diana 1Kg', cantidad: 2),
          ],
        );
        await tester.tap(boton('Quitar Arroz Diana 1Kg'));
        await tester.pumpAndSettle();
        expect(find.text('El carrito está vacío'), findsOneWidget);
      },
    );

    testWidgets(
      'vaciar pide confirmar: «Cancelar» lo conserva, «Vaciar» lo borra (también del celular)',
      (tester) async {
        await abrir(
          tester,
          pantalla: const CarritoScreen(),
          lineas: const [
            LineaCarrito(idProducto: 1, nombre: 'Arroz Diana 1Kg', cantidad: 2),
          ],
        );
        await tester.tap(boton('Vaciar carrito'));
        await tester.pumpAndSettle();
        expect(find.text('¿Vaciar el carrito?'), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(find.text('Arroz Diana 1Kg'), findsOneWidget);

        await tester.tap(boton('Vaciar carrito'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Vaciar'));
        await tester.pumpAndSettle();
        expect(find.text('El carrito está vacío'), findsOneWidget);
        expect(almacen.datos.containsKey('carrito_v1_2_1'), isFalse);
      },
    );

    testWidgets(
      'un carrito guardado de antes aparece tal cual al abrir (no se pierde la venta)',
      (tester) async {
        await abrir(
          tester,
          pantalla: const CarritoScreen(),
          lineas: const [
            LineaCarrito(idProducto: 1, nombre: 'Arroz Diana 1Kg', cantidad: 3),
            LineaCarrito(
              idProducto: 2,
              nombre: 'Aceite Gourmet 1L',
              cantidad: 1,
            ),
          ],
        );
        expect(find.text('Arroz Diana 1Kg'), findsOneWidget);
        expect(find.text('Aceite Gourmet 1L'), findsOneWidget);
        expect(
          find.text(r'Total: $25.500'),
          findsOneWidget,
        ); // 3×4.500 + 12.000
        expect(find.text('4 unidades'), findsOneWidget);
      },
    );
  });

  group('productos que NO se pueden agregar', () {
    testWidgets('un agotado: muestra el motivo y se queda en el buscador', (
      tester,
    ) async {
      await abrir(
        tester,
        pantalla: const CarritoScreen(),
        productos: [producto(3, 'Café agotado', cantidad: 0)],
      );
      await agregarDesdeBuscador(tester, 'Café agotado');
      expect(find.textContaining('está agotado'), findsOneWidget);
      expect(find.text('Elegir producto'), findsOneWidget);
    });

    testWidgets('uno SIN PRECIO (0): se rechaza con una explicación', (
      tester,
    ) async {
      await abrir(
        tester,
        pantalla: const CarritoScreen(),
        productos: [producto(4, 'Producto de regalo', precio: '0.00')],
      );
      await agregarDesdeBuscador(tester, 'Producto de regalo');
      expect(find.textContaining('no tiene precio'), findsOneWidget);
      expect(find.text('Elegir producto'), findsOneWidget);
    });
  });

  group('problemas en lo que ya estaba en el carrito', () {
    testWidgets('si bajó el stock: marca la línea, avisa y no deja cobrar', (
      tester,
    ) async {
      await abrir(
        tester,
        pantalla: const CarritoScreen(),
        productos: [
          producto(1, 'Arroz Diana 1Kg', precio: '4500.00', cantidad: 3),
        ],
        lineas: const [
          LineaCarrito(idProducto: 1, nombre: 'Arroz Diana 1Kg', cantidad: 5),
        ],
      );
      expect(find.text('Solo hay 3 unidades en stock.'), findsOneWidget);
      expect(
        find.text('Revisa los productos marcados en rojo antes de cobrar.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'un producto que ya no está en el catálogo se muestra con su nombre guardado y un aviso',
      (tester) async {
        await abrir(
          tester,
          pantalla: const CarritoScreen(),
          productos: [aceite],
          lineas: const [
            LineaCarrito(
              idProducto: 99,
              nombre: 'Producto borrado',
              cantidad: 1,
            ),
          ],
        );
        expect(find.text('Producto borrado'), findsOneWidget);
        expect(
          find.text('Este producto ya no está en el catálogo.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '«Cobrar en efectivo» está bloqueado sin caja abierta, y lo explica',
      (tester) async {
        await abrir(
          tester,
          pantalla: const CarritoScreen(),
          lineas: const [
            LineaCarrito(idProducto: 1, nombre: 'Arroz Diana 1Kg', cantidad: 1),
          ],
        );
        final cobrar = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Cobrar en efectivo'),
        );
        expect(cobrar.onPressed, isNull);
        expect(find.text('Abre la caja para cobrar y escanear.'), findsOneWidget);
      },
    );

    testWidgets(
      '«Cobrar en efectivo» está bloqueado si hay productos con problemas',
      (tester) async {
        await abrir(
          tester,
          pantalla: const CarritoScreen(),
          conCajaAbierta: true,
          productos: [
            producto(1, 'Arroz Diana 1Kg', precio: '4500.00', cantidad: 1),
          ],
          lineas: const [
            LineaCarrito(idProducto: 1, nombre: 'Arroz Diana 1Kg', cantidad: 3),
          ],
        );
        final cobrar = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Cobrar en efectivo'),
        );
        expect(cobrar.onPressed, isNull);
      },
    );

    testWidgets(
      '«Cobrar en efectivo» se habilita con caja abierta y todo en orden',
      (tester) async {
        await abrir(
          tester,
          pantalla: const CarritoScreen(),
          conCajaAbierta: true,
          lineas: const [
            LineaCarrito(idProducto: 1, nombre: 'Arroz Diana 1Kg', cantidad: 1),
          ],
        );
        final cobrar = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Cobrar en efectivo'),
        );
        expect(cobrar.onPressed, isNotNull);
      },
    );
  });

  group('desde la pantalla de inicio', () {
    testWidgets(
      '«Vender» abre el carrito, y al volver el inicio resume lo que hay',
      (tester) async {
        await abrir(
          tester,
          pantalla: const HomeScreen(),
          conCajaAbierta: true,
          lineas: const [
            LineaCarrito(idProducto: 1, nombre: 'Arroz Diana 1Kg', cantidad: 2),
          ],
        );
        // La venta a medias se anuncia en el inicio, sin entrar al carrito.
        expect(find.text(r'Carrito: 2 unidades · $9.000'), findsOneWidget);

        await tester.tap(find.text('Vender'));
        await tester.pumpAndSettle();
        expect(find.text('Carrito'), findsOneWidget);
        expect(find.text('Arroz Diana 1Kg'), findsOneWidget);
      },
    );

    testWidgets('sin carrito no hay resumen en el inicio', (tester) async {
      await abrir(tester, pantalla: const HomeScreen(), conCajaAbierta: true);
      expect(find.textContaining('Carrito:'), findsNothing);
    });
  });
}
