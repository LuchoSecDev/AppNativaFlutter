import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/colores.dart';
import '../../ui/formato.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../caja_providers.dart';

/// Pantalla para abrir la caja con el efectivo que hay al empezar el turno.
class AbrirCajaScreen extends ConsumerStatefulWidget {
  const AbrirCajaScreen({super.key});

  @override
  ConsumerState<AbrirCajaScreen> createState() => _AbrirCajaScreenState();
}

class _AbrirCajaScreenState extends ConsumerState<AbrirCajaScreen> {
  /// Hasta 9 dígitos (999.999.999 pesos): evita un número absurdo por un dedo pegado a la tecla.
  static const int _maximoDeDigitos = 9;

  final _formulario = GlobalKey<FormState>();
  final _monto = TextEditingController();

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  Future<void> _pedirConfirmacion() async {
    if (!(_formulario.currentState?.validate() ?? false)) {
      return;
    }
    final monto = int.parse(_monto.text);
    // El efectivo inicial entra en el arqueo del cierre: un cero de más lo descuadra. Por eso se confirma.
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('¿Abrir la caja?'),
        content: Text(
          'Vas a abrir la caja con ${formatoPesosEnteros(monto)}. ¿Es correcto?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Corregir'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Sí, abrir'),
          ),
        ],
      ),
    );
    if (confirmado == true && mounted) {
      await ref.read(cajaProvider.notifier).abrir(monto);
    }
  }

  @override
  Widget build(BuildContext context) {
    final caja = ref.watch(cajaProvider);

    // Cuando la caja queda abierta, esta pantalla ya no hace falta: se vuelve al inicio.
    ref.listen(cajaProvider, (anterior, nuevo) {
      if (nuevo.fase == FaseCaja.abierta && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });

    return Scaffold(
      backgroundColor: Colores.papel,
      appBar: AppBar(title: const Text('Abrir caja')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Cuenta el efectivo que hay en la caja ahora. Escribe 0 si empiezas sin efectivo.',
                    style: TextStyle(fontSize: 14, color: Colores.tinta),
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: _formulario,
                    child: TextFormField(
                      controller: _monto,
                      enabled: !caja.trabajando,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(_maximoDeDigitos),
                      ],
                      onFieldSubmitted: (_) => _pedirConfirmacion(),
                      decoration: const InputDecoration(
                        labelText: 'Efectivo inicial',
                        prefixText: r'$ ',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Escribe el efectivo inicial'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (caja.mensaje != null) ...[
                    CuadroDeMensaje(caja.mensaje!),
                    const SizedBox(height: 16),
                  ],
                  BotonPrincipal(
                    texto: 'Abrir caja',
                    enEspera: caja.trabajando,
                    alPulsar: _pedirConfirmacion,
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
