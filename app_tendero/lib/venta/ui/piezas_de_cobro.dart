import 'package:flutter/material.dart';

import '../../ui/colores.dart';
import '../../ui/piezas_de_pantalla.dart';

// Los tres estados que comparten TODAS las pantallas de cobro (efectivo, tarjeta, transferencia y fiado) antes de
// mostrar el total: verificando los precios, no se pudo verificar y «el carrito cambió». Viven aquí para que un cambio
// de texto o de comportamiento no haya que repetirlo en cada pantalla.

/// Mientras se vuelve a descargar el catálogo para comprobar los precios.
class VerificandoPrecios extends StatelessWidget {
  const VerificandoPrecios({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text(
          'Verificando los precios…',
          style: TextStyle(fontSize: 16, color: Colores.tinta),
        ),
      ],
    );
  }
}

/// No se pudo descargar el catálogo: no se cobra «a ciegas» con precios que quizá cambiaron.
class NoSePudoVerificarPrecios extends StatelessWidget {
  const NoSePudoVerificarPrecios({
    super.key,
    required this.alReintentar,
    required this.alVolver,
  });

  final VoidCallback alReintentar;
  final VoidCallback alVolver;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CuadroDeMensaje(
          'No se pudo verificar los precios con el servidor, así que no se puede cobrar con seguridad. Revisa tu conexión.',
        ),
        const SizedBox(height: 16),
        BotonPrincipal(texto: 'Reintentar', alPulsar: alReintentar),
        const SizedBox(height: 8),
        TextButton(onPressed: alVolver, child: const Text('Volver al carrito')),
      ],
    );
  }
}

/// Al actualizar el catálogo, algo del carrito dejó de poder cobrarse (sin stock, producto retirado...).
class CarritoCambio extends StatelessWidget {
  const CarritoCambio({super.key, required this.alVolver});

  final VoidCallback alVolver;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CuadroDeMensaje(
          'Al actualizar el catálogo, algunos productos del carrito cambiaron y ya no se pueden cobrar. Revisa los marcados en rojo.',
        ),
        const SizedBox(height: 16),
        BotonPrincipal(texto: 'Volver al carrito', alPulsar: alVolver),
      ],
    );
  }
}
