import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/actualizacion/actualizacion_models.dart';
import 'package:stockpilot/actualizacion/estado_de_version.dart';

/// La regla que decide si se avisa o se obliga a actualizar. Es la más delicada de la función: una versión mínima mal leída
/// puede dejar a todo un negocio sin poder vender, o no obligar cuando el servidor ya no es compatible.
void main() {
  VersionPublicada publicada({int ultima = 5, int minima = 3}) =>
      VersionPublicada(
        versionCode: ultima,
        versionName: '1.0.$ultima',
        minVersionCode: minima,
      );

  NivelDeActualizacion nivel(int? instalada, VersionPublicada? p) =>
      evaluarVersion(instalada: instalada, publicada: p);

  test('menor que la mínima: obligatoria', () {
    expect(nivel(2, publicada()), NivelDeActualizacion.obligatoria);
    expect(nivel(1, publicada()), NivelDeActualizacion.obligatoria);
  });

  test('IGUAL a la mínima: todavía sirve (opcional); es el límite exacto', () {
    expect(nivel(3, publicada()), NivelDeActualizacion.opcional);
  });

  test('entre la mínima y la última: opcional', () {
    expect(nivel(4, publicada()), NivelDeActualizacion.opcional);
  });

  test(
    'IGUAL a la última o más nueva: al día (el límite exacto de la última)',
    () {
      expect(nivel(5, publicada()), NivelDeActualizacion.alDia);
      expect(nivel(6, publicada()), NivelDeActualizacion.alDia);
    },
  );

  test('sin saber la versión instalada o la publicada, al día: ante la duda no se bloquea a nadie', () {
    expect(nivel(null, publicada()), NivelDeActualizacion.alDia);
    expect(nivel(2, null), NivelDeActualizacion.alDia);
    expect(nivel(null, null), NivelDeActualizacion.alDia);
  });

  test('una mínima MAYOR que la última no obliga a nadie a actualizar a una versión que no existe', () {
    expect(
      nivel(2, publicada(ultima: 3, minima: 9)),
      NivelDeActualizacion.opcional,
    );
    expect(
      nivel(3, publicada(ultima: 3, minima: 9)),
      NivelDeActualizacion.alDia,
    );
  });

  test('con la mínima en 1 (la de siempre) nunca es obligatoria', () {
    expect(
      nivel(1, publicada(ultima: 4, minima: 1)),
      NivelDeActualizacion.opcional,
    );
  });
}
