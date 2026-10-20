import 'package:flutter/material.dart';

/// Las dos formas de agregar un producto: escanearlo (con la caja abierta) o buscarlo en la lista. Las mismas con el
/// carrito vacío y con productos, para que el primer producto también se pueda escanear.
class BotonesParaAgregar extends StatelessWidget {
  const BotonesParaAgregar({
    super.key,
    required this.puedeVender,
    required this.alEscanear,
    required this.alBuscar,
    this.principal = false,
  });

  final bool puedeVender;
  final VoidCallback alEscanear;
  final VoidCallback alBuscar;

  /// `true` en el carrito vacío: escanear es el botón destacado.
  final bool principal;

  @override
  Widget build(BuildContext context) {
    const icono = Icon(Icons.qr_code_scanner);
    const etiqueta = Text('Escanear producto');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (principal)
          FilledButton.icon(
            onPressed: puedeVender ? alEscanear : null,
            icon: icono,
            label: etiqueta,
          )
        else
          OutlinedButton.icon(
            onPressed: puedeVender ? alEscanear : null,
            icon: icono,
            label: etiqueta,
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: alBuscar,
          icon: const Icon(Icons.search),
          label: const Text('Buscar manualmente'),
        ),
      ],
    );
  }
}
