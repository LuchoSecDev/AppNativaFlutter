// Datos y resultados de la caja, tal como los entrega la API (contrato: [K1] y [K2]).

/// Una sesión de caja abierta (`session` de `GET /api/caja/sesion`).
class SesionCaja {
  const SesionCaja({
    required this.idSesion,
    required this.montoApertura,
    required this.fechaApertura,
  });

  final int idSesion;

  /// Efectivo con el que se abrió. Llega como TEXTO con dos decimales (`"50000.00"`): para mostrarlo se usa
  /// `formatoPesos`, y para hacer cuentas, un tipo decimal; nunca se suma texto.
  final String montoApertura;

  /// Fecha ISO 8601 en UTC, tal como la manda el servidor.
  final String fechaApertura;

  factory SesionCaja.desdeJson(Map<String, dynamic> json) => SesionCaja(
    idSesion: (json['id_sesion'] as num?)?.toInt() ?? 0,
    montoApertura: json['monto_apertura']?.toString() ?? '0.00',
    fechaApertura: json['fecha_apertura'] as String? ?? '',
  );
}

/// Resultado de `POST /api/caja/abrir`.
sealed class ResultadoAbrirCaja {
  const ResultadoAbrirCaja();
}

final class CajaAbierta extends ResultadoAbrirCaja {
  const CajaAbierta();
}

/// El servidor no la abrió y dijo por qué (monto inválido, o ya había una caja abierta).
final class CajaRechazada extends ResultadoAbrirCaja {
  const CajaRechazada(this.mensaje, {this.yaEstabaAbierta = false});

  final String mensaje;

  /// `true` si el motivo es que esta cuenta ya tenía una caja abierta (por ejemplo, abierta desde la web).
  final bool yaEstabaAbierta;
}
