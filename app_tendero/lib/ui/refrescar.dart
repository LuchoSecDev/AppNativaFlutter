import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../caja/caja_providers.dart';
import '../catalogo/catalogo_providers.dart';

/// Lo que puede cambiar FUERA de la app mientras está abierta: la caja (alguien la cierra o la abre desde la web) y los
/// productos (precio, stock). La app no se entera sola de esos cambios, así que se vuelve a preguntar al servidor.
///
/// Devuelve `true` si la lista de productos quedó al día (la caja se actualiza en silencio: si no hay red conserva lo
/// que se veía).
Future<bool> refrescarCajaYCatalogo(WidgetRef ref) async {
  final caja = ref.read(cajaProvider.notifier).actualizar();
  final productos = ref.read(catalogoProvider.notifier).cargar();
  await caja;
  return productos;
}

/// Igual, para un botón «Actualizar»: además avisa que se hizo, o que no se pudo.
Future<void> refrescarConAviso(BuildContext context, WidgetRef ref) async {
  final alDia = await refrescarCajaYCatalogo(ref);
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          alDia ? 'Actualizado.' : 'No se pudo actualizar. Revisa tu conexión.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
}

/// Al volver a la app (por ejemplo, después de cerrar la caja en la web o de dejar el celular un rato), vuelve a
/// consultar la caja y los productos. Va una sola vez, en la pantalla de inicio, que está debajo de todas las demás.
class RefrescarAlVolver extends ConsumerStatefulWidget {
  const RefrescarAlVolver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RefrescarAlVolver> createState() => _RefrescarAlVolverState();
}

class _RefrescarAlVolverState extends ConsumerState<RefrescarAlVolver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refrescarCajaYCatalogo(ref);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
