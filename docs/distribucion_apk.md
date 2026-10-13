# Firma y release del APK (Android)

**Quién firma:** Luis, que custodia la llave. Los demás compilan en debug y **no** reparten APK.
**Por qué importa:** Android no actualiza una app firmada con otra llave. Si un APK de release se firma con la llave de depuración (que es distinta en cada computador) y se reparte, nunca podrá actualizarse a una versión firmada con la llave de Luis: habría que desinstalar la app en cada celular.

## Qué cambió en el build (13-oct-2026)
- `AndroidManifest.xml` (principal) ahora declara `INTERNET`. Antes solo lo traían los manifiestos de *debug* y *profile*, así que un release no tenía red.
- `android/app/build.gradle.kts` firma el release con la llave de `android/key.properties`. Si ese archivo no existe, **el release se bloquea** con un mensaje; el modo debug (`flutter run`, `flutter test`) no se afecta.

## Crear la llave (una sola vez, Luis)
Fuera del repositorio:

```bash
keytool -genkeypair -v -keystore C:\ruta\fuera\del\repositorio\stockpilot-release.jks -alias stockpilot -keyalg RSA -keysize 2048 -validity 10000
```

Las contraseñas van a un gestor de contraseñas, **nunca** a un archivo del proyecto. **Hacer copia del `.jks` en dos lugares distintos**: sin ella no se puede actualizar a nadie.

## `android/key.properties` (no se sube; ya está en el `.gitignore`)

```properties
storeFile=C:/ruta/fuera/del/repositorio/stockpilot-release.jks
storePassword=<contraseña del almacén>
keyAlias=stockpilot
keyPassword=<contraseña de la llave>
```

## Compilar un release
Desde `app_tendero/` (la dirección del servidor va en `--dart-define`, nunca en el código):

```bash
flutter build apk --release --dart-define=API_BASE_URL=<dirección del servidor>
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk`. Antes, subir el número de `version:` en `pubspec.yaml` (`1.0.2+3`: el `+3` es el `versionCode` y debe ser **mayor** que el de la versión anterior).

Comprobar la firma (herramienta `apksigner` del SDK de Android): `apksigner verify --print-certs app-release.apk` debe mostrar el certificado de Luis, no «Android Debug».

## Probar un release en tu equipo sin la llave
Solo para ver que compila o probar el comportamiento sin depuración; **ese APK no se reparte**:

```powershell
$env:STOCKPILOT_FIRMA_DEPURACION = '1'
flutter build apk --release --dart-define=API_BASE_URL=<dirección del servidor>
```

## Publicar la versión
Calcular la huella SHA-256, subir el APK al almacenamiento privado y configurar las variables del servidor: ver `docs/distribucion_app_beta.md` del repositorio del backend. La app consultará `[U1]` y `[U2]` del contrato para avisar de versiones nuevas.

## Qué no se probó por código
La instalación en un celular real, el permiso «instalar apps desconocidas» y la cámara los prueba una persona.
