import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/catalogo/producto.dart';
import 'package:stockpilot/catalogo/ui/ficha_de_producto.dart';
import 'package:stockpilot/ui/colores.dart';

/// La ficha de un producto: qué muestra, cómo marca el estado del stock y cómo se cierra.
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

  group('el estado del stock', () {
    const casos = {
      'ok': ('Disponible', Colores.exito),
      'reponer': ('Por reponer', Colores.aviso),
      'critico': ('Stock crítico', Colores.peligro),
      'agotado': ('Agotado', Colores.peligro),
    };

    for (final c in casos.entries) {
      test('nivel «${c.key}» → ${c.value.$1}', () {
        final e = estadoDeStock(
          producto(nivelStock: c.key, cantidad: c.key == 'agotado' ? 0 : 5),
        );
        expect(e.texto, c.value.$1);
        expect(e.color, c.value.$2);
      });
    }

    test('sin unidades es «Agotado» aunque el nivel diga otra cosa', () {
      final e = estadoDeStock(producto(cantidad: 0, nivelStock: 'ok'));
      expect(e.texto, 'Agotado');
      expect(e.color, Colores.peligro);
    });

    test('un producto inactivo es «Inactivo», aunque tenga stock', () {
      expect(
        estadoDeStock(producto(estado: 'Inactivo', cantidad: 9)).texto,
        'Inactivo',
      );
      expect(
        estadoDeStock(producto(estado: 'Inactivo', cantidad: 0)).texto,
        'Inactivo',
      );
    });

    test(
      'un nivel desconocido no inventa una alarma: se lee como disponible',
      () {
        expect(estadoDeStock(producto(nivelStock: 'raro')).texto, 'Disponible');
      },
    );

    testWidgets('la etiqueta se ve en la ficha', (tester) async {
      await abrir(tester, producto(nivelStock: 'critico', cantidad: 2));
      expect(enFicha(find.text('Stock crítico')), findsOneWidget);
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
