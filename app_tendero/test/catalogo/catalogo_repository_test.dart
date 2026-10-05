import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/api/errores_de_api.dart';
import 'package:stockpilot/catalogo/catalogo_repository.dart';

import '../support/fake_adapter.dart';

void main() {
  late ServidorFalso servidor;
  late CatalogoRepository repo;

  setUp(() {
    servidor = ServidorFalso();
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
    repo = CatalogoRepository(
      crearClienteApi(
        baseUrl: 'https://servidor.test',
        cookieJar: CookieJar(),
        adapter: servidor,
      ),
    );
  });

  test('lee la lista del ejemplo real: precio como TEXTO, stock como número, código de barras opcional', () async {
    servidor.programar(
      'GET',
      '/api/productos',
      RespuestaFalsa.deEjemplo('13_C1_lista_de_productos'),
    );
    final productos = await repo.listar();
    expect(productos, hasLength(2));

    final aceite = productos.firstWhere((p) => p.codigo == 'ACE-001');
    expect(aceite.nombre, 'Aceite Gourmet 1L');
    expect(aceite.precio, '12000.00');
    expect(aceite.precio, isA<String>());
    expect(aceite.cantidad, 5);
    expect(aceite.codigoBarras, isNull); // sin código de barras asociado
    expect(aceite.estaDisponible, isTrue);
    expect(aceite.agotado, isFalse);

    final arroz = productos.firstWhere((p) => p.codigo == 'ARR-001');
    expect(arroz.codigoBarras, '7701234000011');
  });

  test('una lista vacía es válida (tienda sin productos)', () async {
    servidor.programar(
      'GET',
      '/api/productos',
      const RespuestaFalsa(200, <dynamic>[]),
    );
    expect(await repo.listar(), isEmpty);
  });

  test('ignora elementos que no son productos en vez de fallar', () async {
    servidor.programar(
      'GET',
      '/api/productos',
      const RespuestaFalsa(200, ['basura', 3, null]),
    );
    expect(await repo.listar(), isEmpty);
  });

  test('un producto con campos faltantes no rompe la lista (valores por defecto seguros)', () async {
    servidor.programar(
      'GET',
      '/api/productos',
      const RespuestaFalsa(200, [
        {'id_producto': 7, 'nombre_producto': 'Solo nombre'},
      ]),
    );
    final p = (await repo.listar()).single;
    expect(p.id, 7);
    expect(p.nombre, 'Solo nombre');
    expect(p.cantidad, 0);
    expect(p.agotado, isTrue);
    expect(p.precio, '0.00');
  });

  test('un código de barras vacío cuenta como «sin código»', () async {
    servidor.programar(
      'GET',
      '/api/productos',
      const RespuestaFalsa(200, [
        {'id_producto': 1, 'codigo_barras': ''},
      ]),
    );
    expect((await repo.listar()).single.codigoBarras, isNull);
  });

  test('una respuesta que no es una lista lanza ErrorDeApi', () async {
    servidor.programar(
      'GET',
      '/api/productos',
      const RespuestaFalsa(200, {'error': 'x'}),
    );
    await expectLater(repo.listar(), throwsA(isA<ErrorDeApi>()));
  });

  test('sin conexión o con el servidor caído lanza ErrorDeApi con un mensaje para el usuario', () async {
    servidor.programar(
      'GET',
      '/api/productos',
      const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
    );
    await expectLater(
      repo.listar(),
      throwsA(
        isA<ErrorDeApi>().having(
          (e) => e.mensaje,
          'mensaje',
          contains('conexión'),
        ),
      ),
    );
    servidor.programar(
      'GET',
      '/api/productos',
      const RespuestaFalsa(500, {'error': 'x'}),
    );
    await expectLater(repo.listar(), throwsA(isA<ErrorDeApi>()));
  });

  group('buscarPorCodigoBarras', () {
    test('si el producto existe, devuelve el producto parseado', () async {
      servidor.programar(
        'GET',
        '/api/productos/barcode/7701234000011',
        RespuestaFalsa.deEjemplo('11_C2_producto_por_codigo_de_barras'),
      );
      final p = await repo.buscarPorCodigoBarras('7701234000011');
      expect(p, isNotNull);
      expect(p!.id, 1);
      expect(p.nombre, 'Arroz Diana 1Kg');
      expect(p.codigo, 'ARR-001');
    });

    test('si devuelve 404, devuelve null sin lanzar error', () async {
      servidor.programar(
        'GET',
        '/api/productos/barcode/inexistente',
        RespuestaFalsa.deEjemplo('12_C2_codigo_no_encontrado_404'),
      );
      final p = await repo.buscarPorCodigoBarras('inexistente');
      expect(p, isNull);
    });

    test(
      'el código se CODIFICA en la ruta: un QR con «/» o «?» no cambia de ruta',
      () async {
        servidor.programar(
          'GET',
          '/api/productos/barcode/A%2FB%3Fx%23y',
          RespuestaFalsa.deEjemplo('12_C2_codigo_no_encontrado_404'),
        );
        expect(await repo.buscarPorCodigoBarras('A/B?x#y'), isNull);
        expect(
          servidor.peticiones.last.ruta,
          '/api/productos/barcode/A%2FB%3Fx%23y',
        );
      },
    );

    test('una respuesta 200 sin el producto en «data» lanza ErrorDeApi (no un error de tipos)', () async {
      servidor.programar(
        'GET',
        '/api/productos/barcode/777',
        const RespuestaFalsa(200, {
          'success': true,
          'producto': {'id_producto': 1},
        }),
      );
      await expectLater(
        repo.buscarPorCodigoBarras('777'),
        throwsA(isA<ErrorDeApi>()),
      );
      servidor.programar(
        'GET',
        '/api/productos/barcode/778',
        const RespuestaFalsa(200, {
          'success': true,
          'data': 'no es un producto',
        }),
      );
      await expectLater(
        repo.buscarPorCodigoBarras('778'),
        throwsA(isA<ErrorDeApi>()),
      );
    });

    test('falla de red lanza ErrorDeApi', () async {
      servidor.programar(
        'GET',
        '/api/productos/barcode/555',
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      await expectLater(
        repo.buscarPorCodigoBarras('555'),
        throwsA(isA<ErrorDeApi>()),
      );
    });
  });

  group('vincularCodigoBarras', () {
    test('llamada exitosa completa sin lanzar nada', () async {
      servidor.programar(
        'PUT',
        '/api/productos/10/link-barcode',
        RespuestaFalsa.deEjemplo('14_C3_vincular_codigo_de_barras'),
      );
      await repo.vincularCodigoBarras(10, '7709876543210');
      final req = servidor.peticiones.last;
      expect(req.cuerpo, {'codigo_barras': '7709876543210'});
    });

    test(
      'si da 409 (duplicado), lanza ErrorDeApi con el mensaje del servidor',
      () async {
        servidor.programar(
          'PUT',
          '/api/productos/10/link-barcode',
          RespuestaFalsa.deEjemplo('15_C3_codigo_ya_vinculado_409'),
        );
        await expectLater(
          repo.vincularCodigoBarras(10, '12345'),
          throwsA(
            isA<ErrorDeApi>().having(
              (e) => e.mensaje,
              'mensaje',
              contains('ya pertenece'),
            ),
          ),
        );
      },
    );

    test('un 400 (código de más de 50 caracteres) también muestra el motivo del servidor', () async {
      servidor.programar(
        'PUT',
        '/api/productos/10/link-barcode',
        const RespuestaFalsa(400, {
          'success': false,
          'error': 'El código de barras no puede tener más de 50 caracteres',
        }),
      );
      await expectLater(
        repo.vincularCodigoBarras(10, 'x' * 60),
        throwsA(
          isA<ErrorDeApi>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('50 caracteres'),
          ),
        ),
      );
    });

    test('una falla de red lanza ErrorDeApi con el mensaje de conexión, no un texto técnico', () async {
      servidor.programar(
        'PUT',
        '/api/productos/10/link-barcode',
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      await expectLater(
        repo.vincularCodigoBarras(10, '123'),
        throwsA(
          isA<ErrorDeApi>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('conexión'),
          ),
        ),
      );
    });
  });
}
