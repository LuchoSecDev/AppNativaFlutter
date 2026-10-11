import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/api/api_client.dart';
import 'package:stockpilot/auth/auth_providers.dart';
import 'package:stockpilot/caja/caja_models.dart';
import 'package:stockpilot/caja/caja_providers.dart';
import 'package:stockpilot/carrito/carrito_models.dart';
import 'package:stockpilot/carrito/carrito_providers.dart';
import 'package:stockpilot/carrito/ui/carrito_screen.dart';
import 'package:stockpilot/catalogo/catalogo_providers.dart';
import 'package:stockpilot/catalogo/producto.dart';
import 'package:stockpilot/home_screen.dart';
import 'package:stockpilot/venta/venta_models.dart';
import 'package:stockpilot/venta/venta_providers.dart';

import '../../support/carrito_apoyo.dart';
import '../../support/fake_adapter.dart';

class _CajaAbiertaFija extends CajaNotifier {
  @override
  EstadoCaja build() => const EstadoCaja.abierta(
    SesionCaja(
      idSesion: 1,
      montoApertura: '50000.00',
      fechaApertura: '2026-10-04T15:30:00.000Z',
    ),
  );
}

/// Las pantallas del cobro con el cliente HTTP REAL y un servidor falso con los ejemplos reales del backend.
void main() {
  const clave = '4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22';
  const ruta = '/api/registrar-venta-carrito';

  late ServidorFalso servidor;
  late AlmacenEnMemoria almacenCarrito;
  late AlmacenVentaEnMemoria almacenVenta;
  var llamadasAlGenerador = 0;

  // Lo que ya tiene la app descargado (puede estar «viejo» respecto de lo que dice el servidor).
  Producto arroz({String precio = '4500.00', int cantidad = 10}) =>
      producto(1, 'Arroz Diana 1Kg', precio: precio, cantidad: cantidad);
  final aceite = producto(
    2,
    'Aceite Gourmet 1L',
    precio: '12000.00',
    cantidad: 5,
  );

  ProviderContainer contenedor(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  /// [catalogoDelServidor] es lo que el servidor responderá cuando la pantalla de cobro vuelva a descargar los
  /// precios (por defecto, el ejemplo real: arroz a $4.500 con 10 en stock, aceite a $12.000 con 5).
  Future<void> abrir(
    WidgetTester tester, {
    Widget pantalla = const CarritoScreen(),
    List<Producto>? productosDeLaApp,
    List<LineaCarrito> lineas = const [
      LineaCarrito(idProducto: 1, nombre: 'Arroz Diana 1Kg', cantidad: 2),
    ],
    AlmacenVentaEnMemoria? ventaPrevia,
    RespuestaFalsa? catalogoDelServidor,
    RespuestaFalsa? clientesDelServidor,
  }) async {
    llamadasAlGenerador = 0;
    servidor = ServidorFalso();
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
    servidor.programar(
      'GET',
      '/api/clientes',
      clientesDelServidor ?? RespuestaFalsa.deEjemplo('16_V1_clientes'),
    );
    almacenCarrito = AlmacenEnMemoria();
    if (lineas.isNotEmpty) {
      almacenCarrito.datos['carrito_v1_2_1'] = lineas;
    }
    almacenVenta = ventaPrevia ?? AlmacenVentaEnMemoria();
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
              EstadoCatalogo.listo(productosDeLaApp ?? [arroz(), aceite]),
            ),
          ),
          cajaProvider.overrideWith(() => _CajaAbiertaFija()),
          almacenCarritoProvider.overrideWithValue(almacenCarrito),
          almacenVentaPendienteProvider.overrideWithValue(almacenVenta),
          generadorDeClaveProvider.overrideWithValue(() {
            llamadasAlGenerador++;
            return llamadasAlGenerador == 1
                ? clave
                : 'otra-clave-$llamadasAlGenerador';
          }),
          // Sin reintentos automáticos en estas pruebas: el desenlace se ve de inmediato.
          esperasDeReintentoProvider.overrideWithValue(const []),
        ],
        child: MaterialApp(home: pantalla),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder campoEfectivo() => find.widgetWithText(TextField, 'Efectivo recibido');

  Future<void> abrirCobro(
    WidgetTester tester, {
    String metodo = 'Efectivo',
  }) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Cobrar...'));
    await tester.pumpAndSettle();
    // La hoja «¿Cómo vas a cobrar?» ofrece los cuatro métodos; por defecto se elige el efectivo.
    await tester.tap(find.widgetWithText(InkWell, metodo));
    await tester.pumpAndSettle();
  }

  Future<void> escribir(WidgetTester tester, String pesos) async {
    await tester.enterText(campoEfectivo(), pesos);
    await tester.pump();
  }

  Future<void> confirmar(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar cobro'));
    await tester.pumpAndSettle();
  }

  void programarVentaOk() => servidor.programar(
    'POST',
    ruta,
    RespuestaFalsa.deEjemplo('17_V2_venta_ok'),
  );

  void programarSinRed() => servidor.programar(
    'POST',
    ruta,
    const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
  );

  group('la pantalla de cobro en efectivo', () {
    testWidgets(
      'verifica los precios, muestra el total, el cambio o lo que falta, y solo deja confirmar si alcanza',
      (tester) async {
        await abrir(tester);
        await abrirCobro(tester);

        expect(servidor.veces('GET', '/api/productos'), 1);
        expect(find.text('Total a cobrar'), findsOneWidget);
        expect(find.text(r'$9.000'), findsOneWidget);
        expect(find.textContaining('El total cambió'), findsNothing);

        ElevatedButton confirmarCobro() => tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Confirmar cobro'),
        );
        expect(confirmarCobro().onPressed, isNull, reason: 'sin escribir nada');

        await escribir(tester, '5000');
        expect(find.text(r'Faltan $4.000'), findsOneWidget);
        expect(confirmarCobro().onPressed, isNull);

        await escribir(tester, '8999');
        expect(find.text(r'Faltan $1'), findsOneWidget);
        expect(confirmarCobro().onPressed, isNull);

        await escribir(tester, '9000');
        expect(find.text(r'Cambio: $0'), findsOneWidget);
        expect(confirmarCobro().onPressed, isNotNull);

        await escribir(tester, '10000');
        expect(find.text(r'Cambio: $1.000'), findsOneWidget);
        expect(confirmarCobro().onPressed, isNotNull);
      },
    );

    testWidgets('«Monto exacto» escribe el total', (tester) async {
      await abrir(tester);
      await abrirCobro(tester);
      await tester.tap(find.text('Monto exacto'));
      await tester.pump();
      expect(
        tester.widget<TextField>(campoEfectivo()).controller!.text,
        '9000',
      );
      expect(find.text(r'Cambio: $0'), findsOneWidget);
    });

    testWidgets('el campo solo admite dígitos y hasta 9', (tester) async {
      await abrir(tester);
      await abrirCobro(tester);
      await escribir(tester, '12ab.-3456789012');
      expect(
        tester.widget<TextField>(campoEfectivo()).controller!.text,
        '123456789',
      );
    });

    testWidgets(
      'si el servidor tiene OTRO precio, se avisa que el total cambió y se cobra con el nuevo',
      (tester) async {
        // La app descargó el arroz a $4.000; el servidor ya lo tiene a $4.500.
        await abrir(
          tester,
          productosDeLaApp: [
            arroz(precio: '4000.00'),
            aceite,
          ],
        );
        expect(find.text(r'Total: $8.000'), findsOneWidget);
        await abrirCobro(tester);

        expect(find.text(r'$9.000'), findsOneWidget);
        expect(
          find.textContaining(
            r'El total cambió al actualizar los precios: antes era $8.000',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'si no se pueden verificar los precios NO se deja cobrar; «Reintentar» lo intenta de nuevo',
      (tester) async {
        await abrir(
          tester,
          catalogoDelServidor: const RespuestaFalsa.falloDeRed(
            DioExceptionType.connectionError,
          ),
        );
        await abrirCobro(tester);

        expect(
          find.textContaining('No se pudo verificar los precios'),
          findsOneWidget,
        );
        expect(campoEfectivo(), findsNothing);
        expect(
          find.widgetWithText(ElevatedButton, 'Confirmar cobro'),
          findsNothing,
        );

        servidor.programar(
          'GET',
          '/api/productos',
          RespuestaFalsa.deEjemplo('13_C1_lista_de_productos'),
        );
        await tester.tap(find.widgetWithText(ElevatedButton, 'Reintentar'));
        await tester.pumpAndSettle();
        expect(campoEfectivo(), findsOneWidget);
      },
    );

    testWidgets(
      'si al verificar, un producto ya no alcanza (stock 1 de 2), no se deja cobrar y se vuelve al carrito',
      (tester) async {
        await abrir(
          tester,
          catalogoDelServidor: const RespuestaFalsa(200, [
            {
              'id_producto': 1,
              'codigo': 'ARR-001',
              'codigo_barras': null,
              'nombre_producto': 'Arroz Diana 1Kg',
              'categoria': 'Granos',
              'precio': '4500.00',
              'cantidad': 1,
              'estado': 'Disponible',
              'nivel_stock': 'critico',
            },
          ]),
        );
        await abrirCobro(tester);

        expect(
          find.textContaining('algunos productos del carrito cambiaron'),
          findsOneWidget,
        );
        expect(campoEfectivo(), findsNothing);
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Volver al carrito'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Solo hay 1 unidad en stock.'), findsOneWidget);
      },
    );
  });

  group('el desenlace del cobro, en el carrito', () {
    testWidgets(
      'venta registrada: comprobante con el cambio; «Nueva venta» deja el carrito vacío y en la copia no queda nada',
      (tester) async {
        await abrir(tester);
        programarVentaOk();
        await abrirCobro(tester);
        await escribir(tester, '10000');
        await confirmar(tester);

        expect(find.text('Venta registrada'), findsOneWidget);
        expect(find.text('Venta n.º 1'), findsOneWidget);
        expect(find.text(r'$9.000'), findsOneWidget);
        expect(find.text(r'$10.000'), findsOneWidget);
        expect(find.text('Cambio a devolver'), findsOneWidget);
        expect(find.text(r'$1.000'), findsOneWidget);
        expect(find.textContaining('ya estaba registrada'), findsNothing);
        expect(almacenVenta.datos, isEmpty);
        expect(servidor.veces('POST', ruta), 1);

        await tester.tap(find.text('Nueva venta'));
        await tester.pumpAndSettle();
        expect(find.text('El carrito está vacío'), findsOneWidget);
        expect(almacenCarrito.datos['carrito_v1_2_1'], isNull);
      },
    );

    testWidgets(
      'sin red: «sin confirmar», con aviso de no cobrar otra vez, líneas bloqueadas; «Reintentar» recupera la MISMA venta',
      (tester) async {
        await abrir(tester);
        programarSinRed();
        await abrirCobro(tester);
        await escribir(tester, '10000');
        await confirmar(tester);

        expect(find.textContaining('No la cobres otra vez'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(find.text('Cancelar este cobro'), findsOneWidget);
        expect(find.text('Registrando la venta…'), findsNothing);
        // Las líneas siguen a la vista pero no se pueden cambiar.
        expect(find.text('Arroz Diana 1Kg'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
              .onPressed,
          isNull,
        );
        expect(find.widgetWithText(FilledButton, 'Cobrar...'), findsNothing);
        expect(find.byTooltip('Vaciar carrito'), findsNothing);
        expect(almacenVenta.datos, isNotEmpty);

        servidor.programar(
          'POST',
          ruta,
          RespuestaFalsa.deEjemplo('18_V2_reintento_misma_clave_200'),
        );
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();

        expect(find.text('Venta registrada'), findsOneWidget);
        expect(find.textContaining('ya estaba registrada'), findsOneWidget);
        final envios = servidor.peticiones.where(
          (p) => p.clave == 'POST $ruta',
        );
        expect(envios.map((p) => p.headers['Idempotency-Key']), [clave, clave]);
        expect(almacenVenta.datos, isEmpty);
      },
    );

    testWidgets(
      '«Cancelar este cobro» advierte del riesgo de duplicar; si se confirma, se puede cobrar otra vez',
      (tester) async {
        await abrir(tester);
        programarSinRed();
        await abrirCobro(tester);
        await escribir(tester, '10000');
        await confirmar(tester);

        await tester.tap(find.text('Cancelar este cobro'));
        await tester.pumpAndSettle();
        expect(find.textContaining('quedará duplicada'), findsOneWidget);

        await tester.tap(find.text('Volver'));
        await tester.pumpAndSettle();
        expect(
          find.text('Reintentar'),
          findsOneWidget,
          reason: 'sigue sin confirmar',
        );

        await tester.tap(find.text('Cancelar este cobro'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancelar el cobro'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(FilledButton, 'Cobrar...'), findsOneWidget);
        expect(almacenVenta.datos, isEmpty);
      },
    );

    testWidgets(
      'un rechazo del servidor se muestra con su mensaje, el carrito sigue y se puede corregir',
      (tester) async {
        await abrir(tester);
        servidor.programar(
          'POST',
          ruta,
          RespuestaFalsa.deEjemplo('20_V2_stock_insuficiente_400'),
        );
        await abrirCobro(tester);
        await escribir(tester, '10000');
        await confirmar(tester);

        expect(
          find.text('Stock insuficiente para el producto: Arroz Diana 1Kg'),
          findsOneWidget,
        );
        expect(find.text('Arroz Diana 1Kg'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Cobrar...'),
              )
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'al salir del carrito con la venta registrada, la próxima vez empieza limpio',
      (tester) async {
        await abrir(tester, pantalla: const HomeScreen());
        await tester.tap(find.text('Vender'));
        await tester.pumpAndSettle();
        programarVentaOk();
        await abrirCobro(tester);
        await escribir(tester, '10000');
        await confirmar(tester);
        expect(find.text('Venta registrada'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(contenedor(tester).read(cobroProvider).fase, FaseCobro.libre);

        await tester.tap(find.text('Vender'));
        await tester.pumpAndSettle();
        expect(find.text('Venta registrada'), findsNothing);
        expect(find.text('El carrito está vacío'), findsOneWidget);
      },
    );
  });

  group('el selector de método de pago', () {
    testWidgets('ofrece los cuatro métodos y cada uno abre su pantalla', (
      tester,
    ) async {
      await abrir(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Cobrar...'));
      await tester.pumpAndSettle();
      expect(find.text('¿Cómo vas a cobrar?'), findsOneWidget);
      for (final metodo in ['Efectivo', 'Tarjeta', 'Transferencia', 'Fiado']) {
        expect(find.widgetWithText(InkWell, metodo), findsOneWidget);
      }

      await tester.tap(find.widgetWithText(InkWell, 'Tarjeta'));
      await tester.pumpAndSettle();
      expect(find.text('Cobrar con Tarjeta'), findsOneWidget);
      expect(find.text('¿Cómo vas a cobrar?'), findsNothing);
    });
  });

  group('tarjeta y transferencia', () {
    for (final metodo in ['Tarjeta', 'Transferencia']) {
      testWidgets(
        '$metodo: verifica los precios, nombra el método y cobra SIN efectivo ni cliente, con la misma clave de idempotencia',
        (tester) async {
          await abrir(tester);
          programarVentaOk();
          await abrirCobro(tester, metodo: metodo);

          expect(servidor.veces('GET', '/api/productos'), 1);
          expect(find.text('Cobrar con $metodo'), findsOneWidget);
          expect(find.text(r'$9.000'), findsOneWidget);
          // Antes de corregirlo, el texto decía «por MetodoPago.tarjeta.valorApi».
          expect(
            find.textContaining('el pago por $metodo antes de confirmar'),
            findsOneWidget,
          );

          await tester.tap(
            find.widgetWithText(ElevatedButton, 'Confirmar pago recibido'),
          );
          await tester.pumpAndSettle();

          final peticion = servidor.peticiones.singleWhere(
            (p) => p.clave == 'POST $ruta',
          );
          expect(peticion.cuerpo, {
            'items': [
              {'id_producto': 1, 'cantidad': 2},
            ],
            'metodo_pago': metodo,
          });
          expect(peticion.headers['Idempotency-Key'], clave);
          expect(find.text('Venta registrada'), findsOneWidget);
        },
      );
    }

    testWidgets(
      'si no se pueden verificar los precios NO se deja confirmar el pago',
      (tester) async {
        await abrir(
          tester,
          catalogoDelServidor: const RespuestaFalsa.falloDeRed(
            DioExceptionType.connectionError,
          ),
        );
        await abrirCobro(tester, metodo: 'Tarjeta');
        expect(
          find.textContaining('No se pudo verificar los precios'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(ElevatedButton, 'Confirmar pago recibido'),
          findsNothing,
        );
        expect(servidor.veces('POST', ruta), 0);
      },
    );

    testWidgets('si el servidor tiene OTRO precio, avisa que el total cambió', (
      tester,
    ) async {
      await abrir(
        tester,
        productosDeLaApp: [
          arroz(precio: '4000.00'),
          aceite,
        ],
      );
      await abrirCobro(tester, metodo: 'Transferencia');
      expect(find.text(r'$9.000'), findsOneWidget);
      expect(
        find.textContaining(
          r'El total cambió al actualizar los precios: antes era $8.000',
        ),
        findsOneWidget,
      );
    });
  });

  group('fiado', () {
    // Un arroz: $4.500. El cliente del ejemplo real (Doña Rosa) tiene cupo de $5.000 y no debe nada.
    const unArroz = [
      LineaCarrito(idProducto: 1, nombre: 'Arroz Diana 1Kg', cantidad: 1),
    ];

    /// Una lista de clientes con la forma del ejemplo real `16_V1_clientes` (otros nombres, cupos y saldos).
    RespuestaFalsa clientes(List<Map<String, Object?>> lista) =>
        RespuestaFalsa(200, {
          'success': true,
          'clientes': [
            for (final c in lista)
              {
                'celular': null,
                'fecha_registro': '2026-10-04T15:30:00.000Z',
                'total_fiado': '0',
                'total_abonado': '0',
                ...c,
              },
          ],
        });

    Map<String, Object?> cliente(
      int id,
      String nombre, {
      String limite = '5000.00',
      Object saldo = 0,
    }) => {
      'id_cliente': id,
      'nombre': nombre,
      'limite_credito': limite,
      'saldo_pendiente': saldo,
    };

    Finder botonConfirmar() =>
        find.widgetWithText(ElevatedButton, 'Confirmar fiado');

    bool confirmarHabilitado(WidgetTester tester) =>
        tester.widget<ElevatedButton>(botonConfirmar()).onPressed != null;

    String valorDe(WidgetTester tester, String titulo) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.widgetWithText(Row, titulo).first,
            matching: find.byType(Text),
          ),
        )
        .last
        .data!;

    Future<void> elegir(WidgetTester tester, String nombre) async {
      await tester.tap(find.text(nombre));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'trae los clientes del servidor (una vez) y muestra lo que debe y el cupo EN PESOS',
      (tester) async {
        await abrir(
          tester,
          lineas: unArroz,
          clientesDelServidor: clientes([
            cliente(1, 'Doña Rosa', saldo: 2500),
            cliente(2, 'Don Pedro', limite: '0.00'),
          ]),
        );
        await abrirCobro(tester, metodo: 'Fiado');

        expect(servidor.veces('GET', '/api/clientes'), 1);
        expect(find.text('Doña Rosa'), findsOneWidget);
        expect(find.text(r'Debe $2.500 · cupo $5.000'), findsOneWidget);
        expect(find.text(r'Debe $0 · sin tope'), findsOneWidget);
      },
    );

    testWidgets('el buscador filtra por nombre sin distinguir mayúsculas', (
      tester,
    ) async {
      await abrir(
        tester,
        lineas: unArroz,
        clientesDelServidor: clientes([
          cliente(1, 'Doña Rosa'),
          cliente(2, 'Don Pedro'),
        ]),
      );
      await abrirCobro(tester, metodo: 'Fiado');

      await tester.enterText(find.byType(TextField), 'PEDRO');
      await tester.pump();
      expect(find.text('Don Pedro'), findsOneWidget);
      expect(find.text('Doña Rosa'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.textContaining('No se encontraron clientes'), findsOneWidget);

      await tester.tap(find.byTooltip('Borrar la búsqueda'));
      await tester.pump();
      expect(find.text('Doña Rosa'), findsOneWidget);
      expect(find.text('Don Pedro'), findsOneWidget);
    });

    testWidgets(
      'elegir y confirmar: manda Fiado con id_cliente, sin efectivo y con la clave de idempotencia',
      (tester) async {
        await abrir(tester, lineas: unArroz);
        programarVentaOk();
        await abrirCobro(tester, metodo: 'Fiado');
        await elegir(tester, 'Doña Rosa');

        expect(valorDe(tester, 'Total de la compra'), r'$4.500');
        expect(valorDe(tester, 'Debe ahora'), r'$0');
        expect(valorDe(tester, 'Quedaría debiendo'), r'$4.500');
        expect(valorDe(tester, 'Cupo'), r'$5.000');

        await tester.tap(botonConfirmar());
        await tester.pumpAndSettle();

        final peticion = servidor.peticiones.singleWhere(
          (p) => p.clave == 'POST $ruta',
        );
        expect(peticion.cuerpo, {
          'items': [
            {'id_producto': 1, 'cantidad': 1},
          ],
          'metodo_pago': 'Fiado',
          'id_cliente': 1,
        });
        expect(peticion.headers['Idempotency-Key'], clave);
        expect(find.text('Venta registrada'), findsOneWidget);
      },
    );

    testWidgets(
      'si la venta se pasa del cupo NO se deja confirmar, lo explica y no se manda nada',
      (tester) async {
        // Dos arroces: $9.000 contra un cupo de $5.000.
        await abrir(tester);
        await abrirCobro(tester, metodo: 'Fiado');
        await elegir(tester, 'Doña Rosa');

        expect(
          find.textContaining('supera el cupo de crédito del cliente'),
          findsOneWidget,
        );
        expect(confirmarHabilitado(tester), isFalse);
        expect(servidor.veces('POST', ruta), 0);
      },
    );

    testWidgets(
      'el cupo cuenta lo que ya debe, y estar JUSTO en el cupo es válido',
      (tester) async {
        // $4.500 de venta. Al que ya debe $500 le quedan justo $5.000 (válido); al que debe $501, no.
        await abrir(
          tester,
          lineas: unArroz,
          clientesDelServidor: clientes([
            cliente(1, 'Justo', saldo: 500),
            cliente(2, 'Pasado', saldo: 501),
          ]),
        );
        await abrirCobro(tester, metodo: 'Fiado');

        await elegir(tester, 'Justo');
        expect(valorDe(tester, 'Quedaría debiendo'), r'$5.000');
        expect(confirmarHabilitado(tester), isTrue);

        await tester.tap(find.byTooltip('Elegir otro cliente'));
        await tester.pumpAndSettle();
        await elegir(tester, 'Pasado');
        expect(confirmarHabilitado(tester), isFalse);
      },
    );

    testWidgets('un cupo de 0 es «sin tope»: deja fiar cualquier monto', (
      tester,
    ) async {
      await abrir(
        tester,
        clientesDelServidor: clientes([
          cliente(7, 'Sin tope', limite: '0.00', saldo: 90000),
        ]),
      );
      await abrirCobro(tester, metodo: 'Fiado');
      await elegir(tester, 'Sin tope');

      expect(valorDe(tester, 'Cupo'), 'Sin tope');
      expect(valorDe(tester, 'Quedaría debiendo'), r'$99.000');
      expect(confirmarHabilitado(tester), isTrue);
    });

    testWidgets('«Elegir otro cliente» vuelve a la lista y no cobra nada', (
      tester,
    ) async {
      await abrir(tester, lineas: unArroz);
      await abrirCobro(tester, metodo: 'Fiado');
      await elegir(tester, 'Doña Rosa');
      await tester.tap(find.byTooltip('Elegir otro cliente'));
      await tester.pumpAndSettle();
      expect(find.text('Doña Rosa'), findsOneWidget);
      expect(botonConfirmar(), findsNothing);
      expect(servidor.veces('POST', ruta), 0);
    });

    testWidgets(
      'si no se pudo traer la lista de clientes: mensaje y «Reintentar»',
      (tester) async {
        await abrir(
          tester,
          lineas: unArroz,
          clientesDelServidor: const RespuestaFalsa.falloDeRed(
            DioExceptionType.connectionError,
          ),
        );
        await abrirCobro(tester, metodo: 'Fiado');
        expect(find.textContaining('No hay conexión'), findsOneWidget);

        servidor.programar(
          'GET',
          '/api/clientes',
          RespuestaFalsa.deEjemplo('16_V1_clientes'),
        );
        await tester.tap(find.widgetWithText(OutlinedButton, 'Reintentar'));
        await tester.pumpAndSettle();
        expect(find.text('Doña Rosa'), findsOneWidget);
      },
    );

    testWidgets(
      'una tienda sin clientes lo dice en vez de mostrar una lista vacía',
      (tester) async {
        await abrir(
          tester,
          lineas: unArroz,
          clientesDelServidor: clientes(const []),
        );
        await abrirCobro(tester, metodo: 'Fiado');
        expect(
          find.textContaining('todavía no tiene clientes'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'si no se pueden verificar los precios, ni siquiera se piden los clientes',
      (tester) async {
        await abrir(
          tester,
          lineas: unArroz,
          catalogoDelServidor: const RespuestaFalsa.falloDeRed(
            DioExceptionType.connectionError,
          ),
        );
        await abrirCobro(tester, metodo: 'Fiado');
        expect(
          find.textContaining('No se pudo verificar los precios'),
          findsOneWidget,
        );
        expect(servidor.veces('GET', '/api/clientes'), 0);
      },
    );

    testWidgets(
      'el servidor decide: si rechaza por cupo (un saldo que la app no conocía), se muestra su mensaje y el carrito sigue',
      (tester) async {
        await abrir(tester, lineas: unArroz);
        servidor.programar(
          'POST',
          ruta,
          RespuestaFalsa.deEjemplo('22_V2_fiado_supera_el_cupo_400'),
        );
        await abrirCobro(tester, metodo: 'Fiado');
        await elegir(tester, 'Doña Rosa');
        await tester.tap(botonConfirmar());
        await tester.pumpAndSettle();

        expect(
          find.textContaining(
            'Esta venta supera el cupo de crédito del cliente',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Cobrar...'),
              )
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'cliente inexistente o de otra tienda (404, según el contrato): se muestra el mensaje del servidor',
      (tester) async {
        await abrir(tester, lineas: unArroz);
        // Sin ejemplo real en el backend: el cuerpo sale del contrato [V2].
        servidor.programar(
          'POST',
          ruta,
          const RespuestaFalsa(404, {
            'success': false,
            'error': 'Cliente no encontrado',
          }),
        );
        await abrirCobro(tester, metodo: 'Fiado');
        await elegir(tester, 'Doña Rosa');
        await tester.tap(botonConfirmar());
        await tester.pumpAndSettle();
        expect(find.text('Cliente no encontrado'), findsOneWidget);
      },
    );

    testWidgets(
      'sin red al confirmar: «sin confirmar» y «Reintentar» manda la MISMA venta (misma clave, mismo cliente)',
      (tester) async {
        await abrir(tester, lineas: unArroz);
        programarSinRed();
        await abrirCobro(tester, metodo: 'Fiado');
        await elegir(tester, 'Doña Rosa');
        await tester.tap(botonConfirmar());
        await tester.pumpAndSettle();
        expect(find.textContaining('No la cobres otra vez'), findsOneWidget);

        programarVentaOk();
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();

        final ventas = servidor.peticiones
            .where((p) => p.clave == 'POST $ruta')
            .toList();
        expect(ventas, hasLength(2));
        expect(ventas[1].headers['Idempotency-Key'], clave);
        expect(ventas[1].cuerpo, ventas[0].cuerpo);
        expect((ventas[1].cuerpo as Map)['id_cliente'], 1);
        expect(find.text('Venta registrada'), findsOneWidget);
      },
    );
  });

  group('desde la pantalla de inicio', () {
    testWidgets('una venta sin confirmar se anuncia en el inicio', (
      tester,
    ) async {
      final previa = AlmacenVentaEnMemoria()
        ..datos['venta_pendiente_v1_2_1'] = const VentaPendiente(
          clave: clave,
          items: [ItemVenta(idProducto: 1, cantidad: 2)],
          metodoPago: MetodoPago.efectivo,
          totalCentavos: 900000,
          efectivoRecibido: 10000,
        );
      await abrir(tester, pantalla: const HomeScreen(), ventaPrevia: previa);
      expect(
        find.textContaining('Hay una venta sin confirmar'),
        findsOneWidget,
      );
    });

    testWidgets('sin ventas pendientes no hay aviso', (tester) async {
      await abrir(tester, pantalla: const HomeScreen());
      expect(find.textContaining('sin confirmar'), findsNothing);
    });
  });
}
