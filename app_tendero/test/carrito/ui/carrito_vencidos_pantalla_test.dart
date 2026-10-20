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
import 'package:stockpilot/catalogo/estado_vencimiento.dart';
import 'package:stockpilot/catalogo/producto.dart';
import 'package:stockpilot/venta/venta_providers.dart';

import '../../support/carrito_apoyo.dart';
import '../../support/estado_producto_apoyo.dart';

class _CajaAbierta extends CajaNotifier {
  @override
  EstadoCaja build() => const EstadoCaja.abierta(
    SesionCaja(
      idSesion: 1,
      montoApertura: '50000.00',
      fechaApertura: '2026-10-04T15:30:00.000Z',
    ),
  );
}

/// El carrito ante un producto vencido: no se agrega desde el buscador y, si ya estaba, no deja cobrar. Lo que vence
/// HOY sí se vende.
void main() {
  final yogur = productoConEstado(
    'Yogur natural 1L',
    id: 9,
    vence: vencimiento(TipoVencimiento.vencido, -3),
  );
  final leche = productoConEstado(
    'Leche entera 1L',
    id: 8,
    vence: vencimiento(TipoVencimiento.hoy, 0),
  );

  Future<ProviderContainer> abrir(
    WidgetTester tester,
    List<Producto> productos, {
    List<LineaCarrito> lineas = const [],
  }) async {
    final almacen = AlmacenEnMemoria();
    if (lineas.isNotEmpty) {
      almacen.datos['carrito_v1_2_1'] = lineas;
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sesionProvider.overrideWith(() => SesionFija(sesionActiva())),
          catalogoProvider.overrideWith(
            () => CatalogoFijo(EstadoCatalogo.listo(productos)),
          ),
          almacenCarritoProvider.overrideWithValue(almacen),
          almacenVentaPendienteProvider.overrideWithValue(
            AlmacenVentaEnMemoria(),
          ),
          cajaProvider.overrideWith(_CajaAbierta.new),
        ],
        child: const MaterialApp(home: CarritoScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  Future<void> agregarDesdeBuscador(WidgetTester tester, String nombre) async {
    await tester.tap(find.text('Buscar manualmente').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(nombre));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'un vencido no se agrega: dice por qué y se queda en el buscador',
    (tester) async {
      final c = await abrir(tester, [yogur, leche]);
      await agregarDesdeBuscador(tester, 'Yogur natural 1L');
      expect(
        find.text('«Yogur natural 1L» está vencido y no se puede vender.'),
        findsOneWidget,
      );
      expect(find.text('Elegir producto'), findsOneWidget);
      expect(c.read(carritoProvider).lineas, isEmpty);
    },
  );

  testWidgets('lo que vence hoy sí se agrega', (tester) async {
    final c = await abrir(tester, [yogur, leche]);
    await agregarDesdeBuscador(tester, 'Leche entera 1L');
    expect(find.text('Agregado: Leche entera 1L'), findsOneWidget);
    expect(c.read(carritoProvider).lineas.single.idProducto, 8);
  });

  testWidgets(
    'un vencido que ya estaba en el carrito lo dice y bloquea «Cobrar...»',
    (tester) async {
      await abrir(
        tester,
        [yogur],
        lineas: [
          const LineaCarrito(idProducto: 9, nombre: 'Yogur', cantidad: 1),
        ],
      );
      expect(
        find.text(
          'Este producto está vencido y no se puede vender. Quítalo del carrito.',
        ),
        findsOneWidget,
      );
      final cobrar = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Cobrar...'),
      );
      expect(cobrar.onPressed, isNull);
    },
  );
}
