# Plan T1: Registrar egresos (gastos de caja chica) en la app

**Estado (19-oct-2026):** **sin empezar.** Propuesta de fase para aprobar. Lucho tomó la tarea T1 (19-oct). Las decisiones D1 a D6 llevan su recomendación; ninguna fase arranca hasta que Lucho las confirme.
**Fecha:** 2026-10-19
**Rama:** aún no existe (`feat/t1-egresos-ld`). Reclamar la tarea: PR en borrador `[T1] Egresos — Lucho` (la guía, sección 5). Nota: `gh` perdió la sesión el 19-oct (HTTP 401); hay que volver a iniciarla para abrir el PR desde la terminal.
**Origen:** Lucho (19-oct). El plan 07, sección 6.2, del backend: «Sin el registro de egresos, cada gasto de caja chica aparece como faltante en el cierre». La app ya cierra caja con arqueo; sin T1 ese arqueo da diferencias falsas.
**Relacionado con:** contrato `[K4]` y ejemplos 24, 25, 32 y 33 (repositorio del backend, `docs/`); `docs/guia_del_equipo.md` (T1, y las reglas de reintentos); `docs/planes/propuesta_imagenes_almacenamiento_de_objetos.md` (la foto queda **fuera**, mejora futura).

**Marcas de evidencia:** **[V]** = lo leí en el código o en el contrato; **[I]** = inferido; **[?]** = se comprueba antes de implementar.

---

## 1. Qué cubre y qué no
- **Sí:** un formulario para registrar un gasto (monto, categoría, motivo) con caja abierta; reintento seguro con `Idempotency-Key`; comprobante; vibración y aviso al confirmar o rechazar; validaciones de ayuda en la app.
- **No:** la foto del comprobante (D1); ver la lista de egresos (el contrato no tiene una consulta para el Tendero **[?]**, se confirma en la F1); aprobar o rechazar egresos (es del Administrador, responde 403); cambiar el contrato.

## 2. Hallazgos
1. **`[K4]` `POST /api/caja/egreso`**, con CSRF. Cuerpo `{ monto, motivo, categoria?, foto_soporte? }`. 200 `{ success, message, id_egreso }` (queda «Registrado», pendiente de aprobación). Errores 400 con solo `error`: sin caja abierta, monto ≤ 0, motivo de menos de 5 caracteres, monto sobre el tope (el igual al tope es válido). **[V]** contrato `[K4]`.
2. **Idempotencia desplegada:** `Idempotency-Key` (UUID v4, 8 a 100 caracteres) **nueva por egreso y la misma en sus reintentos**; repetición → 200 con `Idempotent-Replayed: true`; misma clave con otra carga → 422 `IDEMPOTENCY_KEY_REUSED`; un fallo (400…) no consume la clave. **[V]** (confirmado desplegado por Lucho el 12-oct).
3. **Ejemplos reales que existen en el backend y todavía no están en `test/fixtures/api/` de la app:** `24_K4_egreso_ok` (con clave), `25_K4_egreso_sobre_el_tope_400` (**sin** clave y sin `categoria`), `32_K4_reintento_misma_clave_200` (cabecera `Idempotent-Replayed`), `33_K4_misma_clave_otra_carga_422`. **[V]**. **No hay ejemplo real** del 400 «No hay ninguna caja abierta», del 400 de monto y del 400 de motivo corto: sus cuerpos salen del contrato y se marcan como tales **[V]**.
4. **El servidor no valida la categoría contra una lista** (no hay enum; la columna es `VARCHAR(50)`, un comentario del esquema nombra otros valores: `database/init_pg.sql:166`, **desactualizado [I]**). La web ofrece seis: `Proveedor menor`, `Insumos / Bolsas`, `Transporte`, `Limpieza`, `Servicios`, `Otro` (`frontend/src/components/ExpenseModal.jsx:23-30`), y arranca en `Proveedor menor` (`:10`). El contrato dice que por defecto es `Otro`. **[V]**
5. **El tope solo aplica al rol Tendero** (bloque `if (userRole === 'Tendero')` de `controllers/cashRegisterController.js`, tras la validación de la foto **[V]**) y sale de `limiteEgresoTendero` de `[S4]`: en la app es un texto (`'150000.00'`, `lib/auth/auth_models.dart:53` y `:66`) **[V]**.
6. **El arqueo ya cuenta los egresos** no rechazados, también los pendientes de aprobación (`lib/caja/caja_models.dart:147-148`) **[V]**, así que tras registrar uno el cierre de caja lo resta.
7. **Patrón a reutilizar para el reintento seguro:** `generarUuidV4` (`lib/venta/clave_de_venta.dart`), el almacén de la venta pendiente con interfaz y versión local (`lib/venta/almacen_venta.dart:9` y `:19`), y el `CobroNotifier` (clave guardada antes de enviar, «sin confirmar», descartar respuestas de otra sesión con `_generacion`) **[V]**. Piezas de pantalla y de aviso ya hechas: `BotonPrincipal`, `CuadroDeMensaje`, `mostrarAviso`, `vibrar`.
8. **Dónde poner el botón:** `lib/caja/ui/tarjeta_de_caja.dart` (archivo compartido; ya tiene «Abrir caja» en `:71-77` y «Cerrar caja» en `:116-123`) **[V]**. Para saber si hay caja abierta: `puedeVenderProvider` (`lib/caja/caja_providers.dart:75`) **[V]**.
9. **El dinero:** la app guarda centavos enteros; el `monto` del contrato va en **pesos** (número). Se envían pesos enteros, como el efectivo de la venta (`efectivo_recibido`). Si el servidor admite decimales en `monto` **no está claro [?]**: no se prueba, no se ofrecen.

