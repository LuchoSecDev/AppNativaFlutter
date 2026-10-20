import '../../ui/dinero.dart';
import '../../ui/formato.dart';

/// Centavos enteros como pesos para mostrar («$12.000»). Lo usan las tres partes del cobro fiado.
String pesosDeCentavos(int centavos) =>
    formatoPesos(importeDeCentavos(centavos));
