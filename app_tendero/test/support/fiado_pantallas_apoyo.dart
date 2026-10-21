import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/carrito/carrito_models.dart';

import 'fake_adapter.dart';

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
