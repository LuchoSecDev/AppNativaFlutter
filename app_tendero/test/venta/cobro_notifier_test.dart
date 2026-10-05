import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/auth/session_state.dart';
import 'package:stockpilot/caja/caja_models.dart';
import 'package:stockpilot/caja/caja_providers.dart';
import 'package:stockpilot/carrito/carrito_models.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/catalogo/catalogo_providers.dart';
import 'package:stockpilot/venta/venta_models.dart';
import 'package:stockpilot/venta/venta_providers.dart';
import 'package:stockpilot/venta/venta_repository.dart';

import '../support/carrito_apoyo.dart';
import '../support/fake_adapter.dart';

class _CajaAbiertaFija extends CajaNotifier {
  @override
  EstadoCaja build() => const EstadoCaja.abierta(
    SesionCaja(
      idSesion: 1,
      montoApertura: '50000.00',
      fechaApertura: '2026-10-04T15:30:00.000Z',
    ),
  );
}

class _CajaCerradaFija extends CajaNotifier {
  @override
  EstadoCaja build() => const EstadoCaja.cerrada();
}

/// Un repositorio que revienta: simula un error de programación dentro del cobro.
class _RepositorioRoto extends VentaRepository {
  _RepositorioRoto() : super(Dio());

  @override
  Future<ResultadoVenta> registrar(VentaPendiente venta) =>
      throw StateError('error de programación simulado');
}

/// Entrega la clave esperada la primera vez y claves distintas después.
String Function() _generadorDeUnaSolaClave() {
  var llamadas = 0;
  return () => llamadas++ == 0
      ? '4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22'
      : 'otra-clave-$llamadas';
}

