# StockPilot · App del Tendero

App nativa (Flutter, **Android primero**) para que el Tendero de una tienda de barrio **venda, escanee productos, abra y cierre caja** desde el celular. Se conecta a la API del backend de StockPilot.

> **Si vas a trabajar en este repositorio, lee primero [`docs/guia_del_equipo.md`](docs/guia_del_equipo.md).** Ahí están las tareas, las reglas y cómo subir tu trabajo. Este archivo es solo la puerta de entrada.

## Las cuatro reglas que más importan
1. **Nunca se sube nada a `main`.** Cada tarea va en su propia rama y se sube con un *pull request* en borrador. **Solo Lucho mezcla.** `main` está protegida: exige un PR.
2. **Antes de empezar una tarea, mira si alguien ya la tomó** y reclámala abriendo tu rama y tu PR en borrador el primer día.
3. **Este repositorio es público.** Ni contraseñas, ni claves, ni llaves de firma, ni cookies, ni la dirección del servidor en el código. Revisa tu `git diff` antes de cada `push`.
4. **Contrato antes que código.** La forma de cada respuesta de la API sale de los ejemplos reales del backend, nunca de tu imaginación.

## Qué está hecho y qué falta
- **Hecho:** sesión (login, segundo factor, primer cambio de contraseña), caja (abrir y cerrar con arqueo), catálogo y búsqueda, carrito, cobro en efectivo, tarjeta, transferencia y fiado, escáner dentro de la venta, actualizar al volver a la app, y el aviso de versión nueva.
- **Por hacer:** egresos, recibir mercancía, alertas, ventas del turno, solicitar un producto y las pruebas en celular. El tablero con el detalle de cada una está en [`docs/guia_del_equipo.md`](docs/guia_del_equipo.md), sección 5.

## Empezar
1. **Pide a Lucho, por un canal privado** (nunca por el repositorio):
   - **acceso de lectura al repositorio del backend** (`LuchoSecDev/StockPilot`). **Es privado**, y el contrato de la API y los ejemplos reales viven en su carpeta `docs/` (`contrato_api_app_tendero.md` y `ejemplos_app_tendero/`). Sin ese acceso no puedes empezar una tarea;
   - la dirección del servidor y las cuentas de prueba.
2. **Instala Flutter 3.47.x (Dart 3.13.x)** y un celular Android con depuración por USB o inalámbrica.
3. **Clona el repositorio en una ruta sin tildes ni espacios** (por ejemplo `C:\Estudio\AppNativaFlutter`). Con una tilde en la ruta, el analizador de Flutter falla en Windows.
4. **Todos los comandos se ejecutan desde `app_tendero/`**, no desde la raíz (el proyecto Flutter vive en esa subcarpeta):
   ```bash
   cd app_tendero
   flutter pub get
   flutter test        # no necesita celular ni internet
   flutter analyze
   flutter run --dart-define=API_BASE_URL=https://<servidor>
   ```
   La dirección del servidor va **solo** en `--dart-define`.

## Cómo está organizado
```
app_tendero/          el proyecto Flutter
  lib/                código (api, auth, caja, carrito, catalogo, clientes, venta, ui…)
  test/               pruebas; test/fixtures/api = ejemplos REALES copiados del backend
  tool/               herramienta de mutaciones (comprueba que las pruebas detectan errores)
docs/
  guia_del_equipo.md  tareas, reglas y cómo subir tu trabajo  ← empieza aquí
  pruebas_sesion.md   qué se probó en celular y qué falta
  planes/             propuestas para el futuro (no son tareas del tablero)
AGENTS.md             reglas para asistentes de IA (también valen para personas)
.github/              plantilla del pull request
```
Cada función sigue las mismas cinco capas (modelos, repositorio, estado con Riverpod, pantalla y pruebas). El detalle y la receta están en la guía, secciones 3 y 4.

## Subir tu trabajo
```bash
git switch main && git pull
git switch -c feat/t1-egresos-<tus-iniciales>        # una rama por tarea
# ... trabaja con commits pequeños, en español
flutter analyze && flutter test                      # antes de cada push (desde app_tendero/)
git push -u origin feat/t1-egresos-<tus-iniciales>   # SIEMPRE a tu rama
```
Abre un PR en borrador hacia `main` con la plantilla del repositorio, y márcalo «listo para revisar» cuando termine. **Lucho revisa y mezcla.**

## Lo que NO se toca sin hablar antes con Lucho
El contrato de la API; el cobro y el carrito (`venta/`, `carrito/`); el cierre de caja; la sesión y el interceptor (`api/`, `auth/`); las dependencias nuevas (`pubspec.yaml`) y los permisos de Android; y todo lo relacionado con la firma de la app y su distribución.

## Otros documentos
- [`AGENTS.md`](AGENTS.md): las reglas de calidad si usas un asistente de IA.
- [`docs/pruebas_sesion.md`](docs/pruebas_sesion.md): la lista de pruebas de celular de cada función.
- [`app_tendero/README.md`](app_tendero/README.md): notas del proyecto Flutter.
- [`docs/planes/`](docs/planes/): propuestas para después (la cartilla de códigos y las imágenes). **No las empieces.**
