import 'package:dio/dio.dart';

import '../api/errores_de_api.dart';
import 'producto.dart';

/// Habla con el servidor para el catálogo de la tienda. Igual que los demás repositorios: solo las fallas de red o del
/// servidor se lanzan, como [ErrorDeApi].
class CatalogoRepository {
  CatalogoRepository(this._dio);

  final Dio _dio;

  /// [C1] `GET /api/productos`. Devuelve TODOS los productos de la tienda de la sesión (la API no pagina).
  Future<List<Producto>> listar() async {
    try {
      final r = await _dio.get<dynamic>('/api/productos');
      final datos = r.data;
      if (datos is! List) {
        throw const ErrorDeApi(respuestaInesperada);
      }
      return [
        for (final item in datos)
          if (item is Map<String, dynamic>) Producto.desdeJson(item),
      ];
    } on DioException catch (e) {
      throw ErrorDeApi(mensajeDeFalla(e));
    }
  }

  /// `GET /api/productos/barcode/:code`. Busca un producto por código o código de barras.
  /// Si existe devuelve el producto, si es 404 devuelve `null`.
  Future<Producto?> buscarPorCodigoBarras(String code) async {
    try {
      final r = await _dio.get<dynamic>('/api/productos/barcode/$code');
      final datos = r.data;
      if (datos is! Map<String, dynamic> || !datos.containsKey('producto')) {
        throw const ErrorDeApi(respuestaInesperada);
      }
      return Producto.desdeJson(datos['producto'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ErrorDeApi(mensajeDeFalla(e));
    }
  }

  /// `PUT /api/productos/:id/link-barcode`. Vincula un código de barras nuevo a un producto existente.
  Future<void> vincularCodigoBarras(int productoId, String codigoBarras) async {
    try {
      await _dio.put<dynamic>(
        '/api/productos/$productoId/link-barcode',
        data: {'codigo_barras': codigoBarras},
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw ErrorDeApi(mensajeDelServidor(e.response?.data) ?? mensajeDeFalla(e));
      }
      throw ErrorDeApi(mensajeDeFalla(e));
    }
  }
}
