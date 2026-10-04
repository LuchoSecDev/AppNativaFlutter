import 'package:flutter_riverpod/flutter_riverpod.dart';

/// La fecha y hora de «ahora». Es un provider para que las pruebas puedan fijarla: un texto como «hoy a las 15:27»
/// depende del día en que se mira, y una prueba que dependa del reloj real fallaría según el día.
final ahoraProvider = Provider<DateTime>((ref) => DateTime.now());
