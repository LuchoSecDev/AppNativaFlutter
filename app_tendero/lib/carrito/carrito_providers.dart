import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../auth/session_state.dart';
import '../catalogo/catalogo_providers.dart';
import '../catalogo/producto.dart';
import '../ui/dinero.dart';
import '../venta/venta_providers.dart';
import 'almacen_carrito.dart';
import 'carrito_models.dart';

/// Dónde se guarda el carrito. `main()` lo sustituye por el real (`shared_preferences`); las pruebas, por uno en
/// memoria.
final almacenCarritoProvider = Provider<AlmacenCarrito>(
  (ref) =>
      throw UnimplementedError('almacenCarritoProvider se sustituye en main()'),
);

/// Las líneas del carrito (producto y cantidad) de la persona que tiene la sesión abierta.
class EstadoCarrito {
  const EstadoCarrito({this.lineas = const [], this.cargando = false});

  final List<LineaCarrito> lineas;

  /// `true` mientras se lee del almacenamiento del celular.
  final bool cargando;
}

final carritoProvider = NotifierProvider<CarritoNotifier, EstadoCarrito>(
  CarritoNotifier.new,
);

/// El carrito con los datos actuales del catálogo: precios, subtotales, total y problemas por línea.
final resumenCarritoProvider = Provider<ResumenCarrito>((ref) {
  final lineas = ref.watch(carritoProvider).lineas;
  final catalogo = ref.watch(catalogoProvider);
  final porId = {for (final p in catalogo.productos) p.id: p};
  final catalogoListo = catalogo.fase == FaseCatalogo.listo;

  return ResumenCarrito(
    lineas: [
      for (final linea in lineas)
        _detallar(linea, porId[linea.idProducto], catalogoListo),
    ],
  );
});

LineaDetallada _detallar(
  LineaCarrito linea,
  Producto? producto,
  bool catalogoListo,
) {
  if (producto == null) {
    return LineaDetallada(
      linea: linea,
      producto: null,
      precioUnitarioCentavos: null,
      problema: catalogoListo
          ? ProblemaLinea.noEstaEnElCatalogo
          : ProblemaLinea.esperandoCatalogo,
    );
  }
  final precio = centavosDeImporte(producto.precio);
  final ProblemaLinea problema;
  if (!producto.estaDisponible) {
    problema = ProblemaLinea.inactivo;
  } else if (precio == null || precio <= 0) {
    problema = ProblemaLinea.sinPrecio;
  } else if (linea.cantidad > producto.cantidad) {
    problema = ProblemaLinea.sinStockSuficiente;
  } else {
    problema = ProblemaLinea.ninguno;
  }
  return LineaDetallada(
    linea: linea,
    producto: producto,
    precioUnitarioCentavos: precio,
    problema: problema,
  );
}

class CarritoNotifier extends Notifier<EstadoCarrito> {
  AlmacenCarrito get _almacen => ref.read(almacenCarritoProvider);

  /// Se incrementa cada vez que cambia la sesión: una lectura tardía de la cuenta anterior se descarta.
  int _generacion = 0;

  /// Dónde se guarda el carrito de ESTA persona en ESTA tienda. Distinta por usuario y tienda: al entrar otra
  /// cuenta en el mismo celular no ve el carrito de la anterior.
  String? _clave;

  bool _obsoleto(int generacion) => generacion != _generacion || !ref.mounted;

  /// Mientras se cobra (o hay un cobro sin confirmar) el carrito no se toca: el reintento debe enviar exactamente lo
  /// mismo que la primera vez. Se pregunta aquí, y no solo en las pantallas, para que ninguna entrada futura (el
  /// escáner, por ejemplo) pueda cambiar un carrito que se está cobrando.
  bool get _bloqueado => ref.read(cobroProvider).bloqueaElCarrito;

  @override
  EstadoCarrito build() {
    // Se vuelve a ejecutar cuando cambia la sesión (entrar, salir, caducar, cambiar de cuenta).
    final sesion = ref.watch(
      sesionProvider.select((e) => (e.fase, e.info?.userId, e.info?.tiendaId)),
    );
    final (fase, userId, tiendaId) = sesion;
    _generacion++;
    // Enciende el cobro ya (los providers se crean al leerlos por primera vez): así su lectura del celular corre a la
    // vez que la del carrito, y la primera acción no se encuentra con «todavía no sé si hay un cobro a medias».
    ref.read(cobroProvider);

    if (fase == FaseSesion.activa && userId != null && tiendaId != null) {
      _clave = 'carrito_v1_${userId}_$tiendaId';
      Future.microtask(_cargar);
      return const EstadoCarrito(cargando: true);
    }
    // Sin sesión no hay carrito a la vista. Lo guardado en el celular NO se borra: si la sesión caducó a mitad de
    // una venta, al volver a entrar la misma persona recupera su carrito.
    _clave = null;
    return const EstadoCarrito();
  }

