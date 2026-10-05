import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_providers.dart';
import 'caja/caja_providers.dart';
import 'caja/ui/tarjeta_de_caja.dart';
import 'catalogo/ui/buscar_producto_screen.dart';
import 'scanner_screen.dart';
import 'ui/colores.dart';

/// Pantalla de inicio una vez que hay sesión: quién entró, el estado de la caja y las acciones disponibles.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(sesionProvider);
    final info = estado.info;
    final puedeVender = ref.watch(puedeVenderProvider);

    return Scaffold(
      backgroundColor: Colores.papel,
      appBar: AppBar(
        title: const Text('StockPilot'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: estado.trabajando
                ? null
                : () => ref.read(sesionProvider.notifier).cerrarSesion(),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Hola, ${info?.nombres ?? ''}',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colores.tinta,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${info?.tiendaNombre ?? ''} · ${info?.rol ?? ''}',
              style: const TextStyle(fontSize: 14, color: Colores.tinta),
            ),
            const SizedBox(height: 24),
            const TarjetaDeCaja(),
            const SizedBox(height: 16),
            // Solo se ofrece vender con la caja abierta (el servidor también lo exige: 403 sin caja abierta).
            FilledButton.icon(
              onPressed: puedeVender
                  ? () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'La pantalla de venta llega en el siguiente paso.',
                        ),
                      ),
                    )
                  : null,
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Vender'),
            ),
            if (!puedeVender) ...[
              const SizedBox(height: 4),
              const Text(
                'Abre la caja para vender.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colores.tinta),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BuscarProductoScreen(),
                ),
              ),
              icon: const Icon(Icons.search),
              label: const Text('Consultar productos'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ScannerScreen()),
              ),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Probar el escáner'),
            ),
          ],
        ),
      ),
    );
  }
}
