import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/auth/session_state.dart';
import 'package:stockpilot/clientes/clientes_providers.dart';

import '../support/carrito_apoyo.dart';
import '../support/fake_adapter.dart';

/// El estado de los clientes: carga bajo demanda, errores, sesión que cambia y buscador.
void main() {
  late ServidorFalso servidor;
  late SesionFija sesion;
  late ProviderContainer contenedor;

  void armar({EstadoSesion? sesionInicial}) {
    servidor = ServidorFalso();
    sesion = SesionFija(sesionInicial ?? sesionActiva());
    contenedor = ProviderContainer(
      overrides: [
        sesionProvider.overrideWith(() => sesion),
        dioProvider.overrideWithValue(
          crearClienteApi(
            baseUrl: 'https://servidor.test',
            cookieJar: CookieJar(),
            adapter: servidor,
          ),
        ),
      ],
    );
    addTearDown(contenedor.dispose);
    contenedor.read(sesionProvider);
  }

  setUp(armar);

  ClientesNotifier notifier() => contenedor.read(clientesProvider.notifier);
  EstadoClientes estado() => contenedor.read(clientesProvider);

  test('no pide nada al servidor hasta que alguien carga (solo quien fía los necesita)', () async {
    estado();
    await Future<void>.delayed(Duration.zero);
    expect(servidor.veces('GET', '/api/clientes'), 0);
    expect(estado().fase, FaseClientes.cargando);
  });

  test('cargar trae los clientes del servidor', () async {
    servidor.programar(
      'GET',
      '/api/clientes',
      RespuestaFalsa.deEjemplo('16_V1_clientes'),
    );
    await notifier().cargar();
    expect(estado().fase, FaseClientes.listo);
    expect(estado().clientes.map((c) => c.nombre), ['Doña Rosa']);
  });

  test(
    'si falla, queda en error con un mensaje entendible y sin clientes viejos',
    () async {
      servidor.programar(
        'GET',
        '/api/clientes',
        RespuestaFalsa.deEjemplo('16_V1_clientes'),
      );
      await notifier().cargar();
      servidor.programar(
        'GET',
        '/api/clientes',
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      await notifier().cargar();
      expect(estado().fase, FaseClientes.error);
      expect(estado().mensajeError, contains('No hay conexión'));
      expect(estado().clientes, isEmpty, reason: 'no se ofrecen saldos viejos');
    },
  );

  test('sin sesión no se pide nada', () async {
    armar(sesionInicial: const EstadoSesion.sinSesion());
    await notifier().cargar();
    expect(servidor.veces('GET', '/api/clientes'), 0);
  });

  test('una respuesta que llega cuando la sesión ya cambió se descarta (no se muestran los clientes de otra tienda)', () async {
    // Como en la app, hay una pantalla escuchando: el estado se reconstruye en cuanto cambia la sesión. Sin un
    // oyente, Riverpod reconstruiría al leer y borraría la respuesta tardía por casualidad, ocultando el fallo.
    contenedor.listen(clientesProvider, (_, _) {});
    final espera = Completer<void>();
    servidor.programar(
      'GET',
      '/api/clientes',
      RespuestaFalsa.demorada(
        200,
        RespuestaFalsa.deEjemplo('16_V1_clientes').cuerpo,
        espera.future,
      ),
    );
    final carga = notifier().cargar();
    await Future<void>.delayed(Duration.zero);

    // Otra persona entra (otra tienda) antes de que llegue la respuesta de la anterior.
    sesion.poner(const EstadoSesion.sinSesion());
    sesion.poner(sesionActiva(userId: 9, tiendaId: 2));
    espera.complete();
    await carga;

    expect(estado().clientes, isEmpty);
    expect(estado().fase, FaseClientes.cargando);
  });

  test('al cerrar la sesión se olvidan los clientes', () async {
    servidor.programar(
      'GET',
      '/api/clientes',
      RespuestaFalsa.deEjemplo('16_V1_clientes'),
    );
    await notifier().cargar();
    expect(estado().clientes, isNotEmpty);
    sesion.poner(const EstadoSesion.sinSesion());
    expect(estado().clientes, isEmpty);
  });

  test(
    'el filtro busca por nombre sin distinguir mayúsculas ni espacios de más',
    () async {
      servidor.programar(
        'GET',
        '/api/clientes',
        const RespuestaFalsa(200, {
          'success': true,
          'clientes': [
            {
              'id_cliente': 1,
              'nombre': 'Ana Gómez',
              'celular': null,
              'limite_credito': '50000.00',
              'saldo_pendiente': 0,
            },
            {
              'id_cliente': 2,
              'nombre': 'Juan Pérez',
              'celular': null,
              'limite_credito': '0.00',
              'saldo_pendiente': 0,
            },
          ],
        }),
      );
      await notifier().cargar();

      List<String> buscar(String q) => contenedor
          .read(clientesFiltradosProvider(q))
          .map((c) => c.nombre)
          .toList();

      expect(buscar(''), ['Ana Gómez', 'Juan Pérez']);
      expect(buscar('   '), ['Ana Gómez', 'Juan Pérez']);
      expect(buscar('ana'), ['Ana Gómez']);
      expect(buscar('  PÉREZ '), ['Juan Pérez']);
      expect(buscar('a'), ['Ana Gómez', 'Juan Pérez']);
      expect(buscar('Carlos'), isEmpty);
    },
  );
}
