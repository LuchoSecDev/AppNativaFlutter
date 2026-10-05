import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../carrito/carrito_providers.dart';
import '../../catalogo/catalogo_providers.dart';
import '../../ui/colores.dart';
import '../../ui/dinero.dart';
import '../../ui/formato.dart';
import '../../ui/piezas_de_pantalla.dart';
import '../venta_models.dart';
import '../venta_providers.dart';

/// Cobrar el carrito en efectivo: confirma el total, pide cuánto entregó el cliente y muestra el cambio.
///
/// Antes de mostrar el total se VUELVE A DESCARGAR el catálogo. El servidor cobra con los precios que tiene en ese
/// momento y la app no lo puede saber de otra forma: si el Administrador cambió un precio desde la última descarga,
/// el total que ve el Tendero no sería el que queda registrado.
class CobrarEfectivoScreen extends ConsumerStatefulWidget {
  const CobrarEfectivoScreen({super.key});

  @override
  ConsumerState<CobrarEfectivoScreen> createState() =>
      _CobrarEfectivoScreenState();
}

class _CobrarEfectivoScreenState extends ConsumerState<CobrarEfectivoScreen> {
  /// Hasta 9 dígitos (999.999.999 pesos): evita un número absurdo por un dedo pegado a la tecla.
  static const int _maximoDeDigitos = 9;

  final _recibido = TextEditingController();

  /// El total que tenía el carrito al pulsar «Cobrar»: sirve para avisar si la verificación lo cambió.
  late final int _totalAlAbrir;

  /// `null` mientras se verifica; `true` si los precios quedaron al día; `false` si no se pudo verificar.
  bool? _preciosAlDia;

  @override
  void initState() {
    super.initState();
    _totalAlAbrir = ref.read(resumenCarritoProvider).totalCentavos;
    // Riverpod no deja cambiar un provider mientras se construye el árbol de widgets (y descargar el catálogo cambia
    // su estado al empezar): se espera a que termine la construcción.
    Future.microtask(_verificarPrecios);
  }

  @override
  void dispose() {
    _recibido.dispose();
    super.dispose();
  }

  Future<void> _verificarPrecios() async {
    setState(() => _preciosAlDia = null);
    final alDia = await ref.read(catalogoProvider.notifier).cargar();
    if (mounted) {
      setState(() => _preciosAlDia = alDia);
    }
  }

  /// Pesos enteros escritos, o `null` si el campo está vacío.
  int? get _efectivo => int.tryParse(_recibido.text);

  void _cobrar(int total) {
    final efectivo = _efectivo;
    if (efectivo == null || efectivo * 100 < total) {
      return;
    }
    // No se espera el resultado aquí: la pantalla del carrito muestra el envío, los reintentos y el desenlace.
    ref
        .read(cobroProvider.notifier)
        .cobrar(metodo: MetodoPago.efectivo, efectivoRecibido: efectivo);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final resumen = ref.watch(resumenCarritoProvider);
    final total = resumen.totalCentavos;

    return Scaffold(
      backgroundColor: Colores.papel,
      appBar: AppBar(title: const Text('Cobrar en efectivo')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: switch (_preciosAlDia) {
                null => const _Verificando(),
                false => _NoSePudoVerificar(
                  alReintentar: _verificarPrecios,
                  alVolver: () => Navigator.of(context).pop(),
                ),
                true =>
                  !resumen.sePuedeCobrar
                      ? _CarritoCambio(
                          alVolver: () => Navigator.of(context).pop(),
                        )
                      : _formulario(total),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _formulario(int total) {
    final efectivo = _efectivo;
    final alcanza = efectivo != null && efectivo * 100 >= total;
    final diferencia = efectivo == null ? null : efectivo * 100 - total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Total a cobrar',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colores.tinta),
        ),
        Text(
          formatoPesos(importeDeCentavos(total)),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: Colores.tinta,
          ),
        ),
        if (total != _totalAlAbrir) ...[
          const SizedBox(height: 12),
          CuadroDeMensaje(
            'El total cambió al actualizar los precios: antes era ${formatoPesos(importeDeCentavos(_totalAlAbrir))}.',
            esError: false,
          ),
        ],
        const SizedBox(height: 24),
        TextField(
          controller: _recibido,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_maximoDeDigitos),
          ],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Efectivo recibido',
            prefixText: r'$ ',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () {
              // El cliente entrega pesos enteros: con centavos en el total, el «exacto» es el entero siguiente.
              _recibido.text = ((total + 99) ~/ 100).toString();
              setState(() {});
            },
            child: const Text('Monto exacto'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 28,
          child: diferencia == null
              ? null
              : alcanza
              ? Text(
                  'Cambio: ${formatoPesos(importeDeCentavos(diferencia))}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colores.exito,
                  ),
                )
              : Text(
                  'Faltan ${formatoPesos(importeDeCentavos(-diferencia))}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colores.peligro,
                  ),
                ),
        ),
        const SizedBox(height: 16),
        BotonPrincipal(
          texto: 'Confirmar cobro',
          alPulsar: alcanza ? () => _cobrar(total) : null,
        ),
      ],
    );
  }
}

class _Verificando extends StatelessWidget {
  const _Verificando();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text(
          'Verificando los precios…',
          style: TextStyle(fontSize: 16, color: Colores.tinta),
        ),
      ],
    );
  }
}

class _NoSePudoVerificar extends StatelessWidget {
  const _NoSePudoVerificar({
    required this.alReintentar,
    required this.alVolver,
  });

  final VoidCallback alReintentar;
  final VoidCallback alVolver;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CuadroDeMensaje(
          'No se pudo verificar los precios con el servidor, así que no se puede cobrar con seguridad. Revisa tu conexión.',
        ),
        const SizedBox(height: 16),
        BotonPrincipal(texto: 'Reintentar', alPulsar: alReintentar),
        const SizedBox(height: 8),
        TextButton(onPressed: alVolver, child: const Text('Volver al carrito')),
      ],
    );
  }
}

class _CarritoCambio extends StatelessWidget {
  const _CarritoCambio({required this.alVolver});

  final VoidCallback alVolver;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CuadroDeMensaje(
          'Al actualizar el catálogo, algunos productos del carrito cambiaron y ya no se pueden cobrar. Revisa los marcados en rojo.',
        ),
        const SizedBox(height: 16),
        BotonPrincipal(texto: 'Volver al carrito', alPulsar: alVolver),
      ],
    );
  }
}
