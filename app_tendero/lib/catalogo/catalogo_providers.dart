import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/errores_de_api.dart';
import '../auth/auth_providers.dart';
import '../auth/session_state.dart';
import 'catalogo_repository.dart';
import 'producto.dart';

enum FaseCatalogo {
  /// Descargando por primera vez (o todavía no hay sesión).
  cargando,

  /// Hay una lista (puede estar vacía) para mostrar.
  listo,

  /// No se pudo descargar y no hay ninguna lista anterior que mostrar.
  error,
}

/// Lo que la app sabe del catálogo en este momento. Inmutable.
class EstadoCatalogo {
  const EstadoCatalogo._({
    required this.fase,
    this.productos = const [],
    this.mensaje,
    this.actualizando = false,
  });

  const EstadoCatalogo.cargando() : this._(fase: FaseCatalogo.cargando);

  /// [aviso]: algo que decirle al usuario aunque haya lista (por ejemplo, que no se pudo actualizar).
  const EstadoCatalogo.listo(List<Producto> productos, {String? aviso})
    : this._(fase: FaseCatalogo.listo, productos: productos, mensaje: aviso);

  const EstadoCatalogo.error(String mensaje)
    : this._(fase: FaseCatalogo.error, mensaje: mensaje);

  final FaseCatalogo fase;
  final List<Producto> productos;

  /// Un error o aviso para mostrar, en español.
  final String? mensaje;

  /// `true` mientras se vuelve a descargar teniendo ya una lista (se sigue mostrando la anterior).
  final bool actualizando;

  EstadoCatalogo enActualizacion() =>
      EstadoCatalogo._(fase: fase, productos: productos, actualizando: true);
}

final catalogoRepositoryProvider = Provider<CatalogoRepository>(
  (ref) => CatalogoRepository(ref.watch(dioProvider)),
);

/// El catálogo de la tienda de la persona que tiene la sesión abierta.
final catalogoProvider = NotifierProvider<CatalogoNotifier, EstadoCatalogo>(
  CatalogoNotifier.new,
);

class CatalogoNotifier extends Notifier<EstadoCatalogo> {
  CatalogoRepository get _repo => ref.read(catalogoRepositoryProvider);

  /// Igual que en la caja: una respuesta tardía de una sesión anterior (otra cuenta, otra tienda) se descarta.
  int _generacion = 0;

  bool _obsoleto(int generacion) => generacion != _generacion || !ref.mounted;

  /// `true` mientras hay una descarga en curso: una segunda petición (un doble toque en «Reintentar») no lanza otra.
  bool _enCurso = false;

  @override
  EstadoCatalogo build() {
    // build() se vuelve a ejecutar cada vez que cambia la fase de la sesión: al cerrar sesión el catálogo se vacía
    // solo, y no queda a la vista el de la tienda anterior.
    final fase = ref.watch(sesionProvider.select((e) => e.fase));
    _generacion++;
    _enCurso = false;
    if (fase == FaseSesion.activa) {
      Future.microtask(cargar);
    }
    return const EstadoCatalogo.cargando();
  }

  /// [C1] Descarga el catálogo. Si ya había una lista y la descarga falla, se CONSERVA la lista anterior con un aviso:
  /// un catálogo un poco viejo es mejor que ninguno cuando la señal es mala.
  Future<void> cargar() async {
    if (_enCurso) {
      return;
    }
    _enCurso = true;
    final g = _generacion;
    final previos = state.productos;
    state = previos.isEmpty
        ? const EstadoCatalogo.cargando()
        : state.enActualizacion();
    try {
      final lista = await _repo.listar();
      if (_obsoleto(g)) {
        return;
      }
      state = EstadoCatalogo.listo(lista);
    } on ErrorDeApi catch (e) {
      if (_obsoleto(g)) {
        return;
      }
      state = previos.isEmpty
          ? EstadoCatalogo.error(e.mensaje)
          : EstadoCatalogo.listo(
              previos,
              aviso: 'No se pudo actualizar la lista: ${e.mensaje}',
            );
    } finally {
      if (!_obsoleto(g)) {
        _enCurso = false;
      }
    }
  }
}
