import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../venta/venta_providers.dart';
import '../carrito_providers.dart';

/// Pregunta antes de vaciar el carrito entero.
Future<void> confirmarVaciarCarrito(BuildContext context, WidgetRef ref) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: const Text('¿Vaciar el carrito?'),
      content: const Text('Se quitarán todos los productos.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(contexto).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(contexto).pop(true),
          child: const Text('Vaciar'),
        ),
      ],
    ),
  );
  if (confirmado == true) {
    ref.read(carritoProvider.notifier).vaciar();
  }
}

/// Renunciar a un cobro sin confirmar es lo único que permite cobrar de nuevo con otra clave. Si el servidor SÍ había
/// registrado la venta, cobrar otra vez la duplicaría: por eso se advierte antes.
Future<void> confirmarDescartarCobro(
  BuildContext context,
  WidgetRef ref,
) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: const Text('¿Cancelar este cobro?'),
      content: const Text(
        'No sabemos si la venta se registró. Si cancelas y la venta SÍ se había registrado, al cobrar de nuevo quedará duplicada. Reintentar es lo más seguro.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(contexto).pop(false),
          child: const Text('Volver'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(contexto).pop(true),
          child: const Text('Cancelar el cobro'),
        ),
      ],
    ),
  );
  if (confirmado == true) {
    await ref.read(cobroProvider.notifier).descartarSinConfirmar();
  }
}
