import 'package:flutter/material.dart';

import '../../ui/colores.dart';
import '../../ui/dinero.dart';
import '../../ui/formato.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../../ui/retroalimentacion.dart';
import '../../venta/venta_providers.dart';

/// El comprobante de la venta ya registrada, con el cambio a devolver.
class VentaRegistrada extends StatelessWidget {
  const VentaRegistrada({
    super.key,
    required this.cobro,
    required this.alTerminar,
  });

  final EstadoCobro cobro;
  final VoidCallback alTerminar;

  @override
  Widget build(BuildContext context) {
    final venta = cobro.venta;
    final cambio = venta?.cambioCentavos;
    return VibrarAlAparecer(
      intensidad: Intensidad.media,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle, size: 64, color: Colores.exito),
              const SizedBox(height: 12),
              const Text(
                'Venta registrada',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colores.tinta,
                ),
              ),
              Text(
                'Venta n.º ${cobro.idVenta}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colores.tinta),
              ),
              if (cobro.repetida) ...[
                const SizedBox(height: 12),
                const CuadroDeMensaje(
                  'Esta venta ya estaba registrada: se recuperó sin cobrarla otra vez.',
                  esError: false,
                ),
              ],
              if (venta != null) ...[
                const SizedBox(height: 20),
                _Renglon(
                  'Total',
                  formatoPesos(importeDeCentavos(venta.totalCentavos)),
                ),
                if (venta.efectivoRecibido != null)
                  _Renglon(
                    'Efectivo recibido',
                    formatoPesosEnteros(venta.efectivoRecibido!),
                  ),
                if (cambio != null && cambio >= 0)
                  _Renglon(
                    'Cambio a devolver',
                    formatoPesos(importeDeCentavos(cambio)),
                    destacado: true,
                  ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: alTerminar,
                child: const Text('Nueva venta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Renglon extends StatelessWidget {
  const _Renglon(this.etiqueta, this.valor, {this.destacado = false});

  final String etiqueta;
  final String valor;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      fontSize: destacado ? 20 : 16,
      fontWeight: destacado ? FontWeight.w800 : FontWeight.w500,
      color: destacado ? Colores.exito : Colores.tinta,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: estilo),
          Text(valor, style: estilo),
        ],
      ),
    );
  }
}
