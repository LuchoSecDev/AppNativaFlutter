import 'actualizacion_models.dart';

/// Qué tan urgente es actualizar la app.
enum NivelDeActualizacion {
  /// Nada que hacer (o no se pudo saber: ante la duda no se molesta ni se bloquea a nadie).
  alDia,

  /// Hay una versión nueva, pero la instalada todavía sirve: se avisa y se puede seguir trabajando.
  opcional,

  /// La instalada ya no funciona con el servidor: no se puede usar la app hasta actualizar.
  obligatoria,
}

/// Compara la versión instalada con la publicada (contrato `[U1]`).
///
///  - Sin saber una de las dos, [NivelDeActualizacion.alDia]: un fallo al consultar nunca debe dejar a alguien sin su caja.
///  - [instalada] menor que la mínima: [NivelDeActualizacion.obligatoria].
///  - [instalada] menor que la última: [NivelDeActualizacion.opcional].
///
/// Una mínima MAYOR que la última versión no tiene sentido (obligaría a actualizar a algo que no existe): se ignora, igual
/// que hace el servidor.
NivelDeActualizacion evaluarVersion({
  required int? instalada,
  required VersionPublicada? publicada,
}) {
  if (instalada == null || publicada == null) {
    return NivelDeActualizacion.alDia;
  }
  final minima = publicada.minVersionCode <= publicada.versionCode
      ? publicada.minVersionCode
      : 1;
  if (instalada < minima) return NivelDeActualizacion.obligatoria;
  if (instalada < publicada.versionCode) return NivelDeActualizacion.opcional;
  return NivelDeActualizacion.alDia;
}
