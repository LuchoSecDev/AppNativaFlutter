import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../caja/caja_providers.dart';
import '../../catalogo/ui/buscar_producto_screen.dart';
import '../../ui/avisos.dart';
import '../../ui/colores.dart';
import '../../ui/refrescar.dart';
import '../../venta/ui/escaner_venta_screen.dart';
import '../../venta/ui/selector_pago_screen.dart';
import '../../venta/venta_providers.dart';
import '../carrito_models.dart';
import '../carrito_providers.dart';
import 'carrito_vacio.dart';
import 'cobro_enviando.dart';
import 'dialogos_del_carrito.dart';
import 'fila_del_carrito.dart';
import 'pie_del_carrito.dart';
import 'venta_registrada.dart';

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
      mostrarAviso(context, 'Agregado: $agregado', tipo: TipoAviso.exito);
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
                onPressed: () => confirmarVaciarCarrito(context, ref),
              ),
          ],
        ),
        body: SafeArea(
          child: carrito.cargando || cobro.cargando
              ? const Center(child: CircularProgressIndicator())
              : cobro.fase == FaseCobro.registrada
              ? VentaRegistrada(
                  cobro: cobro,
                  alTerminar: () =>
                      ref.read(cobroProvider.notifier).aceptarResultado(),
                )
              : cobro.fase == FaseCobro.enviando
              ? CobroEnviando(cobro: cobro)
              : resumen.estaVacio
              ? CarritoVacio(
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
                        itemBuilder: (_, i) => FilaDelCarrito(
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
                              mostrarAviso(
                                context,
                                mensajeDeAgregar(r, producto)!,
                                tipo: TipoAviso.aviso,
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
                    PieDelCarrito(
                      resumen: resumen,
                      cobro: cobro,
                      puedeVender: puedeVender,
                      alEscanear: () => _abrirEscaner(context),
                      alBuscar: () => _agregarProducto(context, ref),
                      alCobrar: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const SelectorPagoScreen(),
                        );
                      },
                      alReintentar: () =>
                          ref.read(cobroProvider.notifier).reintentar(),
                      alDescartar: () => confirmarDescartarCobro(context, ref),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
