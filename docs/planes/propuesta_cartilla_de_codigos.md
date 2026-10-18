# Propuesta: Cartilla de códigos de barras (imprimir los códigos de los productos desde la app)

**Estado (17-oct-2026):** **sin empezar.** Es una propuesta para aprobar. Las decisiones D1 a D3 ya las tomó Lucho; D4 a D8 siguen **pendientes** (sección 4). Ninguna fase que dependa de una decisión pendiente puede arrancar.
**Fecha:** 2026-10-17
**Rama:** aún no existe (se crea al empezar la F1: `feat/cartilla-de-codigos`).
**Origen:** Lucho (17-oct): en las tiendas que venden productos sin empaque, los productos no traen código de barras. Quiere que la app pueda **imprimir** un código para cada producto y, si un producto no tiene ninguno, **generarlo**. Sus respuestas: la impresora de pruebas **se comprará después**; el formato es una **cartilla de códigos** (una hoja, no una etiqueta por unidad); la pueden imprimir **el Tendero y el Administrador**, sin restricción.
**Número del plan:** provisional. El plan definitivo se numera en `docs/planes/` del repositorio del backend (`LuchoSecDev/StockPilot`), que es donde vive el seguimiento. Este archivo está en el repositorio de la app para que lo lean las dos sesiones sin escribir en el repositorio ajeno.
**Relacionado con:**
- Contrato `[C2]` y `[C3]` (`docs/contrato_api_app_tendero.md` del backend).
- `docs/guia_del_equipo.md` (tablero T1 a T7; este plan **no** toca ninguna de esas tareas).
- `docs/planes/propuesta_imagenes_almacenamiento_de_objetos.md` (opcional, F4: poner la miniatura del producto en la cartilla).

**Marcas de evidencia:** **[V]** = lo leí en el código o en el contrato; **[I]** = inferido, con su base; **[?]** = supuesto que se comprueba antes de implementar.

---

## 1. Qué cubre y qué no
- **Sí:** una pantalla de la app que arma una hoja PDF con el nombre y el código de barras de los productos elegidos y la manda a imprimir con el diálogo de impresión de Android (o la comparte como PDF); y, para los productos sin ningún código, generar uno y guardarlo con `[C3]`.
- **No:** impresión directa a impresoras Bluetooth térmicas (F3, sin fecha: depende del modelo que se compre); precio en la etiqueta; productos por peso con el peso o el precio dentro del código (depende de una balanza); cambios en el servidor o en el contrato.

## 2. Hallazgos (lo que hace el sistema hoy)
1. **El escáner de la app ya lee EAN-13, EAN-8, UPC-A, Code 128 y QR.** `app_tendero/lib/vista_de_escaneo.dart:14-19` **[V]**.
2. **`[C2]` busca por `codigo_barras` y también por `codigo` (el SKU).** Un producto sin código comercial puede llevar una etiqueta propia con su `codigo` en Code 128 o QR y el escáner lo encuentra igual. Contrato `[C2]` del backend **[V]**; la prueba de celular de esa etiqueta ya existe en `docs/pruebas_sesion.md`, sección del escáner, punto 6 **[V]**.
3. **`[C3]` `PUT /api/productos/:id/link-barcode`** lo puede usar el Tendero. Responde 409 `BARCODE_DUPLICADO` si otro producto de la tienda ya tiene ese valor **o ese SKU**; el mismo producto puede repetir su propio código (200); la comprobación es atómica por tienda; el código tiene como máximo 50 caracteres. Contrato `[C3]` **[V]**; backend `productController.js:385-412` y `models/Product.js:159` (bloqueo `pg_advisory_xact_lock` por tienda) **[V]**.
4. **La app ya tiene el método para vincular:** `CatalogoRepository.vincularCodigoBarras(int productoId, String codigoBarras)` en `app_tendero/lib/catalogo/catalogo_repository.dart:58` **[V]**; y los ejemplos reales `14_C3_vincular_codigo_de_barras.json` y `15_C3_codigo_ya_vinculado_409.json` ya están en `app_tendero/test/fixtures/api/` **[V]**.
5. **En la app, `Producto.codigo` es un texto que puede venir vacío** (`app_tendero/lib/catalogo/producto.dart:21`, y `desdeJson` lo rellena con `''`), y `codigoBarras` es `null` cuando falta o viene vacío (`producto.dart:24` y `:52`) **[V]**. En la base, `Productos.codigo` es `VARCHAR(100)` **anulable** (`database/init_pg.sql:101`) **[V]**. **No sé cuántos productos reales tienen los dos vacíos [?]** (ver F0).
6. **La app no tiene dependencias de PDF ni de impresión.** `app_tendero/pubspec.yaml` (dependencias: dio, dio_cookie_manager, cookie_jar, path_provider, flutter_riverpod, mobile_scanner, shared_preferences, package_info_plus, url_launcher) **[V]**.
7. **La web no genera etiquetas ni códigos.** Solo escanea (`frontend/src/components/CameraScannerModal.jsx`). **[I]** (búsqueda en `frontend/src`, `controllers`, `services` y `routes`; no exhaustiva). El backend sí trae `qrcode` y `pdfkit` (`package.json:54,58`) **[V]**, sin uso para etiquetas.
8. **Un hallazgo que justifica validar el dígito verificador:** el código `7709990000012` del producto «Café» en `test/catalogo/ui/buscar_producto_pantalla_test.dart` no tiene un dígito verificador EAN-13 válido (calculado a mano daría `…6`; la prueba de F1 lo comprueba **[?]**), mientras `7701234000011` sí es válido (dígito `1`, calculado a mano). Un código «EAN» mal escrito en la tienda no debe imprimirse como EAN-13.

