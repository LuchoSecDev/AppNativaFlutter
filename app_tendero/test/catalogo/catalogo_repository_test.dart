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
}
