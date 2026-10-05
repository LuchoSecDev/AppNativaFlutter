import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/venta/clave_de_venta.dart';
import 'package:stockpilot/venta/venta_models.dart';

void main() {
  group('MetodoPago', () {
    test('usa EXACTAMENTE los textos que exige el servidor', () {
      expect(MetodoPago.efectivo.valorApi, 'Efectivo');
      expect(MetodoPago.tarjeta.valorApi, 'Tarjeta');
      expect(MetodoPago.transferencia.valorApi, 'Transferencia');
      expect(MetodoPago.fiado.valorApi, 'Fiado');
    });

    test('desdeApi reconoce solo la escritura exacta', () {
      expect(MetodoPago.desdeApi('Efectivo'), MetodoPago.efectivo);
      expect(MetodoPago.desdeApi('efectivo'), isNull);
      expect(MetodoPago.desdeApi(' Efectivo'), isNull);
      expect(MetodoPago.desdeApi(null), isNull);
    });
  });

  group('VentaPendiente', () {
    const venta = VentaPendiente(
      clave: '4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22',
      items: [
        ItemVenta(idProducto: 1, cantidad: 2),
        ItemVenta(idProducto: 2, cantidad: 1),
      ],
      metodoPago: MetodoPago.efectivo,
      totalCentavos: 2100000,
      efectivoRecibido: 25000,
    );

    test('el cuerpo de la petición sigue el contrato: cantidades enteras, método exacto, efectivo en pesos', () {
      expect(venta.cuerpoDeLaPeticion(), {
        'items': [
          {'id_producto': 1, 'cantidad': 2},
          {'id_producto': 2, 'cantidad': 1},
        ],
        'metodo_pago': 'Efectivo',
        'efectivo_recibido': 25000,
      });
    });

    test('sin efectivo recibido, el campo no se envía', () {
      const sinEfectivo = VentaPendiente(
        clave: '4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22',
        items: [ItemVenta(idProducto: 1, cantidad: 1)],
        metodoPago: MetodoPago.tarjeta,
        totalCentavos: 450000,
      );
      expect(
        sinEfectivo.cuerpoDeLaPeticion().containsKey('efectivo_recibido'),
        isFalse,
      );
    });

    test('el cambio se calcula en centavos exactos', () {
      expect(venta.cambioCentavos, 25000 * 100 - 2100000); // $4.000
      const conCentavos = VentaPendiente(
        clave: '4f9d2c1e-7a3b-4c58-9e10-5b6a8d0c1f22',
        items: [ItemVenta(idProducto: 1, cantidad: 1)],
        metodoPago: MetodoPago.efectivo,
        totalCentavos: 450050, // $4.500,50
        efectivoRecibido: 5000,
      );
      expect(conCentavos.cambioCentavos, 49950); // $499,50
    });

    test('guardada y leída queda igual (la clave y la carga no cambian)', () {
      final leida = VentaPendiente.desdeJson(venta.aJson())!;
      expect(leida.clave, venta.clave);
      expect(leida.cuerpoDeLaPeticion(), venta.cuerpoDeLaPeticion());
      expect(leida.totalCentavos, venta.totalCentavos);
    });

    test('lo guardado dañado o de otra forma se descarta (null)', () {
      final bueno = venta.aJson();
      expect(VentaPendiente.desdeJson(null), isNull);
      expect(VentaPendiente.desdeJson('texto'), isNull);
      expect(VentaPendiente.desdeJson({...bueno, 'clave': 'corta'}), isNull);
      expect(VentaPendiente.desdeJson({...bueno, 'clave': 5}), isNull);
      expect(
        VentaPendiente.desdeJson({...bueno, 'metodo_pago': 'efectivo'}),
        isNull,
      );
      expect(
        VentaPendiente.desdeJson({...bueno, 'total_centavos': 'x'}),
        isNull,
      );
      expect(VentaPendiente.desdeJson({...bueno, 'items': []}), isNull);
      expect(
        VentaPendiente.desdeJson({
          ...bueno,
          'items': [
            {'id_producto': 1, 'cantidad': 0},
          ],
        }),
        isNull,
      );
      expect(
        VentaPendiente.desdeJson({
          ...bueno,
          'items': [
            {'id_producto': 1, 'cantidad': 1.5},
          ],
        }),
        isNull,
      );
      expect(
        VentaPendiente.desdeJson({...bueno, 'efectivo_recibido': -1}),
        isNull,
      );
    });
  });

  group('generarUuidV4', () {
    final formato = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    test(
      'tiene la forma de un UUID v4 y cumple el formato que acepta el servidor',
      () {
        final clave = generarUuidV4();
        expect(clave, matches(formato));
        expect(clave, matches(RegExp(r'^[A-Za-z0-9_-]{8,100}$')));
      },
    );

    test('con el mismo azar da la misma clave (determinista para pruebas)', () {
      expect(generarUuidV4(Random(7)), generarUuidV4(Random(7)));
    });

    test('mil claves seguidas son todas distintas y válidas', () {
      final claves = {for (var i = 0; i < 1000; i++) generarUuidV4()};
      expect(claves, hasLength(1000));
      expect(claves.every(formato.hasMatch), isTrue);
    });
  });
}
