// Formatos para mostrar dinero y horas. Sin paquetes externos y sin hacer cuentas con decimales.

/// Convierte el importe tal como llega de la API (TEXTO con dos decimales, por ejemplo `"50000.00"`) a pesos
/// colombianos para mostrar: `$50.000`. Si tiene centavos, los muestra con coma: `"4500.50"` -> `$4.500,50`.
///
/// Trabaja con el texto, no con números decimales, para no introducir errores de redondeo al mostrar dinero.
/// Si el texto no tiene la forma esperada, lo devuelve tal cual con el signo `$` delante, en vez de inventar una cifra.
String formatoPesos(String importe) {
  final partes = importe.trim().split('.');
  final enteros = partes.first;
  if (partes.length > 2 || !RegExp(r'^-?\d+$').hasMatch(enteros)) {
    return '\$$importe';
  }

  final negativo = enteros.startsWith('-');
  final digitos = negativo ? enteros.substring(1) : enteros;
  final agrupados = digitos.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );

  var centavos = partes.length == 2 ? partes[1] : '';
  if (centavos.isNotEmpty && !RegExp(r'^\d+$').hasMatch(centavos)) {
    return '\$$importe';
  }
  if (RegExp(r'^0*$').hasMatch(centavos)) centavos = ''; // ".00" no se muestra

  return '${negativo ? '-' : ''}\$$agrupados${centavos.isEmpty ? '' : ',$centavos'}';
}

/// Lo mismo, para un número entero de pesos (lo que escribe el usuario).
String formatoPesosEnteros(int pesos) => formatoPesos(pesos.toString());

/// Cuándo ocurrió algo, en palabras: `hoy a las 15:27`, `ayer a las 08:10` o `el 03/10 a las 08:10`. Sirve para
/// que una caja olvidada de hace días no se lea igual que una abierta hoy. [ahora] solo se pasa en las pruebas.
/// Devuelve `null` si el texto no es una fecha válida.
String? descripcionDeFecha(String fechaIso, {DateTime? ahora}) {
  final fecha = DateTime.tryParse(fechaIso)?.toLocal();
  final hora = horaLocal(fechaIso);
  if (fecha == null || hora == null) {
    return null;
  }
  final dias = _diasDeDiferencia(fecha, ahora ?? DateTime.now());
  if (dias == 0) {
    return 'hoy a las $hora';
  }
  if (dias == 1) {
    return 'ayer a las $hora';
  }
  final dia = fecha.day.toString().padLeft(2, '0');
  final mes = fecha.month.toString().padLeft(2, '0');
  return 'el $dia/$mes a las $hora';
}

/// `true` si la fecha cae en un día anterior al de [ahora] (por ejemplo, una caja que se quedó abierta).
bool esDeUnDiaAnterior(String fechaIso, {DateTime? ahora}) {
  final fecha = DateTime.tryParse(fechaIso)?.toLocal();
  return fecha != null &&
      _diasDeDiferencia(fecha, ahora ?? DateTime.now()) >= 1;
}

/// Días de calendario entre dos fechas locales (ignora la hora). Se calcula en UTC para que el cambio de hora
/// de verano no desfase un día.
int _diasDeDiferencia(DateTime fecha, DateTime ahora) {
  final a = DateTime.utc(fecha.year, fecha.month, fecha.day);
  final b = DateTime.utc(ahora.year, ahora.month, ahora.day);
  return b.difference(a).inDays;
}

/// Hora local en formato de 24 horas (`15:30`) a partir de una fecha ISO 8601 en UTC, como las de la API.
/// Devuelve `null` si el texto no es una fecha válida.
String? horaLocal(String fechaIso) {
  final fecha = DateTime.tryParse(fechaIso)?.toLocal();
  if (fecha == null) return null;
  final hh = fecha.hour.toString().padLeft(2, '0');
  final mm = fecha.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}
