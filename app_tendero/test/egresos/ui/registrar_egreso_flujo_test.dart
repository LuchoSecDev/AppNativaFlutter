import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/egresos/egreso_models.dart';

import '../../support/egreso_apoyo.dart';
import '../../support/egreso_pantallas_apoyo.dart';
import '../../support/fake_adapter.dart';
import '../../support/vibracion_apoyo.dart';

/// El recorrido completo de registrar un gasto, con el cliente HTTP real y un servidor falso con los ejemplos reales.
void main() {
  const claveDelAlmacen = 'egreso_pendiente_v1_2_1';

  late EntornoDeEgresos e;
  late List<String> vibraciones;

  Future<void> abrirRegistroDeGastos(
    WidgetTester tester, {
    void Function(EntornoDeEgresos)? antes,
  }) async {
    e = EntornoDeEgresos();
    antes?.call(e);
    vibraciones = registrarVibraciones(tester);
    await abrirPantallaDeEgresos(tester, e);
    await abrirRegistro(tester);
  }

  Future<void> llenar(
    WidgetTester tester, {
    String monto = '10000',
    String motivo = 'Bolsas y hielo',
    String categoria = 'Otro',
  }) async {
    await tester.enterText(find.widgetWithText(TextField, 'Monto'), monto);
    await tester.enterText(find.widgetWithText(TextField, 'Motivo'), motivo);
    await tester.tap(find.widgetWithText(ChoiceChip, categoria));
    await tester.pump();
  }

  Future<void> registrar(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, 'Registrar gasto'));
    await tester.pumpAndSettle();
  }

  void programar(RespuestaFalsa r) =>
      e.servidor.programar('POST', EntornoDeEgresos.ruta, r);

  testWidgets(
    '[24] registrar: comprobante con el gasto, «pendiente de aprobación», una vibración y «Listo» vuelve',
    (tester) async {
      await abrirRegistroDeGastos(tester);
      programar(RespuestaFalsa.deEjemplo('24_K4_egreso_ok'));
      await llenar(tester);
      await registrar(tester);

      expect(find.text('Gasto registrado'), findsOneWidget);
      expect(find.text('Gasto n.º 1'), findsOneWidget);
      expect(find.text(r'$10.000'), findsOneWidget);
      expect(find.text('Otro'), findsOneWidget);
      expect(find.text('Bolsas y hielo'), findsOneWidget);
      expect(
        find.text('Queda pendiente de aprobación del Administrador.'),
        findsOneWidget,
      );
      expect(find.textContaining('ya estaba registrado'), findsNothing);
      expect(vibraciones, [vibracionMedia]);
      expect(e.envios().single.cuerpo, {
        'monto': 10000,
        'motivo': 'Bolsas y hielo',
        'categoria': 'Otro',
      });
      expect(e.envios().single.headers['Idempotency-Key'], claveDeEgreso);

      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();
      expect(find.text('Abrir gasto'), findsOneWidget);
      expect(e.almacen.datos, isEmpty);
    },
  );

  testWidgets(
    'después de registrar, el siguiente gasto empieza con el formulario en blanco',
    (tester) async {
      await abrirRegistroDeGastos(tester);
      programar(RespuestaFalsa.deEjemplo('24_K4_egreso_ok'));
      await llenar(tester);
      await registrar(tester);
      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();

      await abrirRegistro(tester);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Monto'))
            .controller!
            .text,
        '',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Motivo'))
            .controller!
            .text,
        '',
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Otro'))
            .selected,
        isFalse,
      );
    },
  );

  testWidgets(
    'rechazo del servidor: muestra su mensaje, vibra fuerte una vez y CONSERVA lo escrito',
    (tester) async {
      await abrirRegistroDeGastos(tester);
      // Sin ejemplo real: el cuerpo sale del contrato [K4].
      programar(
        const RespuestaFalsa(400, {
          'error': 'No hay ninguna caja abierta. No puedes registrar gastos.',
        }),
      );
      await llenar(tester);
      await registrar(tester);

      expect(
        find.text('No hay ninguna caja abierta. No puedes registrar gastos.'),
        findsOneWidget,
      );
      expect(vibraciones, [vibracionFuerte]);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Monto'))
            .controller!
            .text,
        '10000',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Motivo'))
            .controller!
            .text,
        'Bolsas y hielo',
      );
      expect(
        find.widgetWithText(ElevatedButton, 'Registrar gasto'),
        findsOneWidget,
      );
    },
  );

  testWidgets('salir y volver conserva lo escrito', (tester) async {
    await abrirRegistroDeGastos(tester);
    await llenar(
      tester,
      monto: '2500',
      motivo: 'Pasaje del domingo',
      categoria: 'Transporte',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await abrirRegistro(tester);

    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Monto'))
          .controller!
          .text,
      '2500',
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Motivo'))
          .controller!
          .text,
      'Pasaje del domingo',
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Transporte'))
          .selected,
      isTrue,
    );
  });

  testWidgets(
    'salir con un rechazo a la vista: al volver no queda el mensaje viejo',
    (tester) async {
      await abrirRegistroDeGastos(tester);
      programar(
        const RespuestaFalsa(400, {'error': 'El monto debe ser mayor a 0.'}),
      );
      await llenar(tester);
      await registrar(tester);
      expect(find.text('El monto debe ser mayor a 0.'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await abrirRegistro(tester);
      expect(find.text('El monto debe ser mayor a 0.'), findsNothing);
    },
  );

  group('cuando no se sabe qué pasó', () {
    Future<void> hastaSinConfirmar(WidgetTester tester) async {
      await abrirRegistroDeGastos(tester);
      programar(
        const RespuestaFalsa.falloDeRed(DioExceptionType.connectionError),
      );
      await llenar(tester);
      await registrar(tester);
    }

    testWidgets(
      'sin red: «sin confirmar» con el gasto a la vista, una vibración y SIN «registrar de nuevo»',
      (tester) async {
        await hastaSinConfirmar(tester);

        expect(find.textContaining('No lo registres otra vez'), findsOneWidget);
        expect(find.text(r'$10.000'), findsOneWidget);
        expect(find.text('Bolsas y hielo'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
        expect(find.text('Cancelar este gasto'), findsOneWidget);
        expect(
          find.widgetWithText(ElevatedButton, 'Registrar gasto'),
          findsNothing,
          reason: 'nunca se ofrece registrar de nuevo',
        );
        expect(vibraciones, [vibracionMedia]);
        expect(e.almacen.datos[claveDelAlmacen], isNotNull);
      },
    );

    testWidgets(
      '[32] «Reintentar» manda la MISMA clave y carga; si ya estaba, lo dice y no duplica',
      (tester) async {
        await hastaSinConfirmar(tester);
        programar(RespuestaFalsa.deEjemplo('32_K4_reintento_misma_clave_200'));

        await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
        await tester.pumpAndSettle();

        expect(find.text('Gasto registrado'), findsOneWidget);
        expect(find.textContaining('ya estaba registrado'), findsOneWidget);
        expect(e.envios(), hasLength(2));
        expect(
          e.envios()[1].headers['Idempotency-Key'],
          e.envios()[0].headers['Idempotency-Key'],
        );
        expect(e.envios()[1].cuerpo, e.envios()[0].cuerpo);
        expect(e.almacen.datos, isEmpty);
      },
    );

    testWidgets(
      '«Cancelar este gasto» advierte del riesgo de duplicar; «Volver» no cambia nada',
      (tester) async {
        await hastaSinConfirmar(tester);
        await tester.tap(find.text('Cancelar este gasto'));
        await tester.pumpAndSettle();
        expect(find.textContaining('lo duplicaría'), findsOneWidget);

        await tester.tap(find.text('Volver'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
        expect(e.almacen.datos[claveDelAlmacen], isNotNull);
      },
    );

    testWidgets(
      'confirmar la cancelación: vuelve el formulario y se borra lo guardado',
      (tester) async {
        await hastaSinConfirmar(tester);
        await tester.tap(find.text('Cancelar este gasto'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancelar el gasto'));
        await tester.pumpAndSettle();

        expect(
          find.widgetWithText(ElevatedButton, 'Registrar gasto'),
          findsOneWidget,
        );
        expect(e.almacen.datos, isEmpty);
      },
    );
  });

  testWidgets(
    'un gasto que quedó a medias aparece al abrir, listo para reintentar (no se reenvía solo)',
    (tester) async {
      await abrirRegistroDeGastos(
        tester,
        antes: (e) => e.almacen.datos[claveDelAlmacen] = const EgresoPendiente(
          clave: claveDeEgreso,
          montoPesos: 4500,
          motivo: 'Hielo para la nevera',
          categoria: CategoriaEgreso.insumosYBolsas,
        ),
      );

      expect(
        find.textContaining('Quedó un gasto sin confirmar'),
        findsOneWidget,
      );
      expect(find.text(r'$4.500'), findsOneWidget);
      expect(find.text('Insumos / Bolsas'), findsOneWidget);
      expect(find.text('Hielo para la nevera'), findsOneWidget);
      expect(e.envios(), isEmpty);
    },
  );
}
