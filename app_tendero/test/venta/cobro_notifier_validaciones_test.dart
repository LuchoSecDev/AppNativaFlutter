import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/carrito/carrito_models.dart';
import 'package:stockpilot/venta/venta_models.dart';
import 'package:stockpilot/venta/venta_providers.dart';

import '../support/cobro_notifier_apoyo.dart';
import '../support/fake_adapter.dart';

/// Lo que la app valida antes de enviar nada.
void main() {
  const ruta = rutaDeVenta;
  final b = BancoDelNotificador();

  group('lo que la app valida antes de enviar nada', () {
    test('el efectivo no alcanza: no se envía', () async {
      await b.armar();
      b.llenarCarrito(); // $9.000
      await b.notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 8999,
      );
      expect(b.cobro().fase, FaseCobro.rechazada);
      expect(b.cobro().mensaje, contains('no alcanza'));
      expect(b.envios(), isEmpty);
      expect(b.almacenVenta.datos, isEmpty);
    });

    test(
      'el efectivo justo (9.000 pesos) sí alcanza: el cambio es 0',
      () async {
        await b.armar();
        b.llenarCarrito();
        b.servidor.programar(
          'POST',
          ruta,
          RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
        );
        await b.notificador().cobrar(
          metodo: MetodoPago.efectivo,
          efectivoRecibido: 9000,
        );
        expect(b.cobro().fase, FaseCobro.registrada);
        expect(b.cobro().venta!.cambioCentavos, 0);
      },
    );

    test('sin efectivo recibido, o en 0: no se envía', () async {
      await b.armar();
      b.llenarCarrito();
      await b.notificador().cobrar(metodo: MetodoPago.efectivo);
      expect(b.cobro().fase, FaseCobro.rechazada);
      await b.notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 0,
      );
      expect(b.cobro().fase, FaseCobro.rechazada);
      expect(b.envios(), isEmpty);
    });

    test('sin caja abierta: no se envía', () async {
      await b.armar(cajaAbierta: false);
      b.llenarCarrito();
      await b.notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      expect(b.cobro().fase, FaseCobro.rechazada);
      expect(b.cobro().mensaje, contains('caja'));
      expect(b.envios(), isEmpty);
    });

    test('carrito vacío: no se envía', () async {
      await b.armar();
      await b.notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      expect(b.cobro().fase, FaseCobro.rechazada);
      expect(b.envios(), isEmpty);
    });

    test(
      'carrito con más unidades que el stock (11 de 10): no se envía',
      () async {
        await b.armar(
          lineasGuardadas: const [
            LineaCarrito(
              idProducto: 1,
              nombre: 'Arroz Diana 1Kg',
              cantidad: 11,
            ),
          ],
        );
        await b.notificador().cobrar(
          metodo: MetodoPago.efectivo,
          efectivoRecibido: 100000,
        );
        expect(b.cobro().fase, FaseCobro.rechazada);
        expect(b.cobro().mensaje, contains('problemas'));
        expect(b.envios(), isEmpty);
      },
    );

    test('un resultado se cierra con aceptarResultado', () async {
      await b.armar();
      await b.notificador().cobrar(metodo: MetodoPago.efectivo);
      expect(b.cobro().fase, FaseCobro.rechazada);
      b.notificador().aceptarResultado();
      expect(b.cobro().fase, FaseCobro.libre);
    });
  });
}