## 3. Marco de decisión: por qué la F1 no escribe nada en el servidor
El SKU ya funciona como código escaneable (hallazgo 2). Imprimirlo no cambia datos, no cambia el contrato y no puede crear duplicados. Por eso la F1 solo imprime lo que ya existe. **Generar** códigos nuevos (F2) sí escribe en el servidor y solo hace falta para los productos que no tienen ni SKU ni código de barras.

## 4. Decisiones

| # | Decisión | Opciones y trade-offs | Recomendación | Quién decide | Estado |
|---|---|---|---|---|---|
| D1 | Formato | Cartilla (una hoja con todos) · etiqueta por unidad | Cartilla: en productos sin empaque (granel) una etiqueta por unidad rara vez tiene dónde pegarse | Lucho | **Decidida (17-oct): cartilla** |
| D2 | Quién imprime | Tendero y Administrador · solo Administrador | Los dos; `[C3]` ya los permite a ambos | Lucho | **Decidida (17-oct): los dos** |
| D3 | Impresora | Comprar una térmica · usar la de oficina | Se compra una para pruebas; **la F1 y la F2 no dependen de ella** (PDF + diálogo de Android) | Lucho | **Decidida (17-oct): se comprará una de pruebas** |
| D4 | Qué código se dibuja por producto | (a) `codigo_barras` si existe y es válido, si no el `codigo` (SKU), si no uno generado · (b) siempre el SKU | (a). Un `codigo_barras` EAN-13 válido se dibuja como EAN-13; todo lo demás como Code 128 | Lucho | **Pendiente** |
| D5 | Formato del código generado (F2) | (a) `SP-` + `id_producto` con ceros a 6 dígitos (por ejemplo `SP-000123`) en Code 128 · (b) EAN-13 con prefijo 2 (rango GS1 de uso interno [I], conocimiento general, no está en el repositorio) y su dígito verificador · (c) aleatorio | (a): es único por construcción (nace del `id_producto`), dos celulares generan el mismo valor (el `200` repetido de `[C3]` lo hace inofensivo) y no choca con ningún código comercial. (b) solo si algún lector o caja exige 13 dígitos; hoy **no hay evidencia de eso [?]** | Lucho | **Pendiente** |
| D6 | Diseño de la hoja | A4 vertical, 3 columnas × 8 filas (24 códigos por hoja): nombre (máx. 2 líneas), texto del código y barras, **sin precio** · con precio | Sin precio: el código identifica el producto y el precio cambia; una hoja con precio queda vieja | Lucho | **Pendiente** |
| D7 | Dependencias nuevas | `pdf`, `printing` y `barcode` (pub.dev) | Aprobar las tres. Comprobar versión estable, mantenimiento y tamaño del APK (hoy ~66,8 MB, según `docs/distribucion_app_beta.md` del backend) antes de fijarlas **[?]** | Lucho (la guía, sección 8, reserva las dependencias nuevas) | **Pendiente** |
| D8 | Qué productos entran por defecto | Los activos **sin** `codigo_barras` (con opción «todos») · todos | Los activos sin `codigo_barras`; la cartilla existe para los productos que no traen código | Lucho | **Pendiente** |

