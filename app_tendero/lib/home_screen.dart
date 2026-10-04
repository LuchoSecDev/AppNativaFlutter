import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_providers.dart';
import 'scanner_screen.dart';
import 'ui/colores.dart';

/// Pantalla de inicio una vez que hay sesión. Por ahora es un marcador: muestra quién entró y desde aquí se
/// abre la prueba del escáner. Aquí irán después la caja y las ventas.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(sesionProvider);
    final info = estado.info;

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
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ScannerScreen()),
              ),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Probar el escáner'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Próximamente: abrir caja, vender y cerrar caja.',
              style: TextStyle(fontSize: 13, color: Colores.tinta),
            ),
          ],
        ),
      ),
    );
  }
}
