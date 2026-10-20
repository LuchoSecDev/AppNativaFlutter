import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/colores.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../cierre_providers.dart';
import 'cierre_sin_confirmar.dart';
import 'comprobante_de_cierre.dart';
import 'desglose_del_arqueo.dart';
import 'desglose_por_metodo.dart';
import 'tarjeta_de_diferencia.dart';

/// Cerrar la caja en tres tiempos: 1) contar y escribir el total, 2) VER cuánto debería haber y la diferencia (y poder
/// recontar) y 3) confirmar. El arqueo del paso 2 no cierra nada: solo el botón «Confirmar cierre» lo hace.
class CerrarCajaScreen extends ConsumerStatefulWidget {
  const CerrarCajaScreen({super.key});

  @override
  ConsumerState<CerrarCajaScreen> createState() => _CerrarCajaScreenState();
}

class _CerrarCajaScreenState extends ConsumerState<CerrarCajaScreen> {
  /// Hasta 9 dígitos (999.999.999 pesos): evita un número absurdo por un dedo pegado a la tecla.
  static const int _maximoDeDigitos = 9;

  final _contado = TextEditingController();
  String? _avisoDelCampo;

  @override
  void initState() {
    super.initState();
    // Riverpod no deja cambiar un provider mientras se construye el árbol: se espera a que termine.
    Future.microtask(() {
      if (mounted) {
        ref.read(cierreProvider.notifier).iniciar();
        final declarado = ref.read(cierreProvider).declaradoPesos;
        if (declarado != null) {
          _contado.text = declarado.toString();
        }
      }
    });
  }

  @override
  void dispose() {
    _contado.dispose();
    super.dispose();
  }

  void _verArqueo() {
    final pesos = int.tryParse(_contado.text);
    if (pesos == null) {
      setState(
        () => _avisoDelCampo =
            'Escribe cuánto contaste en el cajón (0 si no hay efectivo).',
      );
      return;
    }
    setState(() => _avisoDelCampo = null);
    ref.read(cierreProvider.notifier).verArqueo(pesos);
  }

  @override
  Widget build(BuildContext context) {
    final cierre = ref.watch(cierreProvider);

    // Al recontar se vuelve al campo con lo que había escrito.
    ref.listen(cierreProvider, (anterior, nuevo) {
      if (nuevo.fase == FaseCierre.contando &&
          nuevo.declaradoPesos != null &&
          _contado.text != nuevo.declaradoPesos.toString()) {
        _contado.text = nuevo.declaradoPesos.toString();
      }
    });

    return PopScope(
      // Si sale sin terminar, la próxima vez empieza de cero (salvo que haya algo en curso).
      onPopInvokedWithResult: (salio, _) {
        if (salio) {
          ref.read(cierreProvider.notifier).iniciar();
        }
      },
      child: Scaffold(
        backgroundColor: Colores.papel,
        appBar: AppBar(
          title: Text(switch (cierre.fase) {
            FaseCierre.contando || FaseCierre.calculando => 'Cerrar caja',
            FaseCierre.revisando || FaseCierre.cerrando => 'Revisar arqueo',
            FaseCierre.cerrada => 'Caja cerrada',
            FaseCierre.sinConfirmar => 'Cerrar caja',
          }),
          // Mientras se cierra no se puede salir: se perdería el resultado.
          automaticallyImplyLeading: !cierre.enCurso,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: switch (cierre.fase) {
                  FaseCierre.contando ||
                  FaseCierre.calculando => _paso1(cierre),
                  FaseCierre.revisando || FaseCierre.cerrando => _paso2(cierre),
                  FaseCierre.cerrada => ComprobanteDeCierre(cierre: cierre),
                  FaseCierre.sinConfirmar => CierreSinConfirmar(cierre: cierre),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _paso1(EstadoCierre cierre) {
    final calculando = cierre.fase == FaseCierre.calculando;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Cuenta el efectivo que hay en el cajón y escribe el total. Después verás cuánto debería haber y la diferencia.',
          style: TextStyle(fontSize: 14, color: Colores.tinta),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _contado,
          enabled: !calculando,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_maximoDeDigitos),
          ],
          onSubmitted: (_) => _verArqueo(),
          decoration: InputDecoration(
            labelText: 'Efectivo contado',
            prefixText: r'$ ',
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
            errorText: _avisoDelCampo,
          ),
        ),
        const SizedBox(height: 16),
        if (cierre.mensaje != null) ...[
          CuadroDeMensaje(cierre.mensaje!),
          const SizedBox(height: 16),
        ],
        BotonPrincipal(
          texto: 'Ver arqueo',
          enEspera: calculando,
          alPulsar: _verArqueo,
        ),
      ],
    );
  }

  Widget _paso2(EstadoCierre cierre) {
    final arqueo = cierre.arqueoPrevio!;
    final cerrando = cierre.fase == FaseCierre.cerrando;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Esto es lo que debería haber en el cajón',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colores.tinta),
        ),
        const SizedBox(height: 12),
        DesgloseDelArqueo(arqueo: arqueo),
        const SizedBox(height: 16),
        TarjetaDeDiferencia(arqueo: arqueo),
        DesglosePorMetodo(arqueo: arqueo),
        const SizedBox(height: 12),
        const Text(
          'Solo el efectivo entra al cajón: lo vendido con tarjeta, transferencia o fiado no se cuenta en lo que debería haber. Si se registra algo mientras revisas, el arqueo final puede cambiar.',
          style: TextStyle(fontSize: 12, color: Colores.tinta),
        ),
        if (cierre.mensaje != null) ...[
          const SizedBox(height: 12),
          CuadroDeMensaje(cierre.mensaje!),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: cerrando
                      ? null
                      : () => ref.read(cierreProvider.notifier).recontar(),
                  icon: const Icon(Icons.replay),
                  label: const Text('Recontar'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BotonPrincipal(
                texto: 'Confirmar cierre',
                enEspera: cerrando,
                alPulsar: () => ref.read(cierreProvider.notifier).confirmar(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
