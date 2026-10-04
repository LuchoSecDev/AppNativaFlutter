/// Confirma un código de barras solo después de leerlo varias veces seguidas.
///
/// El lector puede devolver lecturas erróneas ocasionales (etiquetas borrosas, curvas o con brillo).
/// Exigir que el mismo código aparezca [requiredReads] veces antes de darlo por bueno evita registrar
/// un producto equivocado. Es lógica pura de Dart, sin cámara, para poder probarla sin un celular.
class ScanStabilizer {
  ScanStabilizer({this.requiredReads = 3}) : assert(requiredReads > 0);

  /// Lecturas iguales que se necesitan para confirmar un código.
  final int requiredReads;

  String? _candidate;
  int _count = 0;
  String? _confirmed;

  /// Registra una lectura. Devuelve el código si **acaba de confirmarse**; si no, `null`.
  ///
  /// Un código distinto al candidato actual reinicia la cuenta. Un código ya confirmado no se vuelve a
  /// confirmar hasta que se llame a [reset].
  String? register(String code) {
    if (code == _candidate) {
      _count++;
    } else {
      _candidate = code;
      _count = 1;
    }

    if (_count >= requiredReads && code != _confirmed) {
      _confirmed = code;
      return code;
    }
    return null;
  }

  /// Olvida el candidato y el código confirmado (por ejemplo, al pulsar «Escanear otro»).
  void reset() {
    _candidate = null;
    _count = 0;
    _confirmed = null;
  }
}
