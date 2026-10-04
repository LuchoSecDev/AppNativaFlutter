import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home_screen.dart';
import '../../ui/colores.dart';
import '../auth_providers.dart';
import '../session_state.dart';
import 'login_screen.dart';
import 'primer_cambio_clave_screen.dart';
import 'verificacion_2fa_screen.dart';

/// La «puerta» de la app: según en qué fase esté la sesión, muestra la pantalla que corresponde. Es lo único que
/// decide qué se ve; ninguna pantalla navega por su cuenta hacia otra de la sesión.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fase = ref.watch(sesionProvider.select((e) => e.fase));
    return switch (fase) {
      FaseSesion.iniciando => const PantallaConectando(),
      FaseSesion.sinSesion => const LoginScreen(),
      FaseSesion.codigo2FA => const Verificacion2FAScreen(),
      FaseSesion.cambioClave => const PrimerCambioClaveScreen(),
      FaseSesion.activa => const HomeScreen(),
    };
  }
}

/// Se muestra al abrir la app mientras se comprueba si ya hay una sesión. Si el servidor estaba dormido, la
/// primera respuesta puede tardar cerca de un minuto: la pantalla lo explica para que el usuario no crea que
/// se trabó.
class PantallaConectando extends StatelessWidget {
  const PantallaConectando({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colores.papel,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'StockPilot',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colores.azul,
                ),
              ),
              SizedBox(height: 24),
              CircularProgressIndicator(),
              SizedBox(height: 24),
              Text(
                'Conectando…',
                style: TextStyle(fontSize: 18, color: Colores.tinta),
              ),
              SizedBox(height: 8),
              Text(
                'La primera vez puede tardar hasta un minuto si el servidor estaba dormido.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colores.tinta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
