import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/clientes/cliente.dart';
import 'package:stockpilot/venta/venta_models.dart';
import 'package:stockpilot/venta/venta_providers.dart';

import '../support/cobro_notifier_apoyo.dart';
import '../support/fake_adapter.dart';

/// El cobro cuando el celular falla, y cobrar con tarjeta, transferencia y fiado.
void main() {
  const clave = claveDeVenta;
  const ruta = rutaDeVenta;
  const claveDelAlmacen = claveDelAlmacenDeVenta;
  final b = BancoDelNotificador();

  group('cobrar en efectivo: fallos del celular y de programación', () {
    test('con la copia del celular rota, la venta se cobra igual', () async {
      await b.armar();
      b.llenarCarrito();
      b.almacenVenta.fallar = true;
      b.servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
      );
      await b.notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      expect(b.cobro().fase, FaseCobro.registrada);
    });

    test('un error de programación no deja la pantalla girando ni da la venta por fallida: queda «sin confirmar» y el error se relanza', () async {
      await b.armar(
        extra: [ventaRepositoryProvider.overrideWithValue(RepositorioRoto())],
      );
      b.llenarCarrito();
      await expectLater(
        b.notificador().cobrar(
          metodo: MetodoPago.efectivo,
          efectivoRecibido: 10000,
        ),
        throwsA(isA<StateError>()),
      );
      expect(b.cobro().fase, FaseCobro.sinConfirmar);
      expect(b.almacenVenta.datos[claveDelAlmacen], isNotNull);
    });
  });

  group('cobrar con tarjeta, transferencia y fiado', () {
    const rosa = Cliente(
      id: 1,
      nombre: 'Doña Rosa',
      celular: null,
      limiteCreditoCentavos: 500000, // cupo $5.000
      saldoPendienteCentavos: 0,
    );
    const sinTope = Cliente(
      id: 2,
      nombre: 'Don Pedro',
      celular: null,
      limiteCreditoCentavos: 0,
      saldoPendienteCentavos: 0,
    );

    for (final metodo in [MetodoPago.tarjeta, MetodoPago.transferencia]) {
      test(
        '${metodo.valorApi}: se manda sin efectivo ni cliente, no hay cambio y el carrito se vacía',
        () async {
          await b.armar();
          b.llenarCarrito();
          b.servidor.programar(
            'POST',
            ruta,
            RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
          );

          await b.notificador().cobrar(metodo: metodo);

          expect(b.cobro().fase, FaseCobro.registrada);
          expect(b.cobro().venta!.cambioCentavos, isNull);
          expect(b.envios().single.cuerpo, {
            'items': [
              {'id_producto': 1, 'cantidad': 2},
            ],
            'metodo_pago': metodo.valorApi,
          });
          expect(b.c.read(carritoProvider).lineas, isEmpty);
          expect(b.almacenVenta.datos, isEmpty);
        },
      );
    }

    test('fiado sin cliente: no se envía', () async {
      await b.armar();
      b.llenarCarrito();
      await b.notificador().cobrar(metodo: MetodoPago.fiado);
      expect(b.cobro().fase, FaseCobro.rechazada);
      expect(b.cobro().mensaje, contains('cliente'));
      expect(b.envios(), isEmpty);
      expect(b.almacenVenta.datos, isEmpty);
    });

    test(
      'fiado que se pasa del cupo (9.000 pesos contra 5.000): no se envía',
      () async {
        await b.armar();
        b.llenarCarrito();
        await b.notificador().cobrar(metodo: MetodoPago.fiado, cliente: rosa);
        expect(b.cobro().fase, FaseCobro.rechazada);
        expect(b.cobro().mensaje, contains('cupo'));
        expect(b.envios(), isEmpty);
        expect(b.almacenVenta.datos, isEmpty);
      },
    );

    test(
      'fiado dentro del cupo: manda Fiado e id_cliente y no manda efectivo',
      () async {
        await b.armar();
        b.c.read(carritoProvider.notifier).agregar(arroz); // $4.500
        b.servidor.programar(
          'POST',
          ruta,
          RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
        );

        await b.notificador().cobrar(metodo: MetodoPago.fiado, cliente: rosa);

        expect(b.cobro().fase, FaseCobro.registrada);
        expect(b.envios().single.cuerpo, {
          'items': [
            {'id_producto': 1, 'cantidad': 1},
          ],
          'metodo_pago': 'Fiado',
          'id_cliente': 1,
        });
        expect(b.envios().single.headers['Idempotency-Key'], clave);
      },
    );

    test(
      'fiado a un cliente sin tope: se envía aunque el monto sea grande',
      () async {
        await b.armar();
        b.llenarCarrito();
        b.servidor.programar(
          'POST',
          ruta,
          RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
        );
        await b.notificador().cobrar(
          metodo: MetodoPago.fiado,
          cliente: sinTope,
        );
        expect(b.cobro().fase, FaseCobro.registrada);
        expect((b.envios().single.cuerpo as Map)['id_cliente'], 2);
      },
    );

    test('el servidor rechaza el fiado por cupo (400 real): se muestra su mensaje, nada se pierde y la misma clave sirve al corregir', () async {
      await b.armar();
      b.c.read(carritoProvider.notifier).agregar(arroz);
      b.servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('22_V2_fiado_supera_el_cupo_400'),
      );

      await b.notificador().cobrar(metodo: MetodoPago.fiado, cliente: rosa);

      expect(b.cobro().fase, FaseCobro.rechazada);
      expect(
        b.cobro().mensaje,
        contains('supera el cupo de crédito del cliente'),
      );
      expect(b.c.read(carritoProvider).lineas.single.cantidad, 1);
      expect(b.almacenVenta.datos, isEmpty);
    });

    test('sin red: la venta pendiente guarda al cliente, para reintentar la MISMA venta', () async {
      await b.armar(esperas: const []);
      b.c.read(carritoProvider.notifier).agregar(arroz);
      b.servidor.programar(
        'POST',
        ruta,
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );

      await b.notificador().cobrar(metodo: MetodoPago.fiado, cliente: rosa);

      expect(b.cobro().fase, FaseCobro.sinConfirmar);
      final guardada = b.almacenVenta.datos[claveDelAlmacen]!;
      expect(guardada.idCliente, 1);
      expect(guardada.metodoPago, MetodoPago.fiado);
    });
  });
}
