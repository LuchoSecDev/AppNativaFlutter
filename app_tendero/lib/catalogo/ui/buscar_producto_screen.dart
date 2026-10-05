import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/colores.dart';
import '../../ui/dinero.dart';
import '../../ui/formato.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../buscar_productos.dart';
import '../catalogo_providers.dart';
import '../producto.dart';

/// Pantalla para buscar un producto escribiendo su nombre, categoría o código.
///
/// Con [alElegir] sirve para ELEGIR un producto (la usa el carrito): al tocar uno se llama a esa función, que decide
/// si lo acepta. Si devuelve `null` se vuelve atrás; si devuelve un texto (por ejemplo «está agotado») se muestra y
/// se sigue en la pantalla. Sin [alElegir] es una consulta: al tocar un producto se muestran sus datos.
class BuscarProductoScreen extends ConsumerStatefulWidget {
  const BuscarProductoScreen({super.key, this.alElegir});

  final String? Function(Producto producto)? alElegir;

  @override
  ConsumerState<BuscarProductoScreen> createState() =>
      _BuscarProductoScreenState();
}

class _BuscarProductoScreenState extends ConsumerState<BuscarProductoScreen> {
  final _campo = TextEditingController();
  String _consulta = '';

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  void _tocar(Producto producto) {
    if (widget.alElegir == null) {
      _mostrarDatos(producto);
      return;
    }
    // Quien elige decide si acepta el producto: si no, devuelve el motivo y se queda en la pantalla.
    final rechazo = widget.alElegir!(producto);
    if (rechazo != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(rechazo)));
      return;
    }
    Navigator.of(context).pop(producto);
  }

  void _mostrarDatos(Producto p) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.nombre,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colores.tinta,
              ),
            ),
            const SizedBox(height: 12),
            Text('Precio: ${formatoPesos(p.precio)}'),
            Text(
              'Stock: ${p.cantidad} ${p.cantidad == 1 ? 'unidad' : 'unidades'}',
            ),
            if (p.categoria.isNotEmpty) Text('Categoría: ${p.categoria}'),
            if (p.codigo.isNotEmpty) Text('Código: ${p.codigo}'),
            Text(
              p.codigoBarras == null
                  ? 'Código de barras: sin asociar'
                  : 'Código de barras: ${p.codigoBarras}',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = ref.watch(catalogoProvider);
    final resultados = buscarProductos(catalogo.productos, _consulta);

    return Scaffold(
      backgroundColor: Colores.papel,
      appBar: AppBar(
        title: Text(widget.alElegir == null ? 'Productos' : 'Elegir producto'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _campo,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => _consulta = v),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre, categoría o código',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: _consulta.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Borrar búsqueda',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _campo.clear();
                            setState(() => _consulta = '');
                          },
                        ),
                ),
              ),
            ),
            if (catalogo.mensaje != null && catalogo.fase == FaseCatalogo.listo)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: CuadroDeMensaje(catalogo.mensaje!, esError: false),
              ),
            Expanded(child: _cuerpo(catalogo, resultados)),
          ],
        ),
      ),
    );
  }

  Widget _cuerpo(EstadoCatalogo catalogo, List<Producto> resultados) {
    switch (catalogo.fase) {
      case FaseCatalogo.cargando:
        return const Center(child: CircularProgressIndicator());
      case FaseCatalogo.error:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CuadroDeMensaje(
                catalogo.mensaje ?? 'No se pudo cargar los productos.',
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.read(catalogoProvider.notifier).cargar(),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        );
      case FaseCatalogo.listo:
        return RefreshIndicator(
          onRefresh: () => ref.read(catalogoProvider.notifier).cargar(),
          child: resultados.isEmpty
              ? ListView(
                  // Siempre desplazable: así se puede «tirar para actualizar» aunque no haya resultados.
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      _consulta.trim().isEmpty
                          ? 'La tienda no tiene productos disponibles.'
                          : 'No encontré productos con «${_consulta.trim()}».',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colores.tinta),
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: resultados.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _FilaDeProducto(
                    producto: resultados[i],
                    alTocar: () => _tocar(resultados[i]),
                  ),
                ),
        );
    }
  }
}

class _FilaDeProducto extends StatelessWidget {
  const _FilaDeProducto({required this.producto, required this.alTocar});

  final Producto producto;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final agotado = producto.agotado;
    final centavos = centavosDeImporte(producto.precio);
    final sinPrecio = centavos == null || centavos <= 0;
    return ListTile(
      onTap: alTocar,
      tileColor: Colors.white,
      title: Text(
        producto.nombre,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: agotado ? Colors.black45 : Colores.tinta,
        ),
      ),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              [
                if (producto.categoria.isNotEmpty) producto.categoria,
                'Stock: ${producto.cantidad}',
              ].join(' · '),
            ),
          ),
          if (agotado) ...[
            const SizedBox(width: 8),
            const _Etiqueta('Agotado', Colores.peligro, Colores.peligroSuave),
          ],
          // Sin precio (0 o ilegible): casi siempre es un error de datos y no se puede vender.
          if (sinPrecio) ...[
            const SizedBox(width: 8),
            const _Etiqueta('Sin precio', Colores.aviso, Colores.avisoSuave),
          ],
        ],
      ),
      trailing: Text(
        formatoPesos(producto.precio),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto, this.color, this.fondo);

  final String texto;
  final Color color;
  final Color fondo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
