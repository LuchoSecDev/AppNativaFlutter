import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/colores.dart';
import '../../ui/formato.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../../ui/reloj.dart';
import '../caja_providers.dart';
import 'abrir_caja_screen.dart';
import 'cerrar_caja_screen.dart';

/// La tarjeta de la pantalla de inicio que muestra el estado de la caja: cargando, cerrada (con el botón para
/// abrirla), abierta (con el efectivo inicial y la hora) o con error (con «Reintentar»).
class TarjetaDeCaja extends ConsumerWidget {
  const TarjetaDeCaja({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caja = ref.watch(cajaProvider);
    final ahora = ref.watch(ahoraProvider);

    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: switch (caja.fase) {
            FaseCaja.cargando => [
              const Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Consultando la caja…',
                    style: TextStyle(color: Colores.tinta),
                  ),
                ],
              ),
            ],
            FaseCaja.error => [
              CuadroDeMensaje(caja.mensaje ?? 'No se pudo consultar la caja.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.read(cajaProvider.notifier).cargar(),
                child: const Text('Reintentar'),
              ),
            ],
            FaseCaja.cerrada => [
              _Titulo(
                icono: Icons.lock_outline,
                texto: 'Caja cerrada',
                color: Colores.aviso,
                alActualizar: () =>
                    ref.read(cajaProvider.notifier).actualizar(),
              ),
              const SizedBox(height: 4),
              const Text(
                'Abre la caja para poder vender.',
                style: TextStyle(color: Colores.tinta),
              ),
              if (caja.mensaje != null) ...[
                const SizedBox(height: 12),
                CuadroDeMensaje(caja.mensaje!),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AbrirCajaScreen(),
                  ),
                ),
                child: const Text('Abrir caja'),
              ),
            ],
            FaseCaja.abierta => [
              _Titulo(
                icono: Icons.lock_open,
                texto: 'Caja abierta',
                color: Colores.exito,
                alActualizar: () =>
                    ref.read(cajaProvider.notifier).actualizar(),
              ),
              const SizedBox(height: 4),
              Text(
                'Efectivo inicial: ${formatoPesos(caja.sesion!.montoApertura)}',
                style: const TextStyle(color: Colores.tinta),
              ),
              if (descripcionDeFecha(caja.sesion!.fechaApertura, ahora: ahora)
                  case final cuando?)
                Text(
                  'Abierta $cuando',
                  style: const TextStyle(color: Colores.tinta),
                ),
              // Una caja que se quedó abierta de un día anterior descuadra el arqueo de hoy: se avisa para que
              // se cierre (por ahora, desde la web) antes de empezar a vender.
              if (esDeUnDiaAnterior(
                caja.sesion!.fechaApertura,
                ahora: ahora,
              )) ...[
                const SizedBox(height: 12),
                const CuadroDeMensaje(
                  'Esta caja se abrió en un día anterior. Ciérrala antes de empezar el turno de hoy.',
                  esError: false,
                ),
              ],
              if (caja.mensaje != null) ...[
                const SizedBox(height: 12),
                CuadroDeMensaje(caja.mensaje!, esError: false),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CerrarCajaScreen(),
                  ),
                ),
                icon: const Icon(Icons.lock_outline),
                label: const Text('Cerrar caja'),
              ),
            ],
          },
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo({
    required this.icono,
    required this.texto,
    required this.color,
    required this.alActualizar,
  });

  final IconData icono;
  final String texto;
  final Color color;

  /// Vuelve a consultar la caja: puede haber cambiado desde la web.
  final VoidCallback alActualizar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Actualizar la caja',
          icon: const Icon(Icons.refresh),
          color: Colores.tinta,
          onPressed: alActualizar,
        ),
      ],
    );
  }
}
