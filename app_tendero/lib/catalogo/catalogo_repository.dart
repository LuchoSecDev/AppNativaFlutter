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
}
