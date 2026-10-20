/// El formato que el servidor acepta para la cabecera `Idempotency-Key`: de 8 a 100 caracteres, solo letras, números,
/// guion o guion bajo (contrato `[V2]`, `[K4]` y `[M1]`). Una clave que no cumpla recibe 400 y no registra nada.
///
/// Sirve para descartar, al leer del celular, una clave guardada que quedó dañada: reenviarla no tendría sentido.
final RegExp _formatoDeClave = RegExp(r'^[A-Za-z0-9_-]{8,100}$');

bool esClaveDeIdempotenciaValida(String clave) =>
    _formatoDeClave.hasMatch(clave);
