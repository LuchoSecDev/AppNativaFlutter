import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../caja/caja_providers.dart';
import '../../catalogo/ui/buscar_producto_screen.dart';
import '../../ui/colores.dart';
import '../../ui/dinero.dart';
import '../../ui/formato.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../../ui/refrescar.dart';
import '../../venta/ui/cobrar_efectivo_screen.dart';
import '../../venta/ui/escaner_venta_screen.dart';
import '../../venta/venta_providers.dart';
import '../carrito_models.dart';
import '../carrito_providers.dart';

/// El carrito de la venta en curso: productos, cantidades, total y los problemas que impiden cobrar.
///
/// El carrito se guarda en el celular: si la app se cierra o la sesión caduca a mitad de una venta, al volver sigue
/// aquí.
class CarritoScreen extends ConsumerWidget {
  const CarritoScreen({super.key});

  void _abrirEscaner(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const EscanerVentaScreen()));
  }

  Future<void> _agregarProducto(BuildContext context, WidgetRef ref) async {
    String? agregado;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BuscarProductoScreen(
          alElegir: (producto) {
            final r = ref.read(carritoProvider.notifier).agregar(producto);
            final rechazo = mensajeDeAgregar(r, producto);
            if (rechazo == null) {
              agregado = producto.nombre;
            }
            return rechazo;
          },
        ),
      ),
    );
    if (agregado != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Agregado: $agregado')));
    }
  }

  Future<void> _confirmarVaciar(BuildContext context, WidgetRef ref) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('¿Vaciar el carrito?'),
        content: const Text('Se quitarán todos los productos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Vaciar'),
          ),
        ],
      ),
    );
    if (confirmado == true) {
      ref.read(carritoProvider.notifier).vaciar();
    }
  }

  /// Renunciar a un cobro sin confirmar es lo único que permite cobrar de nuevo con otra clave. Si el servidor SÍ había
  /// registrado la venta, cobrar otra vez la duplicaría: por eso se advierte antes.
  Future<void> _confirmarDescartar(BuildContext context, WidgetRef ref) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('¿Cancelar este cobro?'),
        content: const Text(
          'No sabemos si la venta se registró. Si cancelas y la venta SÍ se había registrado, al cobrar de nuevo quedará duplicada. Reintentar es lo más seguro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Cancelar el cobro'),
          ),
        ],
      ),
    );
    if (confirmado == true) {
      await ref.read(cobroProvider.notifier).descartarSinConfirmar();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carrito = ref.watch(carritoProvider);
    final resumen = ref.watch(resumenCarritoProvider);
    final cobro = ref.watch(cobroProvider);
    final puedeVender = ref.watch(puedeVenderProvider);

    // Al salir del carrito se cierra el resultado del cobro (venta registrada o error): la próxima vez que se entre
    // se empieza una venta nueva en vez de ver otra vez el comprobante anterior.
    return PopScope(
      onPopInvokedWithResult: (salio, _) {
        if (salio) {
          ref.read(cobroProvider.notifier).aceptarResultado();
        }
      },
      child: Scaffold(
        backgroundColor: Colores.papel,
        appBar: AppBar(
          title: const Text('Carrito'),
          actions: [
            if (!cobro.bloqueaElCarrito)
              IconButton(
                tooltip: 'Actualizar caja y precios',
                icon: const Icon(Icons.refresh),
                onPressed: () => refrescarConAviso(context, ref),
              ),
            if (!resumen.estaVacio && !cobro.bloqueaElCarrito)
              IconButton(
                tooltip: 'Vaciar carrito',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () => _confirmarVaciar(context, ref),
              ),
          ],
        ),
        body: SafeArea(
          child: carrito.cargando || cobro.cargando
              ? const Center(child: CircularProgressIndicator())
              : cobro.fase == FaseCobro.registrada
              ? _VentaRegistrada(
                  cobro: cobro,
                  alTerminar: () =>
                      ref.read(cobroProvider.notifier).aceptarResultado(),
                )
              : cobro.fase == FaseCobro.enviando
              ? _Enviando(cobro: cobro)
              : resumen.estaVacio
              ? _CarritoVacio(
                  puedeVender: puedeVender,
                  alEscanear: () => _abrirEscaner(context),
                  alBuscar: () => _agregarProducto(context, ref),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        itemCount: resumen.lineas.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => _FilaDelCarrito(
                          detalle: resumen.lineas[i],
                          bloqueado: cobro.bloqueaElCarrito,
                          alMas: () {
                            final id = resumen.lineas[i].linea.idProducto;
                            final producto = resumen.lineas[i].producto;
                            final r = ref
                                .read(carritoProvider.notifier)
                                .incrementar(id);
                            if (r == ResultadoAgregar.limiteDeStock &&
                                producto != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(mensajeDeAgregar(r, producto)!),
                                ),
                              );
                            }
                          },
                          alMenos: () => ref
                              .read(carritoProvider.notifier)
                              .decrementar(resumen.lineas[i].linea.idProducto),
                          alQuitar: () => ref
                              .read(carritoProvider.notifier)
                              .quitar(resumen.lineas[i].linea.idProducto),
                        ),
                      ),
                    ),
                    _PieDelCarrito(
                      resumen: resumen,
                      cobro: cobro,
                      puedeVender: puedeVender,
                      alEscanear: () => _abrirEscaner(context),
                      alBuscar: () => _agregarProducto(context, ref),
                      alCobrar: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const CobrarEfectivoScreen(),
                        ),
                      ),
                      alReintentar: () =>
                          ref.read(cobroProvider.notifier).reintentar(),
                      alDescartar: () => _confirmarDescartar(context, ref),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CarritoVacio extends StatelessWidget {
  const _CarritoVacio({
    required this.puedeVender,
    required this.alEscanear,
    required this.alBuscar,
  });

  final bool puedeVender;
  final VoidCallback alEscanear;
  final VoidCallback alBuscar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shopping_cart_outlined,
              size: 56,
              color: Colores.tinta,
            ),
            const SizedBox(height: 12),
            const Text(
              'El carrito está vacío',
              style: TextStyle(fontSize: 18, color: Colores.tinta),
            ),
            const SizedBox(height: 16),
            _BotonesParaAgregar(
              puedeVender: puedeVender,
              alEscanear: alEscanear,
              alBuscar: alBuscar,
              principal: true,
            ),
            if (!puedeVender) ...[
              const SizedBox(height: 8),
              const Text(
                'Abre la caja para escanear.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colores.tinta),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Las dos formas de agregar un producto: escanearlo (con la caja abierta) o buscarlo en la lista. Las mismas con el
/// carrito vacío y con productos, para que el primer producto también se pueda escanear.
class _BotonesParaAgregar extends StatelessWidget {
  const _BotonesParaAgregar({
    required this.puedeVender,
    required this.alEscanear,
    required this.alBuscar,
    this.principal = false,
  });

  final bool puedeVender;
  final VoidCallback alEscanear;
  final VoidCallback alBuscar;

  /// `true` en el carrito vacío: escanear es el botón destacado.
  final bool principal;

  @override
  Widget build(BuildContext context) {
    const icono = Icon(Icons.qr_code_scanner);
    const etiqueta = Text('Escanear producto');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (principal)
          FilledButton.icon(
            onPressed: puedeVender ? alEscanear : null,
            icon: icono,
            label: etiqueta,
          )
        else
          OutlinedButton.icon(
            onPressed: puedeVender ? alEscanear : null,
            icon: icono,
            label: etiqueta,
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: alBuscar,
          icon: const Icon(Icons.search),
          label: const Text('Buscar manualmente'),
        ),
      ],
    );
  }
}

