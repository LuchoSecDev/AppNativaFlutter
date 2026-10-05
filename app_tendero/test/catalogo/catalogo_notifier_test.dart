import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/auth/session_state.dart';
import 'package:stockpilot/catalogo/catalogo_providers.dart';

import '../support/fake_adapter.dart';

/// Estado del catálogo con el cliente HTTP REAL y un servidor falso con los ejemplos del backend.
void main() {
  late ServidorFalso servidor;
  late StreamController<void> caducidad;
  late ProviderContainer contenedor;

  setUp(() {
    servidor = ServidorFalso();
    caducidad = StreamController<void>.broadcast();
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
    final dio = crearClienteApi(
      baseUrl: 'https://servidor.test',
      cookieJar: CookieJar(),
      adapter: servidor,
      onSessionExpired: () => caducidad.add(null),
    );
    contenedor = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(dio),
        sesionCaducadaProvider.overrideWithValue(caducidad.stream),
      ],
    );
    addTearDown(() {
      contenedor.dispose();
      caducidad.close();
    });
  });

  EstadoCatalogo estado() => contenedor.read(catalogoProvider);

  Future<T> esperarQue<T>(T Function() leer, bool Function(T) condicion) async {
    for (var i = 0; i < 200; i++) {
      final actual = leer();
      if (condicion(actual)) {
        return actual;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw TimeoutException(
      'La condición nunca se cumplió; el estado quedó en ${leer()}',
    );
  }

  Future<void> conSesionActiva() async {
    servidor.programar(
      'GET',
      '/api/session-info',
      RespuestaFalsa.deEjemplo('05_S4_session_info'),
    );
    contenedor.read(sesionProvider);
    await esperarQue(
      () => contenedor.read(sesionProvider),
      (e) => e.fase == FaseSesion.activa,
    );
  }

  Future<void> hastaQueCargue() async {
    contenedor.listen(catalogoProvider, (_, _) {});
    await esperarQue(
      estado,
      (e) => e.fase != FaseCatalogo.cargando && !e.actualizando,
    );
  }

  test('sin sesión no descarga nada', () async {
    servidor.programar(
      'GET',
      '/api/session-info',
      const RespuestaFalsa(401, {'error': 'x'}),
    );
    contenedor.read(catalogoProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(servidor.veces('GET', '/api/productos'), 0);
  });

  test('con sesión descarga el catálogo y queda «listo»', () async {
    servidor.programar(
      'GET',
      '/api/productos',
      RespuestaFalsa.deEjemplo('13_C1_lista_de_productos'),
    );
    await conSesionActiva();
    await hastaQueCargue();
    expect(estado().fase, FaseCatalogo.listo);
    expect(estado().productos, hasLength(2));
    expect(estado().mensaje, isNull);
  });

  test(
    'si no se puede descargar y no hay lista: «error»; reintentar la carga',
    () async {
      servidor.programar(
        'GET',
        '/api/productos',
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      servidor.programar(
        'GET',
        '/api/productos',
        RespuestaFalsa.deEjemplo('13_C1_lista_de_productos'),
      );
      await conSesionActiva();
      await hastaQueCargue();
      expect(estado().fase, FaseCatalogo.error);
      expect(estado().mensaje, contains('conexión'));

      await contenedor.read(catalogoProvider.notifier).cargar();
      expect(estado().fase, FaseCatalogo.listo);
      expect(estado().productos, hasLength(2));
    },
  );

  test('si falla ACTUALIZAR teniendo ya una lista, se CONSERVA la lista con un aviso', () async {
    servidor.programar(
      'GET',
      '/api/productos',
      RespuestaFalsa.deEjemplo('13_C1_lista_de_productos'),
    );
    servidor.programar(
      'GET',
      '/api/productos',
      const RespuestaFalsa.falloDeRed(DioExceptionType.receiveTimeout),
    );
    await conSesionActiva();
    await hastaQueCargue();
    expect(estado().productos, hasLength(2));

    await contenedor.read(catalogoProvider.notifier).cargar();
    expect(estado().fase, FaseCatalogo.listo);
    expect(estado().productos, hasLength(2));
    expect(estado().mensaje, contains('No se pudo actualizar'));
  });

  test('dos pedidos de carga a la vez descargan UNA sola vez', () async {
    servidor.programar(
      'GET',
      '/api/productos',
      RespuestaFalsa.deEjemplo('13_C1_lista_de_productos'),
    );
    await conSesionActiva();
    await hastaQueCargue();
    final antes = servidor.veces('GET', '/api/productos');
    final n = contenedor.read(catalogoProvider.notifier);
    await Future.wait([n.cargar(), n.cargar()]);
    expect(servidor.veces('GET', '/api/productos') - antes, 1);
  });

  test('al cerrar sesión el catálogo se vacía: no queda a la vista el de la tienda anterior', () async {
    servidor.programar(
      'GET',
      '/api/productos',
      RespuestaFalsa.deEjemplo('13_C1_lista_de_productos'),
    );
    await conSesionActiva();
    await hastaQueCargue();
    expect(estado().productos, isNotEmpty);

    servidor.programar(
      'POST',
      '/api/logout',
      RespuestaFalsa.deEjemplo('28_S5_logout'),
    );
    await contenedor.read(sesionProvider.notifier).cerrarSesion();
    await esperarQue(estado, (e) => e.productos.isEmpty);
    expect(estado().fase, FaseCatalogo.cargando);
  });

  test('una respuesta TARDÍA de la sesión anterior se descarta y no aparece en la cuenta nueva', () async {
    final llega = Completer<void>();
    servidor.programar(
      'GET',
      '/api/session-info',
      RespuestaFalsa.deEjemplo('05_S4_session_info'),
    );
    servidor.programar(
      'GET',
      '/api/productos',
      RespuestaFalsa.demorada(200, const [
        {'id_producto': 99, 'nombre_producto': 'Producto de la cuenta A'},
      ], llega.future),
    );
    contenedor.read(sesionProvider);
    contenedor.listen(catalogoProvider, (_, _) {});
    await esperarQue(
      () => contenedor.read(sesionProvider),
      (e) => e.fase == FaseSesion.activa,
    );
    await esperarQue(
      () => servidor.veces('GET', '/api/productos'),
      (n) => n == 1,
    );

    servidor.programar(
      'POST',
      '/api/logout',
      RespuestaFalsa.deEjemplo('28_S5_logout'),
    );
    await contenedor.read(sesionProvider.notifier).cerrarSesion();
    llega.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(estado().productos, isEmpty);
    expect(estado().fase, FaseCatalogo.cargando);
  });
}
