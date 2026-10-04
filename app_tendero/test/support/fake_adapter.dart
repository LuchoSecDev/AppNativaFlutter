import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Una respuesta que el servidor falso devolverá.
class RespuestaFalsa {
  const RespuestaFalsa(this.estado, this.cuerpo, {this.headers = const {}}) : errorDeRed = null;

  /// Simula que NO se pudo llegar al servidor (sin internet, tiempo agotado...).
  const RespuestaFalsa.falloDeRed(DioExceptionType tipo)
      : estado = 0,
        cuerpo = null,
        headers = const {},
        errorDeRed = tipo;

  final int estado;
  final Object? cuerpo;
  final Map<String, List<String>> headers;
  final DioExceptionType? errorDeRed;

  /// Carga una respuesta desde un ejemplo REAL del backend (carpeta `test/fixtures/api`). Esos archivos son
  /// copias de `docs/ejemplos_app_tendero/` del repositorio del backend: si la API cambia, hay que volver a
  /// copiarlos. Se usa el estado y el cuerpo; las cabeceras del ejemplo son marcadores, no valores reales.
  factory RespuestaFalsa.deEjemplo(String nombre) {
    final texto = File('test/fixtures/api/$nombre.json').readAsStringSync();
    final respuesta = (jsonDecode(texto) as Map<String, dynamic>)['respuesta'] as Map<String, dynamic>;
    return RespuestaFalsa(respuesta['estado'] as int, respuesta['body']);
  }
}

/// Lo que se pidió, ya copiado (Dio reutiliza el objeto de la petición al reintentar, y aquí se quiere ver
/// cada intento tal como salió).
class PeticionRegistrada {
  PeticionRegistrada(this.metodo, this.ruta, this.headers, this.cuerpo);

  final String metodo;
  final String ruta;
  final Map<String, dynamic> headers;

  /// El cuerpo JSON que se envió (null si no llevaba).
  final dynamic cuerpo;

  String get clave => '$metodo $ruta';
}

/// Sustituye la red por respuestas programadas, para probar sin servidor, sin internet y sin celular.
///
/// Se programa una cola de respuestas por cada «MÉTODO ruta». Cada petición gasta la siguiente respuesta; cuando
/// ya no quedan por gastar, se repite la última. Se pueden seguir agregando respuestas a una ruta ya usada: se
/// gastarán a continuación.
class ServidorFalso implements HttpClientAdapter {
  final List<PeticionRegistrada> peticiones = [];
  final Map<String, List<RespuestaFalsa>> _colas = {};
  final Map<String, int> _gastadas = {};

  void programar(String metodo, String ruta, RespuestaFalsa respuesta) {
    _colas.putIfAbsent('$metodo $ruta', () => []).add(respuesta);
  }

  /// Cuántas veces se pidió «MÉTODO ruta».
  int veces(String metodo, String ruta) => peticiones.where((p) => p.clave == '$metodo $ruta').length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final registro = PeticionRegistrada(options.method, options.uri.path, Map<String, dynamic>.of(options.headers), options.data);
    peticiones.add(registro);

    final cola = _colas[registro.clave];
    if (cola == null || cola.isEmpty) {
      throw StateError('El servidor falso no tiene respuesta programada para ${registro.clave}');
    }
    final gastadas = _gastadas[registro.clave] ?? 0;
    final respuesta = cola[gastadas < cola.length ? gastadas : cola.length - 1];
    _gastadas[registro.clave] = gastadas + 1;
    if (respuesta.errorDeRed != null) {
      throw DioException(requestOptions: options, type: respuesta.errorDeRed!, message: 'falla de red simulada');
    }
    return ResponseBody.fromString(
      jsonEncode(respuesta.cuerpo),
      respuesta.estado,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...respuesta.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
