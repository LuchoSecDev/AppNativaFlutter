import 'package:flutter/material.dart';

import '../../ui/colores.dart';
import '../venta_models.dart';
import 'cobrar_digital_screen.dart';
import 'cobrar_efectivo_screen.dart';
import 'cobrar_fiado_screen.dart';

/// Hoja inferior para elegir cómo se cobra (Efectivo, Tarjeta, Transferencia o Fiado). Solo elige: cada método tiene
/// su propia pantalla, que verifica los precios y confirma.
class SelectorPagoScreen extends StatelessWidget {
  const SelectorPagoScreen({super.key});

  /// Cierra la hoja y abre la pantalla del método. El navegador se toma ANTES de cerrar: después de `pop` el
  /// contexto de la hoja ya está saliendo del árbol.
  void _ir(BuildContext context, Widget pantalla) {
    final navegador = Navigator.of(context);
    navegador.pop();
    navegador.push(MaterialPageRoute<void>(builder: (_) => pantalla));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: Colores.papel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              '¿Cómo vas a cobrar?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colores.tinta,
              ),
            ),
            const SizedBox(height: 24),
            _OpcionPago(
              icono: Icons.payments_outlined,
              titulo: 'Efectivo',
              subtitulo: 'Recibe dinero físico y calcula el cambio',
              alPulsar: () => _ir(context, const CobrarEfectivoScreen()),
            ),
            const SizedBox(height: 12),
            _OpcionPago(
              icono: Icons.credit_card_outlined,
              titulo: 'Tarjeta',
              subtitulo: 'Pago por datáfono',
              alPulsar: () => _ir(
                context,
                const CobrarDigitalScreen(metodoPago: MetodoPago.tarjeta),
              ),
            ),
            const SizedBox(height: 12),
            _OpcionPago(
              icono: Icons.account_balance_outlined,
              titulo: 'Transferencia',
              subtitulo: 'Nequi, Daviplata o banco',
              alPulsar: () => _ir(
                context,
                const CobrarDigitalScreen(metodoPago: MetodoPago.transferencia),
              ),
            ),
            const SizedBox(height: 12),
            _OpcionPago(
              icono: Icons.handshake_outlined,
              titulo: 'Fiado',
              subtitulo: 'Selecciona al cliente para fiar la compra',
              alPulsar: () => _ir(context, const CobrarFiadoScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpcionPago extends StatelessWidget {
  const _OpcionPago({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.alPulsar,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: alPulsar,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colores.papel,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icono, color: Colores.azul, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colores.tinta,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }
}
