import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_providers.dart';
import 'carrito/carrito_providers.dart';
import 'carrito/ui/carrito_screen.dart';
import 'caja/caja_providers.dart';
import 'caja/ui/tarjeta_de_caja.dart';
import 'catalogo/ui/buscar_producto_screen.dart';
import 'scanner_screen.dart';
import 'ui/colores.dart';
import 'ui/dinero.dart';
import 'ui/formato.dart';
import 'ui/piezas_de_pantalla.dart';
import 'venta/venta_providers.dart';

/// Pantalla de inicio una vez que hay sesión: quién entró, el estado de la caja y las acciones disponibles.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(sesionProvider);
    final info = estado.info;
    final puedeVender = ref.watch(puedeVenderProvider);
    final carrito = ref.watch(resumenCarritoProvider);
    final cobro = ref.watch(cobroProvider);

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
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CarritoScreen(),
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
            // Recordatorio: el carrito se guarda en el celular, así que puede haber una venta a medias.
            if (!carrito.estaVacio) ...[
              const SizedBox(height: 4),
              Text(
                'Carrito: ${carrito.unidades} ${carrito.unidades == 1 ? 'unidad' : 'unidades'} · ${formatoPesos(importeDeCentavos(carrito.totalCentavos))}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colores.tinta),
              ),
            ],
            // Una venta de la que no se sabe si quedó registrada no se puede olvidar: se avisa desde el inicio.
            if (cobro.fase == FaseCobro.sinConfirmar) ...[
              const SizedBox(height: 8),
              const CuadroDeMensaje(
                'Hay una venta sin confirmar. Abre «Vender» para reintentarla; no la cobres otra vez.',
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
