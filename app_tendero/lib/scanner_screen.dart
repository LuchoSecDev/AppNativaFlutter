import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'scan_stabilizer.dart';
import 'catalogo/catalogo_providers.dart';
import 'carrito/carrito_providers.dart';
import 'carrito/carrito_models.dart';
import 'catalogo/ui/buscar_producto_screen.dart';
import 'catalogo/producto.dart';

/// Interruptor de la zona de lectura. `true`: el lector solo analiza lo que está dentro del recuadro.
/// `false`: analiza toda la imagen de la cámara (el comportamiento anterior).
const bool _usarVentanaDeEscaneo = true;

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.code128,
      BarcodeFormat.qrCode,
    ],
  );

  String? confirmedCode;
  bool isPaused = false;

  // --- Estabilización: confirma un código solo tras varias lecturas iguales seguidas ---
  final ScanStabilizer _stabilizer = ScanStabilizer();

  // --- Animación ---
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  bool _procesando = false;

  void _onDetect(BarcodeCapture capture) async {
    if (isPaused || _procesando) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    final confirmed = _stabilizer.register(code);
    if (confirmed != null) {
      HapticFeedback.mediumImpact();
      setState(() {
        confirmedCode = confirmed;
        isPaused = true;
        _procesando = true;
      });
      _animationController.stop();

      final repo = ref.read(catalogoRepositoryProvider);
      try {
        final producto = await repo.buscarPorCodigoBarras(confirmed);
        if (!mounted) return;
        if (producto != null) {
          final res = ref.read(carritoProvider.notifier).agregar(producto);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res == ResultadoAgregar.agregado ? 'Agregado al carrito' : 'No se pudo agregar: ${res.name}'),
              backgroundColor: const Color(0xFF0B6B45),
            ),
          );
        } else {
          // Mostrar diálogo para vincular
          _mostrarVincularCodigo(confirmed);
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _procesando = false);
      }
    }
  }

  void _mostrarVincularCodigo(String code) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Código no encontrado'),
        content: Text('El código $code no está vinculado a ningún producto. ¿Deseas vincularlo ahora?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resumeScanning();
            },
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _seleccionarParaVincular(code);
            },
            child: const Text('Vincular'),
          ),
        ],
      ),
    );
  }

  Future<void> _seleccionarParaVincular(String code) async {
    // Import needed at the top: import 'catalogo/ui/buscar_producto_screen.dart';
    final producto = await Navigator.push<Producto>(
      context,
      MaterialPageRoute(
        builder: (_) => BuscarProductoScreen(
          alElegir: (p) => null, // Acepta cualquiera, o podríamos restringir
        ),
      ),
    );

    if (producto == null) {
      _resumeScanning();
      return;
    }

    if (!mounted) return;

    setState(() => _procesando = true);
    final repo = ref.read(catalogoRepositoryProvider);
    try {
      await repo.vincularCodigoBarras(producto.id, code);
      if (!mounted) return;
      
      // Actualizar el catálogo
      await ref.read(catalogoProvider.notifier).cargar();
      
      if (!mounted) return;
      // Y agregar al carrito (usamos el producto original ya que la estructura base es la misma
      // o buscamos el nuevo en el catálogo). Mejor el producto con el código añadido.
      final pActualizado = Producto(
        id: producto.id,
        codigo: producto.codigo,
        codigoBarras: code,
        nombre: producto.nombre,
        categoria: producto.categoria,
        precio: producto.precio,
        cantidad: producto.cantidad,
        estado: producto.estado,
        nivelStock: producto.nivelStock,
      );
      final res = ref.read(carritoProvider.notifier).agregar(pActualizado);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vinculado y ${res == ResultadoAgregar.agregado ? 'agregado' : 'no agregado (${res.name})'}'),
          backgroundColor: const Color(0xFF0B6B45),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al vincular: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) _resumeScanning();
    }
  }

  void _resumeScanning() {
    _stabilizer.reset();
    setState(() {
      isPaused = false;
      confirmedCode = null;
      _procesando = false;
    });
    _animationController.repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prueba de Escáner'),
        actions: [
          ValueListenableBuilder(
            valueListenable: cameraController,
            builder: (context, state, child) {
              final torchState = state.torchState;
              return IconButton(
                icon: Icon(
                  torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                  color: torchState == TorchState.on
                      ? Colors.yellow
                      : Colors.grey,
                ),
                iconSize: 28.0,
                onPressed: () => cameraController.toggleTorch(),
              );
            },
          ),
          ValueListenableBuilder(
            valueListenable: cameraController,
            builder: (context, state, child) {
              final facing = state.cameraDirection;
              return IconButton(
                icon: Icon(
                  facing == CameraFacing.front
                      ? Icons.camera_front
                      : Icons.camera_rear,
                ),
                iconSize: 28.0,
                onPressed: () => cameraController.switchCamera(),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // El recuadro que se dibuja y la zona que el lector realmente analiza salen del MISMO cálculo,
                // sobre el tamaño de esta vista previa, para que siempre coincidan.
                final scanWindowWidth = constraints.maxWidth * 0.75;
                final scanWindowHeight =
                    scanWindowWidth *
                    0.6; // Proporción rectangular para códigos de barras
                final scanWindow = Rect.fromCenter(
                  center: constraints.biggest.center(Offset.zero),
                  width: scanWindowWidth,
                  height: scanWindowHeight,
                );
                return Stack(
                  children: [
                    MobileScanner(
                      controller: cameraController,
                      // Solo se leen los códigos dentro del recuadro (evita leer el del producto de al lado).
                      // Si en las pruebas con celulares reales da problemas, poner _usarVentanaDeEscaneo en false.
                      scanWindow: _usarVentanaDeEscaneo ? scanWindow : null,
                      onDetect: _onDetect,
                      // Sin esto, si el usuario niega el permiso o la cámara falla, la pantalla queda vacía.
                      errorBuilder: (context, error) =>
                          _CameraError(error: error),
                    ),
                    // Overlay oscuro con recorte central
                    ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.7),
                        BlendMode.srcOut,
                      ),
                      child: Stack(
                        children: [
                          Container(
                            decoration: const BoxDecoration(
                              color: Colors.black,
                              backgroundBlendMode: BlendMode.dstOut,
                            ),
                          ),
                          Center(
                            child: Container(
                              width: scanWindowWidth,
                              height: scanWindowHeight,
                              decoration: BoxDecoration(
                                color: Colors.black, // Este color se vuelve transparente por el BlendMode
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Bordes del recuadro y línea animada
                    Center(
                      child: SizedBox(
                        width: scanWindowWidth,
                        height: scanWindowHeight,
                        child: Stack(
                          children: [
                            // Borde blanco
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white70,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            // Esquinas resaltadas (decoración visual extra)
                            // Línea roja animada
                            if (!isPaused)
                              AnimatedBuilder(
                                animation: _animationController,
                                builder: (context, child) {
                                  return Positioned(
                                    top:
                                        (_animationController.value *
                                            (scanWindowHeight - 4)) +
                                        2,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      height: 2,
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFFFD84A,
                                        ), // color-resaltador
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFFFD84A)
                                                .withValues(alpha: 0.5),
                                            blurRadius: 4,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Overlay de confirmación (Check verde)
                    if (isPaused)
                      Container(
                        color: Colors.black.withValues(alpha: 0.5),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.check_circle,
                          color: Color(0xFFDDF3E9), // color-exito-suave
                          size: 80,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 20.0,
            ),
            color: confirmedCode != null
                ? const Color(0xFF0B6B45)
                : const Color(0xFF14173F), // color-exito o color-tinta
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  confirmedCode != null
                      ? '✅ Código: $confirmedCode'
                      : 'Centra el código en el recuadro',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (confirmedCode != null) ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _resumeScanning,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Escanear otro'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0B6B45),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    cameraController.dispose();
    super.dispose();
  }
}

/// Mensaje que se muestra cuando la cámara no puede iniciarse (permiso denegado, sin cámara, etc.).
class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  String get _message {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Falta el permiso de la cámara.\n'
            'Actívalo en Ajustes > Aplicaciones > StockPilot > Permisos.';
      case MobileScannerErrorCode.unsupported:
        return 'Este dispositivo no tiene una cámara compatible con el escáner.';
      default:
        return 'No se pudo iniciar la cámara.\nCierra y vuelve a abrir la pantalla.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF14173F), // color-tinta
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography, color: Colors.white70, size: 56),
          const SizedBox(height: 16),
          Text(
            _message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
