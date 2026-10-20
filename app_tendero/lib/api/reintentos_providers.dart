import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'clave_de_idempotencia.dart';

/// Piezas genéricas de toda escritura con `Idempotency-Key` (la venta `[V2]`, el egreso `[K4]` y, más adelante, la
/// entrada de mercancía `[M1]`): de dónde sale la clave y cómo se reintenta. Son providers para que las pruebas puedan
/// fijarlas y no esperar de verdad.

/// De dónde sale la `Idempotency-Key` de cada operación.
final generadorDeClaveProvider = Provider<String Function()>(
  (ref) => generarUuidV4,
);

/// Cuánto se espera antes de cada reintento automático tras un tiempo agotado o un error del servidor: 2 s y luego
/// 5 s (contrato [V2] y [K4]). Si tras eso sigue sin respuesta, decide el Tendero.
final esperasDeReintentoProvider = Provider<List<Duration>>(
  (ref) => const [Duration(seconds: 2), Duration(seconds: 5)],
);

/// La pausa entre reintentos.
final pausaDeReintentoProvider = Provider<Future<void> Function(Duration)>(
  (ref) =>
      (duracion) => Future<void>.delayed(duracion),
);
