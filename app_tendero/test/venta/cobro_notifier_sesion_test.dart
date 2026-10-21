import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/auth/session_state.dart';
import 'package:stockpilot/caja/caja_providers.dart';
import 'package:stockpilot/carrito/carrito_models.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/venta/venta_models.dart';
import 'package:stockpilot/venta/venta_providers.dart';

import '../support/carrito_apoyo.dart';
import '../support/cobro_notifier_apoyo.dart';
import '../support/fake_adapter.dart';

/// El cobro y la sesión: caja cerrada, sesión caducada, volver a entrar, otra cuenta y el doble toque.
void main() {
  const clave = claveDeVenta;
  const ruta = rutaDeVenta;
  const claveDelAlmacen = claveDelAlmacenDeVenta;
  final b = BancoDelNotificador();

  group('cobrar en efectivo: caja, sesión y cuentas', () {
    test('sin caja abierta en el servidor (403): rechazada y se vuelve a consultar la caja', () async {
      await b.armar();
      b.llenarCarrito();
      b.servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('08_V2_venta_sin_caja_403'),
      );
      await b.notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      expect(b.cobro().fase, FaseCobro.rechazada);
      expect(
        b.cobro().mensaje,
        'Debes abrir tu caja antes de realizar ventas.',
      );
      await esperarQue(
        () => b.c.read(cajaProvider).fase,
        (f) => f == FaseCaja.cerrada,
      );
      expect(b.servidor.veces('GET', '/api/caja/sesion'), 1);
      expect(b.c.read(puedeVenderProvider), isFalse);
    });

    test('sesión caducada al cobrar (401): queda sin confirmar, sin reintento automático, y la copia sobrevive', () async {
      await b.armar();
      b.llenarCarrito();
      b.servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('29_S6_sin_sesion_401'),
      );
      await b.notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      expect(b.cobro().fase, FaseCobro.sinConfirmar);
      expect(b.cobro().sesionCaducada, isTrue);
      expect(b.envios(), hasLength(1));
      expect(b.almacenVenta.datos[claveDelAlmacen]!.clave, clave);
      expect(b.c.read(carritoProvider).lineas.single.cantidad, 2);
    });

    test('al volver a entrar tras cerrar la app a mitad de un cobro, reaparece «sin confirmar» y se reintenta con la MISMA clave', () async {
      // Lo que quedó guardado de una app que murió después de guardar y antes de saber el resultado.
      final previo = AlmacenVentaEnMemoria()
        ..datos[claveDelAlmacen] = const VentaPendiente(
          clave: clave,
          items: [ItemVenta(idProducto: 1, cantidad: 2)],
          metodoPago: MetodoPago.efectivo,
          totalCentavos: 900000,
          efectivoRecibido: 10000,
        );
      await b.armar(almacenPrevio: previo);

      expect(b.cobro().fase, FaseCobro.sinConfirmar);
      expect(b.cobro().venta!.clave, clave);
      expect(
        b.envios(),
        isEmpty,
        reason: 'no se reenvía sola: la persona lo ve primero',
      );

      b.servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('18_V2_reintento_misma_clave_200'),
      );
      await b.notificador().reintentar();
      expect(b.cobro().fase, FaseCobro.registrada);
      expect(b.cobro().repetida, isTrue);
      expect(b.envios().single.headers['Idempotency-Key'], clave);
      expect(b.almacenVenta.datos, isEmpty);
    });

    test('la venta pendiente de OTRA cuenta no aparece en esta', () async {
      final previo = AlmacenVentaEnMemoria()
        ..datos['venta_pendiente_v1_9_1'] = const VentaPendiente(
          clave: clave,
          items: [ItemVenta(idProducto: 1, cantidad: 2)],
          metodoPago: MetodoPago.efectivo,
          totalCentavos: 900000,
          efectivoRecibido: 10000,
        );
      await b.armar(almacenPrevio: previo);
      expect(b.cobro().fase, FaseCobro.libre);
    });

    test(
      '«Cancelar este cobro» borra la copia y deja cobrar de nuevo',
      () async {
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

        await b.notificador().descartarSinConfirmar();

        expect(b.cobro().fase, FaseCobro.libre);
        expect(b.almacenVenta.datos, isEmpty);
        expect(b.c.read(carritoProvider).lineas.single.cantidad, 2);
        expect(
          b.c.read(carritoProvider.notifier).agregar(aceite),
          ResultadoAgregar.agregado,
        );
      },
    );

    test('un doble toque en «Confirmar» no manda dos ventas', () async {
      await b.armar();
      b.llenarCarrito();
      b.servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
      );
      final a = b.notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      final segundo = b.notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      await Future.wait([a, segundo]);
      expect(b.envios(), hasLength(1));
      expect(b.cobro().fase, FaseCobro.registrada);
    });

    test('si la respuesta llega cuando ya es OTRA sesión, no toca el carrito nuevo y la venta queda pendiente para su dueño', () async {
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

      // Mientras tanto, la persona sale y entra otra en el mismo celular, que arma su propio carrito.
      b.sesion.poner(const EstadoSesion.sinSesion());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      b.almacenCarrito.datos['carrito_v1_3_1'] = const [
        LineaCarrito(idProducto: 2, nombre: 'Aceite Gourmet 1L', cantidad: 1),
      ];
      b.sesion.poner(sesionActiva(userId: 3));
      await esperarQue(
        () => b.c.read(carritoProvider).cargando,
        (cargando) => !cargando,
      );

      respuesta.complete();
      await cobrando;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(b.c.read(carritoProvider).lineas.single.idProducto, 2);
      expect(b.cobro().fase, FaseCobro.libre);
      expect(
        b.almacenVenta.datos[claveDelAlmacen],
        isNotNull,
        reason: 'al volver el dueño, reintenta y el servidor devuelve la misma venta',
      );
    });
  });
}
