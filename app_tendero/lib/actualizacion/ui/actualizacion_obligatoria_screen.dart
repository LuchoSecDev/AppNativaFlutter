import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../ui/colores.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../actualizacion_providers.dart';

/// Se muestra EN LUGAR del inicio cuando la versión instalada ya no funciona con el servidor (es menor que la mínima).
/// No hay forma de seguir de largo: solo bajar la versión nueva o cerrar sesión. El botón de atrás no hace nada.
class ActualizacionObligatoriaScreen extends ConsumerWidget {
  const ActualizacionObligatoriaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(actualizacionProvider);
    final nombre = estado.publicada?.versionName ?? '';
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colores.papel,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'StockPilot',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colores.azul,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Hay que actualizar la app',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colores.tinta,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    nombre.isEmpty
                        ? 'Esta versión ya no funciona con el servidor. Descarga la versión nueva para seguir usando StockPilot.'
                        : 'Esta versión ya no funciona con el servidor. Descarga la $nombre para seguir usando StockPilot.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: Colores.tinta),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Cuando termine la descarga, ábrela e instálala. Si el celular lo pide, permite instalar desde el navegador.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colores.tinta),
                  ),
                  if (estado.mensaje != null) ...[
                    const SizedBox(height: 16),
                    CuadroDeMensaje(estado.mensaje!),
                  ],
                  const SizedBox(height: 24),
                  BotonPrincipal(
                    texto: 'Descargar la versión nueva',
                    enEspera: estado.abriendo,
                    alPulsar: () =>
                        ref.read(actualizacionProvider.notifier).descargar(),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        ref.read(sesionProvider.notifier).cerrarSesion(),
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
