import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../carrito/carrito_providers.dart';
import '../../catalogo/catalogo_providers.dart';
import '../../ui/colores.dart';
import '../../ui/dinero.dart';
import '../../ui/formato.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../venta_models.dart';
import '../venta_providers.dart';
import 'piezas_de_cobro.dart';

/// Cobrar el carrito con método digital (Tarjeta o Transferencia).
///
/// Solo muestra el total para confirmar. Al igual que el cobro en efectivo,
/// primero debe verificar los precios actuales del catálogo.
class CobrarDigitalScreen extends ConsumerStatefulWidget {
  const CobrarDigitalScreen({super.key, required this.metodoPago});

  final MetodoPago metodoPago;

  @override
  ConsumerState<CobrarDigitalScreen> createState() =>
      _CobrarDigitalScreenState();
}

class _CobrarDigitalScreenState extends ConsumerState<CobrarDigitalScreen> {
  late final int _totalAlAbrir;
  bool? _preciosAlDia;

  @override
  void initState() {
    super.initState();
    _totalAlAbrir = ref.read(resumenCarritoProvider).totalCentavos;
    Future.microtask(_verificarPrecios);
  }

  Future<void> _verificarPrecios() async {
    setState(() => _preciosAlDia = null);
    final alDia = await ref.read(catalogoProvider.notifier).cargar();
    if (mounted) {
      setState(() => _preciosAlDia = alDia);
    }
  }

  void _cobrar() {
    ref.read(cobroProvider.notifier).cobrar(metodo: widget.metodoPago);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final resumen = ref.watch(resumenCarritoProvider);
    final total = resumen.totalCentavos;

    return Scaffold(
      backgroundColor: Colores.papel,
      appBar: AppBar(title: Text('Cobrar con ${widget.metodoPago.valorApi}')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: switch (_preciosAlDia) {
                null => const VerificandoPrecios(),
                false => NoSePudoVerificarPrecios(
                  alReintentar: _verificarPrecios,
                  alVolver: () => Navigator.of(context).pop(),
                ),
                true =>
                  !resumen.sePuedeCobrar
                      ? CarritoCambio(
                          alVolver: () => Navigator.of(context).pop(),
                        )
                      : _ConfirmarCobro(
                          total: total,
                          totalAlAbrir: _totalAlAbrir,
                          metodoPago: widget.metodoPago,
                          alCobrar: _cobrar,
                        ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmarCobro extends StatelessWidget {
  const _ConfirmarCobro({
    required this.total,
    required this.totalAlAbrir,
    required this.metodoPago,
    required this.alCobrar,
  });

  final int total;
  final int totalAlAbrir;
  final MetodoPago metodoPago;
  final VoidCallback alCobrar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          metodoPago == MetodoPago.tarjeta
              ? Icons.credit_card
              : Icons.account_balance,
          size: 64,
          color: Colores.tinta,
        ),
        const SizedBox(height: 16),
        const Text(
          'Total a cobrar',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colores.tinta),
        ),
        Text(
          formatoPesos(importeDeCentavos(total)),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: Colores.tinta,
          ),
        ),
        if (total != totalAlAbrir) ...[
          const SizedBox(height: 12),
          CuadroDeMensaje(
            'El total cambió al actualizar los precios: antes era ${formatoPesos(importeDeCentavos(totalAlAbrir))}.',
            esError: false,
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Asegúrate de que el cliente haya realizado el pago por ${metodoPago.valorApi} antes de confirmar.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Colores.tinta),
        ),
        const SizedBox(height: 32),
        BotonPrincipal(texto: 'Confirmar pago recibido', alPulsar: alCobrar),
      ],
    );
  }
}
