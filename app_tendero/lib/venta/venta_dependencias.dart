import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'almacen_venta.dart';
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
