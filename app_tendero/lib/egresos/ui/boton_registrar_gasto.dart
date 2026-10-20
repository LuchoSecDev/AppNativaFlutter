import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/colores.dart';
import '../egreso_estado.dart';
import '../egreso_providers.dart';
import 'registrar_egreso_screen.dart';

/// El botón de la tarjeta de caja que abre el registro de un gasto. Si quedó un gasto sin confirmar, lo dice y lo
/// destaca: la persona debe resolverlo (reintentar) antes de registrar otro.
class BotonRegistrarGasto extends ConsumerWidget {
  const BotonRegistrarGasto({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sinConfirmar = ref.watch(
      egresoProvider.select((e) => e.fase == FaseEgreso.sinConfirmar),
    );
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const RegistrarEgresoScreen()),
      ),
      style: sinConfirmar
          ? OutlinedButton.styleFrom(foregroundColor: Colores.aviso)
          : null,
      icon: Icon(
        sinConfirmar
            ? Icons.warning_amber_rounded
            : Icons.receipt_long_outlined,
      ),
      label: Text(sinConfirmar ? 'Gasto sin confirmar' : 'Registrar gasto'),
    );
  }
}
