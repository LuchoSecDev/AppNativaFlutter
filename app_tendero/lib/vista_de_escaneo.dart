import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'scan_stabilizer.dart';

/// Interruptor de la zona de lectura. `true`: el lector solo analiza lo que está dentro del recuadro.
/// `false`: analiza toda la imagen de la cámara (el comportamiento anterior).
const bool _usarVentanaDeEscaneo = true;

/// El lector con los formatos que usa la app. Lo crea y lo destruye (`dispose`) quien muestra la pantalla.
MobileScannerController crearControladorDeEscaneo() => MobileScannerController(
  detectionSpeed: DetectionSpeed.normal,
  formats: const [
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.code128,
    BarcodeFormat.qrCode,
  ],
);

/// Los botones de linterna y de cambio de cámara para la barra superior.
List<Widget> accionesDeCamara(MobileScannerController controlador) => [
  ValueListenableBuilder(
    valueListenable: controlador,
    builder: (context, state, child) {
      final torchState = state.torchState;
      return IconButton(
        icon: Icon(
          torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
          color: torchState == TorchState.on ? Colors.yellow : Colors.grey,
        ),
        iconSize: 28.0,
        onPressed: () => controlador.toggleTorch(),
      );
    },
  ),
  ValueListenableBuilder(
    valueListenable: controlador,
    builder: (context, state, child) {
      final facing = state.cameraDirection;
      return IconButton(
        icon: Icon(
          facing == CameraFacing.front ? Icons.camera_front : Icons.camera_rear,
        ),
        iconSize: 28.0,
        onPressed: () => controlador.switchCamera(),
      );
    },
  ),
];

/// La vista previa de la cámara con el recuadro de lectura. Es la MISMA para la pantalla de diagnóstico y para la de
/// vender: así el recuadro, la zona que el lector analiza y las 3 lecturas iguales no pueden diferir entre las dos.
///
/// Cada lectura pasa por el [estabilizador]. Cuando un código se confirma llama a [alConfirmar]. Mientras
/// [pausado] es `true` no confirma nada (el que la usa está procesando el código anterior).
class VistaDeEscaneo extends StatefulWidget {
  const VistaDeEscaneo({
    super.key,
    required this.controlador,
    required this.estabilizador,
    required this.pausado,
    required this.alConfirmar,
  });

  final MobileScannerController controlador;
  final ScanStabilizer estabilizador;
  final bool pausado;
  final ValueChanged<String> alConfirmar;

  @override
  State<VistaDeEscaneo> createState() => _VistaDeEscaneoState();
}

class _VistaDeEscaneoState extends State<VistaDeEscaneo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (!widget.pausado) {
      _animationController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant VistaDeEscaneo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pausado != widget.pausado) {
      if (widget.pausado) {
        _animationController.stop();
      } else {
        _animationController.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    final confirmed = widget.estabilizador.leer(code, pausado: widget.pausado);
    if (confirmed != null) {
      HapticFeedback.mediumImpact();
      widget.alConfirmar(confirmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
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
              controller: widget.controlador,
              // Solo se leen los códigos dentro del recuadro (evita leer el del producto de al lado).
              // Si en las pruebas con celulares reales da problemas, poner _usarVentanaDeEscaneo en false.
              scanWindow: _usarVentanaDeEscaneo ? scanWindow : null,
              onDetect: _onDetect,
              // Sin esto, si el usuario niega el permiso o la cámara falla, la pantalla queda vacía.
              errorBuilder: (context, error) => _CameraError(error: error),
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
                        border: Border.all(color: Colors.white70, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    // Línea animada
                    if (!widget.pausado)
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
            if (widget.pausado)
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
    );
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
