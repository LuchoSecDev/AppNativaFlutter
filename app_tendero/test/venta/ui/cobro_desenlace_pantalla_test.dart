import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/home_screen.dart';
import 'package:stockpilot/venta/venta_providers.dart';

import '../../support/cobro_pantallas_apoyo.dart';
import '../../support/fake_adapter.dart';

/// El desenlace del cobro visto en el carrito: registrada, rechazada, sin confirmar y sus reintentos.
void main() {
  const clave = claveDeCobro;
  const ruta = rutaDeCobro;
  final banco = BancoDeCobro();

  group('el desenlace del cobro, en el carrito', () {
    testWidgets(
      'venta registrada: comprobante con el cambio; «Nueva venta» deja el carrito vacío y en la copia no queda nada',
      (tester) async {
        await banco.abrir(tester);
        banco.programarVentaOk();
        await abrirCobro(tester);
        await escribir(tester, '10000');
        await confirmar(tester);

        expect(find.text('Venta registrada'), findsOneWidget);
        expect(find.text('Venta n.º 1'), findsOneWidget);
        expect(find.text(r'$9.000'), findsOneWidget);
        expect(find.text(r'$10.000'), findsOneWidget);
        expect(find.text('Cambio a devolver'), findsOneWidget);
        expect(find.text(r'$1.000'), findsOneWidget);
        expect(find.textContaining('ya estaba registrada'), findsNothing);
        expect(banco.almacenVenta.datos, isEmpty);
        expect(banco.servidor.veces('POST', ruta), 1);

        await tester.tap(find.text('Nueva venta'));
        await tester.pumpAndSettle();
        expect(find.text('El carrito está vacío'), findsOneWidget);
        expect(banco.almacenCarrito.datos['carrito_v1_2_1'], isNull);
      },
    );

    testWidgets(
      'sin red: «sin confirmar», con aviso de no cobrar otra vez, líneas bloqueadas; «Reintentar» recupera la MISMA venta',
      (tester) async {
        await banco.abrir(tester);
        banco.programarSinRed();
        await abrirCobro(tester);
        await escribir(tester, '10000');
        await confirmar(tester);

        expect(find.textContaining('No la cobres otra vez'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(find.text('Cancelar este cobro'), findsOneWidget);
        expect(find.text('Registrando la venta…'), findsNothing);
        // Las líneas siguen a la vista pero no se pueden cambiar.
        expect(find.text('Arroz Diana 1Kg'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
              .onPressed,
          isNull,
        );
        expect(find.widgetWithText(FilledButton, 'Cobrar...'), findsNothing);
        expect(find.byTooltip('Vaciar carrito'), findsNothing);
        expect(banco.almacenVenta.datos, isNotEmpty);

        banco.servidor.programar(
          'POST',
          ruta,
          RespuestaFalsa.deEjemplo('18_V2_reintento_misma_clave_200'),
        );
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();

        expect(find.text('Venta registrada'), findsOneWidget);
        expect(find.textContaining('ya estaba registrada'), findsOneWidget);
        final envios = banco.servidor.peticiones.where(
          (p) => p.clave == 'POST $ruta',
        );
        expect(envios.map((p) => p.headers['Idempotency-Key']), [clave, clave]);
        expect(banco.almacenVenta.datos, isEmpty);
      },
    );

    testWidgets(
      '«Cancelar este cobro» advierte del riesgo de duplicar; si se confirma, se puede cobrar otra vez',
      (tester) async {
        await banco.abrir(tester);
        banco.programarSinRed();
        await abrirCobro(tester);
        await escribir(tester, '10000');
        await confirmar(tester);

        await tester.tap(find.text('Cancelar este cobro'));
        await tester.pumpAndSettle();
        expect(find.textContaining('quedará duplicada'), findsOneWidget);

        await tester.tap(find.text('Volver'));
        await tester.pumpAndSettle();
        expect(
          find.text('Reintentar'),
          findsOneWidget,
          reason: 'sigue sin confirmar',
        );

        await tester.tap(find.text('Cancelar este cobro'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancelar el cobro'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(FilledButton, 'Cobrar...'), findsOneWidget);
        expect(banco.almacenVenta.datos, isEmpty);
      },
    );

    testWidgets(
      'un rechazo del servidor se muestra con su mensaje, el carrito sigue y se puede corregir',
      (tester) async {
        await banco.abrir(tester);
        banco.servidor.programar(
          'POST',
          ruta,
          RespuestaFalsa.deEjemplo('20_V2_stock_insuficiente_400'),
        );
        await abrirCobro(tester);
        await escribir(tester, '10000');
        await confirmar(tester);

        expect(
          find.text('Stock insuficiente para el producto: Arroz Diana 1Kg'),
          findsOneWidget,
        );
        expect(find.text('Arroz Diana 1Kg'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Cobrar...'),
              )
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'al salir del carrito con la venta registrada, la próxima vez empieza limpio',
      (tester) async {
        await banco.abrir(tester, pantalla: const HomeScreen());
        await tester.tap(find.text('Vender'));
        await tester.pumpAndSettle();
        banco.programarVentaOk();
        await abrirCobro(tester);
        await escribir(tester, '10000');
        await confirmar(tester);
        expect(find.text('Venta registrada'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(contenedor(tester).read(cobroProvider).fase, FaseCobro.libre);

        await tester.tap(find.text('Vender'));
        await tester.pumpAndSettle();
        expect(find.text('Venta registrada'), findsNothing);
        expect(find.text('El carrito está vacío'), findsOneWidget);
      },
    );
  });
}
