import 'package:dio/dio.dart';

import '../api/errores_de_api.dart';
import 'actualizacion_models.dart';

/// El resultado de pedir la descarga: puede que todavía no haya nada publicado (404), y eso es esperable, no una falla.
sealed class ResultadoDescarga {
  const ResultadoDescarga();
}

class DescargaLista extends ResultadoDescarga {
  const DescargaLista(this.descarga);

  final DescargaApp descarga;
}

class DescargaNoDisponible extends ResultadoDescarga {
  const DescargaNoDisponible();
}

/// Habla con el servidor para saber si hay una versión nueva de la app y de dónde bajarla (contrato `[U1]` y `[U2]`).
/// Como `CajaRepository`: lo esperable se DEVUELVE como valor; solo las fallas de red o del servidor se lanzan.
class ActualizacionRepository {
  ActualizacionRepository(this._dio);

  final Dio _dio;

  /// [U1] `GET /api/app/version` (no pide sesión). `null` si no hay ninguna versión publicada o la respuesta no se entiende.
  Future<VersionPublicada?> consultarVersion() async {
    try {
      final r = await _dio.get<dynamic>('/api/app/version');
      return VersionPublicada.desdeJson(r.data);
    } on DioException catch (e) {
      throw ErrorDeApi(mensajeDeFalla(e));
    }
  }

  /// [U2] `GET /api/app/descarga` (pide sesión: la dirección no es pública). Es de solo lectura, repetirlo es seguro.
  Future<ResultadoDescarga> pedirDescarga() async {
    try {
      final r = await _dio.get<dynamic>('/api/app/descarga');
      final descarga = DescargaApp.desdeJson(r.data);
      if (descarga == null) {
        // Una dirección que no sea https, o sin huella, no se usa nunca: se trata como respuesta inesperada.
        throw const ErrorDeApi(respuestaInesperada);
      }
      return DescargaLista(descarga);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const DescargaNoDisponible();
      throw ErrorDeApi(mensajeDeFalla(e));
    }
  }
}
