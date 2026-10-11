import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../carrito/carrito_providers.dart';
import '../../catalogo/catalogo_providers.dart';
import '../../clientes/cliente.dart';
import '../../clientes/clientes_providers.dart';
import '../../ui/colores.dart';
import '../../ui/dinero.dart';
import '../../ui/formato.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../venta_models.dart';
import '../venta_providers.dart';
import 'piezas_de_cobro.dart';

String _pesos(int centavos) => formatoPesos(importeDeCentavos(centavos));

/// Cobrar el carrito «fiado»: se elige a qué cliente de la tienda se le fía y se confirma viendo cuánto quedaría
/// debiendo.
///
/// Igual que el cobro en efectivo, primero se VUELVEN A DESCARGAR los precios (el servidor cobra con los suyos), y
/// además la lista de clientes, porque sus saldos cambian con cada venta fiada y cada abono. El cupo que se muestra
/// es una ayuda: quien decide es el servidor (`[V2]`, 400 si se pasa del cupo; 404 si el cliente no es de la tienda).
/// El Tendero no puede crear clientes ni registrar abonos (decisión D4): solo elige entre los que ya existen.
class CobrarFiadoScreen extends ConsumerStatefulWidget {
  const CobrarFiadoScreen({super.key});

  @override
  ConsumerState<CobrarFiadoScreen> createState() => _CobrarFiadoScreenState();
}

class _CobrarFiadoScreenState extends ConsumerState<CobrarFiadoScreen> {
  final _busqueda = TextEditingController();

  /// El total que tenía el carrito al pulsar «Cobrar»: sirve para avisar si la verificación lo cambió.
  late final int _totalAlAbrir;

  /// `null` mientras se verifica; `true` si los precios quedaron al día; `false` si no se pudo verificar.
  bool? _preciosAlDia;

  Cliente? _cliente;

  @override
  void initState() {
    super.initState();
    _totalAlAbrir = ref.read(resumenCarritoProvider).totalCentavos;
    _busqueda.addListener(() => setState(() {}));
    // Riverpod no deja cambiar un provider mientras se construye el árbol de widgets: se espera a que termine.
    Future.microtask(_verificarPrecios);
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _verificarPrecios() async {
    setState(() => _preciosAlDia = null);
    final alDia = await ref.read(catalogoProvider.notifier).cargar();
    if (!mounted) return;
    setState(() => _preciosAlDia = alDia);
    if (alDia) {
      ref.read(clientesProvider.notifier).cargar();
    }
  }

  void _cobrar() {
    final cliente = _cliente;
    if (cliente == null) return;
    // No se espera el resultado aquí: la pantalla del carrito muestra el envío, los reintentos y el desenlace.
    ref
        .read(cobroProvider.notifier)
        .cobrar(metodo: MetodoPago.fiado, cliente: cliente);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final resumen = ref.watch(resumenCarritoProvider);
    final cliente = _cliente;

    return Scaffold(
      backgroundColor: Colores.papel,
      appBar: AppBar(title: const Text('Fiar compra')),
      body: SafeArea(
        child: switch (_preciosAlDia) {
          null => const Center(child: VerificandoPrecios()),
          false => _centrado(
            NoSePudoVerificarPrecios(
              alReintentar: _verificarPrecios,
              alVolver: () => Navigator.of(context).pop(),
            ),
          ),
          true =>
            !resumen.sePuedeCobrar
                ? _centrado(
                    CarritoCambio(alVolver: () => Navigator.of(context).pop()),
                  )
                : cliente == null
                ? _ElegirCliente(
                    controladorBusqueda: _busqueda,
                    avisoDeTotal: resumen.totalCentavos != _totalAlAbrir
                        ? 'El total cambió al actualizar los precios: antes era ${_pesos(_totalAlAbrir)}.'
                        : null,
                    alElegir: (c) {
                      FocusScope.of(context).unfocus();
                      setState(() => _cliente = c);
                    },
                  )
                : _centrado(
                    _ConfirmarFiado(
                      total: resumen.totalCentavos,
                      totalAlAbrir: _totalAlAbrir,
                      cliente: cliente,
                      alElegirOtro: () => setState(() => _cliente = null),
                      alCobrar: _cobrar,
                    ),
                  ),
        },
      ),
    );
  }

  Widget _centrado(Widget hijo) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: hijo,
      ),
    ),
  );
}

/// Buscador y lista de los clientes de la tienda.
class _ElegirCliente extends ConsumerWidget {
  const _ElegirCliente({
    required this.controladorBusqueda,
    required this.avisoDeTotal,
    required this.alElegir,
  });

