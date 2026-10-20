import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/catalogo/estado_vencimiento.dart';
import 'package:stockpilot/catalogo/producto.dart';
import 'package:stockpilot/catalogo/ui/ficha_de_producto.dart';

import '../../support/estado_producto_apoyo.dart' show vencimiento;

/// La ficha de un producto: qué muestra, qué leyendas lleva (las de la web) y cómo se cierra.
void main() {
  Producto producto({
    String nombre = 'Aceite Gourmet 1L',
    String precio = '12000.00',
    int cantidad = 5,
    String estado = 'Disponible',
    String nivelStock = 'ok',
    String? codigoBarras,
    String codigo = 'ACE-001',
    String categoria = 'Aceites',
    EstadoVencimiento? vence,
    bool sobrestock = false,
  }) => Producto(
    id: 1,
    codigo: codigo,
    codigoBarras: codigoBarras,
    nombre: nombre,
    categoria: categoria,
    precio: precio,
    cantidad: cantidad,
    estado: estado,
    nivelStock: nivelStock,
    estadoVencimiento: vence,
    sobrestock: sobrestock,
  );

  /// Abre la ficha encima de una pantalla con un botón, como se usa en la app.
  Future<void> abrir(WidgetTester tester, Producto p) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => mostrarFichaDeProducto(context, p),
                child: const Text('abrir ficha'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir ficha'));
    await tester.pumpAndSettle();
  }

  Finder enFicha(Finder f) =>
      find.descendant(of: find.byType(FichaDeProducto), matching: f);

  group('lo que muestra', () {
    testWidgets('nombre, precio en pesos, unidades, categoría y códigos', (
      tester,
    ) async {
      await abrir(tester, producto(codigoBarras: '7701234000011'));
      expect(enFicha(find.text('Aceite Gourmet 1L')), findsOneWidget);
      expect(enFicha(find.text(r'$12.000')), findsOneWidget);
      expect(enFicha(find.text('5 unidades')), findsOneWidget);
      expect(enFicha(find.text('Aceites')), findsOneWidget);
      expect(enFicha(find.text('ACE-001')), findsOneWidget);
      expect(enFicha(find.text('7701234000011')), findsOneWidget);
    });

    testWidgets('el precio con centavos los muestra con coma', (tester) async {
      await abrir(tester, producto(precio: '4500.50'));
      expect(enFicha(find.text(r'$4.500,50')), findsOneWidget);
    });

    testWidgets('una sola unidad va en singular', (tester) async {
      await abrir(tester, producto(cantidad: 1));
      expect(enFicha(find.text('1 unidad')), findsOneWidget);
    });

    testWidgets(
      'sin código de barras dice «Sin asociar», no «null» ni un hueco',
      (tester) async {
        await abrir(tester, producto(codigoBarras: null));
        expect(enFicha(find.text('Sin asociar')), findsOneWidget);
        expect(enFicha(find.textContaining('null')), findsNothing);
      },
    );

    testWidgets('una categoría o un código vacíos no dejan una fila vacía', (
      tester,
    ) async {
      await abrir(tester, producto(categoria: '', codigo: ''));
      expect(enFicha(find.text('Categoría')), findsNothing);
      expect(enFicha(find.text('Código')), findsNothing);
      expect(enFicha(find.text('Código de barras')), findsOneWidget);
    });
  });

  group('las leyendas del estado', () {
    testWidgets('un producto sin novedad dice «Suficiente»', (tester) async {
      await abrir(tester, producto());
      expect(enFicha(find.text('Suficiente')), findsOneWidget);
    });

    testWidgets('los niveles de stock usan las palabras de la web', (
      tester,
    ) async {
      await abrir(tester, producto(nivelStock: 'critico', cantidad: 2));
      expect(enFicha(find.text('Por agotarse')), findsOneWidget);
      expect(enFicha(find.text('Stock crítico')), findsNothing);
    });

    testWidgets('«Pedir más» y «Agotado»', (tester) async {
      await abrir(tester, producto(nivelStock: 'reponer'));
      expect(enFicha(find.text('Pedir más')), findsOneWidget);
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      await abrir(tester, producto(cantidad: 0, nivelStock: 'agotado'));
      expect(enFicha(find.text('Agotado')), findsOneWidget);
    });

    testWidgets('un producto inactivo dice «Inactivo», aunque tenga stock', (
      tester,
    ) async {
      await abrir(tester, producto(estado: 'Inactivo', cantidad: 9));
      expect(enFicha(find.text('Inactivo')), findsOneWidget);
      expect(enFicha(find.text('Suficiente')), findsNothing);
    });

    testWidgets('vencido: la leyenda y, debajo, qué hacer', (tester) async {
      await abrir(
        tester,
        producto(vence: vencimiento(TipoVencimiento.vencido, -3)),
      );
      expect(enFicha(find.text('Vencido')), findsOneWidget);
      expect(
        enFicha(find.text('Venció hace 3 días: retíralo de la venta')),
        findsOneWidget,
      );
      expect(enFicha(find.text('Suficiente')), findsNothing);
    });

    testWidgets('vence en N días y sobrestock, con su ayuda', (tester) async {
      await abrir(
        tester,
        producto(
          sobrestock: true,
          vence: vencimiento(TipoVencimiento.critico, 3),
        ),
      );
      expect(enFicha(find.text('Vence en 3 días')), findsOneWidget);
      expect(
        enFicha(find.text('Vence en 3 días: conviene rematarlo')),
        findsOneWidget,
      );
      expect(enFicha(find.text('Sobrestock')), findsOneWidget);
      expect(
        enFicha(find.text('Tienes más de lo que vendes: es capital quieto')),
        findsOneWidget,
      );
    });
  });

  group('cómo se cierra', () {
    testWidgets('con la X', (tester) async {
      await abrir(tester, producto());
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.byType(FichaDeProducto), findsNothing);
    });

    testWidgets('tocando fuera de la ficha', (tester) async {
      await abrir(tester, producto());
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(FichaDeProducto), findsNothing);
    });

    testWidgets('tocar dentro de la ficha NO la cierra', (tester) async {
      await abrir(tester, producto());
      await tester.tap(enFicha(find.text('Aceite Gourmet 1L')));
      await tester.pumpAndSettle();
      expect(find.byType(FichaDeProducto), findsOneWidget);
    });
  });

  group('cómo se ve', () {
    testWidgets('flotante y centrada, no pegada al pie de la pantalla', (
      tester,
    ) async {
      await abrir(tester, producto());
      final pantalla = tester.view.physicalSize / tester.view.devicePixelRatio;
      // El Dialog ocupa toda la ruta; la tarjeta visible es su Material.
      final ficha = tester.getRect(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(ficha.bottom, lessThan(pantalla.height - 24));
      expect(ficha.top, greaterThan(24));
      expect((ficha.center.dy - pantalla.height / 2).abs(), lessThan(1));
    });

    testWidgets('un nombre largo no desborda en una pantalla angosta', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await abrir(
        tester,
        producto(
          nombre: 'Chocolatina Jet de leche con almendras y caramelo 11g x 24',
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(FichaDeProducto), findsOneWidget);
    });
  });
}