  Future<void> _cargar() async {
    final g = _generacion;
    final clave = _clave;
    if (clave == null) {
      return;
    }
    List<LineaCarrito> lineas;
    try {
      lineas = await _almacen.leer(clave);
    } on Object {
      lineas = const []; // el almacenamiento falló: se sigue con un carrito vacío en vez de bloquear la venta
    }
    if (_obsoleto(g)) {
      return;
    }
    state = EstadoCarrito(lineas: lineas);
  }

  // ───────────────────────── acciones ─────────────────────────

  /// Agrega UNA unidad del [producto]. Las reglas viven aquí, en un solo lugar: no se vende lo agotado, lo inactivo ni
  /// lo que no tiene precio, ni se pasa de las unidades en stock.
  ResultadoAgregar agregar(Producto producto) {
    if (state.cargando || _clave == null) {
      return ResultadoAgregar.cargando;
    }
    if (_bloqueado) {
      return ResultadoAgregar.ventaEnCurso;
    }
    if (!producto.estaDisponible) {
      return ResultadoAgregar.noDisponible;
    }
    if (producto.agotado) {
      return ResultadoAgregar.agotado;
    }
    final precio = centavosDeImporte(producto.precio);
    if (precio == null || precio <= 0) {
      return ResultadoAgregar.sinPrecio;
    }

    final lineas = [...state.lineas];
    final i = lineas.indexWhere((l) => l.idProducto == producto.id);
    if (i >= 0) {
      if (lineas[i].cantidad >= producto.cantidad) {
        return ResultadoAgregar.limiteDeStock;
      }
      lineas[i] = lineas[i].conCantidad(lineas[i].cantidad + 1);
    } else {
      lineas.add(
        LineaCarrito(
          idProducto: producto.id,
          nombre: producto.nombre,
          cantidad: 1,
        ),
      );
    }
    _aplicar(lineas);
    return ResultadoAgregar.agregado;
  }

  /// Suma una unidad a una línea del carrito. [ResultadoAgregar.limiteDeStock] si ya no hay más.
  ResultadoAgregar incrementar(int idProducto) {
    if (_bloqueado) {
      return ResultadoAgregar.ventaEnCurso;
    }
    final lineas = [...state.lineas];
    final i = lineas.indexWhere((l) => l.idProducto == idProducto);
    if (i < 0) {
      return ResultadoAgregar.cargando;
    }
    final producto = _productoDelCatalogo(idProducto);
    if (producto != null && lineas[i].cantidad >= producto.cantidad) {
      return ResultadoAgregar.limiteDeStock;
    }
    lineas[i] = lineas[i].conCantidad(lineas[i].cantidad + 1);
    _aplicar(lineas);
    return ResultadoAgregar.agregado;
  }

  /// Resta una unidad. Con una sola unidad no hace nada: para sacar el producto está [quitar].
  void decrementar(int idProducto) {
    if (_bloqueado) {
      return;
    }
    final lineas = [...state.lineas];
    final i = lineas.indexWhere((l) => l.idProducto == idProducto);
    if (i < 0 || lineas[i].cantidad <= 1) {
      return;
    }
    lineas[i] = lineas[i].conCantidad(lineas[i].cantidad - 1);
    _aplicar(lineas);
  }

  void quitar(int idProducto) {
    if (_bloqueado) {
      return;
    }
    _aplicar([...state.lineas.where((l) => l.idProducto != idProducto)]);
  }

  void vaciar() {
    if (_bloqueado) {
      return;
    }
    _aplicar(const []);
  }

  // ───────────────────────── pasos internos ─────────────────────────

  Producto? _productoDelCatalogo(int id) {
    for (final p in ref.read(catalogoProvider).productos) {
      if (p.id == id) {
        return p;
      }
    }
    return null;
  }

  /// Cambia el carrito y lo guarda en el celular. Si guardar falla, la venta no se bloquea: el carrito sigue en
  /// memoria y solo se pierde la copia en disco.
  void _aplicar(List<LineaCarrito> lineas) {
    state = EstadoCarrito(lineas: lineas);
    final clave = _clave;
    if (clave != null) {
      unawaited(_almacen.guardar(clave, lineas).catchError((Object _) {}));
    }
  }
}