  final TextEditingController controladorBusqueda;
  final String? avisoDeTotal;
  final ValueChanged<Cliente> alElegir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(clientesProvider);

    return Column(
      children: [
        if (avisoDeTotal != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: CuadroDeMensaje(avisoDeTotal!, esError: false),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: controladorBusqueda,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar cliente por nombre',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: controladorBusqueda.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Borrar la búsqueda',
                      onPressed: controladorBusqueda.clear,
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: switch (estado.fase) {
            FaseClientes.cargando => const Center(
              child: CircularProgressIndicator(),
            ),
            FaseClientes.error => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CuadroDeMensaje(
                      estado.mensajeError ??
                          'No se pudo cargar la lista de clientes.',
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(clientesProvider.notifier).cargar(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
            FaseClientes.listo => _ListaDeClientes(
              consulta: controladorBusqueda.text,
              alElegir: alElegir,
            ),
          },
        ),
      ],
    );
  }
}

class _ListaDeClientes extends ConsumerWidget {
  const _ListaDeClientes({required this.consulta, required this.alElegir});

  final String consulta;
  final ValueChanged<Cliente> alElegir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientes = ref.watch(clientesFiltradosProvider(consulta));

    if (clientes.isEmpty) {
      final hayClientes = ref.watch(clientesProvider).clientes.isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            hayClientes ? 'No se encontraron clientes con ese nombre.' : 'Esta tienda todavía no tiene clientes. El Administrador los registra desde la web.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colores.tinta),
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: clientes.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = clientes[i];
        final cupo = c.sinTope
            ? 'sin tope'
            : 'cupo ${_pesos(c.limiteCreditoCentavos)}';
        return ListTile(
          title: Text(
            c.nombre,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text('Debe ${_pesos(c.saldoPendienteCentavos)} · $cupo'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => alElegir(c),
        );
      },
    );
  }
}

class _ConfirmarFiado extends StatelessWidget {
  const _ConfirmarFiado({
    required this.total,
    required this.totalAlAbrir,
    required this.cliente,
    required this.alElegirOtro,
    required this.alCobrar,
  });

  final int total;
  final int totalAlAbrir;
  final Cliente cliente;
  final VoidCallback alElegirOtro;
  final VoidCallback alCobrar;

  @override
  Widget build(BuildContext context) {
    final alcanza = cliente.alcanzaCupo(total);
    final nuevoSaldo = cliente.saldoPendienteCentavos + total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Elegir otro cliente',
              onPressed: alElegirOtro,
            ),
            const Text(
              'Confirmar fiado',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colores.tinta,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            children: [
              Text(
                cliente.nombre,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colores.tinta,
                ),
              ),
              const SizedBox(height: 16),
              _Fila('Total de la compra', _pesos(total), negrita: true),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(),
              ),
              _Fila('Debe ahora', _pesos(cliente.saldoPendienteCentavos)),
              const SizedBox(height: 4),
              _Fila(
                'Quedaría debiendo',
                _pesos(nuevoSaldo),
                negrita: true,
                color: alcanza ? Colores.azul : Colores.peligro,
              ),
              const SizedBox(height: 4),
              _Fila(
                'Cupo',
                cliente.sinTope
                    ? 'Sin tope'
                    : _pesos(cliente.limiteCreditoCentavos),
              ),
            ],
          ),
        ),
        if (total != totalAlAbrir) ...[
          const SizedBox(height: 12),
          CuadroDeMensaje(
            'El total cambió al actualizar los precios: antes era ${_pesos(totalAlAbrir)}.',
            esError: false,
          ),
        ],
        if (!alcanza) ...[
          const SizedBox(height: 16),
          CuadroDeMensaje(
            'Esta venta supera el cupo de crédito del cliente: ya debe ${_pesos(cliente.saldoPendienteCentavos)} de un cupo de ${_pesos(cliente.limiteCreditoCentavos)}. No se puede fiar esta cantidad.',
          ),
        ],
        const SizedBox(height: 24),
        BotonPrincipal(
          texto: 'Confirmar fiado',
          alPulsar: alcanza ? alCobrar : null,
        ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila(this.titulo, this.valor, {this.negrita = false, this.color});

  final String titulo;
  final String valor;
  final bool negrita;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(titulo, style: const TextStyle(color: Colores.tinta)),
        Text(
          valor,
          style: TextStyle(
            fontWeight: negrita ? FontWeight.w700 : FontWeight.w400,
            color: color ?? Colores.tinta,
          ),
        ),
      ],
    );
  }
}
