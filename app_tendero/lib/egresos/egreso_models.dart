import '../api/clave_de_idempotencia.dart';

/// En qué se gastó. Son las mismas seis que ofrece la web (`ExpenseModal.jsx`), con la escritura exacta que se envía:
/// el servidor no las valida contra una lista (guarda el texto que llegue), así que la app solo ofrece estas.
enum CategoriaEgreso {
  proveedorMenor('Proveedor menor'),
  insumosYBolsas('Insumos / Bolsas'),
  transporte('Transporte'),
  limpieza('Limpieza'),
  servicios('Servicios'),
  otro('Otro');

  const CategoriaEgreso(this.valorApi);

  final String valorApi;

  /// `null` si [valor] no es exactamente una de las seis: no se adivina una categoría.
  static CategoriaEgreso? desdeApi(Object? valor) {
    for (final c in values) {
      if (c.valorApi == valor) return c;
    }
    return null;
  }
}

/// Un gasto de caja chica tal como se envía a `[K4]`, con la clave de idempotencia que lo identifica.
///
/// La [clave] se genera UNA vez, cuando la persona confirma el gasto, y es la misma en todos los reintentos de ese gasto:
/// así el servidor puede reconocer que es el mismo y no registrarlo dos veces. Se guarda en el celular hasta saber cómo
/// terminó, igual que la venta pendiente.
class EgresoPendiente {
  const EgresoPendiente({
    required this.clave,
    required this.montoPesos,
    required this.motivo,
    required this.categoria,
  });

  /// De 8 a 100 caracteres: letras, números, guion o guion bajo (ver [esClaveDeIdempotenciaValida]).
  final String clave;

  /// En PESOS enteros: es lo que espera `[K4]` (a diferencia del resto de la app, que guarda centavos). Mayor que 0.
  final int montoPesos;

  final String motivo;
  final CategoriaEgreso categoria;

  /// El cuerpo de `[K4]`. Sin `foto_soporte`: el egreso va sin foto (decisión D1 del plan de T1).
  Map<String, dynamic> cuerpoDeLaPeticion() => {
    'monto': montoPesos,
    'motivo': motivo,
    'categoria': categoria.valorApi,
  };

  Map<String, dynamic> aJson() => {
    'clave': clave,
    'monto_pesos': montoPesos,
    'motivo': motivo,
    'categoria': categoria.valorApi,
  };

  /// `null` si lo guardado no tiene la forma esperada (dañado o de otra versión): no se inventa un egreso, porque
  /// reenviarlo registraría dinero que la persona no confirmó.
  static EgresoPendiente? desdeJson(Object? json) {
    if (json is! Map) return null;
    final clave = json['clave'];
    final monto = json['monto_pesos'];
    final motivo = json['motivo'];
    final categoria = CategoriaEgreso.desdeApi(json['categoria']);
    if (clave is! String ||
        !esClaveDeIdempotenciaValida(clave) ||
        monto is! int ||
        monto <= 0 ||
        motivo is! String ||
        categoria == null) {
      return null;
    }
    return EgresoPendiente(
      clave: clave,
      montoPesos: monto,
      motivo: motivo,
      categoria: categoria,
    );
  }
}

/// Cómo terminó un intento de registrar un egreso. Los desenlaces posibles son valores, no excepciones: al registrar
/// dinero, la diferencia entre «no se hizo» y «no sé si se hizo» decide si se puede reintentar sin duplicar.
sealed class ResultadoEgreso {
  const ResultadoEgreso();
}

class EgresoRegistrado extends ResultadoEgreso {
  const EgresoRegistrado(this.idEgreso, {this.repetido = false});

  final int idEgreso;

  /// `true` si el servidor devolvió un egreso que YA estaba registrado (cabecera `Idempotent-Replayed`): un reintento
  /// que no duplicó nada.
  final bool repetido;
}

class EgresoRechazado extends ResultadoEgreso {
  const EgresoRechazado(this.mensaje, {this.claveReutilizada = false});

  /// El motivo, tal como lo dijo el servidor.
  final String mensaje;

  /// `true` si el servidor dijo que esa clave ya se usó con OTRO egreso (422). Es un error de la app, no de la
  /// persona: hay que descartar el pendiente y empezar con una clave nueva.
  final bool claveReutilizada;
}

class EgresoSinConfirmar extends ResultadoEgreso {
  const EgresoSinConfirmar(
    this.mensaje, {
    this.reintentoAutomatico = true,
    this.sesionCaducada = false,
  });

  final String mensaje;

  /// `true` si conviene reintentar solo, con una pausa (sin red, tiempo agotado, 5xx). `false` si reintentar ya no
  /// serviría (sesión caducada, límite de uso, respuesta rara): lo decide la persona.
  final bool reintentoAutomatico;

  /// `true` si el servidor dijo que ya no hay sesión (401): hay que volver a entrar antes de reintentar.
  final bool sesionCaducada;
}
