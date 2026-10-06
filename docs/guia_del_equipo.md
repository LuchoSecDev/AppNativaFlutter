# Guía del equipo: cómo trabajar en la app del Tendero

**Para quién:** quienes van a terminar las funciones que faltan.
**Lo más importante, en cuatro líneas:**
1. **Nunca se sube nada a `main`.** Cada tarea va en su propia rama y se sube con un *pull request* en borrador. **Solo Lucho mezcla.**
2. **Antes de empezar una tarea, mira si alguien ya la tomó** (sección 5). Reclámala abriendo tu rama y tu PR en borrador **el primer día**.
3. **El repositorio es público:** ni contraseñas, ni claves, ni cookies, ni la dirección del servidor en el código (sección 2).
4. **El contrato de la API vive en el repositorio del backend.** La app se adapta a él; si no alcanza, se avisa a Lucho (sección 8). No se contornea.

---

## 1. Qué es esto
App nativa (Flutter, Android primero) para que el Tendero de una tienda de barrio venda, escanee, abra y cierre caja. Habla con la API del backend de StockPilot (repositorio `luchoTeso/StockPilot`, carpeta `docs/`).

Documentos que **debes leer**, en este orden (están en el repositorio del backend):
1. `docs/guia_entorno_app.md`: contra qué servidor desarrollar y reglas que más se olvidan.
2. `docs/contrato_api_app_tendero.md`: la referencia de la API. Cada endpoint tiene un ID (`[K4]`, `[M1]`…) y una prueba que lo respalda.
3. `docs/ejemplos_app_tendero/`: **cada llamada real**, con petición y respuesta.
4. `docs/guia_construccion_app.md`: el orden de los pasos y cuándo se da cada uno por terminado.

Y en este repositorio: `docs/pruebas_sesion.md` (qué se probó en celular y qué falta) y `.agents/rules/reglas_del_proyecto.md` (las reglas de calidad).

## 2. Preparar el entorno
- **Flutter 3.47.x (Dart 3.13.x).** Trabaja en una ruta **sin tildes ni espacios** (por ejemplo `C:\Estudio\AppNativaFlutter`): con una tilde en la ruta el analizador falla en Windows.
- Todos los comandos se ejecutan **desde `app_tendero/`**:
  ```bash
  flutter pub get
  flutter run --dart-define=API_BASE_URL=https://<servidor>   # con un celular Android (USB o depuración inalámbrica)
  flutter test        # sin celular ni internet
  flutter analyze
  ```
- **La dirección del servidor** se pide a Lucho y va **solo** en `--dart-define`. Las **cuentas de prueba** también se piden a Lucho; nunca se escriben en un archivo del repositorio.
- El servidor gratuito (Render) se duerme a los 15 minutos y tarda cerca de un minuto en despertar: la primera petición puede parecer colgada.
- Hoy se desarrolla contra el servidor desplegado, con tiendas de prueba. **No uses cuentas ni datos de una tienda real.**
- **No subas nunca:** `*.jks`, `android/key.properties`, `.env`, `local.properties`, `.idea`, cookies, tokens. El `.gitignore` ya cubre varios, pero **revisa tu `git diff` antes de cada push**.

## 3. Cómo está hecho el código (léelo antes de escribir una línea)
```
lib/
  api/        cliente HTTP (Dio), cookie persistente, token CSRF, manejo de sesión caducada
  auth/       login, 2FA, primer cambio de contraseña, estado de la sesión
  caja/       abrir, cerrar (arqueo en tres tiempos), estado de la caja
  carrito/    carrito de la venta (guardado en el celular)
  catalogo/   lista de productos y búsqueda
  venta/      cobro, escáner de venta, clave de idempotencia
  ui/         piezas comunes: colores, formato de dinero, botones, «actualizar»
  vista_de_escaneo.dart   la cámara con el recuadro (compartida por las dos pantallas del escáner)
test/         espejo de lib/, con test/fixtures/api = ejemplos REALES copiados del backend
tool/mutar.dart           herramienta para comprobar que las pruebas detectan errores (sección 6)
```
Cada función sigue **las mismas cinco capas**; cópiate de `lib/caja/` (la más completa):

