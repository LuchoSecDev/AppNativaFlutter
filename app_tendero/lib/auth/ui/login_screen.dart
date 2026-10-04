import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import '../../scanner_screen.dart';
import '../../ui/colores.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../auth_models.dart';
import '../auth_providers.dart';

/// Pantalla de inicio de sesión.
///
/// `ConsumerStatefulWidget` es un widget que (1) puede recordar cosas mientras está en pantalla, como lo que el
/// usuario escribe (eso es el `State`), y (2) puede observar los providers de Riverpod con `ref`.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formulario = GlobalKey<FormState>();

  // Un TextEditingController lee y controla lo que hay escrito en un campo. Hay que liberarlo en dispose().
  final _usuario = TextEditingController();
  final _clave = TextEditingController();

  bool _ocultarClave = true;

  // Solo para la prueba de conexión de depuración.
  ResultadoConexion? _conexion;
  bool _probandoConexion = false;

  @override
  void dispose() {
    _usuario.dispose();
    _clave.dispose();
    super.dispose();
  }

  /// Valida los campos y, si están completos, pide iniciar sesión. [forzar] cierra la otra sesión de la app.
  void _enviar({bool forzar = false}) {
    if (!(_formulario.currentState?.validate() ?? false)) return;
    ref
        .read(sesionProvider.notifier)
        .iniciarSesion(_usuario.text.trim(), _clave.text, forzar: forzar);
  }

  Future<void> _probarConexion() async {
    setState(() => _probandoConexion = true);
    final resultado = await ref.read(authRepositoryProvider).probarConexion();
    if (!mounted) return;
    setState(() {
      _conexion = resultado;
      _probandoConexion = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // ref.watch hace que esta pantalla se redibuje cada vez que cambia el estado de la sesión.
    final estado = ref.watch(sesionProvider);
    final ocupado = estado.trabajando;

    return PantallaDeEntrada(
      titulo: 'Inicia sesión',
      subtitulo: 'Entra con tu usuario o correo.',
      hijos: [
        Form(
          key: _formulario,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _usuario,
                  enabled: !ocupado,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Usuario o correo',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Escribe tu usuario o correo'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _clave,
                  enabled: !ocupado,
                  obscureText: _ocultarClave,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  enableSuggestions: false,
                  autocorrect: false,
                  onFieldSubmitted: (_) => _enviar(),
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    suffixIcon: IconButton(
                      tooltip: _ocultarClave
                          ? 'Mostrar contraseña'
                          : 'Ocultar contraseña',
                      icon: Icon(
                        _ocultarClave ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () =>
                          setState(() => _ocultarClave = !_ocultarClave),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Escribe tu contraseña' : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (estado.mensaje != null) ...[
          CuadroDeMensaje(estado.mensaje!),
          const SizedBox(height: 16),
        ],
        if (estado.pideForzar) ...[
          _PreguntaCerrarOtraSesion(
            ocupado: ocupado,
            alCancelar: () =>
                ref.read(sesionProvider.notifier).descartarAviso(),
            alConfirmar: () => _enviar(forzar: true),
          ),
          const SizedBox(height: 16),
        ],
        BotonPrincipal(texto: 'Ingresar', enEspera: ocupado, alPulsar: _enviar),
        // Lo de abajo solo existe al ejecutar en modo depuración (flutter run); nunca llega a una versión de entrega.
        if (kDebugMode) ...[
          const SizedBox(height: 32),
          const Divider(),
          const Text(
            'Solo depuración',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colores.tinta),
          ),
          Text(
            'Servidor: ${_servidor()}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colores.tinta),
          ),
          TextButton(
            onPressed: _probandoConexion ? null : _probarConexion,
            child: Text(
              _probandoConexion
                  ? 'Probando…'
                  : 'Probar conexión con el servidor',
            ),
          ),
          if (_conexion != null)
            Text(
              _conexion!.llego
                  ? 'El servidor respondió (código ${_conexion!.estado}) en ${_conexion!.duracion.inMilliseconds} ms.'
                  : 'Sin respuesta: ${_conexion!.error} (${_conexion!.duracion.inMilliseconds} ms).',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: _conexion!.llego ? Colores.exito : Colores.peligro,
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ScannerScreen()),
            ),
            child: const Text('Probar el escáner (sin iniciar sesión)'),
          ),
        ],
      ],
    );
  }

  /// Solo el nombre del servidor (sin ruta), para comprobar de un vistazo que se ejecutó con la dirección correcta.
  String _servidor() {
    final host = Uri.tryParse(AppConfig.apiBaseUrl)?.host ?? '';
    return host.isEmpty ? 'no configurado' : host;
  }
}

/// Aparece cuando el servidor dice que la cuenta ya tiene una sesión abierta en otro celular (409).
class _PreguntaCerrarOtraSesion extends StatelessWidget {
  const _PreguntaCerrarOtraSesion({
    required this.ocupado,
    required this.alCancelar,
    required this.alConfirmar,
  });

  final bool ocupado;
  final VoidCallback alCancelar;
  final VoidCallback alConfirmar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colores.avisoSuave,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Esta cuenta ya tiene una sesión abierta en otro celular. Si continúas, esa sesión se cerrará.',
            style: TextStyle(color: Colores.aviso, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: ocupado ? null : alCancelar,
                  child: const Text('Cancelar'),
                ),
              ),
              Expanded(
                child: FilledButton(
                  onPressed: ocupado ? null : alConfirmar,
                  child: const Text('Cerrar la otra sesión'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
