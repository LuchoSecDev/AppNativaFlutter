import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalogo/producto.dart';
import '../../catalogo/ui/buscar_producto_screen.dart';
import '../../ui/colores.dart';
import '../../ui/dinero.dart';
import '../../ui/formato.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../carrito_models.dart';
import '../carrito_providers.dart';

/// El carrito de la venta en curso: productos, cantidades, total y los problemas que impiden cobrar.
///
/// El carrito se guarda en el celular: si la app se cierra o la sesión caduca a mitad de una venta, al volver sigue
/// aquí.
class CarritoScreen extends ConsumerWidget {
  const CarritoScreen({super.key});

  /// Qué decirle al usuario cuando no se pudo agregar un producto. `null` si se agregó.
  static String? mensajeDeAgregar(
    ResultadoAgregar r,
    Producto p,
  ) => switch (r) {
    ResultadoAgregar.agregado => null,
    ResultadoAgregar.agotado => '«${p.nombre}» está agotado.',
    ResultadoAgregar.noDisponible => '«${p.nombre}» está inactivo.',
    ResultadoAgregar.sinPrecio =>
      '«${p.nombre}» no tiene precio. Pide al administrador que se lo asigne.',
    ResultadoAgregar.limiteDeStock =>
      'Ya agregaste todas las unidades que hay de «${p.nombre}».',
    ResultadoAgregar.cargando => 'Un momento: se está preparando el carrito.',
  };

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carrito = ref.watch(carritoProvider);
    final resumen = ref.watch(resumenCarritoProvider);

    return Scaffold(
      backgroundColor: Colores.papel,
      appBar: AppBar(
        title: const Text('Carrito'),
        actions: [
          if (!resumen.estaVacio)
            IconButton(
              tooltip: 'Vaciar carrito',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _confirmarVaciar(context, ref),
            ),
        ],
      ),
      body: SafeArea(
        child: carrito.cargando
            ? const Center(child: CircularProgressIndicator())
            : resumen.estaVacio
            ? _CarritoVacio(alAgregar: () => _agregarProducto(context, ref))
            : Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      itemCount: resumen.lineas.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) => _FilaDelCarrito(
                        detalle: resumen.lineas[i],
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
                    alAgregar: () => _agregarProducto(context, ref),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CarritoVacio extends StatelessWidget {
  const _CarritoVacio({required this.alAgregar});

  final VoidCallback alAgregar;

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
            FilledButton.icon(
              onPressed: alAgregar,
              icon: const Icon(Icons.add),
              label: const Text('Agregar producto'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaDelCarrito extends StatelessWidget {
  const _FilaDelCarrito({
    required this.detalle,
    required this.alMas,
    required this.alMenos,
    required this.alQuitar,
  });

  final LineaDetallada detalle;
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
                onPressed: alQuitar,
              ),
            ],
          ),
          Row(
            children: [
              IconButton.outlined(
                tooltip: 'Menos',
                icon: const Icon(Icons.remove),
                onPressed: detalle.linea.cantidad > 1 ? alMenos : null,
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
                onPressed: alMas,
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
  const _PieDelCarrito({required this.resumen, required this.alAgregar});

  final ResumenCarrito resumen;
  final VoidCallback alAgregar;

  @override
  Widget build(BuildContext context) {
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
          if (resumen.hayProblemas) ...[
            const SizedBox(height: 8),
            const CuadroDeMensaje(
              'Revisa los productos marcados en rojo antes de cobrar.',
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: alAgregar,
            icon: const Icon(Icons.add),
            label: const Text('Agregar producto'),
          ),
          const SizedBox(height: 8),
          // El cobro llega en el siguiente subpaso. Se deja el botón visible y bloqueado para que se vea el flujo.
          const FilledButton(
            onPressed: null,
            child: Text('Cobrar (próximamente)'),
          ),
        ],
      ),
    );
  }
}
