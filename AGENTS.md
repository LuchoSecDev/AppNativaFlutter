# Instrucciones para asistentes de IA en este repositorio

App Flutter del Tendero de StockPilot (Android primero). La guía completa para personas está en
`docs/guia_del_equipo.md`: léela antes de tocar código. Aquí, lo esencial.

## Comandos (desde `app_tendero/`)
`flutter pub get` · `flutter analyze` · `flutter test` · `dart format <solo los archivos que tocaste>` ·
`dart run tool/mutar.dart tool/mutaciones/<tarea>.json` (comprueba que las pruebas detectan errores).
La ruta del proyecto no puede tener tildes ni espacios.

## Reglas que no se negocian
1. **Nunca subir a `main`.** Una rama por tarea (`feat/<tarea>-<iniciales>`), PR en borrador, y **solo Lucho mezcla**.
   Nunca `git push --force`. No commitees ni subas sin que la persona lo pida.
2. **Contrato antes que código.** El contrato de la API vive en el repositorio del backend
   (`docs/contrato_api_app_tendero.md` y `docs/ejemplos_app_tendero/`). Copia el ejemplo REAL a `test/fixtures/api/` y
   escribe la prueba contra ese archivo. **Nunca inventes la forma de una respuesta.** Si la API no alcanza, avisa a Lucho:
   no se contornea desde la app.
3. **El dinero va en centavos enteros**, nunca `double` (`ui/dinero.dart`).
4. **Ninguna escritura se reintenta a ciegas**, salvo las que llevan `Idempotency-Key`: la venta `[V2]`, el egreso `[K4]` y la
   entrada `[M1]` (desplegadas el 12-oct-2026; ver «Idempotencia» en `docs/guia_del_equipo.md`: una clave nueva por
   operación y la MISMA en sus reintentos). Para el cierre de caja y la apertura, que no la tienen, ante un tiempo de
   espera primero se consulta cómo quedó.
5. **Los widgets no llaman al servidor.** Cinco capas: modelos, repositorio, `Notifier` de Riverpod, pantalla, pruebas.
   Cada `Notifier` descarta respuestas de una sesión anterior (`_generacion`). Cópiate de `lib/caja/`.
6. **Rigor de las pruebas según el riesgo** (tabla en `docs/guia_del_equipo.md`, sección 6). Siempre: ejemplo real
   del servidor y `flutter test` en verde. **Alto** (dinero, idempotencia, sesión, permisos, contrato): además pruebas
   por capa y mutaciones de cada regla importante. **Medio** (modelos y reglas de presentación): pruebas de la función
   pura y de un flujo de pantalla, y mutaciones solo de las reglas centrales (unas 5). **Bajo** (avisos, textos,
   lectura que nunca bloquea): una prueba del flujo completo, sin mutaciones. En la duda, sube un nivel y dilo en el
   PR. Si corres mutaciones y ninguna falla, esa prueba no prueba nada.
7. **No afirmes lo que no ejecutaste.** La cámara y el celular real solo los prueba una persona: dilo explícitamente.
8. **Repositorio público:** ni contraseñas, ni claves (`*.jks`, `key.properties`), ni cookies, ni la dirección del
   servidor (va en `--dart-define=API_BASE_URL=...`). Revisa el diff antes de cualquier push.
9. **Alcance:** una tarea por rama; no copies y pegues pantallas (extrae lo común); no reformatees archivos ajenos; no
   modifiques una pantalla ya validada sin decirlo. Textos y comentarios en español.
10. **Dependencias, permisos de Android, contrato, cobro, carrito, cierre de caja, sesión:** hablar con Lucho antes.

## Antes de dar algo por terminado
Recorre el flujo como el usuario (¿se puede hacer desde cero?, ¿qué pasa si falla la red a mitad?), corre
`flutter analyze` y `flutter test`, corre las mutaciones que pide el nivel de riesgo (regla 6), y reporta qué cubren las
pruebas y qué no.
