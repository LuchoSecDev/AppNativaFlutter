import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/auth/session_state.dart';
import 'package:stockpilot/egresos/egreso_models.dart';
import 'package:stockpilot/egresos/egreso_providers.dart';
import 'package:stockpilot/egresos/egreso_estado.dart';

import '../support/carrito_apoyo.dart';
import '../support/egreso_apoyo.dart';
import '../support/fake_adapter.dart';

/// El estado del registro de egresos: validaciones, reintento seguro, sin confirmar y cambios de sesión.
void main() {
  const claveDelAlmacen = 'egreso_pendiente_v1_2_1'; // usuario 2, tienda 1

  late EntornoDeEgresos e;
  late ProviderContainer c;

  Future<void> armar({
    bool cajaAbierta = true,
    EstadoSesion? sesion,
    List<Duration> esperas = const [],
    bool repositorioRoto = false,
    void Function(EntornoDeEgresos)? antes,
  }) async {
    e = EntornoDeEgresos(
      cajaAbierta: cajaAbierta,
      sesionInicial: sesion,
      esperas: esperas,
      repositorioRoto: repositorioRoto,
    );
    antes?.call(e);
    c = await e.contenedor();
    addTearDown(c.dispose);
  }

  EstadoEgreso estado() => c.read(egresoProvider);
  EgresoNotifier notificador() => c.read(egresoProvider.notifier);

  Future<void> registrar({
    int monto = 10000,
    String motivo = 'Bolsas y hielo',
    CategoriaEgreso categoria = CategoriaEgreso.otro,
  }) => notificador().registrar(
    montoPesos: monto,
    motivo: motivo,
    categoria: categoria,
  );

  void programar(RespuestaFalsa r) =>
      e.servidor.programar('POST', EntornoDeEgresos.ruta, r);

  group('registrar', () {
    test('[24] éxito: manda el cuerpo del contrato con la clave, queda registrado y no deja nada pendiente', () async {
      await armar();
      programar(RespuestaFalsa.deEjemplo('24_K4_egreso_ok'));

      await registrar();

      expect(estado().fase, FaseEgreso.registrado);
      expect(estado().idEgreso, 1);
      expect(estado().repetido, isFalse);
      expect(e.envios(), hasLength(1));
      expect(e.envios().single.cuerpo, {
        'monto': 10000,
        'motivo': 'Bolsas y hielo',
        'categoria': 'Otro',
      });
      expect(e.envios().single.headers['Idempotency-Key'], claveDeEgreso);
      expect(e.almacen.datos, isEmpty);
    });

    test('la clave se guarda en el celular ANTES de enviar (si la app muere a mitad, se puede reintentar)', () async {
      await armar();
      final espera = Completer<void>();
      programar(
        RespuestaFalsa.demorada(200, {
          'success': true,
          'id_egreso': 1,
        }, espera.future),
      );

      final envio = registrar();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(estado().fase, FaseEgreso.enviando);
      expect(e.almacen.datos[claveDelAlmacen]?.clave, claveDeEgreso);
      espera.complete();
      await envio;
      expect(e.almacen.datos, isEmpty);
    });

    test('el motivo se envía sin espacios al principio ni al final', () async {
      await armar();
      programar(RespuestaFalsa.deEjemplo('24_K4_egreso_ok'));
      await registrar(motivo: '   Bolsas y hielo   ');
      expect((e.envios().single.cuerpo as Map)['motivo'], 'Bolsas y hielo');
    });

    test(
      'se puede registrar un segundo gasto después de aceptar el resultado',
      () async {
        await armar();
        programar(RespuestaFalsa.deEjemplo('24_K4_egreso_ok'));
        await registrar();
        notificador().aceptarResultado();
        expect(estado().fase, FaseEgreso.libre);

        await registrar(monto: 5000, motivo: 'Transporte a la plaza');
        expect(e.envios(), hasLength(2));
        expect(e.envios()[1].headers['Idempotency-Key'], 'otra-clave-2');
      },
    );
  });

  group('lo que la app valida antes de enviar (el servidor igual decide)', () {
    Future<void> noEnvia(String texto) async {
      expect(estado().fase, FaseEgreso.rechazado);
      expect(estado().mensaje, contains(texto));
      expect(e.envios(), isEmpty);
      expect(e.almacen.datos, isEmpty);
    }

    test('sin caja abierta: no se envía', () async {
      await armar(cajaAbierta: false);
      await registrar();
      await noEnvia('caja');
    });

    test('monto 0 o negativo: no se envía', () async {
      await armar();
      await registrar(monto: 0);
      await noEnvia('monto');
      await registrar(monto: -5);
      await noEnvia('monto');
    });

    test('motivo de menos de 5 caracteres (ya sin espacios sobrantes): no se envía', () async {
      await armar();
      await registrar(motivo: '  abcd  ');
      await noEnvia('motivo');
      await registrar(motivo: '');
      await noEnvia('motivo');
    });

    test('un motivo de EXACTAMENTE 5 caracteres sí pasa', () async {
      await armar();
      programar(RespuestaFalsa.deEjemplo('24_K4_egreso_ok'));
      await registrar(motivo: 'abcde');
      expect(estado().fase, FaseEgreso.registrado);
    });

    test(
      'Tendero: el monto sobre el tope no se envía, y el IGUAL al tope sí',
      () async {
        await armar(); // tope de 150000
        await registrar(monto: 150001);
        await noEnvia(r'$150.000');

        programar(RespuestaFalsa.deEjemplo('24_K4_egreso_ok'));
        await registrar(monto: 150000);
        expect(estado().fase, FaseEgreso.registrado);
      },
    );

    test('Administrador: no hay tope, aunque el servidor tenga uno para el Tendero', () async {
      await armar(sesion: sesionActiva(rol: 'Administrador'));
      programar(RespuestaFalsa.deEjemplo('24_K4_egreso_ok'));
      await registrar(monto: 5000000);
      expect(estado().fase, FaseEgreso.registrado);
    });

    for (final limite in ['0.00', 'abc', '']) {
      test(
        'un tope ilegible o 0 ("$limite") no bloquea en la app: decide el servidor',
        () async {
          await armar(sesion: sesionActiva(limiteEgreso: limite));
          programar(RespuestaFalsa.deEjemplo('24_K4_egreso_ok'));
          await registrar(monto: 999999);
          expect(estado().fase, FaseEgreso.registrado);
        },
      );
    }
  });

  group('cuando el servidor rechaza', () {
    test('[25] sobre el tope según el servidor: rechazado con su mensaje, sin dejar pendiente, y se refresca la caja', () async {
      await armar(
        sesion: sesionActiva(limiteEgreso: '0.00'),
      ); // la app no lo frena
      programar(RespuestaFalsa.deEjemplo('25_K4_egreso_sobre_el_tope_400'));
      final cajasAntes = e.servidor.veces('GET', '/api/caja/sesion');

      await registrar(monto: 150001, motivo: 'Gasto grande');

      expect(estado().fase, FaseEgreso.rechazado);
      expect(estado().mensaje, contains(r'$150.000'));
      expect(e.almacen.datos, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        e.servidor.veces('GET', '/api/caja/sesion'),
        cajasAntes + 1,
        reason: 'se vuelve a preguntar la caja: pudo cerrarse desde la web',
      );
    });

    test('[33] misma clave con otra carga (422): se descarta lo pendiente y el siguiente intento usa una clave NUEVA', () async {
      await armar();
      programar(RespuestaFalsa.deEjemplo('33_K4_misma_clave_otra_carga_422'));
      await registrar();
      expect(estado().fase, FaseEgreso.rechazado);
      expect(e.almacen.datos, isEmpty);

      programar(RespuestaFalsa.deEjemplo('24_K4_egreso_ok'));
      await registrar();
      expect(e.envios()[1].headers['Idempotency-Key'], 'otra-clave-2');
    });

    test('tras un rechazo se puede corregir y volver a enviar (queda en «rechazado», no bloqueado)', () async {
      await armar();
      programar(
        const RespuestaFalsa(400, {
          'error': 'Debes proporcionar un motivo válido (mínimo 5 caracteres).',
        }),
      );
      await registrar();
      expect(estado().fase, FaseEgreso.rechazado);

      programar(RespuestaFalsa.deEjemplo('24_K4_egreso_ok'));
      await registrar(motivo: 'Motivo corregido');
      expect(estado().fase, FaseEgreso.registrado);
    });
  });

  group('cuando no se sabe qué pasó', () {
    test('sin red: queda «sin confirmar», con el egreso guardado para reintentarlo', () async {
      await armar();
      programar(
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      await registrar();

      expect(estado().fase, FaseEgreso.sinConfirmar);
      expect(estado().mensaje, contains('No hay conexión'));
      expect(e.almacen.datos[claveDelAlmacen]?.clave, claveDeEgreso);
      expect(e.envios(), hasLength(1));
    });

    test('[32] reintentar manda la MISMA clave y la MISMA carga; si ya estaba registrado, no duplica', () async {
      await armar();
      programar(
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      await registrar();
      programar(RespuestaFalsa.deEjemplo('32_K4_reintento_misma_clave_200'));

      await notificador().reintentar();

      expect(estado().fase, FaseEgreso.registrado);
      expect(estado().repetido, isTrue);
      expect(e.envios(), hasLength(2));
      expect(e.envios()[1].headers['Idempotency-Key'], claveDeEgreso);
      expect(e.envios()[1].cuerpo, e.envios()[0].cuerpo);
      expect(e.almacen.datos, isEmpty);
    });

    test('reintento automático: pausas de 2 s y 5 s, y se detiene al tener respuesta', () async {
      await armar(esperas: const [Duration(seconds: 2), Duration(seconds: 5)]);
      const sinRed = RespuestaFalsa.falloDeRed(DioExceptionType.receiveTimeout);
      programar(sinRed);
      programar(RespuestaFalsa.deEjemplo('32_K4_reintento_misma_clave_200'));

      await registrar();

      expect(estado().fase, FaseEgreso.registrado);
      expect(e.envios(), hasLength(2));
      expect(e.pausas, [const Duration(seconds: 2)]);
    });

    test(
      'si tras todos los reintentos sigue sin respuesta, decide la persona',
      () async {
        await armar(
          esperas: const [Duration(seconds: 2), Duration(seconds: 5)],
        );
        programar(
          const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
        );
        await registrar();

        expect(estado().fase, FaseEgreso.sinConfirmar);
        expect(e.envios(), hasLength(3)); // el envío y dos reintentos
        expect(e.pausas, [
          const Duration(seconds: 2),
          const Duration(seconds: 5),
        ]);
      },
    );

    test('401: «sin confirmar», sin reintento automático y avisando que la sesión caducó', () async {
      await armar(esperas: const [Duration(seconds: 2)]);
      programar(const RespuestaFalsa(401, {'error': 'No autenticado'}));
      await registrar();

      expect(estado().fase, FaseEgreso.sinConfirmar);
      expect(estado().sesionCaducada, isTrue);
      expect(e.envios(), hasLength(1));
      expect(e.pausas, isEmpty);
    });

    test('un 200 con forma rara NO se da por registrado', () async {
      await armar();
      programar(const RespuestaFalsa(200, {'success': true}));
      await registrar();
      expect(estado().fase, FaseEgreso.sinConfirmar);
      expect(estado().idEgreso, isNull);
      expect(e.almacen.datos, isNotEmpty);
    });

    test('descartar un gasto sin confirmar: queda libre, se borra lo guardado y el siguiente usa clave nueva', () async {
      await armar();
      programar(
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      await registrar();

      await notificador().descartarSinConfirmar();
      expect(estado().fase, FaseEgreso.libre);
      expect(e.almacen.datos, isEmpty);

      programar(RespuestaFalsa.deEjemplo('24_K4_egreso_ok'));
      await registrar();
      expect(e.envios()[1].headers['Idempotency-Key'], 'otra-clave-2');
    });

    test('reintentar sin un gasto sin confirmar no hace nada', () async {
      await armar();
      await notificador().reintentar();
      expect(e.envios(), isEmpty);
      expect(estado().fase, FaseEgreso.libre);
    });

    test('un error de programación no deja la pantalla girando ni da el gasto por fallido', () async {
      await armar(repositorioRoto: true);
      await expectLater(registrar(), throwsStateError);
      expect(estado().fase, FaseEgreso.sinConfirmar);
      expect(estado().mensaje, contains('error inesperado'));
    });
  });

  group('al abrir la app', () {
    test('un gasto que quedó a medias aparece como «sin confirmar» y NO se reenvía solo', () async {
      await armar(
        antes: (e) => e.almacen.datos[claveDelAlmacen] = const EgresoPendiente(
          clave: claveDeEgreso,
          montoPesos: 10000,
          motivo: 'Bolsas y hielo',
          categoria: CategoriaEgreso.otro,
        ),
      );
      expect(estado().fase, FaseEgreso.sinConfirmar);
      expect(estado().mensaje, contains('sin confirmar'));
      expect(estado().egreso?.clave, claveDeEgreso);
      expect(e.envios(), isEmpty);
    });

    test('lo pendiente de OTRA cuenta no se muestra', () async {
      await armar(
        antes: (e) =>
            e.almacen.datos['egreso_pendiente_v1_9_9'] = const EgresoPendiente(
              clave: claveDeEgreso,
              montoPesos: 10000,
              motivo: 'Bolsas y hielo',
              categoria: CategoriaEgreso.otro,
            ),
      );
      expect(estado().fase, FaseEgreso.libre);
    });

    test('si el celular no deja leer lo guardado, se empieza libre (no se queda cargando)', () async {
      await armar(antes: (e) => e.almacen.fallar = true);
      expect(estado().cargando, isFalse);
      expect(estado().fase, FaseEgreso.libre);
    });
  });

  group('protecciones', () {
    test('doble toque: una sola petición', () async {
      await armar();
      programar(RespuestaFalsa.deEjemplo('24_K4_egreso_ok'));
      final a = registrar();
      final b = registrar();
      await Future.wait([a, b]);
      expect(e.envios(), hasLength(1));
    });

    test('si no se puede guardar en el celular, se registra igual (sin esa protección)', () async {
      await armar();
      programar(RespuestaFalsa.deEjemplo('24_K4_egreso_ok'));
      e.almacen.fallar = true;
      await registrar();
      expect(estado().fase, FaseEgreso.registrado);
    });

    test('una respuesta que llega cuando la sesión ya cambió se descarta; lo pendiente de la cuenta anterior queda', () async {
      await armar();
      final espera = Completer<void>();
      programar(
        RespuestaFalsa.demorada(200, {
          'success': true,
          'id_egreso': 1,
        }, espera.future),
      );
      final envio = registrar();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Otra persona entra (otra cuenta, otra tienda) antes de que llegue la respuesta de la anterior.
      e.sesion.poner(const EstadoSesion.sinSesion());
      e.sesion.poner(sesionActiva(userId: 9, tiendaId: 2));
      espera.complete();
      await envio;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        estado().fase,
        FaseEgreso.libre,
        reason: 'la cuenta nueva no ve el resultado de la anterior',
      );
      expect(estado().idEgreso, isNull);
      expect(
        e.almacen.datos.containsKey(claveDelAlmacen),
        isTrue,
        reason: 'el gasto de la cuenta anterior sigue pendiente para cuando vuelva a entrar',
      );
    });

    test('sin sesión no se puede registrar', () async {
      await armar(sesion: const EstadoSesion.sinSesion());
      await registrar();
      expect(e.envios(), isEmpty);
    });
  });
}
