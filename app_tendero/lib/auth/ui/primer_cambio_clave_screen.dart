import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/piezas_de_pantalla.dart';
import '../auth_providers.dart';

/// Primer inicio de sesión de una cuenta nueva: la contraseña que le dio el Administrador es temporal y hay que
/// elegir una definitiva antes de poder operar.
class PrimerCambioClaveScreen extends ConsumerStatefulWidget {
  const PrimerCambioClaveScreen({super.key});

  @override
  ConsumerState<PrimerCambioClaveScreen> createState() =>
      _PrimerCambioClaveScreenState();
}

class _PrimerCambioClaveScreenState
    extends ConsumerState<PrimerCambioClaveScreen> {
  static const int _minimoDeCaracteres = 8; // el servidor exige al menos 8

  final _formulario = GlobalKey<FormState>();
  final _nueva = TextEditingController();
  final _repetida = TextEditingController();
  bool _ocultar = true;

  @override
  void dispose() {
    _nueva.dispose();
    _repetida.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!(_formulario.currentState?.validate() ?? false)) return;
    ref.read(sesionProvider.notifier).cambiarClaveInicial(_nueva.text);
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(sesionProvider);
    final ocupado = estado.trabajando;
    final nombre = estado.usuario?.nombres ?? '';

    InputDecoration decoracion(String etiqueta) => InputDecoration(
      labelText: etiqueta,
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
      suffixIcon: IconButton(
        tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
        icon: Icon(_ocultar ? Icons.visibility : Icons.visibility_off),
        onPressed: () => setState(() => _ocultar = !_ocultar),
      ),
    );

    return PantallaDeEntrada(
      titulo: 'Elige tu contraseña',
      subtitulo:
          '${nombre.isEmpty ? 'Hola' : 'Hola, $nombre'}. Es tu primer ingreso: la contraseña que recibiste '
          'es temporal. Escribe una nueva de al menos $_minimoDeCaracteres caracteres.',
      hijos: [
        Form(
          key: _formulario,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nueva,
                enabled: !ocupado,
                obscureText: _ocultar,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                decoration: decoracion('Contraseña nueva'),
                validator: (v) => (v == null || v.length < _minimoDeCaracteres)
                    ? 'Debe tener al menos $_minimoDeCaracteres caracteres'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _repetida,
                enabled: !ocupado,
                obscureText: _ocultar,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                onFieldSubmitted: (_) => _guardar(),
                decoration: decoracion('Repite la contraseña'),
                validator: (v) =>
                    v != _nueva.text ? 'Las contraseñas no coinciden' : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (estado.mensaje != null) ...[
          CuadroDeMensaje(estado.mensaje!),
          const SizedBox(height: 16),
        ],
        BotonPrincipal(
          texto: 'Guardar contraseña',
          enEspera: ocupado,
          alPulsar: _guardar,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: ocupado
              ? null
              : () => ref.read(sesionProvider.notifier).cerrarSesion(),
          child: const Text('Salir'),
        ),
      ],
    );
  }
}
