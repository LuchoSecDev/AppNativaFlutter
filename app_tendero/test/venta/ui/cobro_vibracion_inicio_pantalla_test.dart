import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/home_screen.dart';
import 'package:stockpilot/venta/venta_models.dart';

import '../../support/carrito_apoyo.dart';
import '../../support/cobro_pantallas_apoyo.dart';
import '../../support/fake_adapter.dart';
import '../../support/vibracion_apoyo.dart';

/// La vibración del cobro y el resumen en la pantalla de inicio.
void main() {
  const clave = claveDeCobro;
  const ruta = rutaDeCobro;
  final banco = BancoDeCobro();

  group('la vibración del cobro', () {
    testWidgets('venta registrada: vibra una vez al mostrar el comprobante', (
      tester,
    ) async {
      final vibraciones = registrarVibraciones(tester);
      await banco.abrir(tester);
      banco.programarVentaOk();
      await abrirCobro(tester);
      await escribir(tester, '10000');
      expect(vibraciones, isEmpty, reason: 'ni elegir ni escribir vibran');
      await confirmar(tester);
      expect(find.text('Venta registrada'), findsOneWidget);
      expect(vibraciones, [vibracionMedia]);
    });

    testWidgets('rechazo del servidor: vibra fuerte, una vez', (tester) async {
      final vibraciones = registrarVibraciones(tester);
      await banco.abrir(tester);
      banco.servidor.programar(
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
      expect(vibraciones, [vibracionFuerte]);
    });

    testWidgets('sin red (venta sin confirmar): vibra una vez, de atención', (
      tester,
    ) async {
      final vibraciones = registrarVibraciones(tester);
      await banco.abrir(tester);
      banco.programarSinRed();
      await abrirCobro(tester);
      await escribir(tester, '10000');
      await confirmar(tester);
      expect(find.textContaining('No la cobres otra vez'), findsOneWidget);
      expect(vibraciones, [vibracionMedia]);
    });
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
      await banco.abrir(
        tester,
        pantalla: const HomeScreen(),
        ventaPrevia: previa,
      );
      expect(
        find.textContaining('Hay una venta sin confirmar'),
        findsOneWidget,
      );
    });

    testWidgets('sin ventas pendientes no hay aviso', (tester) async {
      await banco.abrir(tester, pantalla: const HomeScreen());
      expect(find.textContaining('sin confirmar'), findsNothing);
    });
  });
}
