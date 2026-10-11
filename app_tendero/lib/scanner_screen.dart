import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'scan_stabilizer.dart';
import 'vista_de_escaneo.dart';

/// Pantalla de DIAGNÓSTICO del escáner (paso 1): lee un código y lo muestra, sin tocar el carrito ni el servidor.
/// Para vender con el escáner está `EscanerVentaScreen`; las dos comparten la cámara (`VistaDeEscaneo`).
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController cameraController = crearControladorDeEscaneo();

  String? confirmedCode;
  bool isPaused = false;

  // Estabilización: confirma un código solo tras varias lecturas iguales seguidas.
  final ScanStabilizer _stabilizer = ScanStabilizer();

  void _onConfirmado(String code) {
    setState(() {
      confirmedCode = code;
      isPaused = true;
    });
  }

  void _resumeScanning() {
    _stabilizer.reset();
    setState(() {
      isPaused = false;
      confirmedCode = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prueba de Escáner'),
        actions: accionesDeCamara(cameraController),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: VistaDeEscaneo(
              controlador: cameraController,
              estabilizador: _stabilizer,
              pausado: isPaused,
              alConfirmar: _onConfirmado,
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
    cameraController.dispose();
    super.dispose();
  }
}
