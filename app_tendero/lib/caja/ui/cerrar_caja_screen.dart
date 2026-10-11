import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/colores.dart';
import '../../ui/dinero.dart';
import '../../ui/formato.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../caja_models.dart';
import '../cierre_providers.dart';

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
                  FaseCierre.cerrada => _Cerrada(cierre: cierre),
                  FaseCierre.sinConfirmar => _SinConfirmar(cierre: cierre),
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
        _Desglose(arqueo: arqueo),
        const SizedBox(height: 16),
        _TarjetaDeDiferencia(arqueo: arqueo),
        _DesglosePorMetodo(arqueo: arqueo),
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

/// De dónde sale lo que debería haber: fondo inicial, ventas, abonos y egresos, y el total contado.
class _Desglose extends StatelessWidget {
  const _Desglose({required this.arqueo});

  final ArqueoCaja arqueo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          _Renglon('Fondo inicial', arqueo.aperturaCentavos),
          _Renglon('+ Ventas en efectivo', arqueo.ventasEfectivoCentavos),
          _Renglon('+ Abonos en efectivo', arqueo.abonosEfectivoCentavos),
          _Renglon('− Egresos (gastos)', arqueo.egresosCentavos),
          const Divider(height: 20),
          _Renglon('Debería haber', arqueo.esperadoCentavos, destacado: true),
          _Renglon('Tú contaste', arqueo.declaradoCentavos, destacado: true),
        ],
      ),
    );
  }
}

class _Renglon extends StatelessWidget {
  const _Renglon(this.etiqueta, this.centavos, {this.destacado = false});

  final String etiqueta;
  final int centavos;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      fontSize: destacado ? 16 : 14,
      fontWeight: destacado ? FontWeight.w800 : FontWeight.w500,
      color: Colores.tinta,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: estilo),
          Text(formatoPesos(importeDeCentavos(centavos)), style: estilo),
        ],
      ),
    );
  }
}

/// «Cuadra», «Sobra» o «Falta», con su color.
class _TarjetaDeDiferencia extends StatelessWidget {
  const _TarjetaDeDiferencia({required this.arqueo});

  final ArqueoCaja arqueo;

  @override
  Widget build(BuildContext context) {
    final (fondo, color) = switch (arqueo.tipo) {
      TipoDiferencia.cuadra => (const Color(0xFFDDF3E9), Colores.exito),
      TipoDiferencia.sobra => (Colores.avisoSuave, Colores.aviso),
      TipoDiferencia.falta => (Colores.peligroSuave, Colores.peligro),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            arqueo.tituloDeLaDiferencia,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            arqueo.detalleDeLaDiferencia,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// El comprobante: la caja quedó cerrada, con el arqueo final.
class _Cerrada extends ConsumerWidget {
  const _Cerrada({required this.cierre});

  final EstadoCierre cierre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arqueo = cierre.arqueoFinal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock, size: 56, color: Colores.exito),
        const SizedBox(height: 8),
        const Text(
          'Caja cerrada',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colores.tinta,
          ),
        ),
        if (cierre.cambio) ...[
          const SizedBox(height: 12),
          const CuadroDeMensaje(
            'Mientras revisabas se registró un movimiento: este es el arqueo FINAL, distinto al que viste.',
            esError: false,
          ),
        ],
        if (arqueo != null) ...[
          const SizedBox(height: 16),
          _Desglose(arqueo: arqueo),
          const SizedBox(height: 16),
          _TarjetaDeDiferencia(arqueo: arqueo),
          _DesglosePorMetodo(arqueo: arqueo),
        ],
        if (cierre.mensaje != null) ...[
          const SizedBox(height: 12),
          CuadroDeMensaje(cierre.mensaje!, esError: false),
        ],
        const SizedBox(height: 24),
        BotonPrincipal(
          texto: 'Volver al inicio',
          alPulsar: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// No se sabe si la caja se cerró: solo se puede comprobar, nunca cerrar otra vez.
class _SinConfirmar extends ConsumerWidget {
  const _SinConfirmar({required this.cierre});

  final EstadoCierre cierre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CuadroDeMensaje(
          cierre.mensaje ?? 'No sabemos si la caja se cerró. Toca «Comprobar»; no la cierres otra vez.',
        ),
        const SizedBox(height: 16),
        BotonPrincipal(
          texto: 'Comprobar',
          alPulsar: () => ref.read(cierreProvider.notifier).comprobar(),
        ),
      ],
    );
  }
}

/// Lo vendido en el turno, separado por método de pago: es el desglose de auditoría. Solo el efectivo entra al cajón; el
/// resto se muestra aparte, marcado, para que se vea que no se olvidó. No se dibuja si el servidor no lo envió.
class _DesglosePorMetodo extends StatelessWidget {
  const _DesglosePorMetodo({required this.arqueo});

  final ArqueoCaja arqueo;

  @override
  Widget build(BuildContext context) {
    if (arqueo.ventasPorMetodo.isEmpty && arqueo.abonosPorMetodo.isEmpty) {
      return const SizedBox.shrink(); // un servidor anterior al desglose
    }
    final ventas = arqueo.ventasPorMetodo.where((m) => m.tieneMovimiento);
    final abonos = arqueo.abonosPorMetodo.where((m) => m.tieneMovimiento);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Lo vendido en el turno, por método de pago',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colores.tinta,
            ),
          ),
          const SizedBox(height: 6),
          if (ventas.isEmpty)
            const Text(
              'Sin ventas en este turno.',
              style: TextStyle(fontSize: 13, color: Colores.tinta),
            )
          else
            for (final m in ventas) _LineaDeMetodo(m, unidad: 'venta'),
          if (abonos.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Abonos de clientes',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colores.tinta,
              ),
            ),
            const SizedBox(height: 6),
            for (final m in abonos) _LineaDeMetodo(m, unidad: 'abono'),
          ],
        ],
      ),
    );
  }
}

class _LineaDeMetodo extends StatelessWidget {
  const _LineaDeMetodo(this.movimiento, {required this.unidad});

  final MovimientoPorMetodo movimiento;
  final String unidad;

  @override
  Widget build(BuildContext context) {
    final cantidad = movimiento.cantidad;
    final detalle =
        '$cantidad ${cantidad == 1 ? unidad : '${unidad}s'}${movimiento.entraAlCajon ? '' : ' · no entra al cajón'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: movimiento.etiqueta,
                    style: const TextStyle(fontSize: 13, color: Colores.tinta),
                  ),
                  TextSpan(
                    text: ' · $detalle',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          Text(
            formatoPesos(importeDeCentavos(movimiento.totalCentavos)),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colores.tinta,
            ),
          ),
        ],
      ),
    );
  }
}
