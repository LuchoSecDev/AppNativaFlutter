// Datos y resultados de la sesión, tal como los entrega la API (contrato: [S2], [S3], [S4], [S7]).

/// El usuario que devuelve el login (`user` de `POST /api/login` y de `POST /api/2fa/verify`).
class UsuarioSesion {
  const UsuarioSesion({
    required this.nombres,
    required this.rol,
    required this.cambioClaveForzoso,
    required this.needs2FASetup,
  });

  final String nombres;

  /// `Tendero` o `Administrador`.
  final String rol;

  /// `true` en el primer inicio de sesión de una cuenta nueva: hay que pedir una contraseña definitiva.
  final bool cambioClaveForzoso;

  /// `true` si es un Administrador sin segundo factor configurado: esa configuración se hace en la web.
  final bool needs2FASetup;

  factory UsuarioSesion.desdeJson(Map<String, dynamic> json) => UsuarioSesion(
        nombres: json['nombres'] as String? ?? '',
        rol: json['rol'] as String? ?? '',
        cambioClaveForzoso: json['cambioClaveForzoso'] == true,
        needs2FASetup: json['needs2FASetup'] == true,
      );
}

/// Lo que devuelve `GET /api/session-info`: quién es el usuario y de qué tienda.
class InfoSesion {
  const InfoSesion({
    required this.userId,
    required this.tiendaId,
    required this.tiendaNombre,
    required this.limiteEgresoTendero,
    required this.rol,
    required this.nombres,
    required this.is2FAEnabled,
    required this.cambioClaveForzoso,
    required this.needs2FASetup,
  });

  final int userId;
  final int tiendaId;
  final String tiendaNombre;

  /// Tope de egresos del Tendero. Llega como TEXTO con dos decimales (`"150000.00"`): al hacer cuentas hay que
  /// convertirlo con un tipo decimal, no sumar texto. No se fija en la app: sale siempre de aquí.
  final String limiteEgresoTendero;
  final String rol;
  final String nombres;
  final bool is2FAEnabled;

  /// Igual que en [UsuarioSesion]: sirve para reabrir la app y saber si la cuenta todavía debe cambiar su contraseña.
  final bool cambioClaveForzoso;
  final bool needs2FASetup;

  factory InfoSesion.desdeJson(Map<String, dynamic> json) => InfoSesion(
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        tiendaId: (json['tiendaId'] as num?)?.toInt() ?? 0,
        tiendaNombre: json['tiendaNombre'] as String? ?? '',
        limiteEgresoTendero: json['limiteEgresoTendero'] as String? ?? '0.00',
        rol: json['rol'] as String? ?? '',
        nombres: json['nombres'] as String? ?? '',
        is2FAEnabled: json['is2FAEnabled'] == true,
        cambioClaveForzoso: json['cambioClaveForzoso'] == true,
        needs2FASetup: json['needs2FASetup'] == true,
      );
}

/// Resultado de `POST /api/login`. `sealed` obliga a quien lo usa a cubrir TODOS los casos.
sealed class ResultadoLogin {
  const ResultadoLogin();
}

/// Credenciales correctas y sin segundo factor: ya hay sesión.
final class LoginExitoso extends ResultadoLogin {
  const LoginExitoso(this.usuario);
  final UsuarioSesion usuario;
}

/// La cuenta tiene segundo factor: todavía NO hay sesión, falta el código de 6 dígitos.
final class LoginRequiere2FA extends ResultadoLogin {
  const LoginRequiere2FA();
}

/// Un Tendero ya tiene una sesión abierta en este canal (409). Se puede repetir con `forzar` para cerrarla.
final class LoginSesionActiva extends ResultadoLogin {
  const LoginSesionActiva();
}

/// El servidor rechazó el intento (credenciales incorrectas, faltan campos o demasiados intentos).
final class LoginRechazado extends ResultadoLogin {
  const LoginRechazado(this.mensaje);
  final String mensaje;
}

/// Resultado de `POST /api/2fa/verify`.
sealed class ResultadoVerificacion {
  const ResultadoVerificacion();
}

final class VerificacionExitosa extends ResultadoVerificacion {
  const VerificacionExitosa(this.usuario);
  final UsuarioSesion usuario;
}

/// Código incorrecto o vencido (la sesión sigue «a medias» y se puede reintentar).
final class VerificacionRechazada extends ResultadoVerificacion {
  const VerificacionRechazada(this.mensaje);
  final String mensaje;
}

/// Resultado de `PUT /api/perfil/first-password`.
sealed class ResultadoCambioClave {
  const ResultadoCambioClave();
}

final class CambioClaveExitoso extends ResultadoCambioClave {
  const CambioClaveExitoso();
}

final class CambioClaveRechazado extends ResultadoCambioClave {
  const CambioClaveRechazado(this.mensaje);
  final String mensaje;
}

/// Resultado de una prueba de conexión (solo para depuración).
class ResultadoConexion {
  const ResultadoConexion({required this.duracion, this.estado, this.error});

  final Duration duracion;

  /// Código HTTP si el servidor respondió.
  final int? estado;

  /// Mensaje si no se pudo llegar al servidor.
  final String? error;

  bool get llego => estado != null;
}

/// Falla de red o del servidor (sin conexión, tiempo agotado, error 5xx...). Lleva un mensaje listo para
/// mostrarle al usuario, en español y sin detalles técnicos.
class ErrorDeApi implements Exception {
  const ErrorDeApi(this.mensaje);
  final String mensaje;

  @override
  String toString() => 'ErrorDeApi($mensaje)';
}
