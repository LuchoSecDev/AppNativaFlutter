import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../api/errores_de_api.dart';
import '../../carrito/carrito_models.dart';
import '../../carrito/carrito_providers.dart';
import '../../catalogo/catalogo_providers.dart';
import '../../catalogo/producto.dart';
import '../../catalogo/ui/buscar_producto_screen.dart';
import '../../scan_stabilizer.dart';
import '../../ui/colores.dart';
import '../../ui/dinero.dart';
import '../../ui/formato.dart';
import '../../vista_de_escaneo.dart';

/// Cuánto tiempo sin ver un código hace falta para aceptarlo otra vez. Mientras la cámara siga apuntando al producto
/// recién agregado NO se agrega de nuevo (una unidad de más sin que nadie lo note). Si en las pruebas con celulares
/// reales el temblor de la cámara agrega unidades dobles, subir este valor; si cuesta escanear dos unidades iguales
/// seguidas, bajarlo.
const Duration silencioParaRepetirProducto = Duration(milliseconds: 1500);

/// Construye la vista de la cámara. Existe para que las pruebas pongan una vista falsa (la cámara real solo se puede
/// probar en un celular); la app real usa [VistaDeEscaneo].
typedef ConstructorDeVistaDeEscaneo = Widget Function(
  BuildContext context,
  ScanStabilizer estabilizador,
  bool pausado,
  ValueChanged<String> alConfirmar,
);

/// Escanear productos para el carrito, uno tras otro. Un código conocido se agrega; uno desconocido ofrece
/// vincularlo a un producto de la lista.
class EscanerVentaScreen extends ConsumerStatefulWidget {
  const EscanerVentaScreen({super.key, @visibleForTesting this.construirVista});

  final ConstructorDeVistaDeEscaneo? construirVista;

  @override
  ConsumerState<EscanerVentaScreen> createState() => _EscanerVentaScreenState();
}

class _EscanerVentaScreenState extends ConsumerState<EscanerVentaScreen> {
  /// `null` cuando las pruebas ponen su propia vista.
  late final MobileScannerController? _camara;

  final ScanStabilizer _estabilizador = ScanStabilizer(
    silencioParaRepetir: silencioParaRepetirProducto,
  );

  /// `true` mientras se procesa un código (consulta al servidor, diálogo, elegir producto). El estado es el seguro
  /// contra una segunda lectura: nada se procesa en pausa.
  bool _pausado = false;

  @override
  void initState() {
    super.initState();
    _camara = widget.construirVista == null
        ? crearControladorDeEscaneo()
        : null;
  }

  @override
  void dispose() {
    _camara?.dispose();
    super.dispose();
  }

  // ───────────────────────── flujo ─────────────────────────

  Future<void> _alConfirmar(String codigo) async {
    if (_pausado) {
      return;
    }
    setState(() => _pausado = true);
    try {
      final producto = await ref
          .read(catalogoRepositoryProvider)
          .buscarPorCodigoBarras(codigo);
      if (!mounted) {
        return;
      }
      if (producto == null) {
        await _ofrecerVincular(codigo);
        return;
      }
      final rechazo = _agregar(producto);
      _avisar(
        rechazo ?? 'Agregado: ${producto.nombre}',
        tipo: rechazo == null ? _Aviso.exito : _Aviso.error,
      );
      // Sin reiniciar: la cámara sigue un momento sobre este producto y no debe agregarse otra vez.
      _reanudar(reiniciar: false);
    } on ErrorDeApi catch (e) {
      if (!mounted) {
        return;
      }
      _avisar(e.mensaje, tipo: _Aviso.error);
      _reanudar(
        reiniciar: true,
      ); // tras un error se puede reintentar el mismo código al instante
    }
  }

  Future<void> _ofrecerVincular(String codigo) async {
    final vincular = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Código no encontrado'),
        content: Text(
          'El código $codigo no está vinculado a ningún producto. ¿Quieres vincularlo a uno de tu lista?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Vincular'),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    if (vincular != true) {
      _reanudar(reiniciar: true);
      return;
    }
    await _vincular(codigo);
  }

