import 'package:flutter/material.dart';

import 'colores.dart';

/// Estructura común de las pantallas de entrada (login, código, contraseña): marca arriba, título, y el
/// contenido en una columna centrada que no se estira demasiado en pantallas grandes.
///
/// Está dentro de un `SingleChildScrollView` para que, cuando aparezca el teclado y falte espacio, la pantalla
/// se pueda desplazar en vez de dar error de desbordamiento.
class PantallaDeEntrada extends StatelessWidget {
  const PantallaDeEntrada({
    super.key,
    required this.titulo,
    this.subtitulo,
    required this.hijos,
  });

  final String titulo;
  final String? subtitulo;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colores.papel,
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
                    'StockPilot',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colores.azul,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colores.tinta,
                    ),
                  ),
                  if (subtitulo != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitulo!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colores.tinta,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ...hijos,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Recuadro para un error (rojo) o un aviso (ámbar), con el texto siempre visible y legible.
class CuadroDeMensaje extends StatelessWidget {
  const CuadroDeMensaje(this.texto, {super.key, this.esError = true});

  final String texto;
  final bool esError;

  @override
  Widget build(BuildContext context) {
    final fondo = esError ? Colores.peligroSuave : Colores.avisoSuave;
    final color = esError ? Colores.peligro : Colores.aviso;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            esError ? Icons.error_outline : Icons.info_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: TextStyle(color: color, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

/// Botón principal. Mientras [enEspera] es `true` muestra una ruedita y no responde a toques, para que un doble
/// toque no envíe la misma petición dos veces.
class BotonPrincipal extends StatelessWidget {
  const BotonPrincipal({
    super.key,
    required this.texto,
    required this.alPulsar,
    this.enEspera = false,
  });

  final String texto;

  /// `null` deshabilita el botón.
  final VoidCallback? alPulsar;
  final bool enEspera;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: enEspera ? null : alPulsar,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colores.azul,
          foregroundColor: Colors.white,
        ),
        child: enEspera
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(texto, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
