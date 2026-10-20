import 'package:dio/dio.dart';

import 'errores_de_api.dart';

/// Cómo terminó una escritura con `Idempotency-Key` que NO salió bien, según lo único que importa: ¿pudo haberse
/// registrado? Lo comparten la venta `[V2]` y el egreso `[K4]` (y mañana la entrada `[M1]`); cada repositorio lo traduce
/// a su propio resultado.
sealed class FalloDeEscritura {
  const FalloDeEscritura();
}

/// No se sabe si el servidor la registró (sin respuesta, 5xx, 429, 401): se reintenta con la MISMA clave.
class FalloSinConfirmar extends FalloDeEscritura {
  const FalloSinConfirmar(
    this.mensaje, {
    this.reintentoAutomatico = true,
    this.sesionCaducada = false,
  });

  final String mensaje;

  /// `false` si reintentar al instante no tiene sentido (sesión caducada, demasiadas peticiones): decide la persona.
  final bool reintentoAutomatico;

  final bool sesionCaducada;
}

/// El servidor la rechazó ANTES de registrar nada (400, 403, 404, 413, 422...). No hay nada que reintentar.
class FalloRechazado extends FalloDeEscritura {
  const FalloRechazado(this.estado, this.mensaje, this.datos);

  final int estado;

  /// El texto del servidor (`error` o `message`), o `null`: entonces lo pone quien llama.
  final String? mensaje;

  /// El cuerpo de la respuesta, por si quien llama necesita su `code`.
  final Object? datos;
}

/// Clasifica el error de una escritura con `Idempotency-Key`. [mensajeSesionCaducada] es el texto del 401, que cambia
/// según qué se estaba registrando («la venta…», «el gasto…»).
FalloDeEscritura clasificarFalloDeEscritura(
  DioException e, {
  required String mensajeSesionCaducada,
}) {
  final estado = e.response?.statusCode;
  if (estado == null) {
    // Sin respuesta: tiempo agotado, sin red... El servidor pudo haberla registrado.
    return FalloSinConfirmar(mensajeDeFalla(e));
  }
  final datos = e.response?.data;
  final mensaje = mensajeDelServidor(datos);
  if (estado == 401) {
    return FalloSinConfirmar(
      mensajeSesionCaducada,
      reintentoAutomatico: false,
      sesionCaducada: true,
    );
  }
  if (estado == 429) {
    return FalloSinConfirmar(
      mensaje ?? 'Demasiadas peticiones. Espera un momento y reintenta.',
      reintentoAutomatico: false,
    );
  }
  if (estado >= 500) {
    return FalloSinConfirmar(mensajeDeFalla(e));
  }
  return FalloRechazado(estado, mensaje, datos);
}

/// Un 200 que sí registró: el id que devolvió el servidor en [campoId] y si es una respuesta repetida
/// (`Idempotent-Replayed: true`, un reintento que no duplicó nada). `null` si la respuesta no tiene la forma
/// esperada: nunca se da por registrado algo que no se pudo leer.
({int id, bool repetida})? leerRegistro(Response<dynamic> r, String campoId) {
  final cuerpo = r.data;
  if (cuerpo is Map<String, dynamic> &&
      cuerpo['success'] == true &&
      cuerpo[campoId] is int) {
    return (
      id: cuerpo[campoId] as int,
      repetida: r.headers.value('idempotent-replayed') == 'true',
    );
  }
  return null;
}
