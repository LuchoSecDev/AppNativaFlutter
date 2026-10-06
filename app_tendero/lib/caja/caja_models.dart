import '../ui/dinero.dart';
import '../ui/formato.dart';

// Datos y resultados de la caja, tal como los entrega la API (contrato: [K1], [K2], [K3] y [K5]).

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

/// Cómo quedó lo contado frente a lo que debería haber.
enum TipoDiferencia { cuadra, sobra, falta }

/// El arqueo del cierre de caja ([K5] la vista previa y [K3] el cierre real): de dónde sale lo que DEBERÍA haber en
/// el cajón y cuánto difiere de lo que el Tendero contó.
///
/// La API manda números (`50000`, `4500.5`); aquí todo se guarda en CENTAVOS enteros para no arrastrar errores de
/// decimales al sumar o comparar dinero.
class ArqueoCaja {
  const ArqueoCaja({
    required this.aperturaCentavos,
    required this.ventasEfectivoCentavos,
    required this.abonosEfectivoCentavos,
    required this.egresosCentavos,
    required this.esperadoCentavos,
    required this.declaradoCentavos,
    required this.diferenciaCentavos,
  });

  final int aperturaCentavos;

  /// Solo las ventas en EFECTIVO: las de tarjeta, transferencia y fiado no entran al cajón.
  final int ventasEfectivoCentavos;
  final int abonosEfectivoCentavos;

  /// Los egresos no rechazados (también los que aún esperan la aprobación del Administrador).
  final int egresosCentavos;

  /// Lo que debería haber: apertura + ventas en efectivo + abonos en efectivo − egresos.
  final int esperadoCentavos;

  /// Lo que el Tendero contó.
  final int declaradoCentavos;

  /// Declarado − esperado: positivo sobra, negativo falta.
  final int diferenciaCentavos;

  static int? _centavos(Object? valor) =>
      valor is num && valor.isFinite ? (valor * 100).round() : null;

  /// `null` si falta algún dato o no es un número: no se inventa un arqueo.
  static ArqueoCaja? desdeJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final apertura = _centavos(json['monto_apertura']);
    final ventas = _centavos(json['ventas_efectivo']);
    final abonos = _centavos(json['abonos_efectivo']);
    final egresos = _centavos(json['egresos']);
    final esperado = _centavos(json['monto_cierre_calculado']);
    final declarado = _centavos(json['monto_cierre_declarado']);
    final diferencia = _centavos(json['diferencia']);
    if (apertura == null ||
        ventas == null ||
        abonos == null ||
        egresos == null ||
        esperado == null ||
        declarado == null ||
        diferencia == null) {
      return null;
    }
    return ArqueoCaja(
      aperturaCentavos: apertura,
      ventasEfectivoCentavos: ventas,
      abonosEfectivoCentavos: abonos,
      egresosCentavos: egresos,
      esperadoCentavos: esperado,
      declaradoCentavos: declarado,
      diferenciaCentavos: diferencia,
    );
  }

  TipoDiferencia get tipo => diferenciaCentavos == 0
      ? TipoDiferencia.cuadra
      : diferenciaCentavos > 0
      ? TipoDiferencia.sobra
      : TipoDiferencia.falta;

  String get tituloDeLaDiferencia => switch (tipo) {
    TipoDiferencia.cuadra => 'Cuadra',
    TipoDiferencia.sobra => 'Sobra',
    TipoDiferencia.falta => 'Falta',
  };

  String get detalleDeLaDiferencia {
    final monto = formatoPesos(importeDeCentavos(diferenciaCentavos.abs()));
    return switch (tipo) {
      TipoDiferencia.cuadra =>
        'Lo que contaste coincide con lo que debería haber.',
      TipoDiferencia.sobra => 'Hay $monto de más en el cajón.',
      TipoDiferencia.falta => 'Faltan $monto en el cajón.',
    };
  }

  /// `true` si son las mismas cifras (lo que debería haber, lo contado y la diferencia). Se usa para saber si, entre
  /// la vista previa y el cierre real, se registró algo (una venta, un egreso) y las cifras cambiaron.
  bool mismasCifrasQue(ArqueoCaja otro) =>
      esperadoCentavos == otro.esperadoCentavos &&
      diferenciaCentavos == otro.diferenciaCentavos &&
      declaradoCentavos == otro.declaradoCentavos;
}

/// Resultado de `POST /api/caja/arqueo-previo` ([K5]): el arqueo SIN cerrar la caja.
sealed class ResultadoArqueo {
  const ResultadoArqueo();
}

final class ArqueoCalculado extends ResultadoArqueo {
  const ArqueoCalculado(this.arqueo);

  final ArqueoCaja arqueo;
}

/// El servidor no calculó el arqueo y dijo por qué (monto inválido, o no hay caja abierta).
final class ArqueoRechazado extends ResultadoArqueo {
  const ArqueoRechazado(this.mensaje, {this.sinCajaAbierta = false});

  final String mensaje;
  final bool sinCajaAbierta;
}

/// Resultado de `POST /api/caja/cerrar` ([K3]).
sealed class ResultadoCierre {
  const ResultadoCierre();
}

/// La caja quedó cerrada. [arqueo] es el arqueo FINAL del servidor (`null` si la respuesta no lo trajo).
final class CierreExitoso extends ResultadoCierre {
  const CierreExitoso(this.arqueo);

  final ArqueoCaja? arqueo;
}

/// El servidor no cerró la caja y dijo por qué: la caja sigue como estaba.
final class CierreRechazado extends ResultadoCierre {
  const CierreRechazado(this.mensaje, {this.sinCajaAbierta = false});

  final String mensaje;
  final bool sinCajaAbierta;
}