| Capa | Archivo típico | Qué hace |
|---|---|---|
| Modelos | `xxx_models.dart` | Los datos y los resultados. Los resultados esperables (400, 404…) son **valores** (`sealed class`), no excepciones. |
| Repositorio | `xxx_repository.dart` | Habla con la API. Solo se lanzan como `ErrorDeApi` las fallas de red o del servidor. |
| Estado | `xxx_providers.dart` | Un `Notifier` de Riverpod. **Los widgets nunca llaman al servidor.** |
| Pantalla | `ui/xxx_screen.dart` | Solo dibuja y reenvía toques al estado. |
| Pruebas | `test/xxx/…` | Una por capa. |

### Reglas del código que no se negocian
- **El dinero va en centavos enteros** (`int`), nunca `double`. Los importes de la API llegan como texto o número: conviértelos con `centavosDeImporte` (`ui/dinero.dart`). Mostrar: `formatoPesos(importeDeCentavos(...))`.
- **Ninguna escritura se reintenta a ciegas**, salvo la venta (tiene `Idempotency-Key`). Egresos, entradas de mercancía y cierre de caja **no** tienen idempotencia: repetirlos duplica el efecto. Ante un tiempo de espera, primero se **consulta** cómo quedó (ver `caja/cierre_providers.dart`).
- **Respuestas tardías:** cada `Notifier` lleva un contador `_generacion` que cambia con la sesión; una respuesta de una sesión anterior se descarta. Mantén ese patrón.
- **Lo que decide la regla es el servidor.** La app ayuda a validar, pero muestra siempre lo que el servidor responde. Los datos de la tienda (como el tope de egresos, `limiteEgresoTendero`) salen de `GET /api/session-info`, no se fijan en la app.
- **No perder el carrito** si falla la red o caduca la sesión. Un 401 vuelve al login sin perder lo que la persona estaba haciendo.
- Textos de pantalla y **comentarios en español**; los comentarios explican el **porqué**, no repiten el código.
- No reformatees archivos ajenos: ejecuta `dart format` **solo sobre los archivos que tocaste**.

## 4. La receta de una función nueva
1. **Contrato.** Lee el endpoint en el contrato y **copia su ejemplo real** de `docs/ejemplos_app_tendero/` del backend a `test/fixtures/api/`. **Nunca inventes la forma de una respuesta**: una vez se inventó una clave y todo pasaba en verde mientras la función no servía.
2. **Modelos y repositorio**, con su prueba contra el fixture (`RespuestaFalsa.deEjemplo('NN_ID_...')`, ver `test/support/fake_adapter.dart`). Cubre: éxito, cada 400/404/403 del contrato, sin red, 500 y una respuesta con forma rara.
3. **Estado (`Notifier`)** con su prueba: flujo feliz, cada falla, doble toque, respuesta tardía de otra sesión.
4. **Pantalla** con su prueba de widgets. El cliente HTTP es el real y el servidor es el falso.
5. **Mutaciones** (sección 6): rompe a propósito cada regla importante y comprueba que alguna prueba falla.
6. **Prueba de celular:** agrega a `docs/pruebas_sesion.md` una lista de lo que solo se ve con un teléfono real (la cámara, la señal, el teclado) y **dilo en tu PR**.
7. `flutter analyze` limpio y `flutter test` en verde. Después, el PR.

## 5. Cómo no pisarse: tablero de tareas
**Para reclamar una tarea:** crea tu rama y abre un **PR en borrador** con el título `[T1] Egresos — tu nombre` el primer día (aunque esté vacío). **Antes de empezar, mira los PR abiertos y las ramas remotas** (`git fetch` y `git branch -r`): si ya hay uno de esa tarea, habla con quien la tiene.

