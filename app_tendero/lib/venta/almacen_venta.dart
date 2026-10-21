import '../api/almacen_pendiente.dart';
import 'venta_models.dart';

/// Dónde se guarda en el celular la venta que se está cobrando, para poder reintentarla con la MISMA clave si la app
/// se cierra o la sesión caduca antes de saber si el servidor la registró.
typedef AlmacenVentaPendiente = AlmacenPendiente<VentaPendiente>;

/// El almacén real de la venta pendiente: `shared_preferences`.
class AlmacenVentaPendienteLocal extends AlmacenPendienteLocal<VentaPendiente> {
  AlmacenVentaPendienteLocal(super.preferencias)
    : super(
        desdeJson: VentaPendiente.desdeJson,
        aJson: (venta) => venta.aJson(),
      );
}
