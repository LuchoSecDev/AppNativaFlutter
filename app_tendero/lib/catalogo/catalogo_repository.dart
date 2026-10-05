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

  /// [C2] `GET /api/productos/barcode/:code`. Busca por código de barras Y por código interno (SKU). Devuelve el
  /// producto, o `null` si el servidor responde 404 (no existe, o es de otra tienda). La respuesta trae el producto en
  /// `data` (contrato, ejemplo 11).
  Future<Producto?> buscarPorCodigoBarras(String code) async {
    try {
      // El código sale de una etiqueta y puede traer `/`, `?` o `#` (un QR, un Code 128): sin codificarlo iría a otra
      // ruta del servidor.
      final r = await _dio.get<dynamic>(
        '/api/productos/barcode/${Uri.encodeComponent(code)}',
      );
      final datos = r.data;
      final producto = datos is Map<String, dynamic> ? datos['data'] : null;
      if (producto is! Map<String, dynamic>) {
        throw const ErrorDeApi(respuestaInesperada);
      }
      return Producto.desdeJson(producto);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      throw ErrorDeApi(mensajeDeFalla(e));
    }
  }

  /// [C3] `PUT /api/productos/:id/link-barcode`. Vincula un código de barras a un producto de la tienda.
  ///
  /// Los rechazos con motivo del servidor (400 código vacío o de más de 50 caracteres, 404 producto inexistente,
  /// 409 «Ese código ya pertenece a «Arroz».») se lanzan como [ErrorDeApi] con ese mismo texto.
  Future<void> vincularCodigoBarras(int productoId, String codigoBarras) async {
    try {
      await _dio.put<dynamic>(
        '/api/productos/$productoId/link-barcode',
        data: {'codigo_barras': codigoBarras},
      );
    } on DioException catch (e) {
      final estado = e.response?.statusCode;
      final conMotivo = estado == 400 || estado == 404 || estado == 409;
      throw ErrorDeApi(
        (conMotivo ? mensajeDelServidor(e.response?.data) : null) ??
            mensajeDeFalla(e),
      );
    }
  }
}
