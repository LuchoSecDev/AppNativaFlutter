import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/catalogo/catalogo_providers.dart';
import 'package:stockpilot/catalogo/estado_vencimiento.dart';
import 'package:stockpilot/catalogo/producto.dart';
import 'package:stockpilot/catalogo/ui/buscar_producto_screen.dart';

import '../../support/carrito_apoyo.dart';
import '../../support/estado_producto_apoyo.dart';

/// «Consultar productos» muestra el estado de cada producto con las leyendas de la web (vencido, vence en N días,
/// sobrestock, agotado...). La lista de ejemplo del servidor está FABRICADA (`13b_C1_FABRICADO_...`): el ejemplo real
/// solo trae `estado_vencimiento: null`.
void main() {
  Future<void> abrir(WidgetTester tester, List<Producto> productos) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sesionProvider.overrideWith(() => SesionFija(sesionActiva())),
          catalogoProvider.overrideWith(
            () => CatalogoFijo(EstadoCatalogo.listo(productos)),
          ),
        ],
        child: const MaterialApp(home: BuscarProductoScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cada producto lleva su leyenda; el inactivo no se ofrece', (
    tester,
  ) async {
    await abrir(
      tester,
      productosDeEjemplo('13b_C1_FABRICADO_estados_de_producto'),
    );
    expect(find.text('Vencido'), findsOneWidget);
    expect(find.text('Vence hoy'), findsOneWidget);
    expect(find.text('Vence en 3 días'), findsOneWidget);
    expect(find.text('Vence en 20 días'), findsOneWidget);
    expect(find.text('Sobrestock'), findsOneWidget);
    expect(find.text('Galletas de soda'), findsNothing);
    expect(find.text('Inactivo'), findsNothing);
  });

  testWidgets('la ayuda de la web va en el tooltip de la leyenda', (
    tester,
  ) async {
    await abrir(
      tester,
      productosDeEjemplo('13b_C1_FABRICADO_estados_de_producto'),
    );
    expect(
      find.byTooltip('Venció hace 3 días: retíralo de la venta'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Tienes más de lo que vendes: es capital quieto'),
      findsOneWidget,
    );
  });

  testWidgets(
    'los niveles de stock: Agotado, Por agotarse, Pedir más, Suficiente',
    (tester) async {
      await abrir(tester, [
        productoConEstado('Cero', id: 1, cantidad: 0, nivelStock: 'agotado'),
        productoConEstado('Poco', id: 2, nivelStock: 'critico'),
        productoConEstado('Reponer', id: 3, nivelStock: 'reponer'),
        productoConEstado('Normal', id: 4),
      ]);
      expect(find.text('Agotado'), findsOneWidget);
      expect(find.text('Por agotarse'), findsOneWidget);
      expect(find.text('Pedir más'), findsOneWidget);
      expect(find.text('Suficiente'), findsOneWidget);
    },
  );

  testWidgets(
    '«Sin precio» sigue avisando (no es de la web, pero evita vender a \$0)',
    (tester) async {
      await abrir(tester, [productoConEstado('Gratis', precio: '0.00')]);
      expect(find.text('Sin precio'), findsOneWidget);
    },
  );

  testWidgets('con varias leyendas y una pantalla angosta no desborda', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await abrir(tester, [
      productoConEstado(
        'Chocolatina Jet de leche con almendras y caramelo 11g x 24',
        cantidad: 0,
        nivelStock: 'agotado',
        sobrestock: true,
        precio: '0.00',
        vence: vencimiento(TipoVencimiento.vencido, -30),
      ),
    ]);
    expect(tester.takeException(), isNull);
  });
}