/// El cobro con el cliente HTTP REAL y un servidor falso con los ejemplos reales del backend.
void main() {
  const clave = '4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22';
  const ruta = '/api/registrar-venta-carrito';
  const claveDelAlmacen = 'venta_pendiente_v1_2_1'; // usuario 2, tienda 1

  final arroz = producto(1, 'Arroz Diana 1Kg', precio: '4500.00', cantidad: 10);
  final aceite = producto(
    2,
    'Aceite Gourmet 1L',
    precio: '12000.00',
    cantidad: 5,
  );

  late ServidorFalso servidor;
  late StreamController<void> caducidad;
  late AlmacenEnMemoria almacenCarrito;
  late AlmacenVentaEnMemoria almacenVenta;
  late List<Duration> pausas;
  late ProviderContainer c;
  late SesionFija sesion;

  Future<T> esperarQue<T>(T Function() leer, bool Function(T) condicion) async {
    for (var i = 0; i < 400; i++) {
      final actual = leer();
      if (condicion(actual)) {
        return actual;
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    throw TimeoutException('La condición nunca se cumplió: ${leer()}');
  }

  EstadoCobro cobro() => c.read(cobroProvider);
  CobroNotifier notificador() => c.read(cobroProvider.notifier);
  List<PeticionRegistrada> envios() =>
      servidor.peticiones.where((p) => p.clave == 'POST $ruta').toList();

  /// Arma el entorno. [caja] decide si hay caja abierta; [esperas] los reintentos automáticos.
  Future<void> armar({
    EstadoSesion? sesionInicial,
    bool cajaAbierta = true,
    List<Duration>? esperas,
    List<Override> extra = const [],
    AlmacenVentaEnMemoria? almacenPrevio,
    List<LineaCarrito>? lineasGuardadas,
    String Function()? generador,
  }) async {
    servidor = ServidorFalso();
    caducidad = StreamController<void>.broadcast();
    almacenCarrito = AlmacenEnMemoria();
    if (lineasGuardadas != null) {
      almacenCarrito.datos['carrito_v1_2_1'] = lineasGuardadas;
    }
    almacenVenta = almacenPrevio ?? AlmacenVentaEnMemoria();
    pausas = [];
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
    servidor.programar(
      'GET',
      '/api/productos',
      RespuestaFalsa.deEjemplo('13_C1_lista_de_productos'),
    );
    servidor.programar(
      'GET',
      '/api/caja/sesion',
      RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'),
    );
    final dio = crearClienteApi(
      baseUrl: 'https://servidor.test',
      cookieJar: CookieJar(),
      adapter: servidor,
      onSessionExpired: () => caducidad.add(null),
    );
    sesion = SesionFija(sesionInicial ?? sesionActiva());
    c = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(dio),
        sesionCaducadaProvider.overrideWithValue(caducidad.stream),
        sesionProvider.overrideWith(() => sesion),
        catalogoProvider.overrideWith(
          () => CatalogoFijo(EstadoCatalogo.listo([arroz, aceite])),
        ),
        cajaProvider.overrideWith(
          () => cajaAbierta ? _CajaAbiertaFija() : _CajaCerradaFija(),
        ),
        almacenCarritoProvider.overrideWithValue(almacenCarrito),
        almacenVentaPendienteProvider.overrideWithValue(almacenVenta),
        // La primera clave es la esperada; si el código pidiera OTRA (por ejemplo, al reintentar), saldría distinta y
        // las pruebas que comparan la clave de cada envío lo detectarían.
        generadorDeClaveProvider.overrideWithValue(
          generador ?? _generadorDeUnaSolaClave(),
        ),
        pausaDeReintentoProvider.overrideWithValue((d) async => pausas.add(d)),
        if (esperas != null)
          esperasDeReintentoProvider.overrideWithValue(esperas),
        ...extra,
      ],
    );
    addTearDown(() {
      c.dispose();
      caducidad.close();
    });
    c.listen(carritoProvider, (_, _) {});
    c.listen(cobroProvider, (_, _) {});
    await esperarQue(
      () => (c.read(carritoProvider).cargando, cobro().cargando),
      (e) => !e.$1 && !e.$2,
    );
  }

  /// Carrito con 2 arroces ($9.000), como en el ejemplo 17 del backend.
  void llenarCarrito() {
    c.read(carritoProvider.notifier).agregar(arroz);
    c.read(carritoProvider.notifier).agregar(arroz);
  }

  group('cobrar en efectivo', () {
    test('venta registrada: manda la clave y el cuerpo del contrato, vacía el carrito y borra la copia del celular', () async {
      await armar();
      llenarCarrito();
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
      );

      await notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );

      expect(cobro().fase, FaseCobro.registrada);
      expect(cobro().idVenta, 1);
      expect(cobro().repetida, isFalse);
      expect(cobro().venta!.cambioCentavos, 100000); // $1.000 de cambio
      expect(envios(), hasLength(1));
      expect(envios().single.headers['Idempotency-Key'], clave);
      expect(envios().single.cuerpo, {
        'items': [
          {'id_producto': 1, 'cantidad': 2},
        ],
        'metodo_pago': 'Efectivo',
        'efectivo_recibido': 10000,
      });
      expect(c.read(carritoProvider).lineas, isEmpty);
      expect(almacenVenta.datos, isEmpty);
      expect(pausas, isEmpty);
    });

    test('la venta se guarda en el celular ANTES de enviarla (si la app muere a mitad, se puede reintentar)', () async {
      await armar();
      llenarCarrito();
      final respuesta = Completer<void>();
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.demorada(200, {
          'success': true,
          'message': 'ok',
          'id_venta': 1,
        }, respuesta.future),
      );

      final cobrando = notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      await esperarQue(() => envios().length, (n) => n == 1);

      // La petición está en vuelo: la venta ya está guardada, con su clave.
      expect(cobro().fase, FaseCobro.enviando);
      expect(almacenVenta.datos[claveDelAlmacen]!.clave, clave);

      respuesta.complete();
      await cobrando;
      expect(cobro().fase, FaseCobro.registrada);
      expect(almacenVenta.datos, isEmpty);
    });

    test('tiempo agotado y luego éxito: reintenta SOLO con la misma clave y la misma carga, con pausa de 2 s', () async {
      await armar();
      llenarCarrito();
      servidor.programar(
        'POST',
        ruta,
        const RespuestaFalsa.falloDeRed(DioExceptionType.receiveTimeout),
      );
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('18_V2_reintento_misma_clave_200'),
      );

      await notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );

      expect(cobro().fase, FaseCobro.registrada);
      expect(cobro().repetida, isTrue);
      expect(envios(), hasLength(2));
      expect(envios().map((p) => p.headers['Idempotency-Key']), [clave, clave]);
      expect(envios()[1].cuerpo, envios()[0].cuerpo);
      expect(pausas, [const Duration(seconds: 2)]);
      expect(c.read(carritoProvider).lineas, isEmpty);
    });

    test('sin red tres veces: queda «sin confirmar» (carrito y copia intactos, carrito bloqueado); «Reintentar» usa la MISMA clave', () async {
      await armar();
      llenarCarrito();
      servidor.programar(
        'POST',
        ruta,
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );

      await notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );

      expect(cobro().fase, FaseCobro.sinConfirmar);
      expect(envios(), hasLength(3)); // el envío y dos reintentos
      expect(pausas, [const Duration(seconds: 2), const Duration(seconds: 5)]);
      expect(c.read(carritoProvider).lineas.single.cantidad, 2);
      expect(almacenVenta.datos[claveDelAlmacen], isNotNull);
      // Con un cobro sin confirmar el carrito no se toca (el reintento debe enviar lo mismo).
      expect(
        c.read(carritoProvider.notifier).agregar(aceite),
        ResultadoAgregar.ventaEnCurso,
      );
      c.read(carritoProvider.notifier).quitar(1);
      c.read(carritoProvider.notifier).vaciar();
      expect(c.read(carritoProvider).lineas.single.cantidad, 2);

      // Vuelve la señal: el servidor responde que esa venta ya existía.
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('18_V2_reintento_misma_clave_200'),
      );
      await notificador().reintentar();

      expect(cobro().fase, FaseCobro.registrada);
      expect(cobro().repetida, isTrue);
      expect(envios(), hasLength(4));
      expect(envios().map((p) => p.headers['Idempotency-Key']).toSet(), {
        clave,
      });
      expect(c.read(carritoProvider).lineas, isEmpty);
      expect(almacenVenta.datos, isEmpty);
    });

    test('un error 500 se trata como «no sé qué pasó»: reintenta con la misma clave', () async {
      await armar();
      llenarCarrito();
      servidor.programar(
        'POST',
        ruta,
        const RespuestaFalsa(500, {'success': false, 'error': 'Error interno'}),
      );
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
      );
      await notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      expect(cobro().fase, FaseCobro.registrada);
      expect(envios().map((p) => p.headers['Idempotency-Key']), [clave, clave]);
    });

    test('stock insuficiente (400): rechazada, el carrito se conserva, no queda copia y se actualiza el catálogo', () async {
      await armar();
      llenarCarrito();
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('20_V2_stock_insuficiente_400'),
      );

      await notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );

      expect(cobro().fase, FaseCobro.rechazada);
      expect(
        cobro().mensaje,
        'Stock insuficiente para el producto: Arroz Diana 1Kg',
      );
      expect(envios(), hasLength(1), reason: 'un rechazo no se reintenta');
      expect(c.read(carritoProvider).lineas.single.cantidad, 2);
      expect(almacenVenta.datos, isEmpty);
      await esperarQue(
        () => servidor.veces('GET', '/api/productos'),
        (n) => n >= 1,
      );
    });

    test('después de un rechazo se puede cobrar de nuevo, y la venta nueva lleva su propia clave', () async {
      var n = 0;
      await armar(generador: () => 'clave-numero-${++n}');
      llenarCarrito();
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('20_V2_stock_insuficiente_400'),
      );
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
      );

      await notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      expect(cobro().fase, FaseCobro.rechazada);
      await notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );

      expect(cobro().fase, FaseCobro.registrada);
      expect(envios().map((p) => p.headers['Idempotency-Key']), [
        'clave-numero-1',
        'clave-numero-2',
      ]);
    });

    test('sin caja abierta en el servidor (403): rechazada y se vuelve a consultar la caja', () async {
      await armar();
      llenarCarrito();
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('08_V2_venta_sin_caja_403'),
      );
      await notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      expect(cobro().fase, FaseCobro.rechazada);
      expect(cobro().mensaje, 'Debes abrir tu caja antes de realizar ventas.');
      await esperarQue(
        () => c.read(cajaProvider).fase,
        (f) => f == FaseCaja.cerrada,
      );
      expect(servidor.veces('GET', '/api/caja/sesion'), 1);
      expect(c.read(puedeVenderProvider), isFalse);
    });

    test('sesión caducada al cobrar (401): queda sin confirmar, sin reintento automático, y la copia sobrevive', () async {
      await armar();
      llenarCarrito();
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('29_S6_sin_sesion_401'),
      );
      await notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      expect(cobro().fase, FaseCobro.sinConfirmar);
      expect(cobro().sesionCaducada, isTrue);
      expect(envios(), hasLength(1));
      expect(almacenVenta.datos[claveDelAlmacen]!.clave, clave);
      expect(c.read(carritoProvider).lineas.single.cantidad, 2);
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
      await armar(almacenPrevio: previo);

      expect(cobro().fase, FaseCobro.sinConfirmar);
      expect(cobro().venta!.clave, clave);
      expect(
        envios(),
        isEmpty,
        reason: 'no se reenvía sola: la persona lo ve primero',
      );

      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('18_V2_reintento_misma_clave_200'),
      );
      await notificador().reintentar();
      expect(cobro().fase, FaseCobro.registrada);
      expect(cobro().repetida, isTrue);
      expect(envios().single.headers['Idempotency-Key'], clave);
      expect(almacenVenta.datos, isEmpty);
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
      await armar(almacenPrevio: previo);
      expect(cobro().fase, FaseCobro.libre);
    });

    test(
      '«Cancelar este cobro» borra la copia y deja cobrar de nuevo',
      () async {
        await armar();
        llenarCarrito();
        servidor.programar(
          'POST',
          ruta,
          const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
        );
        await notificador().cobrar(
          metodo: MetodoPago.efectivo,
          efectivoRecibido: 10000,
        );
        expect(cobro().fase, FaseCobro.sinConfirmar);

        await notificador().descartarSinConfirmar();

        expect(cobro().fase, FaseCobro.libre);
        expect(almacenVenta.datos, isEmpty);
        expect(c.read(carritoProvider).lineas.single.cantidad, 2);
        expect(
          c.read(carritoProvider.notifier).agregar(aceite),
          ResultadoAgregar.agregado,
        );
      },
    );

    test('un doble toque en «Confirmar» no manda dos ventas', () async {
      await armar();
      llenarCarrito();
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
      );
      final a = notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      final b = notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      await Future.wait([a, b]);
      expect(envios(), hasLength(1));
      expect(cobro().fase, FaseCobro.registrada);
    });

    test('si la respuesta llega cuando ya es OTRA sesión, no toca el carrito nuevo y la venta queda pendiente para su dueño', () async {
      await armar();
      llenarCarrito();
      final respuesta = Completer<void>();
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.demorada(200, {
          'success': true,
          'message': 'ok',
          'id_venta': 1,
        }, respuesta.future),
      );
      final cobrando = notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      await esperarQue(() => envios().length, (n) => n == 1);

      // Mientras tanto, la persona sale y entra otra en el mismo celular, que arma su propio carrito.
      sesion.poner(const EstadoSesion.sinSesion());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      almacenCarrito.datos['carrito_v1_3_1'] = const [
        LineaCarrito(idProducto: 2, nombre: 'Aceite Gourmet 1L', cantidad: 1),
      ];
      sesion.poner(sesionActiva(userId: 3));
      await esperarQue(
        () => c.read(carritoProvider).cargando,
        (cargando) => !cargando,
      );

      respuesta.complete();
      await cobrando;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(c.read(carritoProvider).lineas.single.idProducto, 2);
      expect(cobro().fase, FaseCobro.libre);
      expect(
        almacenVenta.datos[claveDelAlmacen],
        isNotNull,
        reason: 'al volver el dueño, reintenta y el servidor devuelve la misma venta',
      );
    });

    test('con la copia del celular rota, la venta se cobra igual', () async {
      await armar();
      llenarCarrito();
      almacenVenta.fallar = true;
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
      );
      await notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      expect(cobro().fase, FaseCobro.registrada);
    });

    test('un error de programación no deja la pantalla girando ni da la venta por fallida: queda «sin confirmar» y el error se relanza', () async {
      await armar(
        extra: [ventaRepositoryProvider.overrideWithValue(_RepositorioRoto())],
      );
      llenarCarrito();
      await expectLater(
        notificador().cobrar(
          metodo: MetodoPago.efectivo,
          efectivoRecibido: 10000,
        ),
        throwsA(isA<StateError>()),
      );
      expect(cobro().fase, FaseCobro.sinConfirmar);
      expect(almacenVenta.datos[claveDelAlmacen], isNotNull);
    });
  });

  group('lo que la app valida antes de enviar nada', () {
    test('el efectivo no alcanza: no se envía', () async {
      await armar();
      llenarCarrito(); // $9.000
      await notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 8999,
      );
      expect(cobro().fase, FaseCobro.rechazada);
      expect(cobro().mensaje, contains('no alcanza'));
      expect(envios(), isEmpty);
      expect(almacenVenta.datos, isEmpty);
    });

    test(
      'el efectivo justo (9.000 pesos) sí alcanza: el cambio es 0',
      () async {
        await armar();
        llenarCarrito();
        servidor.programar(
          'POST',
          ruta,
          RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
        );
        await notificador().cobrar(
          metodo: MetodoPago.efectivo,
          efectivoRecibido: 9000,
        );
        expect(cobro().fase, FaseCobro.registrada);
        expect(cobro().venta!.cambioCentavos, 0);
      },
    );

    test('sin efectivo recibido, o en 0: no se envía', () async {
      await armar();
      llenarCarrito();
      await notificador().cobrar(metodo: MetodoPago.efectivo);
      expect(cobro().fase, FaseCobro.rechazada);
      await notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 0,
      );
      expect(cobro().fase, FaseCobro.rechazada);
      expect(envios(), isEmpty);
    });

    test('sin caja abierta: no se envía', () async {
      await armar(cajaAbierta: false);
      llenarCarrito();
      await notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      expect(cobro().fase, FaseCobro.rechazada);
      expect(cobro().mensaje, contains('caja'));
      expect(envios(), isEmpty);
    });

    test('carrito vacío: no se envía', () async {
      await armar();
      await notificador().cobrar(
        metodo: MetodoPago.efectivo,
        efectivoRecibido: 10000,
      );
      expect(cobro().fase, FaseCobro.rechazada);
      expect(envios(), isEmpty);
    });

    test(
      'carrito con más unidades que el stock (11 de 10): no se envía',
      () async {
        await armar(
          lineasGuardadas: const [
            LineaCarrito(
              idProducto: 1,
              nombre: 'Arroz Diana 1Kg',
              cantidad: 11,
            ),
          ],
        );
        await notificador().cobrar(
          metodo: MetodoPago.efectivo,
          efectivoRecibido: 100000,
        );
        expect(cobro().fase, FaseCobro.rechazada);
        expect(cobro().mensaje, contains('problemas'));
        expect(envios(), isEmpty);
      },
    );

    test('un resultado se cierra con aceptarResultado', () async {
      await armar();
      await notificador().cobrar(metodo: MetodoPago.efectivo);
      expect(cobro().fase, FaseCobro.rechazada);
      notificador().aceptarResultado();
      expect(cobro().fase, FaseCobro.libre);
    });
  });
}