class _FilaDelCarrito extends StatelessWidget {
  const _FilaDelCarrito({
    required this.detalle,
    required this.bloqueado,
    required this.alMas,
    required this.alMenos,
    required this.alQuitar,
  });

  final LineaDetallada detalle;

  /// `true` mientras se cobra: las líneas se ven pero no se pueden cambiar.
  final bool bloqueado;
  final VoidCallback alMas;
  final VoidCallback alMenos;
  final VoidCallback alQuitar;

  @override
  Widget build(BuildContext context) {
    final unitario = detalle.precioUnitarioCentavos;
    final subtotal = detalle.subtotalCentavos;
    final problema = detalle.mensajeDelProblema;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  detalle.nombre,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colores.tinta,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Quitar ${detalle.nombre}',
                icon: const Icon(Icons.delete_outline),
                onPressed: bloqueado ? null : alQuitar,
              ),
            ],
          ),
          Row(
            children: [
              IconButton.outlined(
                tooltip: 'Menos',
                icon: const Icon(Icons.remove),
                onPressed: !bloqueado && detalle.linea.cantidad > 1
                    ? alMenos
                    : null,
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${detalle.linea.cantidad}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton.outlined(
                tooltip: 'Más',
                icon: const Icon(Icons.add),
                onPressed: bloqueado ? null : alMas,
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    subtotal == null
                        ? '—'
                        : formatoPesos(importeDeCentavos(subtotal)),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (unitario != null)
                    Text(
                      '${formatoPesos(importeDeCentavos(unitario))} c/u',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colores.tinta,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          if (problema != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Text(
                problema,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colores.peligro,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PieDelCarrito extends StatelessWidget {
  const _PieDelCarrito({
    required this.resumen,
    required this.cobro,
    required this.puedeVender,
    required this.alEscanear,
    required this.alBuscar,
    required this.alCobrar,
    required this.alReintentar,
    required this.alDescartar,
  });

  final ResumenCarrito resumen;
  final EstadoCobro cobro;
  final bool puedeVender;
  final VoidCallback alEscanear;
  final VoidCallback alBuscar;
  final VoidCallback alCobrar;
  final VoidCallback alReintentar;
  final VoidCallback alDescartar;

  @override
  Widget build(BuildContext context) {
    final sinConfirmar = cobro.fase == FaseCobro.sinConfirmar;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${resumen.unidades} ${resumen.unidades == 1 ? 'unidad' : 'unidades'}',
                style: const TextStyle(color: Colores.tinta),
              ),
              Text(
                'Total: ${formatoPesos(importeDeCentavos(resumen.totalCentavos))}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colores.tinta,
                ),
              ),
            ],
          ),
          if (sinConfirmar) ...[
            const SizedBox(height: 12),
            CuadroDeMensaje(
              '${cobro.mensaje ?? 'No se pudo confirmar la venta.'} No la cobres otra vez: puede que ya esté registrada.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: alReintentar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: alDescartar,
              child: const Text('Cancelar este cobro'),
            ),
          ] else ...[
            if (cobro.fase == FaseCobro.rechazada && cobro.mensaje != null) ...[
              const SizedBox(height: 8),
              CuadroDeMensaje(cobro.mensaje!),
            ],
            if (resumen.hayProblemas) ...[
              const SizedBox(height: 8),
              const CuadroDeMensaje(
                'Revisa los productos marcados en rojo antes de cobrar.',
              ),
            ],
            const SizedBox(height: 12),
            _BotonesParaAgregar(
              puedeVender: puedeVender,
              alEscanear: alEscanear,
              alBuscar: alBuscar,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: resumen.sePuedeCobrar && puedeVender ? alCobrar : null,
              child: const Text('Cobrar en efectivo'),
            ),
            if (!puedeVender) ...[
              const SizedBox(height: 4),
              const Text(
                'Abre la caja para cobrar y escanear.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colores.tinta),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Mientras la venta viaja al servidor (y mientras se reintenta con pausas). No tiene botones: no se debe cobrar dos
/// veces ni cambiar el carrito.
class _Enviando extends StatelessWidget {
  const _Enviando({required this.cobro});

  final EstadoCobro cobro;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text(
              'Registrando la venta…',
              style: TextStyle(fontSize: 18, color: Colores.tinta),
            ),
            if (cobro.intento > 1) ...[
              const SizedBox(height: 4),
              Text(
                'Intento ${cobro.intento}',
                style: const TextStyle(fontSize: 13, color: Colores.tinta),
              ),
            ],
            if (cobro.mensaje != null) ...[
              const SizedBox(height: 12),
              CuadroDeMensaje(cobro.mensaje!, esError: false),
            ],
          ],
        ),
      ),
    );
  }
}

/// El comprobante de la venta ya registrada, con el cambio a devolver.
class _VentaRegistrada extends StatelessWidget {
  const _VentaRegistrada({required this.cobro, required this.alTerminar});

  final EstadoCobro cobro;
  final VoidCallback alTerminar;

  @override
  Widget build(BuildContext context) {
    final venta = cobro.venta;
    final cambio = venta?.cambioCentavos;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle, size: 64, color: Colores.exito),
            const SizedBox(height: 12),
            const Text(
              'Venta registrada',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colores.tinta,
              ),
            ),
            Text(
              'Venta n.º ${cobro.idVenta}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colores.tinta),
            ),
            if (cobro.repetida) ...[
              const SizedBox(height: 12),
              const CuadroDeMensaje(
                'Esta venta ya estaba registrada: se recuperó sin cobrarla otra vez.',
                esError: false,
              ),
            ],
            if (venta != null) ...[
              const SizedBox(height: 20),
              _Renglon(
                'Total',
                formatoPesos(importeDeCentavos(venta.totalCentavos)),
              ),
              if (venta.efectivoRecibido != null)
                _Renglon(
                  'Efectivo recibido',
                  formatoPesosEnteros(venta.efectivoRecibido!),
                ),
              if (cambio != null && cambio >= 0)
                _Renglon(
                  'Cambio a devolver',
                  formatoPesos(importeDeCentavos(cambio)),
                  destacado: true,
                ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: alTerminar,
              child: const Text('Nueva venta'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Renglon extends StatelessWidget {
  const _Renglon(this.etiqueta, this.valor, {this.destacado = false});

  final String etiqueta;
  final String valor;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      fontSize: destacado ? 20 : 16,
      fontWeight: destacado ? FontWeight.w800 : FontWeight.w500,
      color: destacado ? Colores.exito : Colores.tinta,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: estilo),
          Text(valor, style: estilo),
        ],
      ),
    );
  }
}
