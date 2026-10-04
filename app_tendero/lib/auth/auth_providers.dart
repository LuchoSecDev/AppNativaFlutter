import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_models.dart';
import 'auth_repository.dart';
import 'session_state.dart';

/// El cliente HTTP. No se crea aquí porque necesita cosas que solo existen al arrancar la app (la dirección del
/// servidor y el cajón de cookies en disco). `main()` lo sustituye con `overrideWithValue`; en las pruebas se
/// sustituye por uno con un servidor falso.
final dioProvider = Provider<Dio>(
  (ref) => throw UnimplementedError('dioProvider se sustituye en main()'),
);

/// Avisos de «el servidor dice que ya no hay sesión» (un 401 en una ruta protegida). Los emite el interceptor
/// y los escucha [SesionNotifier]. También se sustituye en `main()`.
final sesionCaducadaProvider = Provider<Stream<void>>(
  (ref) =>
      throw UnimplementedError('sesionCaducadaProvider se sustituye en main()'),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(dioProvider)),
);

/// Estado de la sesión de toda la app. Las pantallas lo observan con `ref.watch(sesionProvider)` y le piden
/// cambios con `ref.read(sesionProvider.notifier).iniciarSesion(...)`.
final sesionProvider = NotifierProvider<SesionNotifier, EstadoSesion>(
  SesionNotifier.new,
);

