import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/clientes/cliente.dart';

/// El modelo del cliente contra el ejemplo REAL de `[V1]` y las reglas del cupo de crédito.
void main() {
  Map<String, dynamic> ejemplo() {
    final texto = File('test/fixtures/api/16_V1_clientes.json')
        .readAsStringSync();
    final cuerpo =
        ((jsonDecode(texto) as Map<String, dynamic>)['respuesta']
                as Map<String, dynamic>)['body']
            as Map<String, dynamic>;
    return (cuerpo['clientes'] as List).first as Map<String, dynamic>;
  }

  Cliente crear({int limite = 500000, int saldo = 0}) => Cliente(
    id: 1,
    nombre: 'Doña Rosa',
    celular: null,
    limiteCreditoCentavos: limite,
    saldoPendienteCentavos: saldo,
  );

  group('desdeJson', () {
    test(
      'lee el ejemplo real: el cupo "5000.00" y el saldo 0 pasan a centavos',
      () {
        final c = Cliente.desdeJson(ejemplo())!;
        expect(c.id, 1);
        expect(c.nombre, 'Doña Rosa');
        expect(c.celular, '3001234567');
        expect(c.limiteCreditoCentavos, 500000);
        expect(c.saldoPendienteCentavos, 0);
        expect(c.sinTope, isFalse);
      },
    );

    test('el saldo puede llegar como número entero, decimal o texto', () {
      expect(
        Cliente.desdeJson({...ejemplo(), 'saldo_pendiente': 2500})!
            .saldoPendienteCentavos,
        250000,
      );
      expect(
        Cliente.desdeJson({...ejemplo(), 'saldo_pendiente': 2500.5})!
            .saldoPendienteCentavos,
        250050,
      );
      expect(
        Cliente.desdeJson({...ejemplo(), 'saldo_pendiente': '2500.00'})!
            .saldoPendienteCentavos,
        250000,
      );
    });

    test('el celular puede faltar', () {
      expect(
        Cliente.desdeJson({...ejemplo(), 'celular': null})!.celular,
        isNull,
      );
    });

    test('una forma rara se descarta (null) en vez de inventar valores', () {
      expect(Cliente.desdeJson(null), isNull);
      expect(Cliente.desdeJson('texto'), isNull);
      expect(Cliente.desdeJson({...ejemplo(), 'id_cliente': '1'}), isNull);
      expect(Cliente.desdeJson({...ejemplo(), 'nombre': null}), isNull);
      expect(Cliente.desdeJson({...ejemplo(), 'celular': 3001234567}), isNull);
      expect(
        Cliente.desdeJson({...ejemplo(), 'saldo_pendiente': null}),
        isNull,
      );
      expect(Cliente.desdeJson({...ejemplo(), 'saldo_pendiente': -5}), isNull);
    });

    test('un cupo ilegible NO se convierte en «sin tope» (dejaría fiar sin límite)', () {
      for (final malo in ['abc', '', '-100.00', '1.234', null, true]) {
        expect(
          Cliente.desdeJson({...ejemplo(), 'limite_credito': malo}),
          isNull,
          reason: 'limite_credito: $malo',
        );
      }
    });
  });

  group('el cupo de crédito', () {
    test('cabe si lo que ya debe más la venta no pasa del cupo', () {
      final c = crear(
        limite: 500000,
        saldo: 100000,
      ); // cupo $5.000, debe $1.000
      expect(c.alcanzaCupo(400000), isTrue); // $4.000: queda justo en $5.000
      expect(c.alcanzaCupo(400001), isFalse); // un centavo de más
    });

    test('estar justo en el cupo es válido, igual que en el servidor', () {
      expect(crear(limite: 450000).alcanzaCupo(450000), isTrue);
      expect(crear(limite: 450000).alcanzaCupo(450001), isFalse);
    });

    test('un cupo de 0 significa «sin tope»', () {
      final c = crear(limite: 0, saldo: 9999900);
      expect(c.sinTope, isTrue);
      expect(c.alcanzaCupo(99999900), isTrue);
      expect(c.cupoDisponibleCentavos, isNull);
    });

    test('el cupo disponible es el cupo menos lo que debe', () {
      expect(
        crear(limite: 500000, saldo: 120000).cupoDisponibleCentavos,
        380000,
      );
    });
  });
}