## 5. Fases

### F0. Datos y verificación previa (sin código)
- **Objetivo:** saber cuántos productos reales tienen el SKU y el código de barras vacíos, para decidir si la F2 hace falta y en qué escala.
- **Fuera de alcance:** cualquier cambio.
- **Pasos:** pedir a la sesión web (o a Lucho) una consulta **de solo lectura** a la base: `SELECT COUNT(*) FILTER (WHERE COALESCE(TRIM(codigo),'')='' AND COALESCE(TRIM(codigo_barras),'')='') AS sin_ninguno, COUNT(*) FILTER (WHERE COALESCE(TRIM(codigo_barras),'')='') AS sin_barras, COUNT(*) AS total FROM Productos WHERE estado='Disponible';` por tienda y total. En producción no se escribe nada.
- **Riesgo:** ninguno (lectura). Ojo: no cargar `config/database` con `node -e` (migraría la base del `.env`); usar la herramienta de consulta que Lucho ya use.
- **Salida:** los tres números anotados en este plan. Si `sin_ninguno` es 0 en las tiendas reales, la F2 se **descarta** y queda solo la F1.

### F1. Cartilla con los códigos que ya existen (sin escribir en el servidor)
- **Objetivo:** desde el catálogo, elegir productos y obtener una hoja PDF imprimible (o compartible) con nombre y código de barras de cada uno.
- **Fuera de alcance:** generar códigos (F2), Bluetooth (F3), precio, imágenes, cambiar el contrato.
- **Requiere decididas:** D4, D6, D7, D8.
- **Archivos a crear** (carpeta propia, para no chocar con el equipo):
  - `app_tendero/lib/etiquetas/codigo_de_etiqueta.dart` — función pura `CodigoDeEtiqueta? codigoParaEtiqueta(Producto p)`: devuelve el tipo (`ean13` o `code128`), el valor y el texto que se imprime bajo las barras; `null` si el producto no tiene nada imprimible.
  - `app_tendero/lib/etiquetas/cartilla_pdf.dart` — arma el PDF (bytes) a partir de una lista de productos, 24 por hoja (según D6).
  - `app_tendero/lib/etiquetas/cartilla_providers.dart` — estado: productos elegidos y filtro. **Los widgets no llaman al servidor** (regla del repositorio).
  - `app_tendero/lib/etiquetas/ui/cartilla_screen.dart` — lista con casillas, filtro «sin código de barras» / «todos» y botones «Imprimir» y «Compartir PDF».
  - Pruebas espejo en `app_tendero/test/etiquetas/…` y `app_tendero/tool/mutaciones/cartilla.json`.
- **Archivos a modificar (lo mínimo):**
  - `app_tendero/pubspec.yaml` y `pubspec.lock` (+ `pdf`, `printing`, `barcode`).
  - `app_tendero/lib/catalogo/ui/buscar_producto_screen.dart`: **un** botón en la barra, solo cuando `alElegir == null` (consulta), que abre la cartilla.
  - `docs/pruebas_sesion.md`: lista de pruebas de celular de la cartilla (sección nueva).
- **No tocar:** `lib/venta/`, `lib/carrito/`, `lib/caja/`, `lib/api/`, `lib/auth/`, el contrato, `home_screen.dart`.
- **Pasos y comandos** (desde `app_tendero/`):
  1. `git switch main && git pull && git switch -c feat/cartilla-de-codigos`.
  2. `flutter pub add pdf printing barcode` y revisar que **solo** cambien `pubspec.yaml`/`pubspec.lock` (no commitear los archivos autogenerados de `linux/`, `macos/` y `windows/` que `pub get` regenera).
  3. Escribir **primero** las pruebas de `codigoParaEtiqueta` y verlas fallar; luego la función.
  4. El PDF y su prueba; después la pantalla y sus pruebas de widgets.
  5. `dart format` solo sobre los archivos propios; `flutter analyze`; `flutter test`.
  6. `dart run tool/mutaciones/…` con `tool/mutar.dart tool/mutaciones/cartilla.json`.
