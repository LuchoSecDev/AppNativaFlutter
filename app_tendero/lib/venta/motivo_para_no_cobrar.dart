import '../carrito/carrito_models.dart';
import '../clientes/cliente.dart';
import 'venta_models.dart';

/// Por qué NO se puede cobrar ahora, en español, o `null` si se puede. La app ayuda a validar, pero quien decide es el
/// servidor.
///
/// [puedeVender] es `true` con la caja abierta. [efectivoRecibido] son pesos enteros (solo para el efectivo) y
/// [cliente] es obligatorio para el fiado.
String? motivoParaNoCobrar({
  required bool puedeVender,
  required ResumenCarrito resumen,
  required MetodoPago metodo,
  required int? efectivoRecibido,
  required Cliente? cliente,
}) {
  if (!puedeVender) {
    return 'No hay una caja abierta. Abre la caja para vender.';
  }
  if (!resumen.sePuedeCobrar) {
    return 'El carrito tiene productos con problemas. Revísalos antes de cobrar.';
  }
  if (metodo == MetodoPago.efectivo) {
    if (efectivoRecibido == null ||
        efectivoRecibido <= 0 ||
        efectivoRecibido * 100 < resumen.totalCentavos) {
      return 'El efectivo recibido no alcanza para cubrir el total.';
    }
  }
  if (metodo == MetodoPago.fiado) {
    if (cliente == null) {
      return 'Debes seleccionar un cliente para vender fiado.';
    }
    if (!cliente.alcanzaCupo(resumen.totalCentavos)) {
      return 'El monto de esta venta supera el cupo de crédito del cliente.';
    }
  }
  return null;
}
