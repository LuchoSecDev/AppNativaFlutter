import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Qué tan fuerte vibra el celular: más fuerte, más importante o más grave es lo que pasó.
///
/// Se usa solo la vibración que trae Flutter (`HapticFeedback`): no necesita ninguna dependencia ni permiso de Android.
/// Respeta el ajuste del sistema «vibración al tocar»: si la persona lo apagó, no vibra. Por eso la vibración **nunca**
/// es la única forma de enterarse de algo: siempre va acompañada de lo que se ve en pantalla.
enum Intensidad { suave, media, fuerte }

/// Vibra una vez con la [intensidad] dada.
///
/// Úsala en lo que importa (una venta registrada, un rechazo, un código leído), no en cada toque: si todo vibra, la
/// vibración deja de significar algo.
void vibrar(Intensidad intensidad) {
  switch (intensidad) {
    case Intensidad.suave:
      HapticFeedback.lightImpact();
    case Intensidad.media:
      HapticFeedback.mediumImpact();
    case Intensidad.fuerte:
      HapticFeedback.heavyImpact();
  }
}

/// Vibra **una sola vez**, cuando [child] aparece en pantalla (por ejemplo, el comprobante de una venta).
///
/// No vuelve a vibrar cuando el padre se redibuja, solo si el widget se quita y se vuelve a poner.
class VibrarAlAparecer extends StatefulWidget {
  const VibrarAlAparecer({
    super.key,
    required this.intensidad,
    required this.child,
  });

  final Intensidad intensidad;
  final Widget child;

  @override
  State<VibrarAlAparecer> createState() => _VibrarAlAparecerState();
}

class _VibrarAlAparecerState extends State<VibrarAlAparecer> {
  @override
  void initState() {
    super.initState();
    vibrar(widget.intensidad);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