| ID | Tarea | Endpoints y ejemplos | Qué cuidar | Riesgo |
|---|---|---|---|---|
| **T1** | **Egresos** (gastos de caja chica) | `[K4]`, ejemplos 24 y 25 | Foto opcional: **menos de ~700 KB** (JPEG de 1280 px de lado mayor, calidad media; por encima el servidor responde 413). Necesita elegir y comprimir imágenes: **añade dependencias y permisos de Android, avísale a Lucho antes**. Tope de `session-info`. Exige caja abierta. **Sin idempotencia.** Los egresos pendientes también restan en el arqueo. | Medio |
| **T2** | **Recibir mercancía** | `[M1]`, ejemplo 26 | `cantidad` entera > 0. **Sin idempotencia:** repetirlo suma el stock dos veces; ante un tiempo de espera, comprueba el stock antes de decidir. Reutiliza `vista_de_escaneo.dart` y `catalogo_repository.buscarPorCodigoBarras`. | Medio |
| **T3** | **Alertas** (lista y resolver) | `[A1]` (`GET /api/alertas` y `/stats`) y `[A2]` | **No hay ejemplos reales** (su contenido no es repetible): crea los fixtures a mano **desde el contrato** y márcalos como tales en el archivo. Usa `alerts`, no `data`. No dependas de `datos_json`. Sin tiempo real: se actualiza con el mecanismo de `ui/refrescar.dart`. | Bajo |
| **T4** | **Ventas del turno** | `[V3]` (`GET /api/ventas?turno=actual`), ejemplo 23 | Una fila por producto vendido; paginación con `limit`, `offset` y `hasMore`. | Bajo |
| **T5** | Solicitar un producto al Administrador y notificaciones | `[O1]`, `[O2]` | Opcional («si alcanza el tiempo»). Tampoco tienen ejemplos reales. | Bajo |
| **T6** | Tarjeta, transferencia y **fiado** | `[V1]`, `[V2]` | **Reservada a Lucho.** Toca el cobro y el dinero; no la tomes. | Alto |
| **T7** | Pruebas de celular de lo ya hecho y escáner en un segundo teléfono | `docs/pruebas_sesion.md`, `docs/pruebas_escaner.md` | No es código: anota resultados y modelo del celular. | — |

*La columna «responsable» no existe a propósito: quien la tiene es quien tenga el PR abierto. Si pasan tres días sin avance, avisa para liberar la tarea.*

**Ya está hecho, no lo rehagas:** sesión (login, 2FA, primer cambio de contraseña), apertura y cierre de caja con arqueo y desglose por método, catálogo y búsqueda, carrito, cobro en efectivo con idempotencia, escáner dentro de la venta con vinculación de códigos, y «actualizar» al volver a la app.

## 6. Comprobar que tus pruebas valen (mutaciones)
Un `flutter test` en verde no basta: hay que demostrar que las pruebas **fallan cuando el código está mal**.
1. Escribe `tool/mutaciones/<tu_tarea>.json` con una entrada por cada regla importante (ver `tool/mutaciones/ejemplo.json`). Cada una dice qué texto del código romper y por qué.
2. Con todo guardado y commiteado: `dart run tool/mutar.dart tool/mutaciones/<tu_tarea>.json`.
3. Cada línea del resumen debe decir **DETECTADA**. Si dice **SOBREVIVIÓ**, falta una prueba: escríbela y repite. **NO COMPILA** o **PATRÓN NO ENCONTRADO** significan que la mutación está mal escrita.
4. La herramienta restaura el código sola; si la cortas a la mitad, `git checkout -- <archivo>`.

## 7. Cómo subir tu trabajo (nunca a `main`)
```bash
git checkout main && git pull                         # parte siempre de main actualizado
git checkout -b feat/t1-egresos-<tus-iniciales>       # una rama por tarea
# ... trabaja; commits pequeños, en español: "feat(egresos): ..."
flutter analyze && flutter test                       # antes de cada push
git diff origin/main --stat                           # revisa qué vas a subir: sin secretos ni archivos de más
git push -u origin feat/t1-egresos-<tus-iniciales>    # SIEMPRE a tu rama
```
Luego abre (o actualiza) el **PR en borrador** hacia `main` y, cuando termine, márcalo «listo para revisar». **Lucho revisa y mezcla.**

