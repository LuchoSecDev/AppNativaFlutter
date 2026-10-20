import 'package:flutter/material.dart';

import '../../clientes/cliente.dart';
import '../../ui/colores.dart';
import '../../ui/piezas_de_pantalla.dart';
import 'fiado_formato.dart';

class ConfirmarFiado extends StatelessWidget {
  const ConfirmarFiado({
    super.key,
    required this.total,
    required this.totalAlAbrir,
    required this.cliente,
    required this.alElegirOtro,
    required this.alCobrar,
  });

  final int total;
  final int totalAlAbrir;
  final Cliente cliente;
  final VoidCallback alElegirOtro;
  final VoidCallback alCobrar;

  @override
  Widget build(BuildContext context) {
    final alcanza = cliente.alcanzaCupo(total);
    final nuevoSaldo = cliente.saldoPendienteCentavos + total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Elegir otro cliente',
              onPressed: alElegirOtro,
            ),
            const Text(
              'Confirmar fiado',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colores.tinta,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            children: [
              Text(
                cliente.nombre,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colores.tinta,
                ),
              ),
              const SizedBox(height: 16),
              FilaDelFiado(
                'Total de la compra',
                pesosDeCentavos(total),
                negrita: true,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(),
              ),
              FilaDelFiado(
                'Debe ahora',
                pesosDeCentavos(cliente.saldoPendienteCentavos),
              ),
              const SizedBox(height: 4),
              FilaDelFiado(
                'Quedaría debiendo',
                pesosDeCentavos(nuevoSaldo),
                negrita: true,
                color: alcanza ? Colores.azul : Colores.peligro,
              ),
              const SizedBox(height: 4),
              FilaDelFiado(
                'Cupo',
                cliente.sinTope
                    ? 'Sin tope'
                    : pesosDeCentavos(cliente.limiteCreditoCentavos),
              ),
            ],
          ),
        ),
        if (total != totalAlAbrir) ...[
          const SizedBox(height: 12),
          CuadroDeMensaje(
            'El total cambió al actualizar los precios: antes era ${pesosDeCentavos(totalAlAbrir)}.',
            esError: false,
          ),
        ],
        if (!alcanza) ...[
          const SizedBox(height: 16),
          CuadroDeMensaje(
            'Esta venta supera el cupo de crédito del cliente: ya debe ${pesosDeCentavos(cliente.saldoPendienteCentavos)} de un cupo de ${pesosDeCentavos(cliente.limiteCreditoCentavos)}. No se puede fiar esta cantidad.',
          ),
        ],
        const SizedBox(height: 24),
        BotonPrincipal(
          texto: 'Confirmar fiado',
          alPulsar: alcanza ? alCobrar : null,
        ),
      ],
    );
  }
}

class FilaDelFiado extends StatelessWidget {
  const FilaDelFiado(
    this.titulo,
    this.valor, {
    super.key,
    this.negrita = false,
    this.color,
  });

  final String titulo;
  final String valor;
  final bool negrita;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(titulo, style: const TextStyle(color: Colores.tinta)),
        Text(
          valor,
          style: TextStyle(
            fontWeight: negrita ? FontWeight.w700 : FontWeight.w400,
            color: color ?? Colores.tinta,
          ),
        ),
      ],
    );
  }
}
