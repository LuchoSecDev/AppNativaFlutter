import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/caja/ui/tarjeta_de_caja.dart';
import 'package:stockpilot/egresos/egreso_models.dart';

import '../../support/egreso_apoyo.dart';

/// El botón «Registrar gasto» de la tarjeta de caja del inicio.
void main() {
  Future<void> abrirTarjeta(
    WidgetTester tester,
    EntornoDeEgresos entorno,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: entorno.overrides(),
        child: const MaterialApp(home: Scaffold(body: TarjetaDeCaja())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'con la caja abierta aparece «Registrar gasto» junto a «Cerrar caja»',
    (tester) async {
      await abrirTarjeta(tester, EntornoDeEgresos());
      expect(
        find.widgetWithText(OutlinedButton, 'Registrar gasto'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Cerrar caja'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'con la caja cerrada NO se ofrece registrar gastos (el servidor lo rechazaría)',
    (tester) async {
      await abrirTarjeta(tester, EntornoDeEgresos(cajaAbierta: false));
      expect(find.text('Registrar gasto'), findsNothing);
      expect(find.text('Abrir caja'), findsOneWidget);
    },
  );

  testWidgets('tocarlo abre la pantalla de registrar gasto', (tester) async {
    await abrirTarjeta(tester, EntornoDeEgresos());
    await tester.tap(find.widgetWithText(OutlinedButton, 'Registrar gasto'));
    await tester.pumpAndSettle();
    expect(find.text('Registrar gasto'), findsWidgets);
    expect(find.widgetWithText(TextField, 'Monto'), findsOneWidget);
  });

  testWidgets(
    'si quedó un gasto sin confirmar, el botón lo dice y lleva a resolverlo',
    (tester) async {
      final entorno = EntornoDeEgresos();
      entorno.almacen.datos['egreso_pendiente_v1_2_1'] = const EgresoPendiente(
        clave: claveDeEgreso,
        montoPesos: 10000,
        motivo: 'Bolsas y hielo',
        categoria: CategoriaEgreso.otro,
      );
      await abrirTarjeta(tester, entorno);

      expect(find.text('Gasto sin confirmar'), findsOneWidget);
      expect(find.text('Registrar gasto'), findsNothing);
      await tester.tap(find.text('Gasto sin confirmar'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
    },
  );
}
