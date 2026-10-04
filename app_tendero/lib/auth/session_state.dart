import 'auth_models.dart';

/// En qué punto está la sesión. La pantalla que se muestra depende SOLO de esto.
enum FaseSesion {
  /// Abriendo la app: se pregunta al servidor si la cookie guardada todavía vale.
  iniciando,

  /// No hay sesión: pantalla de login.
  sinSesion,

  /// Contraseña correcta pero la cuenta tiene segundo factor: falta el código de 6 dígitos.
  codigo2FA,

  /// Cuenta nueva con contraseña temporal: hay que elegir una definitiva antes de operar.
  cambioClave,

  /// Sesión lista: se puede usar la app.
  activa,
}

/// Lo que la app sabe de la sesión en este momento. Es inmutable: para cambiarlo se crea otro.
class EstadoSesion {
  const EstadoSesion._({
    required this.fase,
    this.usuario,
    this.info,
    this.mensaje,
    this.trabajando = false,
    this.pideForzar = false,
  });

  const EstadoSesion.iniciando() : this._(fase: FaseSesion.iniciando);

  /// [mensaje]: un error o aviso para mostrar. [pideForzar]: ya hay una sesión abierta en otro dispositivo de la
  /// app y hay que preguntar si se cierra (contrato, [S2] 409).
  const EstadoSesion.sinSesion({String? mensaje, bool pideForzar = false})
      : this._(fase: FaseSesion.sinSesion, mensaje: mensaje, pideForzar: pideForzar);

  const EstadoSesion.codigo2FA({String? mensaje}) : this._(fase: FaseSesion.codigo2FA, mensaje: mensaje);

  const EstadoSesion.cambioClave(UsuarioSesion usuario, {String? mensaje})
      : this._(fase: FaseSesion.cambioClave, usuario: usuario, mensaje: mensaje);

  const EstadoSesion.activa(InfoSesion info) : this._(fase: FaseSesion.activa, info: info);

  final FaseSesion fase;

  /// Quien inició sesión con contraseña temporal (solo en [FaseSesion.cambioClave]).
  final UsuarioSesion? usuario;

  /// Datos de la sesión (solo en [FaseSesion.activa]).
  final InfoSesion? info;

  /// Error o aviso para el usuario, en español.
  final String? mensaje;

  /// `true` mientras se espera la respuesta del servidor: la pantalla muestra un indicador y bloquea el botón.
  final bool trabajando;

  final bool pideForzar;

  /// El mismo estado, marcado como «esperando al servidor» y sin mensajes viejos.
  EstadoSesion enTrabajo() => EstadoSesion._(
        fase: fase,
        usuario: usuario,
        info: info,
        trabajando: true,
      );
}
