import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/cobro_pantallas_apoyo.dart';
import '../../support/fiado_pantallas_apoyo.dart';

/// Cobrar fiado, primera parte: traer los clientes, buscarlos, elegir y confirmar.
void main() {
  const clave = claveDeCobro;
  const ruta = rutaDeCobro;
  final banco = BancoDeCobro();

  group('fiado: elegir al cliente', () {
    testWidgets(
      'trae los clientes del servidor (una vez) y muestra lo que debe y el cupo EN PESOS',
      (tester) async {
        await banco.abrir(
          tester,
          lineas: unArroz,
          clientesDelServidor: clientes([
            cliente(1, 'Doña Rosa', saldo: 2500),
            cliente(2, 'Don Pedro', limite: '0.00'),
          ]),
        );
        await abrirCobro(tester, metodo: 'Fiado');

        expect(banco.servidor.veces('GET', '/api/clientes'), 1);
        expect(find.text('Doña Rosa'), findsOneWidget);
        expect(find.text(r'Debe $2.500 · cupo $5.000'), findsOneWidget);
        expect(find.text(r'Debe $0 · sin tope'), findsOneWidget);
      },
    );

    testWidgets('el buscador filtra por nombre sin distinguir mayúsculas', (
      tester,
    ) async {
      await banco.abrir(
        tester,
        lineas: unArroz,
        clientesDelServidor: clientes([
          cliente(1, 'Doña Rosa'),
          cliente(2, 'Don Pedro'),
        ]),
      );
      await abrirCobro(tester, metodo: 'Fiado');

      await tester.enterText(find.byType(TextField), 'PEDRO');
      await tester.pump();
      expect(find.text('Don Pedro'), findsOneWidget);
      expect(find.text('Doña Rosa'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.textContaining('No se encontraron clientes'), findsOneWidget);

      await tester.tap(find.byTooltip('Borrar la búsqueda'));
      await tester.pump();
      expect(find.text('Doña Rosa'), findsOneWidget);
      expect(find.text('Don Pedro'), findsOneWidget);
    });

    testWidgets(
      'elegir y confirmar: manda Fiado con id_cliente, sin efectivo y con la clave de idempotencia',
      (tester) async {
        await banco.abrir(tester, lineas: unArroz);
        banco.programarVentaOk();
        await abrirCobro(tester, metodo: 'Fiado');
        await elegir(tester, 'Doña Rosa');

        expect(valorDe(tester, 'Total de la compra'), r'$4.500');
        expect(valorDe(tester, 'Debe ahora'), r'$0');
        expect(valorDe(tester, 'Quedaría debiendo'), r'$4.500');
        expect(valorDe(tester, 'Cupo'), r'$5.000');

        await tester.tap(botonConfirmar());
        await tester.pumpAndSettle();

        final peticion = banco.servidor.peticiones.singleWhere(
          (p) => p.clave == 'POST $ruta',
        );
        expect(peticion.cuerpo, {
          'items': [
            {'id_producto': 1, 'cantidad': 1},
          ],
          'metodo_pago': 'Fiado',
          'id_cliente': 1,
        });
        expect(peticion.headers['Idempotency-Key'], clave);
        expect(find.text('Venta registrada'), findsOneWidget);
      },
    );

    testWidgets(
      'si la venta se pasa del cupo NO se deja confirmar, lo explica y no se manda nada',
      (tester) async {
        // Dos arroces: $9.000 contra un cupo de $5.000.
        await banco.abrir(tester);
        await abrirCobro(tester, metodo: 'Fiado');
        await elegir(tester, 'Doña Rosa');

        expect(
          find.textContaining('supera el cupo de crédito del cliente'),
          findsOneWidget,
        );
        expect(confirmarHabilitado(tester), isFalse);
        expect(banco.servidor.veces('POST', ruta), 0);
      },
    );

    testWidgets(
      'el cupo cuenta lo que ya debe, y estar JUSTO en el cupo es válido',
      (tester) async {
        // $4.500 de venta. Al que ya debe $500 le quedan justo $5.000 (válido); al que debe $501, no.
        await banco.abrir(
          tester,
          lineas: unArroz,
          clientesDelServidor: clientes([
            cliente(1, 'Justo', saldo: 500),
            cliente(2, 'Pasado', saldo: 501),
          ]),
        );
        await abrirCobro(tester, metodo: 'Fiado');

        await elegir(tester, 'Justo');
        expect(valorDe(tester, 'Quedaría debiendo'), r'$5.000');
        expect(confirmarHabilitado(tester), isTrue);

        await tester.tap(find.byTooltip('Elegir otro cliente'));
        await tester.pumpAndSettle();
        await elegir(tester, 'Pasado');
        expect(confirmarHabilitado(tester), isFalse);
      },
    );

    testWidgets('un cupo de 0 es «sin tope»: deja fiar cualquier monto', (
      tester,
    ) async {
      await banco.abrir(
        tester,
        clientesDelServidor: clientes([
          cliente(7, 'Sin tope', limite: '0.00', saldo: 90000),
        ]),
      );
      await abrirCobro(tester, metodo: 'Fiado');
      await elegir(tester, 'Sin tope');

      expect(valorDe(tester, 'Cupo'), 'Sin tope');
      expect(valorDe(tester, 'Quedaría debiendo'), r'$99.000');
      expect(confirmarHabilitado(tester), isTrue);
    });
  });
}
