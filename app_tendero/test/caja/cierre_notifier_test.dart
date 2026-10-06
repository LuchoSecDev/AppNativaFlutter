import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/auth/session_state.dart';
import 'package:stockpilot/caja/caja_providers.dart';
import 'package:stockpilot/caja/cierre_providers.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/catalogo/catalogo_providers.dart';
import 'package:stockpilot/venta/venta_models.dart';
import 'package:stockpilot/venta/venta_providers.dart';

import '../support/carrito_apoyo.dart';
import '../support/fake_adapter.dart';

/// El cierre de caja en tres tiempos, con el cliente HTTP REAL y un servidor falso con los ejemplos reales del backend.
void main() {
  const arqueo = '/api/caja/arqueo-previo';
  const cerrar = '/api/caja/cerrar';
  const sesionDeCaja = '/api/caja/sesion';

  late ServidorFalso servidor;
  late ProviderContainer c;
  late SesionFija sesion;

  // El arqueo final cuando entre la vista previa y el cierre se registró otra venta (+4.500 en efectivo).
  const cierreConOtraVenta = RespuestaFalsa(200, {
    'success': true,
    'message': 'Caja cerrada exitosamente (Arqueo completo)',
    'arqueo': {
      'monto_apertura': 50000,
      'ventas_efectivo': 13500,
      'abonos_efectivo': 0,
      'egresos': 10000,
      'monto_cierre_calculado': 53500,
      'monto_cierre_declarado': 57500,
      'diferencia': 4000,
    },
  });

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

  EstadoCierre cierre() => c.read(cierreProvider);
  CierreNotifier notificador() => c.read(cierreProvider.notifier);

  /// Arma el entorno con la caja ABIERTA (la primera consulta de [K1] responde el ejemplo 10).
  Future<void> armar({
    AlmacenVentaEnMemoria? ventaPrevia,
    _CobroFijo? cobro,
  }) async {
    servidor = ServidorFalso();
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
    servidor.programar(
      'GET',
      sesionDeCaja,
      RespuestaFalsa.deEjemplo('10_K1_caja_abierta'),
    );
    servidor.programar(
      'GET',
      '/api/productos',
      RespuestaFalsa.deEjemplo('13_C1_lista_de_productos'),
    );
    final dio = crearClienteApi(
      baseUrl: 'https://servidor.test',
      cookieJar: CookieJar(),
      adapter: servidor,
    );
    sesion = SesionFija(sesionActiva());
    c = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(dio),
        sesionProvider.overrideWith(() => sesion),
        almacenCarritoProvider.overrideWithValue(AlmacenEnMemoria()),
        almacenVentaPendienteProvider.overrideWithValue(
          ventaPrevia ?? AlmacenVentaEnMemoria(),
        ),
        if (cobro != null) cobroProvider.overrideWith(() => cobro),
      ],
    );
    addTearDown(c.dispose);
    c.listen(cajaProvider, (_, _) {});
    c.listen(cierreProvider, (_, _) {});
    c.listen(cobroProvider, (_, _) {});
    c.listen(catalogoProvider, (_, _) {});
    await esperarQue(
      () => (c.read(cajaProvider).fase, c.read(cobroProvider).cargando),
      (e) => e.$1 == FaseCaja.abierta && !e.$2,
    );
  }

  void programarCajaCerrada() => servidor.programar(
    'GET',
    sesionDeCaja,
    RespuestaFalsa.deEjemplo('07_K1_caja_sin_abrir'),
  );

  Future<void> hastaRevisar([int pesos = 57500]) async {
    servidor.programar(
      'POST',
      arqueo,
      RespuestaFalsa.deEjemplo('30_K5_arqueo_previo'),
    );
    await notificador().verArqueo(pesos);
    expect(cierre().fase, FaseCierre.revisando);
  }

  group('el flujo feliz', () {
    test('contar → ver el arqueo (NO cierra nada) → confirmar: la caja queda cerrada y el inicio lo refleja', () async {
      await armar();
      servidor.programar(
        'POST',
        arqueo,
        RespuestaFalsa.deEjemplo('30_K5_arqueo_previo'),
      );
      await notificador().verArqueo(57500);

      expect(cierre().fase, FaseCierre.revisando);
      expect(cierre().arqueoPrevio!.esperadoCentavos, 4900000);
      expect(cierre().arqueoPrevio!.diferenciaCentavos, 850000);
      expect(servidor.veces('POST', arqueo), 1);
      expect(
        servidor.veces('POST', cerrar),
        0,
        reason: 'la vista previa no cierra',
      );
      expect(c.read(cajaProvider).fase, FaseCaja.abierta);

      programarCajaCerrada();
      servidor.programar(
        'POST',
        cerrar,
        RespuestaFalsa.deEjemplo('27_K3_cerrar_caja'),
      );
      await notificador().confirmar();

      expect(cierre().fase, FaseCierre.cerrada);
      expect(cierre().arqueoFinal!.diferenciaCentavos, 850000);
      expect(cierre().cambio, isFalse);
      expect(servidor.veces('POST', cerrar), 1);
      final cuerpo = servidor.peticiones
          .firstWhere((p) => p.clave == 'POST $cerrar')
          .cuerpo;
      expect(cuerpo, {'monto_cierre_declarado': 57500});
      expect(c.read(cajaProvider).fase, FaseCaja.cerrada);
      expect(c.read(puedeVenderProvider), isFalse);
    });

    test('recontar: vuelve a contar conservando lo escrito; se cierra con el ÚLTIMO monto', () async {
      await armar();
      await hastaRevisar(57500);

      notificador().recontar();
      expect(cierre().fase, FaseCierre.contando);
      expect(cierre().declaradoPesos, 57500);
      expect(cierre().arqueoPrevio, isNull);
      expect(servidor.veces('POST', cerrar), 0);

      servidor.programar(
        'POST',
        arqueo,
        const RespuestaFalsa(200, {
          'success': true,
          'arqueo': {
            'monto_apertura': 50000,
            'ventas_efectivo': 9000,
            'abonos_efectivo': 0,
            'egresos': 10000,
            'monto_cierre_calculado': 49000,
            'monto_cierre_declarado': 49000,
            'diferencia': 0,
          },
        }),
      );
      await notificador().verArqueo(49000);
      expect(cierre().arqueoPrevio!.diferenciaCentavos, 0);

      programarCajaCerrada();
      servidor.programar(
        'POST',
        cerrar,
        const RespuestaFalsa(200, {
          'success': true,
          'arqueo': {
            'monto_apertura': 50000,
            'ventas_efectivo': 9000,
            'abonos_efectivo': 0,
            'egresos': 10000,
            'monto_cierre_calculado': 49000,
            'monto_cierre_declarado': 49000,
            'diferencia': 0,
          },
        }),
      );
      await notificador().confirmar();
      expect(cierre().fase, FaseCierre.cerrada);
      expect(
        servidor.peticiones.firstWhere((p) => p.clave == 'POST $cerrar').cuerpo,
        {'monto_cierre_declarado': 49000},
      );
      expect(servidor.veces('POST', arqueo), 2);
    });

    test('si entre la vista previa y el cierre se registró una venta: el arqueo final es el del servidor y se avisa del cambio', () async {
      await armar();
      await hastaRevisar(57500);
      programarCajaCerrada();
      servidor.programar('POST', cerrar, cierreConOtraVenta);
      await notificador().confirmar();

      expect(cierre().fase, FaseCierre.cerrada);
      expect(cierre().cambio, isTrue);
      expect(cierre().arqueoFinal!.esperadoCentavos, 5350000);
      expect(cierre().arqueoFinal!.diferenciaCentavos, 400000);
      expect(cierre().arqueoPrevio!.diferenciaCentavos, 850000);
    });

    test(
      'un cierre con las mismas cifras que la vista previa NO avisa de cambio',
      () async {
        await armar();
        await hastaRevisar(57500);
        programarCajaCerrada();
        servidor.programar(
          'POST',
          cerrar,
          RespuestaFalsa.deEjemplo('27_K3_cerrar_caja'),
        );
        await notificador().confirmar();
        expect(cierre().cambio, isFalse);
      },
    );
  });

  group(
    'lo que sale mal al ver el arqueo (es de solo lectura: se puede repetir)',
    () {
      test(
        'monto rechazado por el servidor: vuelve a contar con su mensaje',
        () async {
          await armar();
          servidor.programar(
            'POST',
            arqueo,
            RespuestaFalsa.deEjemplo('31_K5_monto_invalido_400'),
          );
          await notificador().verArqueo(1);
          expect(cierre().fase, FaseCierre.contando);
          expect(
            cierre().mensaje,
            'El monto de cierre declarado no es válido.',
          );
          expect(cierre().declaradoPesos, 1);
        },
      );

      test('la caja ya no estaba abierta (se cerró en la web): lo dice y actualiza la caja del inicio', () async {
        await armar();
        programarCajaCerrada();
        servidor.programar(
          'POST',
          arqueo,
          const RespuestaFalsa(400, {
            'error': 'No hay ninguna caja abierta para cerrar.',
          }),
        );
        await notificador().verArqueo(1000);
        expect(cierre().fase, FaseCierre.contando);
        expect(cierre().mensaje, contains('No hay ninguna caja abierta'));
        expect(c.read(cajaProvider).fase, FaseCaja.cerrada);
      });

      test(
        'sin red: vuelve a contar con un mensaje claro, y se puede reintentar',
        () async {
          await armar();
          servidor.programar(
            'POST',
            arqueo,
            const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
          );
          await notificador().verArqueo(57500);
          expect(cierre().fase, FaseCierre.contando);
          expect(cierre().mensaje, contains('conexión'));

          servidor.programar(
            'POST',
            arqueo,
            RespuestaFalsa.deEjemplo('30_K5_arqueo_previo'),
          );
          await notificador().verArqueo(57500);
          expect(cierre().fase, FaseCierre.revisando);
        },
      );
    },
  );

  group('cerrar no se repite a ciegas (no tiene idempotencia)', () {
    test('se perdió la respuesta pero SÍ se cerró: se consulta la caja y se dice que se cerró, sin reenviar el POST', () async {
      await armar();
      await hastaRevisar();
      servidor.programar(
        'POST',
        cerrar,
        const RespuestaFalsa.falloDeRed(DioExceptionType.receiveTimeout),
      );
      programarCajaCerrada();

      await notificador().confirmar();

      expect(cierre().fase, FaseCierre.cerrada);
      expect(cierre().arqueoFinal, isNull);
      expect(cierre().mensaje, contains('no llegó el resumen'));
      expect(servidor.veces('POST', cerrar), 1);
      expect(c.read(cajaProvider).fase, FaseCaja.cerrada);
    });

    test('se perdió la respuesta y NO se cerró: vuelve a revisar, avisa que la caja sigue abierta y se puede confirmar de nuevo', () async {
      await armar();
      await hastaRevisar();
      servidor.programar(
        'POST',
        cerrar,
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      await notificador().confirmar(); // la consulta de la caja responde «abierta» (ejemplo 10)

      expect(cierre().fase, FaseCierre.revisando);
      expect(cierre().mensaje, contains('La caja sigue abierta'));
      expect(cierre().arqueoPrevio, isNotNull);
      expect(servidor.veces('POST', cerrar), 1);

      programarCajaCerrada();
      servidor.programar(
        'POST',
        cerrar,
        RespuestaFalsa.deEjemplo('27_K3_cerrar_caja'),
      );
      await notificador().confirmar();
      expect(cierre().fase, FaseCierre.cerrada);
      expect(servidor.veces('POST', cerrar), 2);
    });

    test('no se sabe nada (ni el cierre ni la consulta llegaron): «sin confirmar»; solo se puede COMPROBAR, nunca cerrar otra vez', () async {
      await armar();
      await hastaRevisar();
      servidor.programar(
        'POST',
        cerrar,
        const RespuestaFalsa.falloDeRed(DioExceptionType.receiveTimeout),
      );
      servidor.programar(
        'GET',
        sesionDeCaja,
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      await notificador().confirmar();

      expect(cierre().fase, FaseCierre.sinConfirmar);
      expect(cierre().mensaje, contains('no la cierres otra vez'));
      // En este estado confirmar no hace nada.
      await notificador().confirmar();
      expect(servidor.veces('POST', cerrar), 1);

      programarCajaCerrada();
      await notificador().comprobar();
      expect(cierre().fase, FaseCierre.cerrada);
      expect(servidor.veces('POST', cerrar), 1);
    });

    test('cerrar con la caja ya cerrada en la web (400): lo dice, sin arqueo, y actualiza la caja', () async {
      await armar();
      await hastaRevisar();
      programarCajaCerrada();
      servidor.programar(
        'POST',
        cerrar,
        const RespuestaFalsa(400, {
          'error': 'No hay ninguna caja abierta para cerrar.',
        }),
      );
      await notificador().confirmar();
      expect(cierre().fase, FaseCierre.cerrada);
      expect(cierre().arqueoFinal, isNull);
      expect(cierre().mensaje, contains('ya estaba cerrada'));
      expect(c.read(cajaProvider).fase, FaseCaja.cerrada);
    });
  });

  group('no se cierra la caja con una venta a medias', () {
    test(
      'con una venta «sin confirmar» no se pide el arqueo y se explica por qué',
      () async {
        final previa = AlmacenVentaEnMemoria()
          ..datos['venta_pendiente_v1_2_1'] = const VentaPendiente(
            clave: '4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22',
            items: [ItemVenta(idProducto: 1, cantidad: 2)],
            metodoPago: MetodoPago.efectivo,
            totalCentavos: 900000,
            efectivoRecibido: 10000,
          );
        await armar(ventaPrevia: previa);
        expect(c.read(cobroProvider).fase, FaseCobro.sinConfirmar);

        await notificador().verArqueo(57500);
        expect(cierre().fase, FaseCierre.contando);
        expect(cierre().mensaje, contains('venta sin confirmar'));
        expect(servidor.veces('POST', arqueo), 0);
      },
    );

    test(
      'mientras se está cobrando (enviando) tampoco se pide el arqueo',
      () async {
        final cobro = _CobroFijo();
        await armar(cobro: cobro);
        cobro.poner(const EstadoCobro(fase: FaseCobro.enviando));
        await notificador().verArqueo(57500);
        expect(cierre().fase, FaseCierre.contando);
        expect(cierre().mensaje, contains('venta sin confirmar'));
        expect(servidor.veces('POST', arqueo), 0);
      },
    );

    test('si aparece una venta sin confirmar mientras se revisa, no se confirma el cierre y se sigue en la revisión', () async {
      final cobro = _CobroFijo();
      await armar(cobro: cobro);
      await hastaRevisar();

      cobro.poner(const EstadoCobro(fase: FaseCobro.sinConfirmar));
      await notificador().confirmar();

      expect(servidor.veces('POST', cerrar), 0);
      expect(cierre().fase, FaseCierre.revisando);
      expect(cierre().mensaje, contains('venta sin confirmar'));
      expect(cierre().arqueoPrevio, isNotNull);

      // Resuelta la venta, ya se puede cerrar.
      cobro.poner(const EstadoCobro());
      programarCajaCerrada();
      servidor.programar(
        'POST',
        cerrar,
        RespuestaFalsa.deEjemplo('27_K3_cerrar_caja'),
      );
      await notificador().confirmar();
      expect(cierre().fase, FaseCierre.cerrada);
    });
  });

  group('seguro contra toques repetidos y estados viejos', () {
    test('dos «Ver arqueo» seguidos hacen UNA sola consulta', () async {
      await armar();
      servidor.programar(
        'POST',
        arqueo,
        RespuestaFalsa.deEjemplo('30_K5_arqueo_previo'),
      );
      await Future.wait([
        notificador().verArqueo(57500),
        notificador().verArqueo(57500),
      ]);
      expect(servidor.veces('POST', arqueo), 1);
    });

    test('dos «Confirmar cierre» seguidos hacen UN solo cierre', () async {
      await armar();
      await hastaRevisar();
      programarCajaCerrada();
      servidor.programar(
        'POST',
        cerrar,
        RespuestaFalsa.deEjemplo('27_K3_cerrar_caja'),
      );
      await Future.wait([notificador().confirmar(), notificador().confirmar()]);
      expect(servidor.veces('POST', cerrar), 1);
    });

    test('confirmar sin haber revisado el arqueo no cierra nada', () async {
      await armar();
      await notificador().confirmar();
      expect(servidor.veces('POST', cerrar), 0);
      expect(cierre().fase, FaseCierre.contando);
    });

    test('una respuesta TARDÍA de la sesión anterior se descarta', () async {
      await armar();
      final llega = Completer<void>();
      servidor.programar(
        'POST',
        arqueo,
        RespuestaFalsa.demorada(200, const {
          'success': true,
          'arqueo': {
            'monto_apertura': 50000,
            'ventas_efectivo': 9000,
            'abonos_efectivo': 0,
            'egresos': 10000,
            'monto_cierre_calculado': 49000,
            'monto_cierre_declarado': 57500,
            'diferencia': 8500,
          },
        }, llega.future),
      );
      final calculando = notificador().verArqueo(57500);
      await esperarQue(() => servidor.veces('POST', arqueo), (n) => n == 1);

      sesion.poner(const EstadoSesion.sinSesion());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      llega.complete();
      await calculando;
      expect(cierre().fase, FaseCierre.contando);
      expect(cierre().arqueoPrevio, isNull);
    });

    test('iniciar() empieza de cero desde un comprobante o una revisión, pero no pisa algo en curso', () async {
      await armar();
      await hastaRevisar();
      notificador().iniciar();
      expect(cierre().fase, FaseCierre.contando);
      expect(cierre().declaradoPesos, isNull);

      final llega = Completer<void>();
      servidor.programar(
        'POST',
        arqueo,
        RespuestaFalsa.demorada(200, const {'success': true}, llega.future),
      );
      final calculando = notificador().verArqueo(1000);
      await esperarQue(() => cierre().fase, (f) => f == FaseCierre.calculando);
      notificador().iniciar();
      expect(cierre().fase, FaseCierre.calculando);
      llega.complete();
      await calculando;
    });
  });
}

/// Un cobro cuyo estado la prueba fija a mano (sin servidor): sirve para simular una venta en curso.
class _CobroFijo extends CobroNotifier {
  @override
  EstadoCobro build() => const EstadoCobro();

  void poner(EstadoCobro nuevo) => state = nuevo;
}