## 3. Decisiones

| # | Decisión | Opciones y trade-offs | Recomendación | Quién decide | Estado |
|---|---|---|---|---|---|
| D1 | Foto del comprobante | Sin foto ahora (el contrato la marca opcional) · con foto (compresión, selector de imagen, dependencias y permisos) | **Sin foto.** La foto exige dependencias y permisos de Android, y las imágenes quedaron como mejora futura | Lucho | **Propuesta; se da por aceptada al tomar T1 (19-oct), confirmar** |
| D2 | Categorías | Las seis de la web (obligatorio elegir una, sin preseleccionar) · lista corta · texto libre | Las seis de la web: evita datos sueltos y coincide con lo que verá el Administrador. Elegir una obligatoriamente (la web arranca en «Proveedor menor»; aquí no, para no registrar por inercia) | Lucho | **Pendiente** |
| D3 | Dónde está el botón | En la tarjeta de caja, junto a «Cerrar caja», solo con la caja abierta · en el inicio | La tarjeta de caja (un botón; archivo compartido) | Lucho | **Pendiente** |
| D4 | Qué se ve al terminar | Comprobante simple «Gasto registrado, pendiente de aprobación del Administrador» + vibración media · solo un aviso | Comprobante simple. Sin lista de egresos (no hay consulta para el Tendero **[?]**) | Lucho | **Pendiente** |
| D5 | El tope en la app | Avisar antes de enviar solo si el rol es Tendero (ayuda; decide el servidor) · no validar | Validar solo para el rol Tendero; el monto igual al tope es válido | Lucho | **Pendiente** |
| D6 | Sin red | El patrón de la venta (clave guardada, «sin confirmar», reintentar con la misma clave) · consultar antes de reintentar (como antes de la idempotencia) | El patrón de la venta: la idempotencia ya está desplegada | Lucho | **Pendiente** |

## 4. Diseño de archivos (cada uno con una sola responsabilidad; ninguno debe pasar de ~250 líneas)
- `app_tendero/lib/egresos/egreso_models.dart`: `CategoriaEgreso` (las seis), `EgresoPendiente` (clave + carga, con `aJson`/`desdeJson` que **descarta** lo dañado), `ResultadoEgreso` (sellada: registrado, repetido, rechazado, sinConfirmar).
- `.../egreso_repository.dart`: habla con `[K4]`; lo esperable se devuelve como valor y las fallas de red como «sin confirmar» (como `VentaRepository`).
- `.../almacen_egreso.dart`: interfaz y versión local con `shared_preferences` (copia del patrón de la venta; **la unificación de los dos almacenes queda para el refactor**).
- `.../egreso_providers.dart`: `EgresoNotifier` con `_generacion`, clave guardada antes de enviar, doble toque ignorado.
- `.../ui/registrar_egreso_screen.dart` (pantalla), `.../ui/formulario_de_egreso.dart` (campos y validaciones de ayuda), `.../ui/comprobante_de_egreso.dart`.
- **Se modifica solo:** `lib/caja/ui/tarjeta_de_caja.dart` (**un** botón) y `docs/pruebas_sesion.md`. **No se toca:** `venta/`, `carrito/`, `api/`, `auth/`, el contrato, `cierre_providers.dart`.

## 5. Fases

