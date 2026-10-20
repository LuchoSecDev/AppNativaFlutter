import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../carrito/carrito_providers.dart';
import '../../catalogo/catalogo_providers.dart';
import '../../clientes/cliente.dart';
import '../../clientes/clientes_providers.dart';
import '../../ui/colores.dart';
import '../venta_models.dart';
import '../venta_providers.dart';
import 'fiado_confirmar.dart';
import 'fiado_elegir_cliente.dart';
import 'fiado_formato.dart';
import 'piezas_de_cobro.dart';

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
                ? ElegirCliente(
                    controladorBusqueda: _busqueda,
                    avisoDeTotal: resumen.totalCentavos != _totalAlAbrir
                        ? 'El total cambió al actualizar los precios: antes era ${pesosDeCentavos(_totalAlAbrir)}.'
                        : null,
                    alElegir: (c) {
                      FocusScope.of(context).unfocus();
                      setState(() => _cliente = c);
                    },
                  )
                : _centrado(
                    ConfirmarFiado(
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
