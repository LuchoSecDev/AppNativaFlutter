import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'almacen_venta.dart';
import 'clave_de_venta.dart';
import 'venta_repository.dart';

/// Dónde se guarda la venta que se está cobrando. `main()` lo sustituye por el real (`shared_preferences`); las
/// pruebas, por uno en memoria.
final almacenVentaPendienteProvider = Provider<AlmacenVentaPendiente>(
  (ref) => throw UnimplementedError(
    'almacenVentaPendienteProvider se sustituye en main()',
  ),
);

final ventaRepositoryProvider = Provider<VentaRepository>(
  (ref) => VentaRepository(ref.watch(dioProvider)),
);

/// De dónde sale la `Idempotency-Key` de cada venta. Es un provider para que las pruebas puedan fijarla.
final generadorDeClaveProvider = Provider<String Function()>(
  (ref) => generarUuidV4,
);

/// Cuánto se espera antes de cada reintento automático tras un tiempo agotado o un error del servidor: 2 s y luego
/// 5 s (contrato [V2]). Si tras eso sigue sin respuesta, decide el Tendero.
final esperasDeReintentoProvider = Provider<List<Duration>>(
  (ref) => const [Duration(seconds: 2), Duration(seconds: 5)],
);

/// La pausa entre reintentos. Es un provider para que las pruebas no esperen de verdad.
final pausaDeReintentoProvider = Provider<Future<void> Function(Duration)>(
  (ref) =>
      (duracion) => Future<void>.delayed(duracion),
);
