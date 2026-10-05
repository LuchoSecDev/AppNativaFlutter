import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/auth/auth_models.dart';
import 'package:stockpilot/auth/session_state.dart';
import 'package:stockpilot/carrito/almacen_carrito.dart';
import 'package:stockpilot/carrito/carrito_models.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/catalogo/catalogo_providers.dart';
import 'package:stockpilot/catalogo/producto.dart';
import 'package:stockpilot/venta/almacen_venta.dart';
import 'package:stockpilot/venta/venta_models.dart';
import 'package:stockpilot/venta/venta_providers.dart';

/// Un almacén de carritos en memoria, con ganchos para simular fallas y lecturas lentas.
class AlmacenEnMemoria implements AlmacenCarrito {
  final Map<String, List<LineaCarrito>> datos = {};
  int lecturas = 0;
  int guardados = 0;

  /// Si es `true`, leer y guardar fallan (disco lleno, permisos...).
  bool fallar = false;

  /// Si no es `null`, la lectura espera a que se complete (para probar respuestas tardías).
  Completer<void>? lecturaDemorada;

  @override
  Future<List<LineaCarrito>> leer(String clave) async {
    lecturas++;
    if (lecturaDemorada != null) {
      await lecturaDemorada!.future;
    }
    if (fallar) {
      throw Exception('fallo de lectura simulado');
    }
    return [...?datos[clave]];
  }

  @override
  Future<void> guardar(String clave, List<LineaCarrito> lineas) async {
    guardados++;
    if (fallar) {
      throw Exception('fallo de escritura simulado');
    }
    if (lineas.isEmpty) {
      datos.remove(clave);
    } else {
      datos[clave] = [...lineas];
    }
  }
}

/// Un almacén de ventas pendientes en memoria, con un gancho para simular fallas del disco.
class AlmacenVentaEnMemoria implements AlmacenVentaPendiente {
  final Map<String, VentaPendiente> datos = {};

  /// Si es `true`, leer, guardar y borrar fallan (disco lleno, permisos...).
  bool fallar = false;

  @override
  Future<VentaPendiente?> leer(String clave) async {
    if (fallar) {
      throw Exception('fallo de lectura simulado');
    }
    return datos[clave];
  }

  @override
  Future<void> guardar(String clave, VentaPendiente venta) async {
    if (fallar) {
      throw Exception('fallo de escritura simulado');
    }
    datos[clave] = venta;
  }

  @override
  Future<void> borrar(String clave) async {
    if (fallar) {
      throw Exception('fallo de borrado simulado');
    }
    datos.remove(clave);
  }
}

/// Una sesión fija (sin servidor): se puede cambiar con [poner] para simular entrar, salir o cambiar de cuenta.
class SesionFija extends SesionNotifier {
  SesionFija(this._inicial);

  final EstadoSesion _inicial;

  @override
  EstadoSesion build() => _inicial;

  void poner(EstadoSesion nuevo) => state = nuevo;
}

/// Un catálogo fijo (sin servidor): se puede cambiar con [poner] para simular cambios de precio o de stock.
class CatalogoFijo extends CatalogoNotifier {
  CatalogoFijo(this._inicial);

  final EstadoCatalogo _inicial;

  @override
  EstadoCatalogo build() => _inicial;

  void poner(EstadoCatalogo nuevo) => state = nuevo;
}

EstadoSesion sesionActiva({int userId = 2, int tiendaId = 1}) =>
    EstadoSesion.activa(
      InfoSesion(
        userId: userId,
        tiendaId: tiendaId,
        tiendaNombre: 'Tienda La Esperanza',
        limiteEgresoTendero: '150000.00',
        rol: 'Tendero',
        nombres: 'Carlos Pérez',
        is2FAEnabled: false,
        cambioClaveForzoso: false,
        needs2FASetup: false,
      ),
    );

Producto producto(
  int id,
  String nombre, {
  String precio = '1000.00',
  int cantidad = 10,
  String estado = 'Disponible',
}) => Producto(
  id: id,
  codigo: 'P-$id',
  codigoBarras: null,
  nombre: nombre,
  categoria: 'General',
  precio: precio,
  cantidad: cantidad,
  estado: estado,
  nivelStock: 'ok',
);

/// Arma un contenedor con sesión, catálogo y almacén fijos. Devuelve también los controladores para cambiarlos.
({ProviderContainer contenedor, SesionFija sesion, CatalogoFijo catalogo})
armarContenedor({
  required AlmacenEnMemoria almacen,
  EstadoSesion? sesion,
  List<Producto> productos = const [],
}) {
  final sesionFija = SesionFija(sesion ?? sesionActiva());
  final catalogoFijo = CatalogoFijo(EstadoCatalogo.listo(productos));
  final contenedor = ProviderContainer(
    overrides: [
      sesionProvider.overrideWith(() => sesionFija),
      catalogoProvider.overrideWith(() => catalogoFijo),
      almacenCarritoProvider.overrideWithValue(almacen),
      almacenVentaPendienteProvider.overrideWithValue(AlmacenVentaEnMemoria()),
    ],
  );
  // Los providers se crean al leerlos por primera vez; se encienden ya para que `poner` funcione desde el inicio.
  contenedor.read(sesionProvider);
  contenedor.read(catalogoProvider);
  return (contenedor: contenedor, sesion: sesionFija, catalogo: catalogoFijo);
}
