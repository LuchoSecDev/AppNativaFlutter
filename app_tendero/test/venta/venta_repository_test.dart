import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/venta/venta_models.dart';
import 'package:stockpilot/venta/venta_repository.dart';

import '../support/fake_adapter.dart';

/// El repositorio de ventas con el cliente HTTP REAL y un servidor falso con los ejemplos reales del backend.
void main() {
  late ServidorFalso servidor;
  late VentaRepository repo;
  var sesionesCaducadas = 0;

  const clave = '4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22';
  const venta = VentaPendiente(
    clave: clave,
    items: [ItemVenta(idProducto: 1, cantidad: 2)],
    metodoPago: MetodoPago.efectivo,
    totalCentavos: 900000,
    efectivoRecibido: 10000,
  );

  const ruta = '/api/registrar-venta-carrito';

  setUp(() {
    sesionesCaducadas = 0;
    servidor = ServidorFalso();
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
    repo = VentaRepository(
      crearClienteApi(
        baseUrl: 'https://servidor.test',
        cookieJar: CookieJar(),
        adapter: servidor,
        onSessionExpired: () => sesionesCaducadas++,
      ),
    );
  });

  test('[17] una venta en efectivo: manda la Idempotency-Key, el token y el cuerpo del contrato, y devuelve el id', () async {
    servidor.programar(
      'POST',
      ruta,
      RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
    );
    final r = await repo.registrar(venta);

    expect(r, isA<VentaRegistrada>());
    expect((r as VentaRegistrada).idVenta, 1);
    expect(r.repetida, isFalse);

    final peticion = servidor.peticiones.firstWhere(
      (p) => p.clave == 'POST $ruta',
    );
    expect(peticion.headers['Idempotency-Key'], clave);
    expect(peticion.headers['X-CSRF-Token'], isNotEmpty);
    expect(peticion.headers['Accept'], 'application/json');
    expect(peticion.cuerpo, {
      'items': [
        {'id_producto': 1, 'cantidad': 2},
      ],
      'metodo_pago': 'Efectivo',
      'efectivo_recibido': 10000,
    });
  });

  test('[18] el reintento con la misma clave devuelve la misma venta marcada como repetida', () async {
    servidor.programar(
      'POST',
      ruta,
      RespuestaFalsa.deEjemplo('18_V2_reintento_misma_clave_200'),
    );
    final r = await repo.registrar(venta) as VentaRegistrada;
    expect(r.idVenta, 1);
    expect(r.repetida, isTrue);
  });

  test('[19] la misma clave con otra carga (422): rechazada, con el mensaje del servidor', () async {
    servidor.programar(
      'POST',
      ruta,
      RespuestaFalsa.deEjemplo('19_V2_misma_clave_otra_carga_422'),
    );
    final r = await repo.registrar(venta);
    expect(r, isA<VentaRechazada>());
    expect((r as VentaRechazada).mensaje, contains('Idempotency-Key'));
    expect(r.cajaCerrada, isFalse);
  });

  test(
    '[20] stock insuficiente (400): rechazada con el nombre del producto',
    () async {
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('20_V2_stock_insuficiente_400'),
      );
      final r = await repo.registrar(venta) as VentaRechazada;
      expect(r.mensaje, 'Stock insuficiente para el producto: Arroz Diana 1Kg');
      expect(r.cajaCerrada, isFalse);
    },
  );

  test('[21] método de pago inválido (400) y [22] cupo superado (400): rechazadas, no «sin confirmar»', () async {
    servidor.programar(
      'POST',
      ruta,
      RespuestaFalsa.deEjemplo('21_V2_metodo_de_pago_invalido_400'),
    );
    servidor.programar(
      'POST',
      ruta,
      RespuestaFalsa.deEjemplo('22_V2_fiado_supera_el_cupo_400'),
    );
    final a = await repo.registrar(venta);
    final b = await repo.registrar(venta);
    expect(a, isA<VentaRechazada>());
    expect((a as VentaRechazada).mensaje, contains('Método de pago no válido'));
    expect(b, isA<VentaRechazada>());
    expect((b as VentaRechazada).mensaje, contains('supera el cupo'));
  });

  test(
    '[08] sin caja abierta (403): rechazada y avisa que la caja está cerrada',
    () async {
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('08_V2_venta_sin_caja_403'),
      );
      final r = await repo.registrar(venta) as VentaRechazada;
      expect(r.mensaje, 'Debes abrir tu caja antes de realizar ventas.');
      expect(r.cajaCerrada, isTrue);
    },
  );

  test('un 403 de CSRF que persiste tras el reintento NO se confunde con «caja cerrada»', () async {
    servidor.programar(
      'POST',
      ruta,
      RespuestaFalsa.deEjemplo('06_S6_escritura_sin_csrf_403'),
    );
    final r = await repo.registrar(venta) as VentaRechazada;
    expect(r.cajaCerrada, isFalse);
  });

  test('un 403 de CSRF se reintenta UNA vez y el reintento conserva la misma Idempotency-Key', () async {
    servidor.programar(
      'POST',
      ruta,
      RespuestaFalsa.deEjemplo('06_S6_escritura_sin_csrf_403'),
    );
    servidor.programar(
      'POST',
      ruta,
      RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
    );
    final r = await repo.registrar(venta);
    expect(r, isA<VentaRegistrada>());
    final envios = servidor.peticiones
        .where((p) => p.clave == 'POST $ruta')
        .toList();
    expect(envios, hasLength(2));
    expect(envios.map((p) => p.headers['Idempotency-Key']), [clave, clave]);
  });

  group(
    'no se sabe si quedó registrada: «sin confirmar», nunca «rechazada»',
    () {
      for (final tipo in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      ]) {
        test('$tipo: sin confirmar, con reintento automático', () async {
          servidor.programar('POST', ruta, RespuestaFalsa.falloDeRed(tipo));
          final r = await repo.registrar(venta);
          expect(r, isA<VentaSinConfirmar>());
          expect((r as VentaSinConfirmar).reintentoAutomatico, isTrue);
          expect(r.sesionCaducada, isFalse);
        });
      }

      test('un 500: sin confirmar, con reintento automático', () async {
        servidor.programar(
          'POST',
          ruta,
          const RespuestaFalsa(500, {
            'success': false,
            'error': 'Error interno',
          }),
        );
        final r = await repo.registrar(venta) as VentaSinConfirmar;
        expect(r.reintentoAutomatico, isTrue);
      });

      test('un 429 (límite de uso): sin confirmar, SIN reintento automático, con el mensaje del servidor', () async {
        servidor.programar(
          'POST',
          ruta,
          const RespuestaFalsa(429, {
            'success': false,
            'error': 'Demasiadas peticiones, espera.',
          }),
        );
        final r = await repo.registrar(venta) as VentaSinConfirmar;
        expect(r.reintentoAutomatico, isFalse);
        expect(r.mensaje, 'Demasiadas peticiones, espera.');
      });

      test('un 401 (sesión caducada): sin confirmar, avisa de la caducidad, sin reintento automático', () async {
        servidor.programar(
          'POST',
          ruta,
          RespuestaFalsa.deEjemplo('29_S6_sin_sesion_401'),
        );
        final r = await repo.registrar(venta) as VentaSinConfirmar;
        expect(r.sesionCaducada, isTrue);
        expect(r.reintentoAutomatico, isFalse);
        expect(
          sesionesCaducadas,
          1,
          reason: 'el interceptor avisa para volver al login',
        );
      });

      test(
        'un 200 sin id_venta no se da por registrado ni se reintenta solo',
        () async {
          servidor.programar(
            'POST',
            ruta,
            const RespuestaFalsa(200, {'success': true}),
          );
          final r = await repo.registrar(venta) as VentaSinConfirmar;
          expect(r.reintentoAutomatico, isFalse);
        },
      );
    },
  );
}
