import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/carrito/carrito_models.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/venta/venta_models.dart';
import 'package:stockpilot/venta/venta_providers.dart';

import '../support/cobro_notifier_apoyo.dart';
import '../support/fake_adapter.dart';

/// El cobro en efectivo: el envío con su clave, el guardado en el celular y los reintentos.
void main() {
  const clave = claveDeVenta;
  const ruta = rutaDeVenta;
  const claveDelAlmacen = claveDelAlmacenDeVenta;
  final b = BancoDelNotificador();

  group('cobrar en efectivo: envío y reintentos', () {
    test('venta registrada: manda la clave y el cuerpo del contrato, vacía el carrito y borra la copia del celular', () async {
      await b.armar();
      b.llenarCarrito();
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
      expect(b.cobro().idVenta, 1);
      expect(b.cobro().repetida, isFalse);
      expect(b.cobro().venta!.cambioCentavos, 100000); // $1.000 de cambio
      expect(b.envios(), hasLength(1));
      expect(b.envios().single.headers['Idempotency-Key'], clave);
      expect(b.envios().single.cuerpo, {
        'items': [
          {'id_producto': 1, 'cantidad': 2},
        ],
        'metodo_pago': 'Efectivo',
        'efectivo_recibido': 10000,
      });
      expect(b.c.read(carritoProvider).lineas, isEmpty);
      expect(b.almacenVenta.datos, isEmpty);
      expect(b.pausas, isEmpty);
    });

    test('la venta se guarda en el celular ANTES de enviarla (si la app muere a mitad, se puede reintentar)', () async {
      await b.armar();
      b.llenarCarrito();
      final respuesta = Completer<void>();
      b.servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.demorada(200, {
          'success': true,
          'message': 'ok',
          'id_venta': 1,
        }, respuesta.future),
      );

      final cobrando = b.notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      await esperarQue(() => b.envios().length, (n) => n == 1);

      // La petición está en vuelo: la venta ya está guardada, con su clave.
      expect(b.cobro().fase, FaseCobro.enviando);
      expect(b.almacenVenta.datos[claveDelAlmacen]!.clave, clave);

      respuesta.complete();
      await cobrando;
      expect(b.cobro().fase, FaseCobro.registrada);
      expect(b.almacenVenta.datos, isEmpty);
    });

    test('tiempo agotado y luego éxito: reintenta SOLO con la misma clave y la misma carga, con pausa de 2 s', () async {
      await b.armar();
      b.llenarCarrito();
      b.servidor.programar(
        'POST',
        ruta,
        const RespuestaFalsa.falloDeRed(DioExceptionType.receiveTimeout),
      );
      b.servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('18_V2_reintento_misma_clave_200'),
      );

      await b.notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );

      expect(b.cobro().fase, FaseCobro.registrada);
      expect(b.cobro().repetida, isTrue);
      expect(b.envios(), hasLength(2));
      expect(b.envios().map((p) => p.headers['Idempotency-Key']), [
        clave,
        clave,
      ]);
      expect(b.envios()[1].cuerpo, b.envios()[0].cuerpo);
      expect(b.pausas, [const Duration(seconds: 2)]);
      expect(b.c.read(carritoProvider).lineas, isEmpty);
    });

    test('sin red tres veces: queda «sin confirmar» (carrito y copia intactos, carrito bloqueado); «Reintentar» usa la MISMA clave', () async {
      await b.armar();
      b.llenarCarrito();
      b.servidor.programar(
        'POST',
        ruta,
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );

      await b.notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );

      expect(b.cobro().fase, FaseCobro.sinConfirmar);
      expect(b.envios(), hasLength(3)); // el envío y dos reintentos
      expect(b.pausas, [
        const Duration(seconds: 2),
        const Duration(seconds: 5),
      ]);
      expect(b.c.read(carritoProvider).lineas.single.cantidad, 2);
      expect(b.almacenVenta.datos[claveDelAlmacen], isNotNull);
      // Con un cobro sin confirmar el carrito no se toca (el reintento debe enviar lo mismo).
      expect(
        b.c.read(carritoProvider.notifier).agregar(aceite),
        ResultadoAgregar.ventaEnCurso,
      );
      b.c.read(carritoProvider.notifier).quitar(1);
      b.c.read(carritoProvider.notifier).vaciar();
      expect(b.c.read(carritoProvider).lineas.single.cantidad, 2);

      // Vuelve la señal: el servidor responde que esa venta ya existía.
      b.servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('18_V2_reintento_misma_clave_200'),
      );
      await b.notificador().reintentar();

      expect(b.cobro().fase, FaseCobro.registrada);
      expect(b.cobro().repetida, isTrue);
      expect(b.envios(), hasLength(4));
      expect(b.envios().map((p) => p.headers['Idempotency-Key']).toSet(), {
        clave,
      });
      expect(b.c.read(carritoProvider).lineas, isEmpty);
      expect(b.almacenVenta.datos, isEmpty);
    });

    test('un error 500 se trata como «no sé qué pasó»: reintenta con la misma clave', () async {
      await b.armar();
      b.llenarCarrito();
      b.servidor.programar(
        'POST',
        ruta,
        const RespuestaFalsa(500, {'success': false, 'error': 'Error interno'}),
      );
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
      expect(b.envios().map((p) => p.headers['Idempotency-Key']), [
        clave,
        clave,
      ]);
    });

    test('stock insuficiente (400): rechazada, el carrito se conserva, no queda copia y se actualiza el catálogo', () async {
      await b.armar();
      b.llenarCarrito();
      b.servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('20_V2_stock_insuficiente_400'),
      );

      await b.notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );

      expect(b.cobro().fase, FaseCobro.rechazada);
      expect(
        b.cobro().mensaje,
        'Stock insuficiente para el producto: Arroz Diana 1Kg',
      );
      expect(b.envios(), hasLength(1), reason: 'un rechazo no se reintenta');
      expect(b.c.read(carritoProvider).lineas.single.cantidad, 2);
      expect(b.almacenVenta.datos, isEmpty);
      await esperarQue(
        () => b.servidor.veces('GET', '/api/productos'),
        (n) => n >= 1,
      );
    });

    test('después de un rechazo se puede cobrar de nuevo, y la venta nueva lleva su propia clave', () async {
      var n = 0;
      await b.armar(generador: () => 'clave-numero-${++n}');
      b.llenarCarrito();
      b.servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('20_V2_stock_insuficiente_400'),
      );
      b.servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
      );

      await b.notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      expect(b.cobro().fase, FaseCobro.rechazada);
      await b.notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );

      expect(b.cobro().fase, FaseCobro.registrada);
      expect(b.envios().map((p) => p.headers['Idempotency-Key']), [
        'clave-numero-1',
        'clave-numero-2',
      ]);
    });
  });
}
