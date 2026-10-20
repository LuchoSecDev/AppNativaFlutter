import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/catalogo/leyendas_de_producto.dart';
import 'package:stockpilot/catalogo/ui/pildora_de_leyenda.dart';
import 'package:stockpilot/ui/colores.dart';

/// Los colores de las leyendas (los de la web): rojo sólido lo vencido, rojo suave hasta 7 días y lo agotado, ámbar de
/// 8 a 30 días y «Pedir más».
void main() {
  test('cada tono tiene sus colores', () {
    expect(PildoraDeLeyenda.coloresDe(TonoLeyenda.vencido), (
      Colores.peligro,
      Colors.white,
    ));
    expect(PildoraDeLeyenda.coloresDe(TonoLeyenda.peligro), (
      Colores.peligroSuave,
      Colores.peligro,
    ));
    expect(PildoraDeLeyenda.coloresDe(TonoLeyenda.aviso), (
      Colores.avisoSuave,
      Colores.aviso,
    ));
    expect(PildoraDeLeyenda.coloresDe(TonoLeyenda.exito).$2, Colores.exito);
    expect(
      PildoraDeLeyenda.coloresDe(TonoLeyenda.informativo).$2,
      Colores.azul,
    );
  });

  testWidgets('la píldora usa los colores de su tono', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PildoraDeLeyenda(Leyenda('Vencido', TonoLeyenda.vencido)),
        ),
      ),
    );
    final texto = tester.widget<Text>(find.text('Vencido'));
    expect(texto.style?.color, Colors.white);
    final caja = tester.widget<Container>(find.byType(Container));
    expect((caja.decoration! as BoxDecoration).color, Colores.peligro);
  });

  testWidgets(
    'sin ayuda no hay tooltip; con ayuda sí, salvo que se pida sin él',
    (tester) async {
      Future<void> mostrar(Leyenda l, {bool conTooltip = true}) =>
          tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: PildoraDeLeyenda(l, conTooltip: conTooltip)),
            ),
          );
      await mostrar(const Leyenda('Suficiente', TonoLeyenda.exito));
      expect(find.byType(Tooltip), findsNothing);
      const conAyuda = Leyenda('Vencido', TonoLeyenda.vencido, ayuda: 'Ayuda');
      await mostrar(conAyuda);
      expect(find.byTooltip('Ayuda'), findsOneWidget);
      await mostrar(conAyuda, conTooltip: false);
      expect(find.byType(Tooltip), findsNothing);
    },
  );
}
