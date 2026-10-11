import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/api/errores_de_api.dart';
import 'package:stockpilot/clientes/clientes_repository.dart';

import '../support/fake_adapter.dart';

/// `[V1]` `GET /api/clientes` con el cliente HTTP REAL y un servidor falso con el ejemplo real del backend.
void main() {
  late ServidorFalso servidor;
  late ClientesRepository repositorio;

  setUp(() {
    servidor = ServidorFalso();
    repositorio = ClientesRepository(
      crearClienteApi(
        baseUrl: 'https://servidor.test',
        cookieJar: CookieJar(),
        adapter: servidor,
      ),
    );
  });

  Future<Object?> fallo() async {
    try {
      await repositorio.obtenerClientes();
    } on ErrorDeApi catch (e) {
      return e.mensaje;
    }
    return null;
  }

  test(
    '200: devuelve los clientes del ejemplo real, con el dinero en centavos',
    () async {
      servidor.programar(
        'GET',
        '/api/clientes',
        RespuestaFalsa.deEjemplo('16_V1_clientes'),
      );
      final clientes = await repositorio.obtenerClientes();
      expect(clientes, hasLength(1));
      expect(clientes.single.nombre, 'Doña Rosa');
      expect(clientes.single.limiteCreditoCentavos, 500000);
      expect(clientes.single.saldoPendienteCentavos, 0);
    },
  );

  test('una tienda sin clientes devuelve una lista vacía', () async {
    servidor.programar(
      'GET',
      '/api/clientes',
      const RespuestaFalsa(200, {'success': true, 'clientes': []}),
    );
    expect(await repositorio.obtenerClientes(), isEmpty);
  });

  test('sin red: un error entendible, no una excepción cruda', () async {
    servidor.programar(
      'GET',
      '/api/clientes',
      const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
    );
    expect(
      await fallo(),
      'No hay conexión con el servidor. Revisa tu internet.',
    );
  });

  test('500: un error entendible', () async {
    servidor.programar(
      'GET',
      '/api/clientes',
      const RespuestaFalsa(500, {'success': false}),
    );
    expect(
      await fallo(),
      'El servidor tuvo un problema. Inténtalo de nuevo en un momento.',
    );
  });

  test('un 4xx con mensaje del servidor lo muestra tal cual', () async {
    servidor.programar(
      'GET',
      '/api/clientes',
      const RespuestaFalsa(403, {
        'success': false,
        'error': 'No tienes permiso.',
      }),
    );
    expect(await fallo(), 'No tienes permiso.');
  });

  test(
    'una respuesta con forma rara es «inesperada», no una lista a medias',
    () async {
      for (final rara in <Object?>[
        {'success': true},
        {'success': true, 'clientes': 'x'},
        {'success': false, 'clientes': []},
        {
          'success': true,
          'clientes': [
            // Un cupo ilegible: con el resto de la lista, dejaría fiar sin tope por error.
            {
              'id_cliente': 1,
              'nombre': 'Ana',
              'limite_credito': 'abc',
              'saldo_pendiente': 0,
            },
          ],
        },
      ]) {
        servidor = ServidorFalso();
        repositorio = ClientesRepository(
          crearClienteApi(
            baseUrl: 'https://servidor.test',
            cookieJar: CookieJar(),
            adapter: servidor,
          ),
        );
        servidor.programar('GET', '/api/clientes', RespuestaFalsa(200, rara));
        expect(await fallo(), respuestaInesperada, reason: '$rara');
      }
    },
  );
}
