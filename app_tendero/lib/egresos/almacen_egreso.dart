import '../api/almacen_pendiente.dart';
import 'egreso_models.dart';

/// Dónde se guarda en el celular el egreso que se está registrando, para poder reintentarlo con la MISMA clave si la
/// app se cierra o la sesión caduca antes de saber si el servidor lo registró.
typedef AlmacenEgresoPendiente = AlmacenPendiente<EgresoPendiente>;

/// El almacén real del egreso pendiente: `shared_preferences`.
class AlmacenEgresoPendienteLocal
    extends AlmacenPendienteLocal<EgresoPendiente> {
  AlmacenEgresoPendienteLocal(super.preferencias)
    : super(
        desdeJson: EgresoPendiente.desdeJson,
        aJson: (egreso) => egreso.aJson(),
      );
}