- **Riesgo:** bajo (no escribe en el servidor, no toca dinero ni sesión). **Detenerse y preguntar si:** `printing` exige un permiso de Android nuevo; el APK crece más de lo razonable (anotar el tamaño antes y después); hace falta tocar un archivo compartido más allá de una línea.
- **Verificación:**
  - *Pruebas de `codigoParaEtiqueta`:* EAN-13 válido (`7701234000011`) → `ean13`; EAN-13 con dígito verificador **incorrecto** (`7709990000012`) → `code128` con el mismo texto; `codigo_barras` nulo con SKU `ARR-001` → `code128 'ARR-001'`; ambos vacíos → `null`; SKU con tildes o caracteres fuera de ASCII → `null` (Code 128 no los codifica) con aviso en pantalla; texto de más de 30 caracteres → `null` con aviso (no cabe legible en la celda); espacios al principio y al final se recortan.
  - *Pruebas del PDF:* empieza con `%PDF`; 1 a 24 productos → 1 hoja, 25 → 2 hojas, 0 → no se arma; un nombre muy largo no rompe la celda (se corta en 2 líneas).
  - *Pruebas de la pantalla:* filtro por defecto (D8); elegir/quitar; «Imprimir» deshabilitado sin selección; lista vacía dice por qué; un producto sin nada imprimible aparece marcado y no se puede elegir.
  - *Mutaciones* (todas deben quedar DETECTADAS): comparar el dígito verificador con otro valor; dibujar siempre `code128`; dejar pasar `null` como imprimible; 24 → 25 por hoja; quitar el recorte de espacios.
  - *Recorrido manual en celular (se anota en `docs/pruebas_sesion.md`):* abrir la cartilla, elegir 5 productos, **imprimir en una impresora real** y también «Compartir PDF»; **escanear lo impreso con la propia app** («Escanear producto») a unos 20 cm con luz normal, con **dos celulares distintos**, y comprobar que cada código encuentra su producto; repetir con la hoja impresa «al 70 %» para conocer el tamaño mínimo legible; con un código Code 128 que no se lea, probar el mismo producto como QR (alternativa).
  - *Lo que NO cubre:* que el diálogo de impresión de cada marca de impresora respete el tamaño exacto (solo un celular real lo muestra).
- **Salida:** `flutter analyze` sin avisos; todas las pruebas en verde (decir cuántas); mutaciones todas DETECTADAS; los códigos impresos se escanean en dos celulares; la lista de pruebas de celular está en `docs/pruebas_sesion.md` y el PR dice qué **no** se pudo probar.

### F2. Generar y guardar el código de los productos que no tienen ninguno
- **Objetivo:** para los productos activos con `codigo` y `codigo_barras` vacíos, generar el código (D5) y guardarlo en el producto, para que entren en la cartilla.
- **Fuera de alcance:** cambiar `[C3]`; generar códigos para productos que ya tienen SKU o código de barras (esos se imprimen tal cual); EAN-13 (solo si D5 cambia a la opción b).
- **Requiere decididas:** D5 y el resultado de la F0. **No empezar si la F0 da `sin_ninguno = 0`.**
- **Archivos:** en `app_tendero/lib/etiquetas/`: `generar_codigos_models.dart` (resultado por producto: guardado, ya tenía, duplicado, falla), `generar_codigos_providers.dart` (un `Notifier` con el contador `_generacion` del proyecto) y la pantalla de confirmación; reutiliza `CatalogoRepository.vincularCodigoBarras` (hallazgo 4). Pruebas espejo.
- **Pasos:** (1) función pura `codigoGenerado(int idProducto)` → `SP-` + 6 dígitos; (2) el `Notifier` recorre los productos **uno por uno** (no en paralelo: así un fallo no deja medio lote desconocido) y por cada uno llama a `[C3]`; (3) un `409` se muestra con el nombre que trae el servidor y no se reintenta; un fallo de red se puede reintentar (`[C3]` es idempotente por naturaleza: repetir el mismo valor al mismo producto da 200); (4) al terminar, se vuelve a descargar el catálogo.
- **Riesgo:** **medio, escribe datos en el servidor** (un código guardado queda en el producto). **Detenerse y preguntar si** D5 es EAN-13 (cambia el formato y los fixtures), si el servidor responde algo que no está en el contrato, o si la F0 muestra miles de productos (haría falta pensar en lotes y en el tiempo de espera).
- **Verificación:** pruebas contra los fixtures reales `14_` (éxito) y `15_` (409); sin red; 404 (producto de otra tienda); doble toque; respuesta tardía de otra sesión; un lote con un 409 a la mitad (los demás siguen); mutación: generar sin ceros a la izquierda, no dejar de reintentar un 409, no refrescar el catálogo. Celular: generar el código de un producto de prueba y **comprobarlo en la web** (el producto muestra el código); generar de nuevo (dos veces) no cambia nada; escanear la etiqueta impresa.
- **Salida:** pruebas y mutaciones como en la F1; el producto de prueba muestra el código en la web y se encuentra al escanear.

