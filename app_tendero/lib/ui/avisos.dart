import 'package:flutter/material.dart';

import 'colores.dart';

/// Qué clase de noticia es un aviso: decide su color, su ícono y cuánto dura.
///
/// Lo bueno se lee de un vistazo y se va pronto (2 s). Lo que el Tendero necesita leer con calma —un rechazo o algo que
/// quedó a medias— dura más (3,5 s). En los dos casos se puede cerrar tocándolo.
enum TipoAviso {
  exito(Colores.exito, Icons.check_circle_rounded, Duration(seconds: 2)),
  aviso(
    Colores.aviso,
    Icons.warning_amber_rounded,
    Duration(milliseconds: 3500),
  ),
  error(Colores.peligro, Icons.error_rounded, Duration(milliseconds: 3500));

  const TipoAviso(this.color, this.icono, this.duracion);

  final Color color;
  final IconData icono;
  final Duration duracion;
}

/// Muestra un aviso flotante y redondeado, con ícono, que reemplaza al anterior (no se acumulan en cola).
///
/// **Úsala en vez de `SnackBar` directo:** así todos los avisos de la app se ven y duran igual. Un aviso flotante tapa
/// lo que hay debajo mientras está a la vista; por eso, tocarlo en cualquier parte (o deslizarlo hacia un lado) lo cierra
/// al instante, sin esperar a que se acabe el tiempo.
void mostrarAviso(
  BuildContext context,
  String texto, {
  required TipoAviso tipo,
}) {
  final mensajes = ScaffoldMessenger.of(context);
  mensajes
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: tipo.color,
        duration: tipo.duracion,
        elevation: 6,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        // Sin relleno propio: el relleno va dentro del contenido, para que el toque cubra TODO el aviso.
        padding: EdgeInsets.zero,
        dismissDirection: DismissDirection.horizontal,
        content: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: mensajes.hideCurrentSnackBar,
          child: Semantics(
            liveRegion: true,
            hint: 'Toca para cerrar',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(tipo.icono, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      texto,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
}
