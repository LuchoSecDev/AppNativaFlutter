import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/piezas_de_pantalla.dart';
import '../auth_providers.dart';

/// Pantalla del código de 6 dígitos del segundo factor (la app autenticadora del Administrador).
class Verificacion2FAScreen extends ConsumerStatefulWidget {
  const Verificacion2FAScreen({super.key});

  @override
  ConsumerState<Verificacion2FAScreen> createState() =>
      _Verificacion2FAScreenState();
}

class _Verificacion2FAScreenState extends ConsumerState<Verificacion2FAScreen> {
  final _codigo = TextEditingController();

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  void _verificar() {
    if (_codigo.text.length != 6) return;
    ref.read(sesionProvider.notifier).verificarCodigo(_codigo.text);
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(sesionProvider);
    final ocupado = estado.trabajando;

    return PantallaDeEntrada(
      titulo: 'Código de verificación',
      subtitulo:
          'Escribe el código de 6 dígitos de tu aplicación autenticadora.',
      hijos: [
        TextField(
          controller: _codigo,
          enabled: !ocupado,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          // Solo se aceptan dígitos.
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 28, letterSpacing: 8),
          onChanged: (_) => setState(
            () {},
          ), // para habilitar o deshabilitar el botón según cuántos dígitos hay
          onSubmitted: (_) => _verificar(),
          decoration: const InputDecoration(
            counterText: '',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
            hintText: '000000',
          ),
        ),
        const SizedBox(height: 16),
        if (estado.mensaje != null) ...[
          CuadroDeMensaje(estado.mensaje!),
          const SizedBox(height: 16),
        ],
        BotonPrincipal(
          texto: 'Verificar',
          enEspera: ocupado,
          alPulsar: _codigo.text.length == 6 ? _verificar : null,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: ocupado
              ? null
              : () => ref.read(sesionProvider.notifier).cerrarSesion(),
          child: const Text('Volver al inicio de sesión'),
        ),
      ],
    );
  }
}
