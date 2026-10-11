// Comprueba que las pruebas de verdad detectan un error: rompe el código a propósito, corre `flutter test` y mira si
// ALGUNA prueba falla. Si ninguna falla, esa prueba no protege nada (una «mutación sobreviviente»).
//
// Uso (desde la carpeta app_tendero):
//   dart run tool/mutar.dart tool/mutaciones/mi_funcion.json            # todas las mutaciones del archivo
//   dart run tool/mutar.dart tool/mutaciones/mi_funcion.json M01 M03    # solo las que empiezan por esos nombres
//
// El archivo JSON es una lista de objetos:
//   { "nombre": "M01 no se vacía el carrito al cobrar",
//     "archivo": "lib/venta/venta_providers.dart",
//     "patron": "ref\\.read\\(carritoProvider\\.notifier\\)\\.vaciar\\(\\);",   // expresión regular de Dart
//     "reemplazo": "" }
//
// Cada mutación se aplica sola y el archivo SIEMPRE se restaura al terminar (se comprueba byte a byte). Aun así, trabaja
// con todo commiteado o guardado: si cortas la ejecución a la mitad, `git checkout -- <archivo>` lo deja como estaba.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> argumentos) async {
  if (argumentos.isEmpty) {
    stderr.writeln(
      'Uso: dart run tool/mutar.dart <archivo.json> [prefijo de nombre ...]',
    );
    exit(64);
  }
  final lista = jsonDecode(File(argumentos.first).readAsStringSync());
  if (lista is! List) {
    stderr.writeln('El archivo debe contener una lista de mutaciones.');
    exit(64);
  }
  final filtros = argumentos.skip(1).toList();
  final resultados = <String>[];
  var hayProblemas = false;

  for (final entrada in lista) {
    final nombre = entrada['nombre'] as String;
    if (filtros.isNotEmpty && !filtros.any(nombre.startsWith)) {
      continue;
    }
    final archivo = File(entrada['archivo'] as String);
    if (!archivo.existsSync()) {
      resultados.add('$nombre | ARCHIVO NO ENCONTRADO: ${archivo.path}');
      hayProblemas = true;
      continue;
    }
    final original = archivo.readAsBytesSync();
    final texto = utf8.decode(original);
    final patron = RegExp(entrada['patron'] as String, dotAll: true);
    if (!patron.hasMatch(texto)) {
      resultados.add(
        '$nombre | PATRÓN NO ENCONTRADO (el código cambió: actualiza la mutación)',
      );
      hayProblemas = true;
      continue;
    }
    String veredicto;
    try {
      archivo.writeAsStringSync(
        texto.replaceFirst(patron, entrada['reemplazo'] as String),
      );
      final reloj = Stopwatch()..start();
      final r = await Process.run('flutter', [
        'test',
        '--reporter',
        'github',
      ], runInShell: true);
      final salida = '${r.stdout}${r.stderr}';
      final fallos = RegExp(r'\(failed\)').allMatches(salida).length;
      if (fallos > 0 || salida.contains('Some tests failed')) {
        veredicto = 'DETECTADA ($fallos pruebas fallan)';
      } else if (salida.contains('Compilation failed')) {
        veredicto = 'NO COMPILA (mutación inválida: ajústala)';
        hayProblemas = true;
      } else if (RegExp(r'\d+ tests? passed').hasMatch(salida)) {
        veredicto = 'SOBREVIVIÓ: ninguna prueba falló (falta una prueba)';
        hayProblemas = true;
      } else {
        veredicto =
            'NO CONCLUYENTE: no se pudo leer el resultado de las pruebas';
        hayProblemas = true;
      }
      veredicto = '$veredicto | ${reloj.elapsed.inSeconds} s';
    } finally {
      archivo.writeAsBytesSync(original);
      if (!_iguales(original, archivo.readAsBytesSync())) {
        stderr.writeln(
          '¡¡NO SE RESTAURÓ ${archivo.path}!! Usa: git checkout -- ${archivo.path}',
        );
        exit(2);
      }
    }
    resultados.add('$nombre | $veredicto');
    stdout.writeln(resultados.last);
  }

  stdout.writeln('\n===== RESUMEN =====');
  resultados.forEach(stdout.writeln);
  exit(hayProblemas ? 1 : 0);
}

bool _iguales(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
