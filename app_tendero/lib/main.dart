import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'scanner_screen.dart';

void main() {
  runApp(
    // Envolvemos la app en un ProviderScope de Riverpod según las decisiones técnicas
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StockPilot - Prueba Escáner',
      theme: ThemeData(
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
      ),
      home: const ScannerScreen(),
    );
  }
}
