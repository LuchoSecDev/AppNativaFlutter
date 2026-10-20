import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/piezas_de_pantalla.dart';
import '../cierre_providers.dart';

/// No se sabe si la caja se cerró: solo se puede comprobar, nunca cerrar otra vez.
class CierreSinConfirmar extends ConsumerWidget {
  const CierreSinConfirmar({super.key, required this.cierre});

  final EstadoCierre cierre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CuadroDeMensaje(
          cierre.mensaje ?? 'No sabemos si la caja se cerró. Toca «Comprobar»; no la cierres otra vez.',
        ),
        const SizedBox(height: 16),
        BotonPrincipal(
          texto: 'Comprobar',
          alPulsar: () => ref.read(cierreProvider.notifier).comprobar(),
        ),
      ],
    );
  }
}
