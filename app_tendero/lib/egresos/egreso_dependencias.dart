import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'almacen_egreso.dart';
import 'egreso_repository.dart';

/// Dónde se guarda el egreso que se está registrando. `main()` lo sustituye por el real (`shared_preferences`); las
/// pruebas, por uno en memoria.
final almacenEgresoPendienteProvider = Provider<AlmacenEgresoPendiente>(
  (ref) => throw UnimplementedError(
    'almacenEgresoPendienteProvider se sustituye en main()',
  ),
);

final egresoRepositoryProvider = Provider<EgresoRepository>(
  (ref) => EgresoRepository(ref.watch(dioProvider)),
);
