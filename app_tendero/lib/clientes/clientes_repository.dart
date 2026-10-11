import 'package:dio/dio.dart';

import '../api/errores_de_api.dart';
import 'cliente.dart';

class ClientesRepository {
  const ClientesRepository(this._dio);

  final Dio _dio;

  /// `[V1]` `GET /api/clientes`: los clientes de la tienda, para elegir a quién se le fía. Solo lectura: el Tendero
  /// no puede crear clientes ni registrar abonos (403, decisión D4).
  ///
  /// Si algún cliente no tiene la forma esperada se falla de forma entendible, en vez de mostrar una lista a medias:
  /// con un cupo mal leído se podría fiar de más.
  Future<List<Cliente>> obtenerClientes() async {
    try {
      final respuesta = await _dio.get<Map<String, dynamic>>('/api/clientes');
      final datos = respuesta.data;
      final crudos = datos?['clientes'];
      if (datos == null || datos['success'] != true || crudos is! List) {
        throw const ErrorDeApi(respuestaInesperada);
      }
      final clientes = <Cliente>[];
      for (final crudo in crudos) {
        final cliente = Cliente.desdeJson(crudo);
        if (cliente == null) throw const ErrorDeApi(respuestaInesperada);
        clientes.add(cliente);
      }
      return clientes;
    } on DioException catch (e) {
      throw ErrorDeApi(
        mensajeDelServidor(e.response?.data) ?? mensajeDeFalla(e),
      );
    }
  }
}
