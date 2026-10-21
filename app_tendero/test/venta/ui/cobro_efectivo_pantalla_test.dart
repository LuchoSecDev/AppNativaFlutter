import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/cobro_pantallas_apoyo.dart';
import '../../support/fake_adapter.dart';

/// Cobrar en efectivo desde el carrito, con el cliente HTTP REAL y un servidor falso con los ejemplos reales del backend.
void main() {
  final banco = BancoDeCobro();

  group('la pantalla de cobro en efectivo', () {
    testWidgets(
      'verifica los precios, muestra el total, el cambio o lo que falta, y solo deja confirmar si alcanza',
      (tester) async {
        await banco.abrir(tester);
        await abrirCobro(tester);

        expect(banco.servidor.veces('GET', '/api/productos'), 1);
        expect(find.text('Total a cobrar'), findsOneWidget);
        expect(find.text(r'$9.000'), findsOneWidget);
        expect(find.textContaining('El total cambió'), findsNothing);

        ElevatedButton confirmarCobro() => tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Confirmar cobro'),
        );
        expect(confirmarCobro().onPressed, isNull, reason: 'sin escribir nada');

        await escribir(tester, '5000');
        expect(find.text(r'Faltan $4.000'), findsOneWidget);
        expect(confirmarCobro().onPressed, isNull);

        await escribir(tester, '8999');
        expect(find.text(r'Faltan $1'), findsOneWidget);
        expect(confirmarCobro().onPressed, isNull);

        await escribir(tester, '9000');
        expect(find.text(r'Cambio: $0'), findsOneWidget);
        expect(confirmarCobro().onPressed, isNotNull);

        await escribir(tester, '10000');
        expect(find.text(r'Cambio: $1.000'), findsOneWidget);
        expect(confirmarCobro().onPressed, isNotNull);
      },
    );

    testWidgets('«Monto exacto» escribe el total', (tester) async {
      await banco.abrir(tester);
      await abrirCobro(tester);
      await tester.tap(find.text('Monto exacto'));
      await tester.pump();
      expect(
        tester.widget<TextField>(campoEfectivo()).controller!.text,
        '9000',
      );
      expect(find.text(r'Cambio: $0'), findsOneWidget);
    });

    testWidgets('el campo solo admite dígitos y hasta 9', (tester) async {
      await banco.abrir(tester);
      await abrirCobro(tester);
      await escribir(tester, '12ab.-3456789012');
      expect(
        tester.widget<TextField>(campoEfectivo()).controller!.text,
        '123456789',
      );
    });

    testWidgets(
      'si el servidor tiene OTRO precio, se avisa que el total cambió y se cobra con el nuevo',
      (tester) async {
        // La app descargó el arroz a $4.000; el servidor ya lo tiene a $4.500.
        await banco.abrir(
          tester,
          productosDeLaApp: [
            arroz(precio: '4000.00'),
            aceite,
          ],
        );
        expect(find.text(r'Total: $8.000'), findsOneWidget);
        await abrirCobro(tester);

        expect(find.text(r'$9.000'), findsOneWidget);
        expect(
          find.textContaining(
            r'El total cambió al actualizar los precios: antes era $8.000',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'si no se pueden verificar los precios NO se deja cobrar; «Reintentar» lo intenta de nuevo',
      (tester) async {
        await banco.abrir(
          tester,
          catalogoDelServidor: const RespuestaFalsa.falloDeRed(
            DioExceptionType.connectionError,
          ),
        );
        await abrirCobro(tester);

        expect(
          find.textContaining('No se pudo verificar los precios'),
          findsOneWidget,
        );
        expect(campoEfectivo(), findsNothing);
        expect(
          find.widgetWithText(ElevatedButton, 'Confirmar cobro'),
          findsNothing,
        );

        banco.servidor.programar(
          'GET',
          '/api/productos',
          RespuestaFalsa.deEjemplo('13_C1_lista_de_productos'),
        );
        await tester.tap(find.widgetWithText(ElevatedButton, 'Reintentar'));
        await tester.pumpAndSettle();
        expect(campoEfectivo(), findsOneWidget);
      },
    );

    testWidgets(
      'si al verificar, un producto ya no alcanza (stock 1 de 2), no se deja cobrar y se vuelve al carrito',
      (tester) async {
        await banco.abrir(
          tester,
          catalogoDelServidor: const RespuestaFalsa(200, [
            {
              'id_producto': 1,
              'codigo': 'ARR-001',
              'codigo_barras': null,
              'nombre_producto': 'Arroz Diana 1Kg',
              'categoria': 'Granos',
              'precio': '4500.00',
              'cantidad': 1,
              'estado': 'Disponible',
              'nivel_stock': 'critico',
            },
          ]),
        );
        await abrirCobro(tester);

        expect(
          find.textContaining('algunos productos del carrito cambiaron'),
          findsOneWidget,
        );
        expect(campoEfectivo(), findsNothing);
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Volver al carrito'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Solo hay 1 unidad en stock.'), findsOneWidget);
      },
    );
  });
}
