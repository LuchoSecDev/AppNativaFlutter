import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_adapter.dart';
import '../../support/cobro_pantallas_apoyo.dart';
import '../../support/fiado_pantallas_apoyo.dart';

/// Cobrar fiado, segunda parte: errores, el cupo del servidor y los reintentos.
void main() {
  const clave = claveDeCobro;
  const ruta = rutaDeCobro;
  final banco = BancoDeCobro();

  group('fiado: errores y reintentos', () {
    testWidgets('«Elegir otro cliente» vuelve a la lista y no cobra nada', (
      tester,
    ) async {
      await banco.abrir(tester, lineas: unArroz);
      await abrirCobro(tester, metodo: 'Fiado');
      await elegir(tester, 'Doña Rosa');
      await tester.tap(find.byTooltip('Elegir otro cliente'));
      await tester.pumpAndSettle();
      expect(find.text('Doña Rosa'), findsOneWidget);
      expect(botonConfirmar(), findsNothing);
      expect(banco.servidor.veces('POST', ruta), 0);
    });

    testWidgets(
      'si no se pudo traer la lista de clientes: mensaje y «Reintentar»',
      (tester) async {
        await banco.abrir(
          tester,
          lineas: unArroz,
          clientesDelServidor: const RespuestaFalsa.falloDeRed(
            DioExceptionType.connectionError,
          ),
        );
        await abrirCobro(tester, metodo: 'Fiado');
        expect(find.textContaining('No hay conexión'), findsOneWidget);

        banco.servidor.programar(
          'GET',
          '/api/clientes',
          RespuestaFalsa.deEjemplo('16_V1_clientes'),
        );
        await tester.tap(find.widgetWithText(OutlinedButton, 'Reintentar'));
        await tester.pumpAndSettle();
        expect(find.text('Doña Rosa'), findsOneWidget);
      },
    );

    testWidgets(
      'una tienda sin clientes lo dice en vez de mostrar una lista vacía',
      (tester) async {
        await banco.abrir(
          tester,
          lineas: unArroz,
          clientesDelServidor: clientes(const []),
        );
        await abrirCobro(tester, metodo: 'Fiado');
        expect(
          find.textContaining('todavía no tiene clientes'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'si no se pueden verificar los precios, ni siquiera se piden los clientes',
      (tester) async {
        await banco.abrir(
          tester,
          lineas: unArroz,
          catalogoDelServidor: const RespuestaFalsa.falloDeRed(
            DioExceptionType.connectionError,
          ),
        );
        await abrirCobro(tester, metodo: 'Fiado');
        expect(
          find.textContaining('No se pudo verificar los precios'),
          findsOneWidget,
        );
        expect(banco.servidor.veces('GET', '/api/clientes'), 0);
      },
    );

    testWidgets(
      'el servidor decide: si rechaza por cupo (un saldo que la app no conocía), se muestra su mensaje y el carrito sigue',
      (tester) async {
        await banco.abrir(tester, lineas: unArroz);
        banco.servidor.programar(
          'POST',
          ruta,
          RespuestaFalsa.deEjemplo('22_V2_fiado_supera_el_cupo_400'),
        );
        await abrirCobro(tester, metodo: 'Fiado');
        await elegir(tester, 'Doña Rosa');
        await tester.tap(botonConfirmar());
        await tester.pumpAndSettle();

        expect(
          find.textContaining(
            'Esta venta supera el cupo de crédito del cliente',
          ),
          findsOneWidget,
        );
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
      'cliente inexistente o de otra tienda (404, según el contrato): se muestra el mensaje del servidor',
      (tester) async {
        await banco.abrir(tester, lineas: unArroz);
        // Sin ejemplo real en el backend: el cuerpo sale del contrato [V2].
        banco.servidor.programar(
          'POST',
          ruta,
          const RespuestaFalsa(404, {
            'success': false,
            'error': 'Cliente no encontrado',
          }),
        );
        await abrirCobro(tester, metodo: 'Fiado');
        await elegir(tester, 'Doña Rosa');
        await tester.tap(botonConfirmar());
        await tester.pumpAndSettle();
        expect(find.text('Cliente no encontrado'), findsOneWidget);
      },
    );

    testWidgets(
      'sin red al confirmar: «sin confirmar» y «Reintentar» manda la MISMA venta (misma clave, mismo cliente)',
      (tester) async {
        await banco.abrir(tester, lineas: unArroz);
        banco.programarSinRed();
        await abrirCobro(tester, metodo: 'Fiado');
        await elegir(tester, 'Doña Rosa');
        await tester.tap(botonConfirmar());
        await tester.pumpAndSettle();
        expect(find.textContaining('No la cobres otra vez'), findsOneWidget);

        banco.programarVentaOk();
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();

        final ventas = banco.servidor.peticiones
            .where((p) => p.clave == 'POST $ruta')
            .toList();
        expect(ventas, hasLength(2));
        expect(ventas[1].headers['Idempotency-Key'], clave);
        expect(ventas[1].cuerpo, ventas[0].cuerpo);
        expect((ventas[1].cuerpo as Map)['id_cliente'], 1);
        expect(find.text('Venta registrada'), findsOneWidget);
      },
    );
  });
}
