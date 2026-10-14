import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/errores_de_api.dart';
import '../auth/auth_providers.dart';
import '../auth/session_state.dart';
import 'actualizacion_models.dart';
import 'actualizacion_repository.dart';
import 'estado_de_version.dart';
import 'version_instalada.dart';

final actualizacionRepositoryProvider = Provider<ActualizacionRepository>(
  (ref) => ActualizacionRepository(ref.watch(dioProvider)),
);

/// Cómo se lee la versión instalada. En la app real habla con el sistema; en las pruebas se sustituye por una función
/// que devuelve la versión que se quiere probar.
final lectorDeVersionInstaladaProvider =
    Provider<Future<VersionInstalada?> Function()>(
      (ref) => leerVersionInstaladaDelSistema,
    );

/// Cómo se abre el enlace de descarga: en el navegador del celular. En las pruebas se sustituye.
final abridorDeEnlacesProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (enlace) => launchUrl(enlace, mode: LaunchMode.externalApplication),
);

/// La versión instalada, para mostrarla en pantalla (y comprobar en un celular real que el número es el esperado).
final versionInstaladaProvider = FutureProvider<VersionInstalada?>(
  (ref) => ref.watch(lectorDeVersionInstaladaProvider)(),
);

/// Lo que la app sabe de las actualizaciones. Inmutable: para cambiarlo se crea otro.
class EstadoActualizacion {
  const EstadoActualizacion({
    this.nivel = NivelDeActualizacion.alDia,
    this.publicada,
    this.avisoDescartado = false,
    this.abriendo = false,
    this.mensaje,
  });

  final NivelDeActualizacion nivel;

  /// La última versión publicada (cuando se pudo consultar).
  final VersionPublicada? publicada;

  /// La persona pulsó «Ahora no» en el aviso (solo vale mientras dura esta sesión).
  final bool avisoDescartado;

  /// `true` mientras se pide la dirección de descarga.
  final bool abriendo;

  /// Un error para mostrar, en español.
  final String? mensaje;

  EstadoActualizacion _con({
    bool? avisoDescartado,
    bool? abriendo,
    String? mensaje,
    bool quitarMensaje = false,
  }) => EstadoActualizacion(
    nivel: nivel,
    publicada: publicada,
    avisoDescartado: avisoDescartado ?? this.avisoDescartado,
    abriendo: abriendo ?? this.abriendo,
    mensaje: quitarMensaje ? null : (mensaje ?? this.mensaje),
  );
}

final actualizacionProvider =
    NotifierProvider<ActualizacionNotifier, EstadoActualizacion>(
      ActualizacionNotifier.new,
    );

class ActualizacionNotifier extends Notifier<EstadoActualizacion> {
  ActualizacionRepository get _repo =>
      ref.read(actualizacionRepositoryProvider);

  /// Igual que en la caja: una respuesta que llega «tarde», de una sesión anterior, se descarta.
  int _generacion = 0;

  bool _obsoleto(int generacion) => generacion != _generacion || !ref.mounted;

  @override
  EstadoActualizacion build() {
    final fase = ref.watch(sesionProvider.select((e) => e.fase));
    _generacion++;
    if (fase == FaseSesion.activa) {
      Future.microtask(consultar);
    }
    return const EstadoActualizacion();
  }

  /// [U1] Pregunta qué versión hay publicada y la compara con la instalada. Cualquier falla (sin red, servidor dormido,
  /// respuesta rara, versión instalada desconocida) deja todo como estaba: NUNCA bloquea la app.
  Future<void> consultar() async {
    if (!ref.mounted) return;
    final g = _generacion;
    try {
      final instalada = await ref.read(lectorDeVersionInstaladaProvider)();
      if (_obsoleto(g) || instalada == null) return;
      final publicada = await _repo.consultarVersion();
      if (_obsoleto(g)) return;
      state = EstadoActualizacion(
        nivel: evaluarVersion(
          instalada: instalada.codigo,
          publicada: publicada,
        ),
        publicada: publicada,
      );
    } on ErrorDeApi {
      // Sin conexión o con el servidor caído: se sigue como estaba.
    }
  }

  /// «Ahora no» en el aviso de versión nueva.
  void descartarAviso() {
    state = state._con(avisoDescartado: true);
  }

  /// [U2] Pide la dirección de descarga (requiere la sesión) y la abre en el navegador. Es de solo lectura: tocarlo dos
  /// veces no hace daño, pero mientras se espera no se vuelve a pedir.
  Future<void> descargar() async {
    if (state.abriendo) return;
    final g = _generacion;
    state = state._con(abriendo: true, quitarMensaje: true);
    try {
      final resultado = await _repo.pedirDescarga();
      if (_obsoleto(g)) return;
      switch (resultado) {
        case DescargaLista(descarga: final d):
          var abrio = false;
          try {
            abrio = await ref.read(abridorDeEnlacesProvider)(d.enlace);
          } catch (_) {
            abrio = false;
          }
          if (_obsoleto(g)) return;
          state = abrio
              ? state._con(abriendo: false)
              : state._con(
                  abriendo: false,
                  mensaje: 'No se pudo abrir la descarga. Inténtalo otra vez o pídele el enlace a quien te dio la app.',
                );
        case DescargaNoDisponible():
          state = state._con(
            abriendo: false,
            mensaje: 'Todavía no hay una versión para descargar. Inténtalo más tarde.',
          );
      }
    } on ErrorDeApi catch (e) {
      if (!_obsoleto(g)) {
        state = state._con(abriendo: false, mensaje: e.mensaje);
      }
    }
  }
}