/// Quien decide en qué fase está la sesión. Un `Notifier` es una clase que GUARDA un estado (`state`) y expone
/// métodos para cambiarlo; cada vez que `state` cambia, las pantallas que lo observan se redibujan solas.
class SesionNotifier extends Notifier<EstadoSesion> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// `build` se ejecuta una vez, al primer uso. Devuelve el estado inicial.
  @override
  EstadoSesion build() {
    // Si el servidor avisa que la sesión caducó, volvemos al login.
    final suscripcion = ref
        .read(sesionCaducadaProvider)
        .listen((_) => _alCaducar());
    ref.onDispose(suscripcion.cancel);

    // Al abrir la app, averiguamos si la cookie guardada todavía vale. Se hace "después" de build porque build no
    // puede cambiar el estado mientras se está construyendo.
    Future.microtask(_restaurar);
    return const EstadoSesion.iniciando();
  }

  // ───────────────────────── acciones que llaman las pantallas ─────────────────────────

  /// Pantalla de login. [forzar] cierra la otra sesión de la app (solo después de que el usuario lo confirme).
  Future<void> iniciarSesion(
    String usuario,
    String password, {
    bool forzar = false,
  }) async {
    // Un segundo toque mientras se espera al servidor no debe enviar otra petición: en el login, el segundo intento
    // recibiría un 409 («ya hay una sesión») provocado por el primero.
    if (state.trabajando) return;
    state = state.enTrabajo();
    try {
      final resultado = await _repo.login(
        usuario: usuario,
        password: password,
        forzar: forzar,
      );
      if (!ref.mounted) return;
      switch (resultado) {
        case LoginExitoso(usuario: final u):
          await _alTenerSesion(u);
        case LoginRequiere2FA():
          state = const EstadoSesion.codigo2FA();
        case LoginSesionActiva():
          state = const EstadoSesion.sinSesion(pideForzar: true);
        case LoginRechazado(mensaje: final m):
          state = EstadoSesion.sinSesion(mensaje: m);
      }
    } on ErrorDeApi catch (e) {
      if (ref.mounted) state = EstadoSesion.sinSesion(mensaje: e.mensaje);
    }
  }

  /// Pantalla del código de 6 dígitos.
  Future<void> verificarCodigo(String codigo) async {
    // Un segundo toque mientras se espera al servidor no debe enviar otra petición: en el login, el segundo intento
    // recibiría un 409 («ya hay una sesión») provocado por el primero.
    if (state.trabajando) return;
    state = state.enTrabajo();
    try {
      final resultado = await _repo.verificarCodigo2FA(codigo);
      if (!ref.mounted) return;
      switch (resultado) {
        case VerificacionExitosa(usuario: final u):
          await _alTenerSesion(u);
        case VerificacionRechazada(mensaje: final m):
          state = EstadoSesion.codigo2FA(mensaje: m);
      }
    } on ErrorDeApi catch (e) {
      if (ref.mounted) state = EstadoSesion.codigo2FA(mensaje: e.mensaje);
    }
  }

  /// Pantalla de «elige tu contraseña» (primer inicio de una cuenta nueva).
  Future<void> cambiarClaveInicial(String nuevaClave) async {
    // Un segundo toque mientras se espera al servidor no debe enviar otra petición: en el login, el segundo intento
    // recibiría un 409 («ya hay una sesión») provocado por el primero.
    if (state.trabajando) return;
    final usuario = state.usuario;
    state = state.enTrabajo();
    try {
      final resultado = await _repo.cambiarClaveInicial(nuevaClave);
      if (!ref.mounted) return;
      switch (resultado) {
        case CambioClaveExitoso():
          await _cargarInfo();
        case CambioClaveRechazado(mensaje: final m):
          if (usuario != null) {
            state = EstadoSesion.cambioClave(usuario, mensaje: m);
          }
      }
    } on ErrorDeApi catch (e) {
      if (ref.mounted && usuario != null) {
        state = EstadoSesion.cambioClave(usuario, mensaje: e.mensaje);
      }
    }
  }

  /// El usuario decidió NO cerrar la otra sesión (cancela la pregunta del 409). No llama al servidor.
  void descartarAviso() {
    if (state.fase == FaseSesion.sinSesion) {
      state = const EstadoSesion.sinSesion();
    }
  }

  /// Cerrar sesión, o «volver» desde la pantalla del código o la de la contraseña.
  Future<void> cerrarSesion() async {
    // Un segundo toque mientras se espera al servidor no debe enviar otra petición: en el login, el segundo intento
    // recibiría un 409 («ya hay una sesión») provocado por el primero.
    if (state.trabajando) return;
    state = state.enTrabajo();
    await _repo.cerrarSesion();
    if (ref.mounted) state = const EstadoSesion.sinSesion();
  }

  // ───────────────────────── pasos internos ─────────────────────────

  Future<void> _restaurar() async {
    try {
      final info = await _repo.restaurarSesion();
      if (!ref.mounted) return;
      if (info == null) {
        state = const EstadoSesion.sinSesion();
      } else {
        await _alTenerSesion(
          UsuarioSesion(
            nombres: info.nombres,
            rol: info.rol,
            cambioClaveForzoso: info.cambioClaveForzoso,
            needs2FASetup: info.needs2FASetup,
          ),
        );
      }
    } on ErrorDeApi catch (e) {
      if (ref.mounted) state = EstadoSesion.sinSesion(mensaje: e.mensaje);
    }
  }

  /// Hay sesión en el servidor (con o sin código 2FA). Falta decidir a dónde va el usuario.
  Future<void> _alTenerSesion(UsuarioSesion usuario) async {
    if (usuario.needs2FASetup) {
      // El Administrador sin segundo factor debe configurarlo en la web: la app no lo hace.
      await _repo.cerrarSesion();
      if (!ref.mounted) return;
      state = const EstadoSesion.sinSesion(
        mensaje: 'Tu cuenta necesita configurar el segundo factor en la versión web antes de usar la app.',
      );
      return;
    }
    if (usuario.cambioClaveForzoso) {
      state = EstadoSesion.cambioClave(usuario);
      return;
    }
    await _cargarInfo();
  }

  Future<void> _cargarInfo() async {
    try {
      final info = await _repo.infoDeSesion();
      if (ref.mounted) state = EstadoSesion.activa(info);
    } on ErrorDeApi catch (e) {
      if (ref.mounted) state = EstadoSesion.sinSesion(mensaje: e.mensaje);
    }
  }

  /// El servidor dijo que ya no hay sesión (401 en una ruta protegida).
  void _alCaducar() {
    if (state.fase == FaseSesion.activa ||
        state.fase == FaseSesion.cambioClave) {
      state = const EstadoSesion.sinSesion(
        mensaje: 'Tu sesión terminó. Inicia sesión de nuevo.',
      );
    }
  }
}
