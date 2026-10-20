import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../ui/colores.dart';
import '../../ui/dinero.dart';
import '../../ui/formato.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../../ui/retroalimentacion.dart';
import '../egreso_borrador.dart';
import '../egreso_models.dart';
import '../egreso_providers.dart';
import '../egreso_reglas.dart';

/// El formulario para registrar un gasto: monto, categoría y motivo. Lo escrito se conserva en [BorradorDeEgreso] si se
/// sale de la pantalla y se vuelve. El botón solo se habilita cuando lo que se escribió se puede enviar; si el servidor
/// igual lo rechaza, [rechazo] muestra por qué (y vibra fuerte una vez).
class FormularioDeEgreso extends ConsumerStatefulWidget {
  const FormularioDeEgreso({super.key, this.rechazo});

  final String? rechazo;

  @override
  ConsumerState<FormularioDeEgreso> createState() => _FormularioDeEgresoState();
}

class _FormularioDeEgresoState extends ConsumerState<FormularioDeEgreso> {
  /// Hasta 9 dígitos (999.999.999 pesos): evita un número absurdo por un dedo pegado a la tecla.
  static const int _maximoDeDigitos = 9;

  late final TextEditingController _monto;
  late final TextEditingController _motivo;

  @override
  void initState() {
    super.initState();
    final borrador = ref.read(borradorDeEgresoProvider);
    _monto = TextEditingController(text: borrador.monto);
    _motivo = TextEditingController(text: borrador.motivo);
  }

  @override
  void dispose() {
    _monto.dispose();
    _motivo.dispose();
    super.dispose();
  }

  void _registrar(BorradorDeEgreso borrador) {
    FocusScope.of(context).unfocus();
    ref
        .read(egresoProvider.notifier)
        .registrar(
          montoPesos: int.parse(borrador.monto),
          motivo: borrador.motivo,
          categoria: borrador.categoria!,
        );
  }

  @override
  Widget build(BuildContext context) {
    final borrador = ref.watch(borradorDeEgresoProvider);
    final info = ref.watch(sesionProvider).info;
    final tope = topeEnCentavos(
      rol: info?.rol ?? '',
      limiteEgresoTendero: info?.limiteEgresoTendero ?? '',
    );
    final monto = int.tryParse(borrador.monto) ?? 0;
    final superaElTope = tope != null && monto * 100 > tope;
    final motivoCorto =
        borrador.motivo.isNotEmpty && !motivoEsValido(borrador.motivo);
    final puedeEnviar =
        monto > 0 &&
        !superaElTope &&
        motivoEsValido(borrador.motivo) &&
        borrador.categoria != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.rechazo != null) ...[
                VibrarAlAparecer(
                  intensidad: Intensidad.fuerte,
                  child: CuadroDeMensaje(widget.rechazo!),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _monto,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_maximoDeDigitos),
                ],
                onChanged: (v) => ref
                    .read(borradorDeEgresoProvider.notifier)
                    .cambiar(monto: v),
                decoration: InputDecoration(
                  labelText: 'Monto',
                  prefixText: r'$ ',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  errorText: superaElTope
                      ? 'Supera tu tope de ${formatoPesos(importeDeCentavos(tope))} por gasto.'
                      : null,
                  helperText: tope != null && !superaElTope
                      ? 'Tu tope por gasto es ${formatoPesos(importeDeCentavos(tope))}.'
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Categoría',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colores.tinta,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in CategoriaEgreso.values)
                    ChoiceChip(
                      label: Text(c.valorApi),
                      selected: borrador.categoria == c,
                      onSelected: (_) => ref
                          .read(borradorDeEgresoProvider.notifier)
                          .cambiar(categoria: c),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _motivo,
                minLines: 2,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (v) => ref
                    .read(borradorDeEgresoProvider.notifier)
                    .cambiar(motivo: v),
                decoration: InputDecoration(
                  labelText: 'Motivo',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  errorText: motivoCorto
                      ? 'Escribe al menos $caracteresMinimosDelMotivo caracteres.'
                      : null,
                ),
              ),
              const SizedBox(height: 24),
              BotonPrincipal(
                texto: 'Registrar gasto',
                alPulsar: puedeEnviar ? () => _registrar(borrador) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
