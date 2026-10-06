import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/api/errores_de_api.dart';
import 'package:stockpilot/caja/caja_models.dart';
import 'package:stockpilot/caja/caja_repository.dart';

import '../support/fake_adapter.dart';

/// El arqueo ([K5], vista previa) y el cierre ([K3]) con los ejemplos reales del backend.
void main() {
  late ServidorFalso servidor;
  late CajaRepository repo;

  setUp(() {
    servidor = ServidorFalso();
    repo = CajaRepository(
      crearClienteApi(
        baseUrl: 'https://servidor.test',
        cookieJar: CookieJar(),
        adapter: servidor,
      ),
    );
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
  });

  group('ArqueoCaja (modelo)', () {
    const json = {
      'monto_apertura': 50000,
      'ventas_efectivo': 9000,
      'abonos_efectivo': 0,
      'egresos': 10000,
      'monto_cierre_calculado': 49000,
      'monto_cierre_declarado': 57500,
      'diferencia': 8500,
    };

    test('lee el ejemplo real y guarda todo en CENTAVOS enteros', () {
      final a = ArqueoCaja.desdeJson(json)!;
      expect(a.aperturaCentavos, 5000000);
      expect(a.ventasEfectivoCentavos, 900000);
      expect(a.abonosEfectivoCentavos, 0);
      expect(a.egresosCentavos, 1000000);
      expect(a.esperadoCentavos, 4900000);
      expect(a.declaradoCentavos, 5750000);
      expect(a.diferenciaCentavos, 850000);
    });

    test('los decimales no acumulan error: 4500.5 son 450050 centavos; 0.1 + 0.2 no inventa una diferencia', () {
      final a = ArqueoCaja.desdeJson({
        ...json,
        'ventas_efectivo': 4500.5,
        'diferencia': 0.1 + 0.2 - 0.3,
      })!;
      expect(a.ventasEfectivoCentavos, 450050);
      expect(a.diferenciaCentavos, 0);
      expect(a.tipo, TipoDiferencia.cuadra);
    });

    test(
      'si falta un dato o no es un número, no se inventa un arqueo (null)',
      () {
        expect(ArqueoCaja.desdeJson(null), isNull);
        expect(ArqueoCaja.desdeJson('texto'), isNull);
        for (final clave in json.keys) {
          expect(
            ArqueoCaja.desdeJson({...json}..remove(clave)),
            isNull,
            reason: 'sin $clave',
          );
          expect(
            ArqueoCaja.desdeJson({...json, clave: '123'}),
            isNull,
            reason: '$clave como texto',
          );
        }
      },
    );

    test('«Cuadra», «Sobra» o «Falta» según el signo, con el monto sin signo menos', () {
      final cuadra = ArqueoCaja.desdeJson({...json, 'diferencia': 0})!;
      expect(cuadra.tipo, TipoDiferencia.cuadra);
      expect(cuadra.tituloDeLaDiferencia, 'Cuadra');

      final sobra = ArqueoCaja.desdeJson(json)!;
      expect(sobra.tipo, TipoDiferencia.sobra);
      expect(sobra.tituloDeLaDiferencia, 'Sobra');
      expect(sobra.detalleDeLaDiferencia, r'Hay $8.500 de más en el cajón.');

      final falta = ArqueoCaja.desdeJson({...json, 'diferencia': -4500})!;
      expect(falta.tipo, TipoDiferencia.falta);
      expect(falta.tituloDeLaDiferencia, 'Falta');
      expect(falta.detalleDeLaDiferencia, r'Faltan $4.500 en el cajón.');
      expect(falta.detalleDeLaDiferencia, isNot(contains('-')));
    });

    test('mismasCifrasQue detecta que cambió lo esperado, lo contado o la diferencia', () {
      final a = ArqueoCaja.desdeJson(json)!;
      expect(a.mismasCifrasQue(ArqueoCaja.desdeJson(json)!), isTrue);
      expect(
        a.mismasCifrasQue(
          ArqueoCaja.desdeJson({
            ...json,
            'monto_cierre_calculado': 53500,
            'diferencia': 4000,
          })!,
        ),
        isFalse,
      );
      expect(
        a.mismasCifrasQue(ArqueoCaja.desdeJson({...json, 'diferencia': 8501})!),
        isFalse,
      );
    });
  });

  group('verArqueo [K5]', () {
    test('[30] con lo contado devuelve el arqueo; manda el monto como NÚMERO y el token CSRF', () async {
      servidor.programar(
        'POST',
        '/api/caja/arqueo-previo',
        RespuestaFalsa.deEjemplo('30_K5_arqueo_previo'),
      );
      final r = await repo.verArqueo(57500);
      expect(r, isA<ArqueoCalculado>());
      final arqueo = (r as ArqueoCalculado).arqueo;
      expect(arqueo.esperadoCentavos, 4900000);
      expect(arqueo.diferenciaCentavos, 850000);

      final p = servidor.peticiones.firstWhere(
        (p) => p.clave == 'POST /api/caja/arqueo-previo',
      );
      expect(p.cuerpo, {'monto_cierre_declarado': 57500});
      expect(p.headers['X-CSRF-Token'], isNotEmpty);
    });

    test(
      '[31] monto inválido (400): rechazado con el mensaje del servidor',
      () async {
        servidor.programar(
          'POST',
          '/api/caja/arqueo-previo',
          RespuestaFalsa.deEjemplo('31_K5_monto_invalido_400'),
        );
        final r = await repo.verArqueo(1) as ArqueoRechazado;
        expect(r.mensaje, 'El monto de cierre declarado no es válido.');
        expect(r.sinCajaAbierta, isFalse);
      },
    );

    test(
      'sin caja abierta (400): rechazado y lo marca para actualizar la caja',
      () async {
        servidor.programar(
          'POST',
          '/api/caja/arqueo-previo',
          const RespuestaFalsa(400, {
            'error': 'No hay ninguna caja abierta para cerrar.',
          }),
        );
        final r = await repo.verArqueo(1000) as ArqueoRechazado;
        expect(r.sinCajaAbierta, isTrue);
      },
    );

    test('sin red, 500 o un 200 sin arqueo: ErrorDeApi (es de solo lectura: se puede reintentar)', () async {
      servidor.programar(
        'POST',
        '/api/caja/arqueo-previo',
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      await expectLater(repo.verArqueo(1), throwsA(isA<ErrorDeApi>()));
      servidor.programar(
        'POST',
        '/api/caja/arqueo-previo',
        const RespuestaFalsa(500, {'error': 'x'}),
      );
      await expectLater(repo.verArqueo(1), throwsA(isA<ErrorDeApi>()));
      servidor.programar(
        'POST',
        '/api/caja/arqueo-previo',
        const RespuestaFalsa(200, {'success': true}),
      );
      await expectLater(repo.verArqueo(1), throwsA(isA<ErrorDeApi>()));
    });
  });

  group('cerrar [K3]', () {
    test('[27] cierra y devuelve el arqueo FINAL del servidor', () async {
      servidor.programar(
        'POST',
        '/api/caja/cerrar',
        RespuestaFalsa.deEjemplo('27_K3_cerrar_caja'),
      );
      final r = await repo.cerrar(57500);
      expect(r, isA<CierreExitoso>());
      expect((r as CierreExitoso).arqueo!.diferenciaCentavos, 850000);
      final p = servidor.peticiones.firstWhere(
        (p) => p.clave == 'POST /api/caja/cerrar',
      );
      expect(p.cuerpo, {'monto_cierre_declarado': 57500});
    });

    test('un 200 sin arqueo cuenta como cerrada (arqueo null): la caja SÍ se cerró', () async {
      servidor.programar(
        'POST',
        '/api/caja/cerrar',
        const RespuestaFalsa(200, {'success': true}),
      );
      final r = await repo.cerrar(1000) as CierreExitoso;
      expect(r.arqueo, isNull);
    });

    test(
      '400: rechazado con su mensaje; «no hay caja abierta» se distingue',
      () async {
        servidor.programar(
          'POST',
          '/api/caja/cerrar',
          const RespuestaFalsa(400, {
            'error': 'No hay ninguna caja abierta para cerrar.',
          }),
        );
        servidor.programar(
          'POST',
          '/api/caja/cerrar',
          const RespuestaFalsa(400, {
            'error': 'El monto de cierre declarado no es válido.',
          }),
        );
        final sinCaja = await repo.cerrar(1) as CierreRechazado;
        expect(sinCaja.sinCajaAbierta, isTrue);
        final invalido = await repo.cerrar(1) as CierreRechazado;
        expect(invalido.sinCajaAbierta, isFalse);
        expect(invalido.mensaje, contains('no es válido'));
      },
    );

    test('sin red o 500: ErrorDeApi, y NO se reintenta (el cierre no tiene idempotencia)', () async {
      servidor.programar(
        'POST',
        '/api/caja/cerrar',
        const RespuestaFalsa.falloDeRed(DioExceptionType.receiveTimeout),
      );
      await expectLater(repo.cerrar(1), throwsA(isA<ErrorDeApi>()));
      expect(servidor.veces('POST', '/api/caja/cerrar'), 1);
      servidor.programar(
        'POST',
        '/api/caja/cerrar',
        const RespuestaFalsa(500, {'error': 'Error al cerrar la caja'}),
      );
      await expectLater(repo.cerrar(1), throwsA(isA<ErrorDeApi>()));
      expect(servidor.veces('POST', '/api/caja/cerrar'), 2);
    });
  });
}
