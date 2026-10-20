import '../ui/dinero.dart';
import '../ui/formato.dart';

/// Las reglas de un gasto que la app comprueba ANTES de enviarlo, para no hacer esperar a la persona por algo que el
/// servidor va a rechazar. Es solo una ayuda: quien decide es el servidor (`[K4]`).

/// Un motivo vale si, sin espacios al principio ni al final, tiene al menos 5 caracteres.
const int caracteresMinimosDelMotivo = 5;

bool motivoEsValido(String motivo) =>
    motivo.trim().length >= caracteresMinimosDelMotivo;

/// El tope por gasto en CENTAVOS, o `null` si la app no debe frenar por tope.
///
/// El tope es solo del rol Tendero (`limiteEgresoTendero` de `[S4]`, texto con dos decimales). Si el valor llega
/// ilegible o en 0, la app no frena nada y decide el servidor: así un dato raro no deja sin poder registrar gastos.
int? topeEnCentavos({
  required String rol,
  required String limiteEgresoTendero,
}) {
  if (rol != 'Tendero') return null;
  final limite = centavosDeImporte(limiteEgresoTendero);
  return limite == null || limite == 0 ? null : limite;
}

/// El motivo para NO enviar el gasto, en español, o `null` si se puede enviar. El monto igual al tope es válido.
String? motivoParaNoRegistrar({
  required bool cajaAbierta,
  required int montoPesos,
  required String motivo,
  required String rol,
  required String limiteEgresoTendero,
}) {
  if (!cajaAbierta) {
    return 'No hay una caja abierta. Abre la caja para registrar gastos.';
  }
  if (montoPesos <= 0) return 'El monto debe ser mayor a 0.';
  if (!motivoEsValido(motivo)) {
    return 'Escribe el motivo del gasto (mínimo $caracteresMinimosDelMotivo caracteres).';
  }
  final tope = topeEnCentavos(
    rol: rol,
    limiteEgresoTendero: limiteEgresoTendero,
  );
  if (tope != null && montoPesos * 100 > tope) {
    return 'Por seguridad, tu rol no permite registrar gastos mayores a ${formatoPesos(importeDeCentavos(tope))}. Consulta al administrador.';
  }
  return null;
}
