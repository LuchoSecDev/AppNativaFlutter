import '../ui/dinero.dart';

/// Cliente registrado en la tienda, devuelto por `GET /api/clientes` (`[V1]`).
///
/// Todo el dinero va en CENTAVOS enteros, igual que en el resto de la app: mezclar pesos y centavos en una cuenta de
/// crédito es la forma más fácil de equivocarse por un factor de 100.
class Cliente {
  const Cliente({
    required this.id,
    required this.nombre,
    required this.celular,
    required this.limiteCreditoCentavos,
    required this.saldoPendienteCentavos,
  });

  final int id;
  final String nombre;
  final String? celular;

  /// Cupo de crédito. **0 significa «sin tope»** (contrato `[V2]`; es una decisión de negocio pendiente de confirmar).
  final int limiteCreditoCentavos;

  /// Lo que el cliente debe hoy: ventas fiadas menos abonos.
  final int saldoPendienteCentavos;

  bool get sinTope => limiteCreditoCentavos == 0;

  /// Cuánto se le puede fiar todavía; `null` si no tiene tope.
  int? get cupoDisponibleCentavos =>
      sinTope ? null : limiteCreditoCentavos - saldoPendienteCentavos;

  /// ¿Una venta fiada por [totalVentaCentavos] cabe en el cupo? Estar justo en el cupo es válido (igual que el
  /// servidor). Es una ayuda: quien decide es el servidor, que además serializa dos fiados simultáneos.
  bool alcanzaCupo(int totalVentaCentavos) {
    if (sinTope) return true;
    return saldoPendienteCentavos + totalVentaCentavos <= limiteCreditoCentavos;
  }

  /// El cliente a partir de un elemento de `clientes` de `[V1]`, o `null` si no tiene la forma esperada. No se
  /// inventan valores: un cupo ilegible NO puede convertirse en «sin tope», porque dejaría fiar sin límite.
  static Cliente? desdeJson(Object? crudo) {
    if (crudo is! Map) return null;
    final id = crudo['id_cliente'];
    final nombre = crudo['nombre'];
    final celular = crudo['celular'];
    final limite = _centavos(crudo['limite_credito']);
    final saldo = _centavos(crudo['saldo_pendiente']);
    if (id is! int ||
        nombre is! String ||
        (celular != null && celular is! String) ||
        limite == null ||
        saldo == null) {
      return null;
    }
    return Cliente(
      id: id,
      nombre: nombre,
      celular: celular as String?,
      limiteCreditoCentavos: limite,
      saldoPendienteCentavos: saldo,
    );
  }

  /// La API manda unos importes como texto con decimales (`"5000.00"`) y otros como número (`"saldo_pendiente": 0`).
  /// Los dos se convierten a centavos enteros sin pasar por `double`.
  static int? _centavos(Object? valor) {
    if (valor is int) return valor < 0 ? null : valor * 100;
    if (valor is double) return centavosDeImporte(valor.toString());
    if (valor is String) return centavosDeImporte(valor);
    return null;
  }
}
