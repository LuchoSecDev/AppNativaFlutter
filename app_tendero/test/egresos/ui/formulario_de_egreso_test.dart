import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/auth/session_state.dart';

import '../../support/carrito_apoyo.dart';
import '../../support/egreso_apoyo.dart';
import '../../support/egreso_pantallas_apoyo.dart';

/// El formulario de gasto: qué deja escribir y cuándo habilita el botón.
void main() {
  Finder campoMonto() => find.widgetWithText(TextField, 'Monto');
  Finder campoMotivo() => find.widgetWithText(TextField, 'Motivo');
  Finder categoria(String c) => find.widgetWithText(ChoiceChip, c);
  Finder boton() => find.widgetWithText(ElevatedButton, 'Registrar gasto');

  bool habilitado(WidgetTester tester) =>
      tester.widget<ElevatedButton>(boton()).onPressed != null;

  Future<void> abrirFormulario(
    WidgetTester tester, {
    EstadoSesion? sesion,
  }) async {
    final entorno = EntornoDeEgresos(sesionInicial: sesion);
    await abrirPantallaDeEgresos(tester, entorno);
    await abrirRegistro(tester);
  }

  Future<void> escribir(WidgetTester tester, Finder campo, String texto) async {
    await tester.enterText(campo, texto);
    await tester.pump();
  }

  testWidgets(
    'al abrir: el botón está bloqueado, no hay categoría elegida y se ve el tope',
    (tester) async {
      await abrirFormulario(tester);
      expect(habilitado(tester), isFalse);
      for (final c in [
        'Proveedor menor',
        'Insumos / Bolsas',
        'Transporte',
        'Limpieza',
        'Servicios',
        'Otro',
      ]) {
        expect(
          tester.widget<ChoiceChip>(categoria(c)).selected,
          isFalse,
          reason: c,
        );
      }
      expect(find.text(r'Tu tope por gasto es $150.000.'), findsOneWidget);
    },
  );

  testWidgets('el monto solo admite dígitos y hasta 9', (tester) async {
    await abrirFormulario(tester);
    await escribir(tester, campoMonto(), '12ab.-3456789012');
    expect(
      tester.widget<TextField>(campoMonto()).controller!.text,
      '123456789',
    );
  });

  testWidgets(
    'el botón se habilita solo con monto, motivo de 5 o más caracteres y una categoría',
    (tester) async {
      await abrirFormulario(tester);
      await escribir(tester, campoMonto(), '10000');
      expect(
        habilitado(tester),
        isFalse,
        reason: 'falta el motivo y la categoría',
      );
      await escribir(tester, campoMotivo(), 'Bolsas y hielo');
      expect(habilitado(tester), isFalse, reason: 'falta la categoría');
      await tester.tap(categoria('Otro'));
      await tester.pump();
      expect(habilitado(tester), isTrue);
      await escribir(tester, campoMonto(), '');
      expect(habilitado(tester), isFalse, reason: 'sin monto');
      await escribir(tester, campoMonto(), '0');
      expect(habilitado(tester), isFalse, reason: 'monto 0');
    },
  );

  testWidgets(
    'un motivo corto lo dice y bloquea; con espacios sobrantes sigue contando corto',
    (tester) async {
      await abrirFormulario(tester);
      await escribir(tester, campoMonto(), '10000');
      await tester.tap(categoria('Otro'));
      await escribir(tester, campoMotivo(), '  abcd  ');
      expect(find.text('Escribe al menos 5 caracteres.'), findsOneWidget);
      expect(habilitado(tester), isFalse);
      await escribir(tester, campoMotivo(), 'abcde');
      expect(find.text('Escribe al menos 5 caracteres.'), findsNothing);
      expect(habilitado(tester), isTrue);
    },
  );

  testWidgets(
    'la categoría es de elección única: elegir otra quita la anterior',
    (tester) async {
      await abrirFormulario(tester);
      await tester.tap(categoria('Transporte'));
      await tester.pump();
      await tester.tap(categoria('Limpieza'));
      await tester.pump();
      expect(
        tester.widget<ChoiceChip>(categoria('Transporte')).selected,
        isFalse,
      );
      expect(tester.widget<ChoiceChip>(categoria('Limpieza')).selected, isTrue);
    },
  );

  testWidgets(
    'Tendero: sobre el tope avisa y bloquea; el IGUAL al tope se puede registrar',
    (tester) async {
      await abrirFormulario(tester);
      await escribir(tester, campoMotivo(), 'Gasto grande');
      await tester.tap(categoria('Otro'));
      await escribir(tester, campoMonto(), '150001');
      expect(
        find.text(r'Supera tu tope de $150.000 por gasto.'),
        findsOneWidget,
      );
      expect(habilitado(tester), isFalse);

      await escribir(tester, campoMonto(), '150000');
      expect(find.textContaining('Supera tu tope'), findsNothing);
      expect(habilitado(tester), isTrue);
    },
  );

  testWidgets('Administrador: no hay tope, ni se menciona', (tester) async {
    await abrirFormulario(tester, sesion: sesionActiva(rol: 'Administrador'));
    expect(find.textContaining('Tu tope'), findsNothing);
    await escribir(tester, campoMonto(), '5000000');
    await escribir(tester, campoMotivo(), 'Compra grande');
    await tester.tap(categoria('Otro'));
    await tester.pump();
    expect(habilitado(tester), isTrue);
  });
}
