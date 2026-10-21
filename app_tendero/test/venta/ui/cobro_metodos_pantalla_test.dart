import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/cobro_pantallas_apoyo.dart';
import '../../support/fake_adapter.dart';

/// El selector de método de pago y el cobro con tarjeta y transferencia.
void main() {
  const clave = claveDeCobro;
  const ruta = rutaDeCobro;
  final banco = BancoDeCobro();

  group('el selector de método de pago', () {
    testWidgets('ofrece los cuatro métodos y cada uno abre su pantalla', (
      tester,
    ) async {
      await banco.abrir(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Cobrar...'));
      await tester.pumpAndSettle();
      expect(find.text('¿Cómo vas a cobrar?'), findsOneWidget);
      for (final metodo in ['Efectivo', 'Tarjeta', 'Transferencia', 'Fiado']) {
        expect(find.widgetWithText(InkWell, metodo), findsOneWidget);
      }

      await tester.tap(find.widgetWithText(InkWell, 'Tarjeta'));
      await tester.pumpAndSettle();
      expect(find.text('Cobrar con Tarjeta'), findsOneWidget);
      expect(find.text('¿Cómo vas a cobrar?'), findsNothing);
    });
  });

  group('tarjeta y transferencia', () {
    for (final metodo in ['Tarjeta', 'Transferencia']) {
      testWidgets(
        '$metodo: verifica los precios, nombra el método y cobra SIN efectivo ni cliente, con la misma clave de idempotencia',
        (tester) async {
          await banco.abrir(tester);
          banco.programarVentaOk();
          await abrirCobro(tester, metodo: metodo);

          expect(banco.servidor.veces('GET', '/api/productos'), 1);
          expect(find.text('Cobrar con $metodo'), findsOneWidget);
          expect(find.text(r'$9.000'), findsOneWidget);
          // Antes de corregirlo, el texto decía «por MetodoPago.tarjeta.valorApi».
          expect(
            find.textContaining('el pago por $metodo antes de confirmar'),
            findsOneWidget,
          );

          await tester.tap(
            find.widgetWithText(ElevatedButton, 'Confirmar pago recibido'),
          );
          await tester.pumpAndSettle();

          final peticion = banco.servidor.peticiones.singleWhere(
            (p) => p.clave == 'POST $ruta',
          );
          expect(peticion.cuerpo, {
            'items': [
              {'id_producto': 1, 'cantidad': 2},
            ],
            'metodo_pago': metodo,
          });
          expect(peticion.headers['Idempotency-Key'], clave);
          expect(find.text('Venta registrada'), findsOneWidget);
        },
      );
    }

    testWidgets(
      'si no se pueden verificar los precios NO se deja confirmar el pago',
      (tester) async {
        await banco.abrir(
          tester,
          catalogoDelServidor: const RespuestaFalsa.falloDeRed(
            DioExceptionType.connectionError,
          ),
        );
        await abrirCobro(tester, metodo: 'Tarjeta');
        expect(
          find.textContaining('No se pudo verificar los precios'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(ElevatedButton, 'Confirmar pago recibido'),
          findsNothing,
        );
        expect(banco.servidor.veces('POST', ruta), 0);
      },
    );

    testWidgets('si el servidor tiene OTRO precio, avisa que el total cambió', (
      tester,
    ) async {
      await banco.abrir(
        tester,
        productosDeLaApp: [
          arroz(precio: '4000.00'),
          aceite,
        ],
      );
      await abrirCobro(tester, metodo: 'Transferencia');
      expect(find.text(r'$9.000'), findsOneWidget);
      expect(
        find.textContaining(
          r'El total cambió al actualizar los precios: antes era $8.000',
        ),
        findsOneWidget,
      );
    });
  });
}