### F1. Contrato, modelos y repositorio
- **Objetivo:** hablar con `[K4]` con la forma real de las respuestas.
- **Pasos:** rama `feat/t1-egresos-ld` desde `main`; copiar los ejemplos 24, 25, 32 y 33 a `test/fixtures/api/` (y anotar en el README de los fixtures cuáles se copiaron); **pruebas primero**; `egreso_models.dart` y `egreso_repository.dart`.
- **Pruebas** (repositorio contra los fixtures): éxito (24); repetición con `Idempotent-Replayed` (32); otra carga con la misma clave (33, 422); sobre el tope (25); y, **de los cuerpos del contrato, marcados como tales:** sin caja abierta, monto ≤ 0, motivo corto; más: sin red, 500, 401, respuesta con forma rara (no se inventa un `id_egreso`); la petición lleva `Idempotency-Key`, el monto en **pesos enteros** y la categoría. En esta fase se confirma si hay consulta de egresos para el Tendero **[?]**.
- **Riesgo:** bajo. **Detenerse y preguntar si:** un ejemplo real no coincide con el contrato.
- **Salida:** `flutter analyze` sin avisos, pruebas en verde.

### F2. Estado
- **Objetivo:** registrar sin duplicar aunque falle la red o se cierre la app.
- **Pruebas** (como `cobro_notifier_test`): flujo feliz; cada rechazo; la **clave se guarda antes de enviar** y se borra tras 200 o rechazo; sin red → «sin confirmar» y reintentar usa la **misma clave y la misma carga**; app reiniciada con un pendiente; doble toque; respuesta tardía de otra sesión se descarta; tope solo para el rol Tendero y **el monto igual al tope pasa**; sin caja abierta no se envía.
- **Riesgo:** **medio** (dinero: el arqueo lo resta). **Detenerse y preguntar si** hace falta tocar `cierre_providers.dart` o cambiar el cálculo del arqueo.
- **Salida:** pruebas en verde.

### F3. Pantalla, botón y comprobante
- **Objetivo:** el Tendero registra un gasto desde la tarjeta de caja.
- **Pruebas de pantalla** (cliente HTTP real, servidor falso): botón visible solo con caja abierta; formulario (solo dígitos, máximo 9; motivo de menos de 5 caracteres bloquea; categoría obligatoria); confirmar → comprobante + vibración media una vez; un rechazo se muestra con el texto del servidor y vibra fuerte; sin red → «sin confirmar» con «Reintentar» (nunca «Confirmar» otra vez); salir y volver conserva lo escrito.
- **Mutaciones** (`tool/mutaciones/egresos.json`, todas DETECTADAS): `>` por `>=` en el tope; motivo mínimo 5 → 4; aceptar monto 0; clave nueva en cada reintento; no guardar el pendiente; no borrarlo tras el éxito; enviar centavos en vez de pesos; no enviar la categoría; no mandar `Idempotency-Key`.
- **Recorrido en celular** (a `docs/pruebas_sesion.md`): registrar un gasto y **verlo en la web** (estado «Registrado», monto, motivo, categoría); **cerrar la caja y comprobar que el arqueo lo resta**; sobre el tope; sin conexión justo al confirmar y reintentar (**un solo** egreso en la web); cerrar la app con un egreso sin confirmar; caja cerrada desde la web antes de confirmar; cambiar de cuenta. **Lo que no se puede probar sin celular:** vibración y teclado.
- **Salida:** `flutter analyze` sin avisos; pruebas en verde (decir cuántas); mutaciones DETECTADAS; lista de celular escrita; el PR dice qué **no** se probó.

## 6. Publicación y vuelta atrás
Solo app: sin migración ni cambio de contrato. Se publica con el APK (`docs/distribucion_apk.md`; durante las 6 semanas del piloto solo correcciones). Vuelta atrás: revertir el PR; un egreso ya registrado queda en la base y lo gestiona el Administrador en la web.

## 7. Entrega al ejecutor
- **Fase ahora:** F1, cuando Lucho confirme D1 a D6 (o «lo que recomiendas»).
- **Rama:** `feat/t1-egresos-ld`. **Nunca a `main`; PR en borrador; mezcla solo Lucho.**
- **Primer comando:** `cd app_tendero && git switch main && git pull && git switch -c feat/t1-egresos-ld`.
- **Debe pasar antes del PR:** `flutter analyze`; `flutter test`; mutaciones DETECTADAS; lista de celular.
- **Detenerse y preguntar si:** hay que tocar el cálculo del arqueo, `cierre_providers.dart`, `venta/`, el contrato o `pubspec.yaml`; un ejemplo real contradice el contrato; hace falta la foto.
- **Reglas del equipo (`AGENTS.md`):** el dinero en centavos enteros; ninguna escritura se reintenta a ciegas (aquí sí hay clave); los widgets no llaman al servidor; **ningún archivo grande ni con varias responsabilidades.**
