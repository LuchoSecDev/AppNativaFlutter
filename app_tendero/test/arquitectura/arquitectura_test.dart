import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reglas de arquitectura que no se negocian (AGENTS.md y la guía del equipo): archivos pequeños y los widgets sin hablar
/// con el servidor. Si una falla, el mensaje dice qué archivo y por qué.
void main() {
  /// Un archivo de `lib/` no pasa de estas líneas: una responsabilidad por archivo.
  const maximoLib = 300;

  /// Un archivo de `test/` no pasa de estas líneas.
  const maximoTest = 400;

  /// Deuda conocida: archivos que HOY pasan del máximo y hasta cuándo se les tolera (no pueden crecer más). Cuando se
  /// parta uno, se borra de aquí (si ya cumple el máximo, la entrada sobra pero no estorba); no se agregan archivos nuevos.
  const deudaLib = <String, int>{
    'lib/carrito/ui/carrito_screen.dart': 676,
    'lib/caja/ui/cerrar_caja_screen.dart': 497,
    'lib/venta/venta_providers.dart': 402,
    'lib/venta/ui/cobrar_fiado_screen.dart': 396,
    'lib/caja/cierre_providers.dart': 305,
  };
  const deudaTest = <String, int>{
    'test/venta/ui/cobro_pantallas_test.dart': 977,
    'test/venta/cobro_notifier_test.dart': 851,
    'test/caja/ui/cerrar_caja_pantalla_test.dart': 691,
    'test/caja/caja_notifier_test.dart': 562,
    'test/caja/cierre_notifier_test.dart': 561,
    'test/venta/ui/escaner_venta_pantalla_test.dart': 538,
    'test/auth/ui/pantallas_de_sesion_test.dart': 515,
    'test/carrito/carrito_test.dart': 487,
    'test/egresos/egreso_notifier_test.dart': 446,
    'test/carrito/ui/carrito_pantalla_test.dart': 443,
    'test/auth/sesion_notifier_test.dart': 411,
  };

  /// Los archivos `.dart` de [carpeta], con ruta relativa y barras `/`.
  List<File> archivosDe(String carpeta) => [
    for (final e in Directory(carpeta).listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart')) e,
  ];

  String ruta(File f) => f.path.replaceAll(r'\', '/');

  int lineas(File f) => f.readAsLinesSync().length;

  /// Los archivos de [archivos] que pasan de [maximo] sin estar tolerados, o que crecieron más allá de lo tolerado.
  List<String> excesos(
    List<File> archivos,
    int maximo,
    Map<String, int> deuda,
  ) {
    final fallas = <String>[];
    for (final f in archivos) {
      final n = lineas(f);
      final r = ruta(f);
      final tope = deuda[r] ?? maximo;
      if (n > tope) {
        fallas.add(
          deuda.containsKey(r)
              ? '$r tiene $n líneas y su tope tolerado es $tope: no puede crecer, hay que partirlo.'
              : '$r tiene $n líneas (máximo $maximo): parte el archivo, una responsabilidad por archivo.',
        );
      }
    }
    return fallas;
  }

  group('tamaño de los archivos', () {
    test('ningún archivo de lib/ pasa de $maximoLib líneas', () {
      expect(excesos(archivosDe('lib'), maximoLib, deudaLib), isEmpty);
    });

    test('ningún archivo de test/ pasa de $maximoTest líneas', () {
      expect(excesos(archivosDe('test'), maximoTest, deudaTest), isEmpty);
    });
  });

  group('capas: los widgets no hablan con el servidor', () {
    /// Las pantallas y piezas visuales: todo lo que está en una carpeta `ui/` más los widgets sueltos de `lib/`.
    List<File> widgets() => [
      for (final f in archivosDe('lib'))
        if (ruta(f).contains('/ui/') ||
            const [
              'lib/home_screen.dart',
              'lib/scanner_screen.dart',
              'lib/vista_de_escaneo.dart',
            ].contains(ruta(f)))
          f,
    ];

    final prohibidas = <String, RegExp>{
      'un repositorio': RegExp(r'''import\s+['"][^'"]*_repository\.dart['"]'''),
      'el cliente HTTP (dio)': RegExp(r'''import\s+['"]package:dio/'''),
      'el cliente de la API': RegExp(
        r'''import\s+['"][^'"]*(api_client|cookie_jar_factory|session_interceptor)\.dart['"]''',
      ),
      'el almacenamiento del celular': RegExp(
        r'''import\s+['"]package:shared_preferences/''',
      ),
    };

    test('hay widgets que revisar (la regla no está vacía)', () {
      expect(widgets().length, greaterThan(20));
    });

    for (final regla in prohibidas.entries) {
      test('ningún widget importa ${regla.key}', () {
        final fallas = [
          for (final f in widgets())
            if (regla.value.hasMatch(f.readAsStringSync()))
              '${ruta(f)} importa ${regla.key}: los widgets hablan con un Notifier, no con el servidor.',
        ];
        expect(fallas, isEmpty);
      });
    }
  });
}
