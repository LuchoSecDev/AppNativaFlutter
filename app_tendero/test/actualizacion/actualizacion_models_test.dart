import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/actualizacion/actualizacion_models.dart';

import '../support/fake_adapter.dart';

/// Lectura de las respuestas de `[U1]` y `[U2]`. Las respuestas buenas son los ejemplos REALES del backend; las malas se
/// escriben a mano porque son justo lo que el servidor no debería mandar y la app no debe creerse.
void main() {
  Object? cuerpo(String ejemplo) => RespuestaFalsa.deEjemplo(ejemplo).cuerpo;

  group('VersionPublicada.desdeJson [U1]', () {
    test('la versión publicada del ejemplo real', () {
      final v = VersionPublicada.desdeJson(cuerpo('37_U1_version_disponible'))!;
      expect(v.versionCode, 3);
      expect(v.versionName, '1.0.2');
      expect(v.minVersionCode, 2);
      expect(v.notas, 'Corrige el escáner con poca luz.');
    });

    test('«disponible: false» (todavía no se publicó nada) es null', () {
      expect(
        VersionPublicada.desdeJson(cuerpo('36_U1_version_sin_configurar')),
        isNull,
      );
    });

    test(
      'lo que no tiene la forma esperada es null, nunca una versión inventada',
      () {
        for (final malo in <Object?>[
          null,
          'texto',
          <dynamic>[],
          <String, dynamic>{},
          {'disponible': true},
          {'disponible': 'true', 'versionCode': 3, 'minVersionCode': 1},
          {'disponible': true, 'versionCode': '3', 'minVersionCode': 1},
          {'disponible': true, 'versionCode': 3.5, 'minVersionCode': 1},
          {'disponible': true, 'versionCode': 0, 'minVersionCode': 1},
          {'disponible': true, 'versionCode': -2, 'minVersionCode': 1},
          {'disponible': true, 'versionCode': 3, 'minVersionCode': 0},
          {'disponible': true, 'versionCode': 3},
        ]) {
          expect(VersionPublicada.desdeJson(malo), isNull, reason: '$malo');
        }
      },
    );

    test(
      'sin nombre usa el código; con notas que no son texto, quedan vacías',
      () {
        final v = VersionPublicada.desdeJson({
          'disponible': true,
          'versionCode': 7,
          'minVersionCode': 1,
          'versionName': '',
          'notas': 12,
        })!;
        expect(v.versionName, '7');
        expect(v.notas, '');
      },
    );
  });

  group('DescargaApp.desdeJson [U2]', () {
    const huella =
        '3f786850e387550fdab836ed7e6dc881de23001b3f786850e387550fdab836ed';
    Map<String, dynamic> buena([Map<String, dynamic> cambios = const {}]) => {
      'versionCode': 3,
      'versionName': '1.0.2',
      'url': 'https://descargas.ejemplo.test/stockpilot-1.0.2.apk',
      'sha256': huella,
      'bytes': 23456789,
      ...cambios,
    };

    test('la descarga del ejemplo real', () {
      final d = DescargaApp.desdeJson(cuerpo('39_U2_descarga_ok'))!;
      expect(d.versionCode, 3);
      expect(d.versionName, '1.0.2');
      expect(d.url, 'https://descargas.ejemplo.test/stockpilot-1.0.2.apk');
      expect(d.sha256, huella);
      expect(d.bytes, 23456789);
      expect(d.enlace.scheme, 'https');
      expect(d.enlace.host, 'descargas.ejemplo.test');
    });

    test('la huella se guarda en minúsculas', () {
      expect(
        DescargaApp.desdeJson(buena({'sha256': huella.toUpperCase()}))!.sha256,
        huella,
      );
    });

    test('una dirección que no sea https NUNCA se acepta (ni http, ni otros esquemas, ni con usuario y clave)', () {
      for (final mala in [
        'http://descargas.ejemplo.test/a.apk',
        'ftp://descargas.ejemplo.test/a.apk',
        'javascript:alert(1)',
        'file:///sdcard/a.apk',
        'https://usuario:clave@descargas.ejemplo.test/a.apk',
        'https:///a.apk',
        '//descargas.ejemplo.test/a.apk',
        'no es una dirección',
        '',
      ]) {
        expect(
          DescargaApp.desdeJson(buena({'url': mala})),
          isNull,
          reason: mala,
        );
      }
    });

    test('sin una huella SHA-256 válida no hay descarga', () {
      for (final mala in <Object?>[
        null,
        'abc',
        'g' * 64,
        'a' * 63,
        'a' * 65,
        ' ${'a' * 63}',
        12345,
      ]) {
        expect(
          DescargaApp.desdeJson(buena({'sha256': mala})),
          isNull,
          reason: '$mala',
        );
      }
    });

    test('el tamaño es opcional: si no sirve, solo se omite', () {
      expect(DescargaApp.desdeJson(buena({'bytes': 'mucho'}))!.bytes, isNull);
      expect(DescargaApp.desdeJson(buena({'bytes': 0}))!.bytes, isNull);
      expect(DescargaApp.desdeJson(buena({'bytes': null}))!.bytes, isNull);
    });

    test(
      'lo que no es un objeto o le falta la dirección o el código es null',
      () {
        expect(DescargaApp.desdeJson(null), isNull);
        expect(DescargaApp.desdeJson('x'), isNull);
        expect(DescargaApp.desdeJson(buena({'url': null})), isNull);
        expect(DescargaApp.desdeJson(buena({'versionCode': 'tres'})), isNull);
      },
    );
  });
}
