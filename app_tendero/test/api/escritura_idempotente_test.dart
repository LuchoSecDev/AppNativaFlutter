import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/escritura_idempotente.dart';

/// Lo que comparten la venta `[V2]` y el egreso `[K4]` al fallar una escritura con `Idempotency-Key`: ¿se pudo haber
/// registrado (hay que reintentar con la MISMA clave) o el servidor la rechazó antes de registrar nada?
void main() {
  const rutaPrueba = '/api/x';
  const sesionCaducada = 'La sesión caducó (texto de cada llamador).';

  DioException conEstado(int estado, [Object? cuerpo]) => DioException(
    requestOptions: RequestOptions(path: rutaPrueba),
    response: Response<dynamic>(
      requestOptions: RequestOptions(path: rutaPrueba),
      statusCode: estado,
      data: cuerpo,
    ),
    type: DioExceptionType.badResponse,
  );

  FalloDeEscritura clasificar(DioException e) =>
      clasificarFalloDeEscritura(e, mensajeSesionCaducada: sesionCaducada);

  group('no se sabe si se registró (se reintenta con la misma clave)', () {
    test('sin respuesta: se reintenta sola', () {
      final f = clasificar(
        DioException(
          requestOptions: RequestOptions(path: rutaPrueba),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(f, isA<FalloSinConfirmar>());
      final s = f as FalloSinConfirmar;
      expect(s.reintentoAutomatico, isTrue);
      expect(s.sesionCaducada, isFalse);
      expect(s.mensaje, 'No hay conexión con el servidor. Revisa tu internet.');
    });

    test('tiempo agotado: se reintenta sola', () {
      final s = clasificar(
        DioException(
          requestOptions: RequestOptions(path: rutaPrueba),
          type: DioExceptionType.receiveTimeout,
        ),
      ) as FalloSinConfirmar;
      expect(s.reintentoAutomatico, isTrue);
    });

    test('500: se reintenta sola', () {
      final s = clasificar(conEstado(500, {'error': 'x'})) as FalloSinConfirmar;
      expect(s.reintentoAutomatico, isTrue);
      expect(
        s.mensaje,
        'El servidor tuvo un problema. Inténtalo de nuevo en un momento.',
      );
    });

    test('401: sesión caducada, NO se reintenta sola', () {
      final s = clasificar(conEstado(401)) as FalloSinConfirmar;
      expect(s.sesionCaducada, isTrue);
      expect(s.reintentoAutomatico, isFalse);
      expect(s.mensaje, sesionCaducada);
    });

    test('429: usa el mensaje del servidor y NO se reintenta sola', () {
      final s =
          clasificar(conEstado(429, {'error': 'Calma.'})) as FalloSinConfirmar;
      expect(s.mensaje, 'Calma.');
      expect(s.reintentoAutomatico, isFalse);
      expect(s.sesionCaducada, isFalse);
    });

    test('429 sin mensaje del servidor: texto estándar', () {
      final s = clasificar(conEstado(429)) as FalloSinConfirmar;
      expect(
        s.mensaje,
        'Demasiadas peticiones. Espera un momento y reintenta.',
      );
    });
  });

  group('el servidor rechazó antes de registrar nada', () {
    test('400 con mensaje: lo conserva junto con el estado y el cuerpo', () {
      final cuerpo = {'success': false, 'error': 'Monto inválido', 'code': 'X'};
      final r = clasificar(conEstado(400, cuerpo)) as FalloRechazado;
      expect(r.estado, 400);
      expect(r.mensaje, 'Monto inválido');
      expect(r.datos, cuerpo);
    });

    test('403, 404, 413 y 422 también son rechazos', () {
      for (final estado in [403, 404, 413, 422]) {
        expect(clasificar(conEstado(estado)), isA<FalloRechazado>());
      }
    });

    test(
      'sin mensaje del servidor el mensaje es null (lo pone el llamador)',
      () {
        final r = clasificar(conEstado(400)) as FalloRechazado;
        expect(r.mensaje, isNull);
      },
    );
  });

  group('leerRegistro (un 200 que sí registró)', () {
    Response<dynamic> ok(Object? cuerpo, {Map<String, List<String>>? h}) =>
        Response<dynamic>(
          requestOptions: RequestOptions(path: rutaPrueba),
          statusCode: 200,
          data: cuerpo,
          headers: Headers.fromMap(h ?? {}),
        );

    test('trae el id y no es repetida', () {
      final r = leerRegistro(ok({'success': true, 'id_venta': 7}), 'id_venta');
      expect(r?.id, 7);
      expect(r?.repetida, isFalse);
    });

    test('con Idempotent-Replayed: true es repetida', () {
      final r = leerRegistro(
        ok(
          {'success': true, 'id_egreso': 9},
          h: {
            'idempotent-replayed': ['true'],
          },
        ),
        'id_egreso',
      );
      expect(r?.id, 9);
      expect(r?.repetida, isTrue);
    });

    test('formas raras NO se dan por registradas', () {
      for (final raro in <Object?>[
        null,
        'ok',
        {'success': false, 'id_venta': 7},
        {'success': true},
        {'success': true, 'id_venta': '7'},
        {'success': true, 'id_otro': 7},
      ]) {
        expect(leerRegistro(ok(raro), 'id_venta'), isNull, reason: '$raro');
      }
    });
  });
}