  Future<void> _vincular(String codigo) async {
    // Vincular un código es un hecho del producto físico: no depende de su stock ni de su precio. Se acepta cualquier
    // producto de la lista y, si luego no se puede agregar (agotado, sin precio), se dice por qué.
    final elegido = await Navigator.of(context).push<Producto>(
      MaterialPageRoute<Producto>(
        builder: (_) => BuscarProductoScreen(alElegir: (_) => null),
      ),
    );
    if (!mounted) {
      return;
    }
    if (elegido == null) {
      _reanudar(reiniciar: true);
      return;
    }

    try {
      await ref
          .read(catalogoRepositoryProvider)
          .vincularCodigoBarras(elegido.id, codigo);
    } on ErrorDeApi catch (e) {
      if (!mounted) {
        return;
      }
      _avisar(e.mensaje, tipo: _Aviso.error);
      _reanudar(reiniciar: true);
      return;
    }
    if (!mounted) {
      return;
    }

    // El catálogo cambió (ahora el producto tiene este código): se vuelve a descargar. Si no se pudo, se sigue con el
    // producto elegido, que tiene el mismo precio y stock.
    final actualizado = await ref.read(catalogoProvider.notifier).cargar();
    if (!mounted) {
      return;
    }
    final producto =
        ref
            .read(catalogoProvider)
            .productos
            .where((p) => p.id == elegido.id)
            .firstOrNull ??
        elegido;
    final rechazo = _agregar(producto);
    final sinLista = actualizado
        ? ''
        : ' No se pudo actualizar la lista de productos.';
    _avisar(
      rechazo == null
          ? 'Vinculado y agregado: ${producto.nombre}.$sinLista'
          : 'Vinculado, pero $rechazo$sinLista',
      tipo: rechazo == null ? _Aviso.exito : _Aviso.aviso,
    );
    _reanudar(reiniciar: false);
  }

  /// Agrega el producto al carrito. Devuelve el motivo si no se pudo, o `null` si se agregó.
  String? _agregar(Producto producto) {
    // El producto puede ser nuevo para esta tienda y no estar en la lista descargada: sin él el carrito no sabría su
    // precio. Se vuelve a descargar la lista sin esperar.
    final enLista = ref
        .read(catalogoProvider)
        .productos
        .any((p) => p.id == producto.id);
    if (!enLista) {
      ref.read(catalogoProvider.notifier).cargar();
    }
    final resultado = ref.read(carritoProvider.notifier).agregar(producto);
    return mensajeDeAgregar(resultado, producto);
  }

  void _reanudar({required bool reiniciar}) {
    if (reiniciar) {
      _estabilizador.reset();
    }
    setState(() => _pausado = false);
  }

  void _avisar(String texto, {required _Aviso tipo}) {
    final mensajes = ScaffoldMessenger.of(context);
    mensajes.clearSnackBars();
    mensajes.showSnackBar(
      SnackBar(
        content: Text(texto),
        duration: const Duration(seconds: 3),
        backgroundColor: switch (tipo) {
          _Aviso.exito => Colores.exito,
          _Aviso.aviso => Colores.aviso,
          _Aviso.error => Colores.peligro,
        },
      ),
    );
  }

  // ───────────────────────── pantalla ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final resumen = ref.watch(resumenCarritoProvider);
    final camara = _camara;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear producto'),
        actions: [if (camara != null) ...accionesDeCamara(camara)],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child:
                widget.construirVista?.call(
                  context,
                  _estabilizador,
                  _pausado,
                  _alConfirmar,
                ) ??
                VistaDeEscaneo(
                  controlador: camara!,
                  estabilizador: _estabilizador,
                  pausado: _pausado,
                  alConfirmar: _alConfirmar,
                ),
          ),
          Container(
            width: double.infinity,
            color: Colores.tinta,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    resumen.estaVacio
                        ? 'Apunta al código del producto'
                        : 'Carrito: ${resumen.unidades} ${resumen.unidades == 1 ? 'unidad' : 'unidades'} · ${formatoPesos(importeDeCentavos(resumen.totalCentavos))}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colores.tinta,
                    ),
                    child: const Text('Listo, volver al carrito'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Aviso { exito, aviso, error }
