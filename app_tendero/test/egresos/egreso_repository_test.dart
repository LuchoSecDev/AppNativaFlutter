import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/api/errores_de_api.dart';
import 'package:stockpilot/egresos/egreso_models.dart';
import 'package:stockpilot/egresos/egreso_repository.dart';

import '../support/fake_adapter.dart';

/// `[K4]` `POST /api/caja/egreso` con el cliente HTTP REAL y un servidor falso con los ejemplos reales del backend.
void main() {
  late ServidorFalso servidor;
  late EgresoRepository repo;
  var sesionesCaducadas = 0;

  const clave = '4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22';
  const ruta = '/api/caja/egreso';
  // La misma carga de los ejemplos 24 y 32 del backend.
  const egreso = EgresoPendiente(
    clave: clave,
    montoPesos: 10000,
    motivo: 'Bolsas y hielo',
    categoria: CategoriaEgreso.otro,
  );

  setUp(() {
    sesionesCaducadas = 0;
    servidor = ServidorFalso();
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
    repo = EgresoRepository(
      crearClienteApi(
        baseUrl: 'https://servidor.test',
        cookieJar: CookieJar(),
        adapter: servidor,
        onSessionExpired: () => sesionesCaducadas++,
      ),
    );
  });

  List<PeticionRegistrada> envios() =>
      servidor.peticiones.where((p) => p.clave == 'POST $ruta').toList();

  group('lo que se envía', () {
    test(
      '[24] manda el cuerpo del contrato, el token CSRF y la Idempotency-Key',
      () async {
        servidor.programar(
          'POST',
          ruta,
          RespuestaFalsa.deEjemplo('24_K4_egreso_ok'),
        );
        await repo.registrar(egreso);

        final p = envios().single;
        expect(p.cuerpo, {
          'monto': 10000,
          'motivo': 'Bolsas y hielo',
          'categoria': 'Otro',
        });
        expect(p.headers['Idempotency-Key'], clave);
        expect(p.headers['X-CSRF-Token'], isNotEmpty);
      },
    );
  });

  group('lo que se entiende de la respuesta', () {
    test(
      '[24] 200: registrado, con su id y sin marcar como repetido',
      () async {
        servidor.programar(
          'POST',
          ruta,
          RespuestaFalsa.deEjemplo('24_K4_egreso_ok'),
        );
        final r = await repo.registrar(egreso);
        expect(r, isA<EgresoRegistrado>());
        expect((r as EgresoRegistrado).idEgreso, 1);
        expect(r.repetido, isFalse);
      },
    );

    test('[32] el reintento de un egreso ya registrado: 200 con Idempotent-Replayed, MISMO id', () async {
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('32_K4_reintento_misma_clave_200'),
      );
      final r = await repo.registrar(egreso) as EgresoRegistrado;
      expect(r.idEgreso, 1);
      expect(r.repetido, isTrue);
    });

    test('[33] misma clave con otra carga (422): rechazado, y se sabe que fue por la clave', () async {
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('33_K4_misma_clave_otra_carga_422'),
      );
      final r = await repo.registrar(egreso) as EgresoRechazado;
      expect(r.mensaje, contains('Genera una clave nueva'));
      expect(r.claveReutilizada, isTrue);
    });

    test('[25] sobre el tope (400): rechazado con el mensaje del servidor, sin culpar a la clave', () async {
      servidor.programar(
        'POST',
        ruta,
        RespuestaFalsa.deEjemplo('25_K4_egreso_sobre_el_tope_400'),
      );
      final r = await repo.registrar(egreso) as EgresoRechazado;
      expect(
        r.mensaje,
        contains('no permite registrar gastos mayores a \$150.000'),
      );
      expect(r.claveReutilizada, isFalse);
    });

    // Sin ejemplo real en el backend: los cuerpos salen del contrato [K4], no de una captura.
    for (final caso in {
      'sin caja abierta':
          'No hay ninguna caja abierta. No puedes registrar gastos.',
      'monto no válido': 'El monto debe ser mayor a 0.',
      'motivo corto':
          'Debes proporcionar un motivo válido (mínimo 5 caracteres).',
    }.entries) {
      test(
        '400 ${caso.key} (cuerpo del contrato): rechazado con ese texto',
        () async {
          servidor.programar(
            'POST',
            ruta,
            RespuestaFalsa(400, {'error': caso.value}),
          );
          final r = await repo.registrar(egreso) as EgresoRechazado;
          expect(r.mensaje, caso.value);
        },
      );
    }

    test('un rechazo sin mensaje usa uno entendible, no queda vacío', () async {
      servidor.programar(
        'POST',
        ruta,
        const RespuestaFalsa(400, {'success': false}),
      );
      final r = await repo.registrar(egreso) as EgresoRechazado;
      expect(r.mensaje, 'No se pudo registrar el gasto.');
    });

    test('403 (permiso o CSRF): rechazado, no «sin confirmar»', () async {
      servidor.programar(
        'POST',
        ruta,
        const RespuestaFalsa(403, {'error': 'Sin permiso.'}),
      );
      final r = await repo.registrar(egreso) as EgresoRechazado;
      expect(r.mensaje, 'Sin permiso.');
    });

    test(
      '413 (cuerpo demasiado grande): rechazado, nada se registró',
      () async {
        servidor.programar(
          'POST',
          ruta,
          const RespuestaFalsa(413, {
            'success': false,
            'error': 'La petición es demasiado grande.',
          }),
        );
        expect(await repo.registrar(egreso), isA<EgresoRechazado>());
      },
    );
  });

  group('cuando no se sabe qué pasó (se puede haber registrado)', () {
    test('sin red: «sin confirmar», con reintento automático', () async {
      servidor.programar(
        'POST',
        ruta,
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      final r = await repo.registrar(egreso) as EgresoSinConfirmar;
      expect(r.reintentoAutomatico, isTrue);
      expect(r.sesionCaducada, isFalse);
      expect(r.mensaje, 'No hay conexión con el servidor. Revisa tu internet.');
    });

    test('tiempo agotado: «sin confirmar», con reintento automático', () async {
      servidor.programar(
        'POST',
        ruta,
        const RespuestaFalsa.falloDeRed(DioExceptionType.receiveTimeout),
      );
      final r = await repo.registrar(egreso) as EgresoSinConfirmar;
      expect(r.reintentoAutomatico, isTrue);
    });

    test('500: «sin confirmar», con reintento automático', () async {
      servidor.programar(
        'POST',
        ruta,
        const RespuestaFalsa(500, {'success': false}),
      );
      final r = await repo.registrar(egreso) as EgresoSinConfirmar;
      expect(r.reintentoAutomatico, isTrue);
    });

    test('401 (sesión caducada): «sin confirmar», sin reintento automático y avisando que hay que volver a entrar', () async {
      servidor.programar(
        'POST',
        ruta,
        const RespuestaFalsa(401, {'error': 'No autenticado'}),
      );
      final r = await repo.registrar(egreso) as EgresoSinConfirmar;
      expect(r.sesionCaducada, isTrue);
      expect(r.reintentoAutomatico, isFalse);
      expect(sesionesCaducadas, 1);
    });

    test(
      '429 (demasiadas peticiones): «sin confirmar», lo decide la persona',
      () async {
        servidor.programar(
          'POST',
          ruta,
          const RespuestaFalsa(429, {'error': 'Demasiadas peticiones.'}),
        );
        final r = await repo.registrar(egreso) as EgresoSinConfirmar;
        expect(r.reintentoAutomatico, isFalse);
        expect(r.mensaje, 'Demasiadas peticiones.');
      },
    );

    for (final rara in <Object?>[
      {'success': true}, // sin id
      {'success': true, 'id_egreso': 'siete'},
      {'success': false, 'id_egreso': 7},
      'texto',
      null,
    ]) {
      test(
        'un 200 con forma rara ($rara) NO se da por registrado: «sin confirmar» y sin reintento solo',
        () async {
          servidor.programar('POST', ruta, RespuestaFalsa(200, rara));
          final r = await repo.registrar(egreso) as EgresoSinConfirmar;
          expect(r.mensaje, respuestaInesperada);
          expect(r.reintentoAutomatico, isFalse);
        },
      );
    }
  });

  test('el repositorio no lanza excepciones por fallas de red: todo desenlace es un valor', () async {
    servidor.programar(
      'POST',
      ruta,
      const RespuestaFalsa.falloDeRed(DioExceptionType.connectionTimeout),
    );
    await expectLater(
      repo.registrar(egreso),
      completion(isA<ResultadoEgreso>()),
    );
  });
}
