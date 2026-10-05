import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/catalogo/catalogo_providers.dart';
import 'package:stockpilot/catalogo/producto.dart';
import 'package:stockpilot/scan_stabilizer.dart';
import 'package:stockpilot/venta/ui/escaner_venta_screen.dart';
import 'package:stockpilot/venta/venta_providers.dart';

import '../../support/carrito_apoyo.dart';
import '../../support/fake_adapter.dart';

/// La pantalla de vender con el escáner, con el cliente HTTP REAL, un servidor falso con los ejemplos reales del
/// backend y una «cámara» falsa: un botón que entrega 3 lecturas iguales del código elegido (la cámara de verdad solo
/// se puede probar en un celular). La regla de «qué se confirma y cuándo» es la MISMA que usa la cámara real
/// (`ScanStabilizer.leer`).
void main() {
  const arroz = '7701234000011';
  const rutaArroz = '/api/productos/barcode/$arroz';

  late ServidorFalso servidor;
  late String codigoALeer;

  /// La hora que ve la «cámara»: la prueba la adelanta para simular que el producto dejó de verse.
  late DateTime reloj;

  Map<String, dynamic> datos({
    int id = 2,
    String nombre = 'Aceite Gourmet 1L',
    String precio = '12000.00',
    int cantidad = 5,
  }) => {
    'id_producto': id,
    'codigo': 'P-$id',
    'codigo_barras': null,
    'nombre_producto': nombre,
    'categoria': 'General',
    'precio': precio,
    'cantidad': cantidad,
    'estado': 'Disponible',
    'nivel_stock': cantidad <= 0 ? 'agotado' : 'ok',
  };

  RespuestaFalsa productoEncontrado(Map<String, dynamic> producto) =>
      RespuestaFalsa(200, {'success': true, 'data': producto});

  Widget camaraFalsa(
    BuildContext context,
    ScanStabilizer estabilizador,
    bool pausado,
    ValueChanged<String> alConfirmar,
  ) => Column(
    children: [
      Text(pausado ? 'PAUSADO' : 'ESCANEANDO'),
      ElevatedButton(
        onPressed: () {
          for (var i = 0; i < 3; i++) {
            final confirmado = estabilizador.leer(
              codigoALeer,
              pausado: pausado,
              ahora: reloj,
            );
            if (confirmado != null) {
              alConfirmar(confirmado);
            }
          }
        },
        child: const Text('Leer'),
      ),
    ],
  );

  ProviderContainer contenedor(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  List<int> idsEnElCarrito(WidgetTester tester) => [
    for (final l in contenedor(tester).read(carritoProvider).lineas)
      l.idProducto,
  ];

  int unidadesEnElCarrito(WidgetTester tester) =>
      contenedor(tester)
          .read(carritoProvider)
          .lineas
          .fold(0, (s, l) => s + l.cantidad);

  /// Abre la pantalla de escanear desde una pantalla de inicio (para que «volver» tenga a dónde volver).
  Future<void> abrir(
    WidgetTester tester, {
    RespuestaFalsa? catalogoDelServidor,
    List<Producto>? catalogoDeLaApp,
  }) async {
    servidor = ServidorFalso();
    codigoALeer = arroz;
    reloj = DateTime(2026, 10, 5, 10);
    servidor.programar(
      'GET',
      '/api/csrf-token',
      RespuestaFalsa.deEjemplo('04_S1_csrf_token'),
    );
    servidor.programar(
      'GET',
      '/api/productos',
      catalogoDelServidor ??
          RespuestaFalsa.deEjemplo('13_C1_lista_de_productos'),
    );
    final dio = crearClienteApi(
      baseUrl: 'https://servidor.test',
      cookieJar: CookieJar(),
      adapter: servidor,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          sesionProvider.overrideWith(() => SesionFija(sesionActiva())),
          catalogoProvider.overrideWith(
            () => CatalogoFijo(
              EstadoCatalogo.listo(
                catalogoDeLaApp ??
                    [
                      producto(
                        1,
                        'Arroz Diana 1Kg',
                        precio: '4500.00',
                        cantidad: 10,
                      ),
                      producto(
                        2,
                        'Aceite Gourmet 1L',
                        precio: '12000.00',
                        cantidad: 5,
                      ),
                    ],
              ),
            ),
          ),
          almacenCarritoProvider.overrideWithValue(AlmacenEnMemoria()),
          almacenVentaPendienteProvider.overrideWithValue(
            AlmacenVentaEnMemoria(),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          EscanerVentaScreen(construirVista: camaraFalsa),
                    ),
                  ),
                  child: const Text('Abrir escáner'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir escáner'));
    await tester.pumpAndSettle();
  }

  Future<void> leer(WidgetTester tester) async {
    await tester.tap(find.text('Leer'));
    await tester.pumpAndSettle();
  }

  void programarArroz() => servidor.programar(
    'GET',
    rutaArroz,
    RespuestaFalsa.deEjemplo('11_C2_producto_por_codigo_de_barras'),
  );

  void programarDesconocido() => servidor.programar(
    'GET',
    rutaArroz,
    RespuestaFalsa.deEjemplo('12_C2_codigo_no_encontrado_404'),
  );

  Future<void> hastaElegirProducto(WidgetTester tester) async {
    programarDesconocido();
    await leer(tester);
    expect(find.text('Código no encontrado'), findsOneWidget);
    await tester.tap(find.text('Vincular'));
    await tester.pumpAndSettle();
    expect(find.text('Elegir producto'), findsOneWidget);
  }

  group('un código conocido', () {
    testWidgets(
      'se agrega al carrito, avisa «Agregado» y sigue escaneando; el panel muestra el carrito',
      (tester) async {
        await abrir(tester);
        programarArroz();
        expect(find.text('Apunta al código del producto'), findsOneWidget);

        await leer(tester);

        expect(idsEnElCarrito(tester), [1]);
        expect(unidadesEnElCarrito(tester), 1);
        expect(find.text('Agregado: Arroz Diana 1Kg'), findsOneWidget);
        expect(find.text('ESCANEANDO'), findsOneWidget);
        expect(find.text(r'Carrito: 1 unidad · $4.500'), findsOneWidget);
        expect(servidor.veces('GET', rutaArroz), 1);
      },
    );

    testWidgets(
      'si la cámara sigue apuntando al MISMO producto, NO se agrega otra unidad (ni 10 lecturas después)',
      (tester) async {
        await abrir(tester);
        programarArroz();
        for (var i = 0; i < 10; i++) {
          await leer(tester);
        }
        expect(unidadesEnElCarrito(tester), 1);
        expect(servidor.veces('GET', rutaArroz), 1);
      },
    );

    testWidgets(
      'el MISMO producto, tras dejar de verse más de 1,5 s, cuenta como otra unidad; antes no',
      (tester) async {
        await abrir(tester);
        programarArroz();
        await leer(tester);
        expect(unidadesEnElCarrito(tester), 1);

        reloj = reloj.add(
          const Duration(milliseconds: 500),
        ); // sigue a la vista
        await leer(tester);
        expect(unidadesEnElCarrito(tester), 1);

        // Se retira el producto y se vuelve a mostrar 3 s después de la última vez que se vio.
        reloj = reloj.add(const Duration(seconds: 3));
        await leer(tester);
        expect(unidadesEnElCarrito(tester), 2);
        expect(servidor.veces('GET', rutaArroz), 2);
      },
    );

    testWidgets('otro producto distinto se agrega de inmediato', (
      tester,
    ) async {
      await abrir(tester);
      programarArroz();
      servidor.programar(
        'GET',
        '/api/productos/barcode/770000000002',
        productoEncontrado(datos()),
      );
      await leer(tester);
      codigoALeer = '770000000002';
      await leer(tester);
      expect(idsEnElCarrito(tester), [1, 2]);
      expect(find.text('Agregado: Aceite Gourmet 1L'), findsOneWidget);
      expect(find.text(r'Carrito: 2 unidades · $16.500'), findsOneWidget);
    });

    testWidgets('agotado: no se agrega y dice por qué', (tester) async {
      await abrir(tester);
      servidor.programar(
        'GET',
        rutaArroz,
        productoEncontrado(
          datos(id: 1, nombre: 'Arroz Diana 1Kg', cantidad: 0),
        ),
      );
      await leer(tester);
      expect(idsEnElCarrito(tester), isEmpty);
      expect(find.text('«Arroz Diana 1Kg» está agotado.'), findsOneWidget);
      expect(find.text('ESCANEANDO'), findsOneWidget);
    });

    testWidgets(
      'un producto que no está en la lista descargada: se agrega y se vuelve a descargar la lista (para conocer su precio)',
      (tester) async {
        await abrir(tester, catalogoDeLaApp: const []);
        programarArroz();
        await leer(tester);
        expect(idsEnElCarrito(tester), [1]);
        expect(servidor.veces('GET', '/api/productos'), 1);
        // Ya con la lista al día, el carrito conoce el precio del producto.
        expect(find.text(r'Carrito: 1 unidad · $4.500'), findsOneWidget);
      },
    );

    testWidgets(
      'un producto que ya está en la lista no la vuelve a descargar',
      (tester) async {
        await abrir(tester);
        programarArroz();
        await leer(tester);
        expect(servidor.veces('GET', '/api/productos'), 0);
      },
    );

    testWidgets('sin precio (0): no se agrega y dice por qué', (tester) async {
      await abrir(tester);
      servidor.programar(
        'GET',
        rutaArroz,
        productoEncontrado(
          datos(id: 1, nombre: 'Arroz Diana 1Kg', precio: '0.00'),
        ),
      );
      await leer(tester);
      expect(idsEnElCarrito(tester), isEmpty);
      expect(find.textContaining('no tiene precio'), findsOneWidget);
    });

    testWidgets(
      'sin red: avisa con un mensaje claro y deja volver a intentar el MISMO código al instante',
      (tester) async {
        await abrir(tester);
        servidor.programar(
          'GET',
          rutaArroz,
          const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
        );
        await leer(tester);
        expect(
          find.text('No hay conexión con el servidor. Revisa tu internet.'),
          findsOneWidget,
        );
        expect(find.textContaining('ErrorDeApi'), findsNothing);
        expect(find.text('ESCANEANDO'), findsOneWidget);

        servidor.programar(
          'GET',
          rutaArroz,
          RespuestaFalsa.deEjemplo('11_C2_producto_por_codigo_de_barras'),
        );
        await leer(tester);
        expect(idsEnElCarrito(tester), [1]);
        expect(servidor.veces('GET', rutaArroz), 2);
      },
    );

    testWidgets('mientras se consulta al servidor no se procesa otra lectura', (
      tester,
    ) async {
      await abrir(tester);
      final respuesta = Completer<void>();
      servidor.programar(
        'GET',
        rutaArroz,
        RespuestaFalsa.demorada(200, {
          'success': true,
          'data': datos(id: 1, nombre: 'Arroz Diana 1Kg', precio: '4500.00'),
        }, respuesta.future),
      );
      await tester.tap(find.text('Leer'));
      await tester.pump();
      expect(find.text('PAUSADO'), findsOneWidget);

      await tester.tap(
        find.text('Leer'),
      ); // la cámara sigue leyendo mientras tanto
      await tester.pump();
      respuesta.complete();
      await tester.pumpAndSettle();

      expect(servidor.veces('GET', rutaArroz), 1);
      expect(unidadesEnElCarrito(tester), 1);
      expect(find.text('ESCANEANDO'), findsOneWidget);
    });

    testWidgets('«Listo, volver al carrito» cierra la pantalla', (
      tester,
    ) async {
      await abrir(tester);
      await tester.tap(find.text('Listo, volver al carrito'));
      await tester.pumpAndSettle();
      expect(find.text('Escanear producto'), findsNothing);
      expect(find.text('Abrir escáner'), findsOneWidget);
    });
  });

  group('un código desconocido (404)', () {
    testWidgets(
      'ofrece vincular; «Cancelar» sigue escaneando y el mismo código se puede leer otra vez al instante',
      (tester) async {
        await abrir(tester);
        programarDesconocido();
        await leer(tester);
        expect(find.text('Código no encontrado'), findsOneWidget);
        expect(find.textContaining(arroz), findsOneWidget);
        expect(find.text('PAUSADO'), findsOneWidget);

        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(find.text('ESCANEANDO'), findsOneWidget);
        expect(servidor.veces('PUT', '/api/productos/1/link-barcode'), 0);

        await leer(tester);
        expect(find.text('Código no encontrado'), findsOneWidget);
        expect(servidor.veces('GET', rutaArroz), 2);
      },
    );

    testWidgets(
      '«Vincular» → elegir producto → queda vinculado, se agrega y se actualiza la lista',
      (tester) async {
        await abrir(tester);
        await hastaElegirProducto(tester);
        servidor.programar(
          'PUT',
          '/api/productos/1/link-barcode',
          RespuestaFalsa.deEjemplo('14_C3_vincular_codigo_de_barras'),
        );

        await tester.tap(find.text('Arroz Diana 1Kg'));
        await tester.pumpAndSettle();

        final vinculo = servidor.peticiones.firstWhere(
          (p) => p.clave == 'PUT /api/productos/1/link-barcode',
        );
        expect(vinculo.cuerpo, {'codigo_barras': arroz});
        expect(servidor.veces('GET', '/api/productos'), 1);
        expect(idsEnElCarrito(tester), [1]);
        expect(
          find.text('Vinculado y agregado: Arroz Diana 1Kg.'),
          findsOneWidget,
        );
        expect(find.text('ESCANEANDO'), findsOneWidget);
      },
    );

    testWidgets(
      'vincular y que el producto esté agotado: el vínculo se hace y se explica por qué no se agregó',
      (tester) async {
        await abrir(
          tester,
          // El arroz ya figura sin stock en la lista de la app: aun así se puede vincular su código.
          catalogoDeLaApp: [
            producto(1, 'Arroz Diana 1Kg', precio: '4500.00', cantidad: 0),
          ],
          // Lo que el servidor devolverá al actualizar la lista: el arroz sin stock.
          catalogoDelServidor: RespuestaFalsa(200, [
            datos(
              id: 1,
              nombre: 'Arroz Diana 1Kg',
              precio: '4500.00',
              cantidad: 0,
            ),
          ]),
        );
        await hastaElegirProducto(tester);
        servidor.programar(
          'PUT',
          '/api/productos/1/link-barcode',
          RespuestaFalsa.deEjemplo('14_C3_vincular_codigo_de_barras'),
        );
        await tester.tap(find.text('Arroz Diana 1Kg'));
        await tester.pumpAndSettle();

        expect(servidor.veces('PUT', '/api/productos/1/link-barcode'), 1);
        expect(idsEnElCarrito(tester), isEmpty);
        expect(
          find.text('Vinculado, pero «Arroz Diana 1Kg» está agotado.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'si no se puede actualizar la lista tras vincular, se agrega igual y se avisa',
      (tester) async {
        await abrir(
          tester,
          catalogoDelServidor: const RespuestaFalsa.falloDeRed(
            DioExceptionType.connectionError,
          ),
        );
        await hastaElegirProducto(tester);
        servidor.programar(
          'PUT',
          '/api/productos/1/link-barcode',
          RespuestaFalsa.deEjemplo('14_C3_vincular_codigo_de_barras'),
        );
        await tester.tap(find.text('Arroz Diana 1Kg'));
        await tester.pumpAndSettle();

        expect(idsEnElCarrito(tester), [1]);
        expect(
          find.textContaining('No se pudo actualizar la lista de productos.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'código ya vinculado a otro producto (409): muestra el motivo del servidor y no agrega nada',
      (tester) async {
        await abrir(tester);
        await hastaElegirProducto(tester);
        servidor.programar(
          'PUT',
          '/api/productos/1/link-barcode',
          RespuestaFalsa.deEjemplo('15_C3_codigo_ya_vinculado_409'),
        );
        await tester.tap(find.text('Arroz Diana 1Kg'));
        await tester.pumpAndSettle();

        expect(find.textContaining('ya pertenece'), findsOneWidget);
        expect(idsEnElCarrito(tester), isEmpty);
        expect(find.text('ESCANEANDO'), findsOneWidget);
        expect(servidor.veces('GET', '/api/productos'), 0);
      },
    );

    testWidgets(
      'volver atrás sin elegir producto: no se vincula nada y se sigue escaneando',
      (tester) async {
        await abrir(tester);
        await hastaElegirProducto(tester);
        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.text('ESCANEANDO'), findsOneWidget);
        expect(servidor.peticiones.where((p) => p.metodo == 'PUT'), isEmpty);
        expect(idsEnElCarrito(tester), isEmpty);
      },
    );
  });
}
