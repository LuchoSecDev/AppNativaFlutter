/// Confirma un código de barras solo después de leerlo varias veces seguidas.
///
/// El lector puede devolver lecturas erróneas ocasionales (etiquetas borrosas, curvas o con brillo).
/// Exigir que el mismo código aparezca [requiredReads] veces antes de darlo por bueno evita registrar
/// un producto equivocado. Es lógica pura de Dart, sin cámara, para poder probarla sin un celular.
///
/// Dos modos de uso:
///  - **Una lectura y pausa** (la pantalla de diagnóstico): el código confirmado no se repite hasta llamar a
///    [reset] («Escanear otro»).
///  - **Escaneo continuo** (vender): con [silencioParaRepetir], el código confirmado se puede confirmar otra vez
///    solo si dejó de verse durante ese tiempo. Así, la cámara que sigue apuntando al mismo producto no lo agrega
///    dos veces, pero volver a mostrarlo después sí cuenta como otra unidad.
class ScanStabilizer {
  ScanStabilizer({this.requiredReads = 3, this.silencioParaRepetir})
    : assert(requiredReads > 0);

  /// Lecturas iguales que se necesitan para confirmar un código.
  final int requiredReads;

  /// Cuánto tiempo sin ver el código ya confirmado hace falta para aceptarlo de nuevo. `null`: nunca (solo [reset]).
  final Duration? silencioParaRepetir;

  String? _candidate;
  int _count = 0;
  String? _confirmed;

  /// La última vez que se vio el código confirmado (para medir el silencio).
  DateTime? _ultimaVezConfirmado;

  /// Registra una lectura. Devuelve el código si **acaba de confirmarse**; si no, `null`.
  ///
  /// Un código distinto al candidato actual reinicia la cuenta. Un código ya confirmado no se vuelve a
  /// confirmar hasta que se llame a [reset] (o, con [silencioParaRepetir], hasta que deje de verse ese tiempo).
  /// [ahora] solo se pasa en las pruebas.
  String? register(String code, {DateTime? ahora}) {
    final t = ahora ?? DateTime.now();
    _rearmarSiHuboSilencio(code, t);
    if (code == _confirmed) {
      _ultimaVezConfirmado =
          t; // sigue a la vista: el silencio se cuenta desde esta lectura
    }

    if (code == _candidate) {
      _count++;
    } else {
      _candidate = code;
      _count = 1;
    }

    if (_count >= requiredReads && code != _confirmed) {
      _confirmed = code;
      _ultimaVezConfirmado = t;
      return code;
    }
    return null;
  }

  /// Anota que se está viendo [code] SIN confirmar nada. Se usa mientras la lectura anterior se procesa (la pantalla
  /// está en pausa): si la cámara sigue apuntando al producto recién agregado, eso cuenta como «sigue a la vista».
  void notarVisto(String code, {DateTime? ahora}) {
    if (code == _confirmed) {
      _ultimaVezConfirmado = ahora ?? DateTime.now();
    }
  }

  /// Procesa una lectura de la cámara: en pausa solo anota que el código se ve; fuera de pausa lo registra.
  /// Es lo que llama la vista de la cámara, para que haya una sola regla.
  String? leer(String code, {required bool pausado, DateTime? ahora}) {
    if (pausado) {
      notarVisto(code, ahora: ahora);
      return null;
    }
    return register(code, ahora: ahora);
  }

  /// Olvida el candidato y el código confirmado (por ejemplo, al pulsar «Escanear otro», o tras un error para poder
  /// volver a leer el mismo código al instante).
  void reset() {
    _candidate = null;
    _count = 0;
    _confirmed = null;
    _ultimaVezConfirmado = null;
  }

  void _rearmarSiHuboSilencio(String code, DateTime ahora) {
    final silencio = silencioParaRepetir;
    final visto = _ultimaVezConfirmado;
    if (silencio == null || code != _confirmed || visto == null) {
      return;
    }
    if (ahora.difference(visto) >= silencio) {
      _confirmed = null;
      _candidate = null;
      _count = 0;
    }
  }
}
