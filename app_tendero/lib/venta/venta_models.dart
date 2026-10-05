/// Cómo paga el cliente. El texto de [valorApi] es el que el servidor exige, con esa escritura exacta (contrato [V2]):
/// cualquier otro valor (`"efectivo"`, `"Débito"`...) da 400 y no se registra nada.
enum MetodoPago {
  efectivo('Efectivo'),
  tarjeta('Tarjeta'),
  transferencia('Transferencia'),
  fiado('Fiado');

  const MetodoPago(this.valorApi);

  final String valorApi;

  static MetodoPago? desdeApi(Object? valor) {
    for (final m in values) {
      if (m.valorApi == valor) {
        return m;
      }
    }
    return null;
  }
}

/// Un producto de la venta tal como se envía al servidor: solo cuál y cuántas unidades. El precio NO se envía: lo
/// decide el servidor con el precio vigente en su base de datos.
class ItemVenta {
  const ItemVenta({required this.idProducto, required this.cantidad});

  final int idProducto;
  final int cantidad;

  Map<String, dynamic> aJson() => {
    'id_producto': idProducto,
    'cantidad': cantidad,
  };
}

/// Una venta que la app ya decidió cobrar y cuyo resultado todavía no conoce con certeza.
///
/// Lleva la [clave] de idempotencia: un UUID nuevo por venta, que se manda en TODOS los reintentos de esa venta. Con
/// la misma clave y la misma carga el servidor devuelve la misma venta en vez de registrar otra, y por eso el cuerpo
/// que se envía sale SIEMPRE de este objeto: nunca se vuelve a armar desde el carrito, que pudo cambiar.
///
/// Se guarda en el celular antes de enviarla: si la app se cierra o la sesión caduca justo al cobrar, al volver se
/// reintenta con la misma clave y no se cobra dos veces.
class VentaPendiente {
  const VentaPendiente({
    required this.clave,
    required this.items,
    required this.metodoPago,
    required this.totalCentavos,
    this.efectivoRecibido,
  });

  /// 8 a 100 caracteres: letras, números, guion o guion bajo (contrato [V2]).
  static final RegExp _formatoDeClave = RegExp(r'^[A-Za-z0-9_-]{8,100}$');

  final String clave;
  final List<ItemVenta> items;
  final MetodoPago metodoPago;

  /// El total que la app le mostró al Tendero al cobrar, en centavos. Es solo para mostrarlo: el servidor calcula el
  /// suyo con los precios que tiene.
  final int totalCentavos;

  /// Efectivo que entregó el cliente, en pesos enteros. `null` si no aplica (otro método de pago).
  final int? efectivoRecibido;

  /// El cambio a devolver, en centavos; `null` si no hay efectivo recibido.
  int? get cambioCentavos =>
      efectivoRecibido == null ? null : efectivoRecibido! * 100 - totalCentavos;

  /// El cuerpo JSON de `POST /api/registrar-venta-carrito`. Las cantidades son enteros.
  Map<String, dynamic> cuerpoDeLaPeticion() => {
    'items': [for (final i in items) i.aJson()],
    'metodo_pago': metodoPago.valorApi,
    'efectivo_recibido': ?efectivoRecibido,
  };

  Map<String, dynamic> aJson() => {
    'clave': clave,
    'items': [for (final i in items) i.aJson()],
    'metodo_pago': metodoPago.valorApi,
    'total_centavos': totalCentavos,
    'efectivo_recibido': ?efectivoRecibido,
  };

  /// `null` si lo guardado no tiene la forma esperada (dañado o de otra versión): no se inventa una venta.
  static VentaPendiente? desdeJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final clave = json['clave'];
    final metodo = MetodoPago.desdeApi(json['metodo_pago']);
    final total = json['total_centavos'];
    final recibido = json['efectivo_recibido'];
    final crudos = json['items'];
    if (clave is! String ||
        !_formatoDeClave.hasMatch(clave) ||
        metodo == null ||
        total is! int ||
        total < 0 ||
        (recibido != null && (recibido is! int || recibido < 0)) ||
        crudos is! List ||
        crudos.isEmpty) {
      return null;
    }
    final items = <ItemVenta>[];
    for (final c in crudos) {
      if (c is! Map) {
        return null;
      }
      final id = c['id_producto'];
      final cantidad = c['cantidad'];
      if (id is! int || cantidad is! int || cantidad < 1) {
        return null;
      }
      items.add(ItemVenta(idProducto: id, cantidad: cantidad));
    }
    return VentaPendiente(
      clave: clave,
      items: items,
      metodoPago: metodo,
      totalCentavos: total,
      efectivoRecibido: recibido as int?,
    );
  }
}

/// Lo que el servidor respondió al cobrar. Son TRES casos, y la diferencia importa:
///  - [VentaRegistrada]: la venta existe.
///  - [VentaRechazada]: el servidor dijo que no y NO registró nada: se puede corregir y volver a intentar.
///  - [VentaSinConfirmar]: no se sabe si quedó registrada (se cortó la señal, el servidor falló...). NO se puede dar
///    por fallida ni volver a cobrar con otra clave: solo reintentar con la MISMA.
sealed class ResultadoVenta {
  const ResultadoVenta();
}

class VentaRegistrada extends ResultadoVenta {
  const VentaRegistrada(this.idVenta, {this.repetida = false});

  final int idVenta;

  /// `true` si el servidor devolvió una venta que YA estaba registrada (cabecera `Idempotent-Replayed`): un reintento
  /// que no duplicó nada.
  final bool repetida;
}

class VentaRechazada extends ResultadoVenta {
  const VentaRechazada(this.mensaje, {this.cajaCerrada = false});

  /// El motivo, tal como lo dijo el servidor.
  final String mensaje;

  /// `true` si el rechazo fue porque no hay caja abierta (403): hay que volver a consultar la caja.
  final bool cajaCerrada;
}

class VentaSinConfirmar extends ResultadoVenta {
  const VentaSinConfirmar(
    this.mensaje, {
    this.reintentoAutomatico = true,
    this.sesionCaducada = false,
  });

  final String mensaje;

  /// `true` si conviene reintentar solo, con una pausa (sin red, tiempo agotado, 5xx). `false` si reintentar ya no
  /// serviría (sesión caducada, límite de uso, respuesta rara): lo decide el Tendero.
  final bool reintentoAutomatico;

  /// `true` si el servidor dijo que ya no hay sesión (401): hay que volver a entrar antes de reintentar.
  final bool sesionCaducada;
}
