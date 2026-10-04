# StockPilot · App del Tendero

App nativa (Flutter, Android primero) para que el Tendero de una tienda de barrio venda, abra y cierre caja desde el celular. Se conecta a la API del backend de StockPilot.

- **Identificador:** `com.lem.stockpilot` (`lem` son las iniciales del equipo fundador; no se cambia).
- **Estado:** en construcción. Hay escáner de prueba (paso 1), la sesión completa (paso 2: login, segundo factor, primer cambio de contraseña y cerrar sesión) y la apertura de caja (paso 3). La guía de construcción define el orden de lo que sigue.

## Documentación (vive en el repositorio del backend, `StockPilot`, carpeta `docs/`)
- `guia_construccion_app.md`: por dónde empezar y cuándo se da cada paso por terminado.
- `contrato_api_app_tendero.md`: la API que usa la app, endpoint por endpoint.
- `ejemplos_app_tendero/`: peticiones y respuestas reales, para simular el servidor en las pruebas.
- `propuesta_tecnica_app_flutter.md`: decisiones técnicas ya tomadas.

## Cómo ejecutarla
```bash
cd app_tendero
flutter pub get
flutter run --dart-define=API_BASE_URL=https://<servidor>   # con un celular Android (USB o depuración inalámbrica)
flutter test         # pruebas (no necesitan celular ni internet)
flutter analyze      # análisis estático
```
La dirección del servidor **no** va en el código: se entrega al ejecutar con `--dart-define`. Sin ella, la app muestra un aviso y solo deja probar el escáner.

**Solo en modo depuración** (`flutter run`, nunca en una versión de entrega), la pantalla de login muestra el servidor al que apunta, un botón **«Probar conexión con el servidor»** (comprueba que la app llega, sin usar credenciales) y otro para **probar el escáner sin iniciar sesión**.

Las credenciales de prueba se escriben en el login o se piden al responsable; **nunca** se guardan en el repositorio.
La cámara solo se puede probar en un celular real. Versión de Flutter con la que se creó el proyecto: 3.47.x (Dart 3.13.x).

## Reglas del proyecto
- **Este repositorio es público.** Nada de contraseñas, claves, cookies, llaves de firma (`*.jks`, `key.properties`) ni la URL del servidor de pruebas en el código; la URL va en configuración local fuera de Git.
- **Trabaja en una ruta sin tildes ni espacios** (por ejemplo `C:\Estudio\AppNativaFlutter`): con una tilde en la ruta, el analizador de Flutter falla en Windows.
- El estado se maneja con `flutter_riverpod`; los widgets no llaman al servidor directamente.