### F3. Impresión directa a una impresora Bluetooth térmica — **no empezar**
Depende de que se compre la impresora (D3) y se conozca su protocolo (ESC/POS, TSPL o ZPL). Cuando se decida el modelo se escribe una actualización de este plan: paquete, permisos de Bluetooth de Android 12 o superior, formato de la etiqueta y pruebas con la impresora física.

### F4. Miniatura del producto en la cartilla — **opcional**
Solo cuando exista `imagen_url` en `[C1]` (F3 de `propuesta_imagenes_almacenamiento_de_objetos.md`). La cartilla pasaría a mostrar la miniatura junto al código; hay que descargar las miniaturas antes de armar el PDF.

## 6. Publicación y vuelta atrás
- **Solo app**; no hay migración, ni variable de entorno, ni cambio de contrato.
- **Vuelta atrás:** revertir el PR; no deja datos que limpiar. La F2 sí deja códigos guardados en productos; se pueden quitar a mano desde la web (editar el producto) y no rompen nada.
- **Publicación:** sigue `docs/distribucion_apk.md` (subir el número después del `+` de `version:`, compilar, firmar con la llave de Lucho, subir el APK y poner las variables de Render). **Congelamiento:** durante las 6 semanas del piloto solo se publican correcciones (`docs/planes/07_fase5_app_companera_flutter.md:87` del backend, y el plan 21). **La fecha de inicio del piloto no la sé [?]**: si cae antes de terminar la F1, esta función espera al final del piloto o se publica antes.

## 7. Filas para el seguimiento (IDs provisionales; la sesión web les pone el definitivo)

| ID provisional | Pendiente | Estado |
|---|---|---|
| CAR-01 | F0: contar productos sin SKU ni código de barras (solo lectura) | No empezado |
| CAR-02 | Decisiones D4 a D8 | Pendiente de Lucho |
| CAR-03 | F1: cartilla con los códigos existentes (PDF + diálogo de impresión) | No empezado |
| CAR-04 | F2: generar y guardar códigos con `[C3]` (condicionada a CAR-01) | No empezado |
| CAR-05 | F3: impresora Bluetooth térmica (condicionada a comprar la impresora) | Bloqueado |
| CAR-06 | F4: miniatura en la cartilla (condicionada al plan de imágenes) | No empezado |

## 8. Entrega al ejecutor (lo que debe leer quien implemente)
- **Fase a hacer ahora:** F1, **solo cuando Lucho responda D4, D6, D7 y D8** (si la respuesta es «lo que recomiendas», se usa la columna «Recomendación»). La F0 se puede pedir ya.
- **Rama:** `feat/cartilla-de-codigos`, desde `main`. **Nunca subir a `main`; PR en borrador; mezcla solo Lucho.**
- **Primer comando:** `cd app_tendero && git switch main && git pull && git switch -c feat/cartilla-de-codigos`.
- **Debe pasar antes del PR:** `flutter analyze` sin avisos; `flutter test` en verde; las mutaciones de `tool/mutaciones/cartilla.json` todas DETECTADAS; la lista de pruebas de celular agregada a `docs/pruebas_sesion.md`.
- **Detenerse y preguntar si:** hace falta un permiso de Android nuevo o cambiar `AndroidManifest.xml`; hay que tocar `venta/`, `carrito/`, `caja/`, `api/`, `auth/` o el contrato; el diálogo de impresión no respeta el tamaño de la hoja; el APK crece de forma notable; la F0 muestra una cantidad de productos que cambia el diseño de la F2.
- **Reglas del repositorio que aplican:** `AGENTS.md` y `docs/guia_del_equipo.md` (el dinero no interviene aquí, pero sí: no inventar la forma de una respuesta, copiar los ejemplos reales, mutaciones, no afirmar lo que no se ejecutó, dato de la impresora real solo lo prueba una persona).
