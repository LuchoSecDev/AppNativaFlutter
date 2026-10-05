import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'api/cookie_jar_factory.dart';
import 'auth/auth_providers.dart';
import 'auth/ui/auth_gate.dart';
import 'carrito/almacen_carrito.dart';
import 'carrito/carrito_providers.dart';
import 'config/app_config.dart';
import 'scanner_screen.dart';
import 'venta/almacen_venta.dart';
import 'venta/venta_providers.dart';

Future<void> main() async {
  // Necesario antes de usar cualquier función de Flutter que hable con el sistema (carpetas, cámara...) antes
  // de que arranque la app.
  WidgetsFlutterBinding.ensureInitialized();

  // Sin la dirección del servidor la app no puede funcionar: se explica cómo ejecutarla en vez de fallar callada.
  if (AppConfig.apiBaseUrl.isEmpty) {
    runApp(const PantallaSinConfiguracion());
    return;
  }

  // Canal por el que el cliente HTTP avisa «el servidor dice que ya no hay sesión».
  final caducidad = StreamController<void>.broadcast();

  // La cookie de sesión se guarda en disco para que sobreviva a cerrar la app.
  final cookieJar = await crearCookieJarPersistente();
  final dio = crearClienteApi(
    baseUrl: AppConfig.apiBaseUrl,
    cookieJar: cookieJar,
    onSessionExpired: () => caducidad.add(null),
  );

  // Almacenamiento local del celular, donde se guarda el carrito y la venta que se está cobrando.
  final preferencias = await SharedPreferences.getInstance();

  runApp(
    // ProviderScope es donde viven los providers de Riverpod. Aquí se les entregan las piezas reales (cliente HTTP
    // y canal de caducidad) que `auth_providers.dart` declara pero no sabe crear.
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        sesionCaducadaProvider.overrideWithValue(caducidad.stream),
        almacenCarritoProvider.overrideWithValue(
          AlmacenCarritoLocal(preferencias),
        ),
        almacenVentaPendienteProvider.overrideWithValue(
          AlmacenVentaPendienteLocal(preferencias),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StockPilot',
      theme: _tema(),
      home: const AuthGate(),
    );
  }
}

ThemeData _tema() => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF252C93), // color-azul
    primary: const Color(0xFF252C93),
    secondary: const Color(0xFFFFD84A), // color-resaltador
    surface: const Color(0xFFEEF0F8), // color-papel
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF14173F), // color-tinta
    foregroundColor: Colors.white,
  ),
  useMaterial3: true,
);

/// Se muestra si se ejecutó sin `--dart-define=API_BASE_URL=...`. En depuración permite igualmente probar el
/// escáner, que no necesita servidor.
class PantallaSinConfiguracion extends StatelessWidget {
  const PantallaSinConfiguracion({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StockPilot',
      theme: _tema(),
      home: Scaffold(
        appBar: AppBar(title: const Text('StockPilot')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Builder(
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Falta la dirección del servidor',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text('Ejecuta la app indicándola así:'),
                const SizedBox(height: 8),
                const SelectableText(
                  'flutter run --dart-define=API_BASE_URL=https://...',
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ScannerScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Probar solo el escáner'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