**Nunca:** `git push origin main` · `git push --force` · mezclar tu propio PR · subir cambios de otra tarea en tu rama · reescribir commits que otros ya bajaron.

**Archivos que todos tocan (donde hay choques):** `lib/home_screen.dart`, `lib/main.dart`, `lib/carrito/ui/carrito_screen.dart`, `lib/caja/ui/tarjeta_de_caja.dart`, `lib/ui/refrescar.dart`, `docs/pruebas_sesion.md`. Reglas: tu función vive en **su propia carpeta** (`lib/egresos/`…); en los archivos compartidos toca **solo lo mínimo** (un botón, una línea) y **no los reformatees**. Si tu rama choca con `main`, actualízala con `git merge origin/main` y resuelve tú el choque.

## 8. Qué NO se toca sin hablar con Lucho
- **Contrato de la API.** Si la API no sirve para lo que necesitas, se avisa a Lucho: el cambio se acuerda primero en `docs/contrato_api_app_tendero.md` del backend y se cambian juntos código, prueba y documento. No se contornea desde la app.
- El cobro y el carrito (`venta/`, `carrito/`), el cierre de caja (`caja/cierre_providers.dart`), la sesión y el interceptor (`api/`, `auth/`): son dinero y datos.
- Dependencias nuevas (`pubspec.yaml`) y permisos de Android.
- Cualquier cosa que suba el repositorio con claves, firma de la app o direcciones de servidor.

## 9. Trampas conocidas (ahorran horas)
- **Ruta con tildes** en Windows: el analizador falla. Usa una ruta sin tildes ni espacios.
- **`dart format` solo en tus archivos.** Sobre todo `lib/` reformatea archivos ajenos y ensucia el diff.
- **Fin de línea (CRLF/LF):** git avisa «LF will be replaced by CRLF»; es normal, no lo «arregles».
- **Pruebas de pantallas:** `pumpAndSettle` no termina si hay una ruedita girando; un `await` directo sobre la red se cuelga (el reloj es simulado): lanza la petición y usa `pumpAndSettle`. `byTooltip` encuentra el *Tooltip*, no el botón: usa `widgetWithIcon`. En una pantalla alta, fija el tamaño con `tester.view.physicalSize`.
- **El servidor falso** (`test/support/fake_adapter.dart`) devuelve la última respuesta programada si ya gastó las demás; programa las respuestas **en el orden en que se pedirán**.
- **Riverpod no deja cambiar un provider mientras se construye el árbol** de widgets: si una pantalla pide datos al abrirse, usa `Future.microtask`.
- **La cámara solo se prueba en un celular real.** Lo que no puedas probar sin teléfono, dilo en el PR en vez de escribir «todo bien».

## 10. Si usas un asistente de IA
Dale `AGENTS.md` y `.agents/rules/`. Las reglas de arriba valen igual para él: **contrato antes que código, mutaciones, no afirmar lo que no se ejecutó, nunca a `main`.** Revisa su diff como revisarías el de una persona.

## 11. Lista antes de abrir el PR
- [ ] Mi rama sale de `main` y tiene **una sola tarea**.
- [ ] Hay fixtures **reales** copiados del backend (o, si no existen, creados desde el contrato y marcados).
- [ ] `flutter analyze` sin avisos y `flutter test` en verde (escribe cuántas pruebas hay).
- [ ] Corrí las mutaciones y todas están **DETECTADAS**.
- [ ] Agregué mi lista de pruebas de celular a `docs/pruebas_sesion.md` y dije qué **no pude** probar.
- [ ] `git diff origin/main` sin secretos, sin archivos generados ni de depuración, y `dart format` solo sobre lo mío.
- [ ] No toqué el contrato ni lo de la sección 8 sin avisar.
