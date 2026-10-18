# Propuesta: Imágenes en almacenamiento de objetos (fotos de productos, de perfil y comprobantes de egresos)

**Estado (17-oct-2026):** **sin empezar.** Es una propuesta para aprobar. D1 y D2 ya las decidió Lucho; D3 a D12 siguen **pendientes** (sección 4). Ninguna fase que dependa de una decisión pendiente puede arrancar.
**Fecha:** 2026-10-17
**Ramas:** aún no existen. Backend y web: `feat/almacenamiento-imagenes` (sesión web). App: `feat/imagenes-en-la-app` (F3).
**Origen:** Lucho (17-oct). Quiere que cada producto del catálogo tenga imagen **sin sobrecargar la base de datos**: guardarla en un almacenamiento de objetos en la nube, comprimirla y redimensionarla antes de subirla y tener caché local en la app. Después pidió **aplicar lo mismo a las fotos de egresos y de perfil**, que hoy se guardan en la base.
**Número del plan:** provisional. El definitivo se asigna en `docs/planes/` del repositorio del backend (`LuchoSecDev/StockPilot`), donde vive el seguimiento. Este archivo está en el repositorio de la app para que lo lean las dos sesiones sin escribir en el repositorio ajeno.
**Quién ejecuta qué:** backend y web (F0 a F2, F4, F5): la sesión web. App (F3, F6): la sesión de la app o el equipo. Lucho decide y mezcla.
**Relacionado con:**
- Plan 24 (P24-07, idempotencia de `[K4]`) y contrato `[K4]`, `[C1]`, `[C2]` (`docs/contrato_api_app_tendero.md` del backend).
- Plan 27 (StockPilot 2.0 en microservicios): **no menciona imágenes ni almacenamiento** (búsqueda de «imagen», «almacenamiento», «R2», «archivos» en `docs/planes/27_…md`, sin resultados útiles). El módulo de almacenamiento se escribe detrás de una interfaz para poder extraerlo a un servicio después.
- `docs/distribucion_app_beta.md` (R2 ya se usa para el APK).
- `docs/guia_del_equipo.md` de la app, tarea **T1** (egresos con foto).
- `docs/planes/propuesta_cartilla_de_codigos.md` (F4 de ese plan usa las miniaturas).

**Marcas de evidencia:** **[V]** = lo leí en el código o en el contrato; **[I]** = inferido, con su base; **[?]** = supuesto que se comprueba antes de implementar.

---

## 1. Qué cubre y qué no
- **Sí:** guardar las imágenes de productos, las fotos de perfil y los comprobantes de egresos en Cloudflare R2; guardar en la base solo una referencia (clave); comprimir y validar; servir las imágenes a la web y a la app; caché en la app; migrar las fotos que hoy están en base64; coordinar con la tarea T1 de la app.
- **No:** subir fotos desde el celular (F6, opcional y posterior); galería de varias imágenes por producto (una por producto); reconocimiento de imágenes; mover otros archivos (reportes, PDFs).

## 2. Hallazgos (lo que hace el sistema hoy)
1. **Las fotos ya están en la base como texto base64.**
   - Perfil: `Usuarios.foto_url TEXT` (`database/init_pg.sql:55`). La web la escribe leyendo el archivo con `FileReader.readAsDataURL` y la manda en `PUT /api/perfil` (`frontend/src/pages/ProfilePage.jsx:146-157`); el servidor la guarda sin transformarla (`controllers/authController.js:294-296`, `models/User.js:104-113`). **[V]**
   - Egresos: `EgresosCaja.foto_soporte TEXT -- base64 de la imagen (max ~2MB)` (`init_pg.sql:167`). Se valida en `controllers/cashRegisterController.js:178-190` y se inserta en `models/CashRegister.js:221-225`. La web la lee con `FileReader` (`frontend/src/components/ExpenseModal.jsx:48-52` y `:87`). **[V]**
2. **Los listados de egresos devuelven el base64 completo de cada fila.** `COLUMNAS_EGRESO` incluye `e.foto_soporte` (`models/CashRegister.js:7`) y se usa en las consultas de `:240` y `:251`; la web lo muestra con `setPreviewImage(e.foto_soporte)` (`frontend/src/components/puntoventa/HistorialEgresosTab.jsx:175-176`). **[V]** Cuánto pesa una respuesta real: **[I]** hasta ~1 MB por egreso con foto.
3. **El tope práctico de la foto de egreso es ~700 KB.** Express rechaza cuerpos JSON de más de 1 MB (`app.js:132`); el contrato `[K4]` lo documenta (413). **[V]**
4. **La validación de la foto solo mira el prefijo del texto** (`data:image/jpeg;base64,` o `…png…`, `cashRegisterController.js:181`); no comprueba los bytes reales ni limita las dimensiones. Un archivo que no es una imagen, o una imagen enorme en pocos bytes, pasaría. **[V]**
5. **Los productos no tienen columna de imagen** (`Productos`, `init_pg.sql:99` en adelante). **[V]**
6. **Una columna nueva en `Productos` se expondría sola a los clientes:** `GET /api/productos` hace `SELECT *` y le suma campos calculados con `{ ...p, … }` (`controllers/productController.js:125-153`, `models/Product.js:140` y `:191`). Hay que mapearla a propósito (clave → URL) y no dejar salir la clave cruda. **[V]** (la parte de `getProducts` posterior a la línea 153, donde se quita lo que el Tendero no debe ver, **no la leí [?]**: revisarla al implementar).
7. **Quién puede editar productos:** crear y editar es solo Administrador (`routes/productRoutes.js:69-70`); vincular código de barras lo puede el Tendero (`:67`). **[V]** Ya hay `multer` en memoria con tope de 5 MB (`productRoutes.js:9-12`), usado en la carga masiva. **[V]**
8. **CSP:** `imgSrc: ["'self'", "data:", "blob:"]` (`app.js:96`; el bloque empieza en `:88`). Una imagen de otro dominio la bloquearía; el commit `f1b0d86` dice que la CSP estricta está «en modo informar» (mensaje del commit, **[V]**; no comprobé su estado hoy [?]). Hay que añadir los dos hosts de R2 antes de pasarla a modo obligatorio.
9. **No hay SDK de almacenamiento ni librería de imágenes** en `package.json`: solo `multer`, `pdfkit` y `qrcode` (líneas 49, 54, 58). **[V]**
10. **R2 ya se usa para el APK,** con una dirección de desarrollo (`…r2.dev`); la guía de distribución dice que esa dirección es de desarrollo y que para algo más amplio se use un dominio propio. `docs/distribucion_app_beta.md`, «Lo aprendido». **[V]**
11. **El servidor es Render** y se mantiene despierto con un monitor (commit `cda79f0`, `GET /healthz`) **[V]**; en ese plan **no hay disco persistente [I]** (por eso el almacenamiento de objetos es lo correcto). **La base es Neon** (`config/database.js:8` detecta `neon.tech`) **[V]**; **su plan y su límite de almacenamiento no los sé [?]**: de eso depende la urgencia de la migración.
12. **En la app:** `Producto` no tiene campo de imagen (`app_tendero/lib/catalogo/producto.dart:5-47`); la lista de productos es un `ListTile` (`lib/catalogo/ui/buscar_producto_screen.dart:176`); la ficha es `lib/catalogo/ui/ficha_de_producto.dart`; no hay dependencias de imágenes ni de caché (`pubspec.yaml`). **[V]**
13. **La tarea T1 de la app (egresos) ya contempla la foto en base64 dentro de `[K4]`**, «menos de ~700 KB» (`docs/guia_del_equipo.md`, fila T1). El equipo la implementará pronto: si el contrato cambia después, rehacen trabajo. **[V]**
14. **La foto de perfil viaja con el usuario:** `models/User.js:63` incluye `foto_url` en la consulta del usuario; **en qué respuestas viaja (inicio de sesión, `session-info`) no lo comprobé [?]**. Si viaja en cada una, cada petición carga el base64 completo.
15. **Reglas del proyecto que aplican:** las migraciones son aditivas, idempotentes y consultan el catálogo antes de cada `ALTER` para no bloquear en cada arranque (`config/migraciones/idempotencia.js`; se registra en `config/database.js:6` y `:392`) **[V]**; la skill `safe-migrations`; pruebas de integración contra `stockpilot_test` y **la suite completa la corre Lucho** en los hitos; política de mutaciones en el `CLAUDE.md` del backend. **[V]**

## 3. Diseño propuesto
- **Dos buckets:** uno **público** (imágenes de productos, que no son datos sensibles) y uno **privado** (fotos de perfil y comprobantes de egresos: pueden mostrar nombres, documentos, cuentas). El privado se sirve con **URLs firmadas de corta vida** (5 a 15 minutos) que genera el API tras comprobar sesión y tienda.
- **Claves de objeto** (el nombre lleva la huella SHA-256 del contenido, abreviada: la imagen es **inmutable**; si cambia, cambia la dirección):
  - público: `p/{id_tienda}/{id_producto}/{huella}.webp` y `…/{huella}_t.webp` (miniatura);
  - privado: `soportes/{id_tienda}/{id_egreso}/{huella}.jpg`, `perfiles/{id_usuario}/{huella}.webp`, y `tmp/{id_tienda}/{huella}` para subidas aún no asociadas (regla de ciclo de vida: borrar a las 24 h).
- **En la base, solo la clave:** `Productos.imagen_key`, `EgresosCaja.foto_soporte_key`, `Usuarios.foto_perfil_key`, todas `TEXT NULL`. Las columnas base64 **no se tocan** hasta la F7.
- **Contrato (todo aditivo y compatible):**
  - `PUT /api/productos/:id/imagen` (multipart, campo `imagen`, Administrador) → `{ success, imagen_url, miniatura_url }`; `DELETE /api/productos/:id/imagen`.
  - `[C1]` y `[C2]` añaden `imagen_url` y `miniatura_url` (`null` si no hay).
  - `POST /api/uploads/soporte` (multipart) → `{ success, foto_key }`. `[K4]` acepta `foto_soporte_key` (debe existir y ser de la tienda) **además** del `foto_soporte` base64 actual. La huella de idempotencia usa la **clave**: los mismos bytes dan la misma clave, así que el problema «reenviar exactamente la misma foto» de T1 desaparece.
  - Las lecturas de egresos añaden `foto_soporte_url` (firmada); el `foto_soporte` base64 queda `null` cuando la fila esté migrada.
  - `PUT /api/perfil/foto` (multipart); `foto_url` sigue siendo el nombre del campo que lee la web, pero devuelve una URL firmada.
- **Módulo `services/almacenamiento/`** con una interfaz (`guardar`, `borrar`, `existe`, `urlFirmada`, `urlPublica`) y dos implementaciones: `r2` (SDK compatible con S3) y `memoria` (para las pruebas, **sin red**). Se configura por variables de entorno: `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET_PUBLICO`, `R2_BUCKET_PRIVADO`, `R2_PUBLIC_BASE_URL`. **Sin configurar, la función queda apagada** (los endpoints nuevos responden 501 «no configurado») y todo lo viejo sigue funcionando: el servidor **no se cae al arrancar**.
- **Validación en el servidor (lo que defiende de verdad; la compresión del cliente solo ahorra datos):** comprobar los **bytes** (JPEG `FFD8FF`, PNG `89504E47`, WebP `RIFF….WEBP`); rechazar SVG, GIF y cualquier otra cosa; límite de píxeles de entrada (contra «bombas de descompresión»); tope de tamaño del archivo; **re-codificar siempre** (elimina el EXIF, que puede traer la ubicación GPS); el tipo de contenido lo fija el servidor, nunca el cliente; cabecera `X-Content-Type-Options: nosniff`.
- **Caché:** en lo público, `Cache-Control: public, max-age=31536000, immutable` (la dirección cambia si la imagen cambia). En lo privado, `private`. En la app, `cached_network_image` con `cacheKey` = la **clave del objeto, no la URL** (la URL firmada cambia en cada consulta y la caché nunca acertaría) **[?]** (comprobar en la F3 que el paquete lo permite como se espera).
- **Aislamiento entre tiendas:** la clave lleva el `id_tienda`; cada endpoint comprueba que la fila es de la tienda de la sesión; pruebas con el patrón de `aislamiento_multitienda.test.js`.
- **Limpieza:** al reemplazar o quitar una imagen se borra la anterior (mejor esfuerzo, con registro de los fallos); al borrar un producto (`deleteProduct`) se borran sus claves; el reinicio de la tienda de demostración también.

## 4. Decisiones

| # | Decisión | Opciones y trade-offs | Recomendación | Quién decide | Estado |
|---|---|---|---|---|---|
| D1 | Dónde guardar las imágenes | Base de datos (como hoy) · almacenamiento de objetos | Almacenamiento de objetos (R2): la base de Neon es pequeña, Render no tiene disco persistente y R2 ya está en uso | Lucho | **Decidida (17-oct): R2** |
| D2 | Alcance | Solo productos · productos + perfil + egresos | Los tres, con el mismo módulo | Lucho | **Decidida (17-oct): los tres** |
| D3 | Acceso | (a) todo público · (b) público para productos y **privado con URL firmada** para perfil y comprobantes · (c) todo privado con el backend como intermediario | (b). Los comprobantes son datos financieros y personales; (c) es más seguro pero pasa todo por Render | Lucho | **Pendiente** |
| D4 | Cómo se sube | (a) multipart por el backend (`multer` + validación de bytes + re-codificación) · (b) URL prefirmada directa a R2 | (a): las imágenes ya llegan comprimidas (≤ ~400 KB) y se suben pocas veces; valida el contenido de verdad. (b) solo si el tráfico lo exige; con URL prefirmada es difícil imponer un tamaño máximo **[?]** | Lucho / sesión web | **Pendiente** |
| D5 | Librería de imágenes en el servidor | `sharp` (nativa, rápida) · `jimp` (JS puro, lenta) | `sharp`; comprobar que instala en Render con Node 24 **[?]** | Sesión web | **Pendiente** |
| D6 | Quién sube la foto del producto | Solo Administrador · también el Tendero | Solo Administrador al principio (editar un producto ya es de Administrador, `productRoutes.js:70`) | Lucho | **Pendiente** |
| D7 | Tamaños y formato | Miniatura 256 px y principal 800 px en WebP (calidad ~75); perfil 256 px; comprobante 1280 px en JPEG (calidad ~80, para que el texto se lea) | Esos | Lucho | **Pendiente** |
| D8 | Migrar lo ya guardado en base64 | (a) script único con simulacro y vuelta atrás · (b) convertir al leer · (c) dejarlo | (a), con punto de restauración de Neon antes | Lucho | **Pendiente** |
| D9 | Clientes que aún mandan base64 | (a) el servidor lo acepta, lo sube a R2 y guarda la clave (la base deja de crecer) · (b) rechazar | (a) durante la transición | Lucho | **Pendiente** |
| D10 | Cuenta de Cloudflare | Nombres de los buckets, token de R2 con permisos mínimos, dominio propio para el bucket público, y **límites y precios del plan gratuito de R2 [?]** | Dominio propio (la dirección `r2.dev` es solo de desarrollo, `docs/distribucion_app_beta.md`) | Lucho | **Pendiente** |
| D11 | Cuándo | Antes del piloto · después (durante las 6 semanas solo se publican correcciones: `docs/planes/07_…:87` del backend y plan 21). Es un cambio de esquema **y** de contrato | Antes del piloto si cabe; **la fecha del piloto no la sé [?]** | Lucho | **Pendiente** |
| D12 | T1 (egresos en la app) | (a) T1 **sin foto** primero y la foto en un PR posterior con el flujo nuevo (F6) · (b) T1 con la foto en base64 y migrarla luego | (a): evita código que se reemplaza y evita el problema de «los mismos bytes» en la idempotencia | Lucho | **Pendiente** |

## 5. Fases

### F0. Decisiones, cuenta de Cloudflare y prueba de humo (sin código del producto)
- **Objetivo:** responder D3 a D12 y comprobar que el almacenamiento funciona desde Render antes de escribir el módulo.
- **Pasos:** (1) Lucho responde la tabla (si dice «lo que recomiendas», vale la columna «Recomendación»). (2) Crear los dos buckets y un token de R2 con permisos de lectura y escritura **solo sobre esos buckets**; guardarlo en un gestor de contraseñas y **nunca** en un repositorio ni en un `.env` que se suba. (3) Regla de ciclo de vida para `tmp/` (borrar a las 24 h). (4) Un script de prueba **local, que no se sube**, que guarde, lea y borre un objeto de prueba; repetirlo desde Render con las variables de entorno y mirar el registro. (5) Confirmar el plan y el límite de Neon y los límites del plan de R2.
- **Riesgo:** configuración de producción y secretos. **Detenerse y preguntar si:** el token pide permisos de cuenta completa; `sharp` no instala en Render.
- **Salida:** D3 a D12 respondidas en este archivo; el script de humo funciona local y desde Render; las variables de entorno están en Render (apagadas hasta la F1).

### F1. Backend: módulo, migración, imagen de producto y URLs en `[C1]`/`[C2]`
- **Objetivo:** que un Administrador pueda subir y quitar la imagen de un producto por la API, y que `[C1]`/`[C2]` devuelvan sus URLs.
- **Fuera de alcance:** la web, la app, perfil y egresos.
- **Requiere decididas:** D3, D4, D5, D7, D10.
- **Archivos a crear:** `services/almacenamiento/{index,r2,memoria,validarImagen}.js`; `config/migraciones/imagenes.js` (`Productos.imagen_key`, aditiva y con la consulta previa al catálogo, como `idempotencia.js`); `tests/business_logic/` (validación de bytes, claves) y `tests/integration/producto_imagen.test.js`, `tests/integration/producto_imagen_aislamiento.test.js`.
- **Archivos a modificar:** `config/database.js` (registrar la migración junto a la línea `:392`), `routes/productRoutes.js` y `controllers/productController.js` (endpoints nuevos; **mapear** la clave a URL en `getProducts`, `getByBarcode` y `getProduct`, sin exponer `imagen_key`; borrar claves en `deleteProduct`), `database/init_pg.sql`, `.env.example`, `package.json` (`@aws-sdk/client-s3`, `@aws-sdk/s3-request-presigner`, `sharp`), `docs/contrato_api_app_tendero.md` (`[C1]`, `[C2]`, endpoint nuevo) y los ejemplos `docs/ejemplos_app_tendero/` (números libres al implementar).
- **No tocar:** ventas, caja, egresos, `docs/planes/reglas_proyecto.md`.
- **Pasos:** rama `feat/almacenamiento-imagenes` desde `main`; leer la skill `safe-migrations` y el contrato `[C1]`; **pruebas primero** y verlas fallar; el módulo con la implementación `memoria`; la migración; los endpoints; el contrato y los ejemplos. **La suite completa de integración la corre Lucho** (`npm run test:integration *> "$env:TEMP\integracion.log"`); mientras tanto no se editan archivos ni se lanza otra suite.
- **Riesgo:** **alto** (esquema, contrato público, configuración de producción, dependencias nuevas). **Detenerse y preguntar si:** la migración necesita algo más que columnas nulas; hay que cambiar un campo existente de `[C1]` (solo se pueden **añadir**); la CSP está en modo obligatorio y hay que tocarla (F2).
- **Verificación:**
  - *Pruebas de validación:* JPEG, PNG y WebP válidos pasan; un `.exe` o texto renombrado a `.jpg`, un SVG, un GIF, un archivo vacío, uno de más de 1 MB y una imagen con dimensiones absurdas se rechazan con 400/413; el EXIF **no** sobrevive (la imagen guardada no lo trae); el tipo de contenido guardado es el del servidor aunque el cliente mande otro.
  - *Pruebas de integración:* subir, reemplazar (la anterior se borra), quitar, repetir la misma imagen (misma clave); Tendero → 403; otra tienda → 404 y la imagen ajena no se toca; sin configurar → 501 y `[C1]` sigue funcionando; `[C1]` y `[C2]` traen `imagen_url`/`miniatura_url` y **no** traen `imagen_key`; borrar el producto borra sus objetos.
  - *Mutaciones* (todas DETECTADAS): quitar la comprobación de bytes; quitar la de tienda; no borrar la imagen anterior; exponer `imagen_key`; aceptar SVG.
  - *Recorrido manual:* subir una imagen con `curl` o la web de pruebas y abrir la dirección devuelta; comprobar que la raíz del bucket no lista archivos.
  - *Lo que no cubre:* el rendimiento con muchas imágenes y los costos reales de R2.
- **Salida:** pruebas unitarias y de integración puntuales en verde; Lucho corre la suite completa y pega el resumen; mutaciones DETECTADAS; contrato y ejemplos actualizados; funciona **apagada** (sin variables) y **encendida**.

### F2. Web: el Administrador sube y ve la imagen del producto
- **Objetivo:** subir, ver y quitar la imagen desde el formulario de producto, y verla en el catálogo.
- **Archivos:** el formulario de producto en `frontend/src/components/productos/` (**archivo exacto [?]**: se identifica al implementar) y la tabla/tarjeta del catálogo; `app.js` (**CSP**: añadir a `imgSrc` el host público y el host del endpoint S3 del bucket privado; hacerlo **antes** de pasar la CSP a modo obligatorio).
- **Fuera de alcance:** perfil y egresos.
- **Riesgo:** bajo-medio (se cuela una imagen de otro dominio: la CSP la bloquearía si no se actualiza). **Detenerse y preguntar si** la CSP ya está en modo obligatorio.
- **Verificación:** pruebas del frontend donde existan; recorrido en navegador: subir, ver, reemplazar, quitar; un archivo que no es imagen muestra un error claro; tamaño y miniatura correctos; sin errores de CSP en la consola.
- **Salida:** `npm run lint` y `npm run build` del frontend sin errores; recorrido manual hecho y anotado.

### F3. App: mostrar la imagen con caché
- **Objetivo:** la lista de productos muestra la miniatura y la ficha muestra la imagen principal, con caché en disco y un marcador mientras carga o si falla.
- **Requiere:** F1 desplegada (los campos nuevos de `[C1]`).
- **Archivos a crear/modificar** (carpeta del catálogo): `Producto` (+ `imagenUrl`, `miniaturaUrl`, ambos opcionales), `buscar_producto_screen.dart` (miniatura en el `ListTile`, `:176`), `ficha_de_producto.dart` (imagen principal), `pubspec.yaml` (+ `cached_network_image`; **dependencia nueva: aprobación de Lucho**, guía sección 8), el fixture de `[C1]` copiado del backend y pruebas espejo; `tool/mutaciones/imagenes.json`; `docs/pruebas_sesion.md`.
- **No tocar:** venta, carrito, caja, api, auth.
- **Pasos:** rama `feat/imagenes-en-la-app`; copiar el ejemplo real actualizado de `[C1]`; pruebas primero del modelo (campos ausentes, vacíos y de tipo raro → `null`, **sin romper la lista**); luego la UI.
- **Riesgo:** bajo. **Detenerse y preguntar si** el paquete pide un permiso de Android o cambia el tamaño del APK de forma notable.
- **Verificación:** pruebas de modelo; pruebas de widgets con una imagen que carga, una que falla (marcador) y un producto sin imagen (la lista se ve igual que hoy); mutaciones: ignorar `miniaturaUrl`, no manejar el error de carga, usar la imagen grande en la lista. **Celular:** con datos móviles, modo avión (la caché muestra lo ya visto), lista de 100 productos sin tirones, y que no se descargue la imagen principal en la lista.
- **Salida:** `flutter analyze` sin avisos, pruebas en verde, mutaciones DETECTADAS, lista de pruebas de celular en `docs/pruebas_sesion.md`.

### F4. Foto de perfil
- **Objetivo:** que la foto de perfil deje de guardarse en base64.
- **Requiere decididas:** D3, D8, D9.
- **Archivos:** migración (`Usuarios.foto_perfil_key`); `controllers/authController.js:294-296` y `models/User.js:63,104-113` (leer clave → URL firmada, nombre de campo `foto_url` sin cambiar para la web); `PUT /api/perfil/foto`; `frontend/src/pages/ProfilePage.jsx:146-157` y `:204-205`; **script `scripts/migrar_fotos_a_r2.js`** (sección F5, es el mismo para perfil y egresos).
- **Pasos clave:** si el servidor recibe base64 en `PUT /api/perfil` (cliente viejo), lo valida, lo sube a R2 y guarda la clave (D9). Comprobar **en qué respuestas viaja `foto_url` [?]** y quitarla de las que no la necesiten.
- **Riesgo:** **medio** (datos personales; migración de datos). **Detenerse y preguntar si** hay fotos de perfil que no se pueden decodificar (se dejan como están y se listan; **nunca** se borran).
- **Verificación:** pruebas de integración (subir, leer URL firmada, otra persona no accede a la foto ajena, cliente viejo con base64 sigue funcionando); mutaciones: devolver la URL sin firmar, aceptar base64 sin validar bytes; recorrido en la web.
- **Salida:** como F1; además el script en simulacro sobre una copia de la base lista las filas a migrar sin cambiar nada.

### F5. Comprobantes de egresos
- **Objetivo:** que los comprobantes dejen de guardarse en base64 y que los listados dejen de arrastrarlos.
- **Requiere decididas:** D3, D8, D9, D12.
- **Archivos:** migración (`EgresosCaja.foto_soporte_key`); `POST /api/uploads/soporte`; `controllers/cashRegisterController.js:149-208` (`[K4]` acepta `foto_soporte_key`; la huella `huellaDe` ya contempla `foto_soporte`, línea `:160`: **añadir la clave sin cambiar la huella de las peticiones antiguas [?]**, o dos pruebas de repetición lo delatarán); `models/CashRegister.js:7,221-225,240,251` (el listado deja de seleccionar el base64 y devuelve `foto_soporte_url`); `frontend/src/components/ExpenseModal.jsx:48-52,87` y `HistorialEgresosTab.jsx:175-176`; contrato `[K4]` y ejemplos nuevos.
- **Script de migración `scripts/migrar_fotos_a_r2.js`:** **simulacro por defecto** (`--aplicar` para escribir); idempotente (salta filas con clave); por filas, cada una en su transacción; valida bytes, re-codifica (D7), sube, guarda la clave, **no borra el base64**; registro sin datos personales; `--limite N` para probar con pocas filas. **Antes de aplicar: punto de restauración de Neon.** No se carga `config/database` con `node -e` (migra la base del `.env`).
- **Riesgo:** **alto** (cambia el contrato de `[K4]`, toca datos persistentes de egresos y la idempotencia). **No cambia** el arqueo: la prueba de cierre de caja debe seguir igual. **Detenerse y preguntar si:** la huella de idempotencia cambia para peticiones existentes; hay egresos cuyo base64 no se decodifica.
- **Verificación:** todas las pruebas de `egresos_idempotencia.test.js` siguen en verde; nuevas: egreso con `foto_soporte_key` válida, de otra tienda (404), inexistente (400), repetido con la misma clave (200 repetido), con otra foto (422); cliente viejo con base64 (se guarda en R2, la base no crece); lectura con URL firmada y sin base64; mutaciones: aceptar clave de otra tienda, no incluir la clave en la huella, seguir devolviendo el base64.
- **Salida:** como F1; Lucho corre la suite completa; el simulacro y luego `--limite 5 --aplicar` sobre la base de pruebas, y recién después el resto.
- **Aviso al equipo de la app:** actualizar `docs/guia_del_equipo.md` (T1) cuando el contrato nuevo esté en `main` del backend **y desplegado**.

### F6. App: subir fotos desde el celular — **opcional y posterior**
Depende de F1 y F5. Elegir imagen o foto (`image_picker`), comprimir y redimensionar en el celular (`flutter_image_compress`) antes de subir, y subir con los endpoints nuevos. Dependencias nuevas y posible permiso: aprobación de Lucho; se escribe una actualización de este plan con el detalle antes de empezar. Es la parte que cierra T1 con foto (D12 a).

### F7. Quitar las columnas base64 — **no antes de varias semanas**
Solo cuando todo esté migrado y verificado, con copia de seguridad y en un **despliegue aparte**, nunca el mismo que F4 o F5.

## 6. Publicación y vuelta atrás
- **Migraciones:** aditivas (columnas nulas); no hay nada que deshacer en la base. Las columnas base64 **siguen existiendo y siguen llenas** hasta la F7.
- **Orden:** (1) desplegar el backend con la función **apagada**; (2) cargar las variables de R2 en Render (cada cambio reinicia el servicio unos segundos) y comprobar el registro; (3) web; (4) app con `versionCode` mayor y la regla de publicación de `docs/distribucion_apk.md`.
- **Vuelta atrás:** quitar las variables de R2 apaga la función; lo viejo (base64) sigue sirviendo porque no se tocó. Los objetos ya subidos en R2 se pueden borrar por prefijo. Para el script de migración: la base conserva el base64 original.
- **Congelamiento:** ver D11. **Esta propuesta cambia esquema y contrato: no entra en las 6 semanas del piloto salvo que Lucho lo decida.**
- **Secretos:** las credenciales de R2 solo en Render y en el gestor de contraseñas de Lucho; **nunca** en el repositorio (público para la app).

## 7. Filas para el seguimiento (IDs provisionales; la sesión web les pone el definitivo)

| ID provisional | Pendiente | Estado |
|---|---|---|
| IMG-01 | F0: decisiones D3 a D12 y cuenta de Cloudflare (buckets, token, dominio, límites) | Pendiente de Lucho |
| IMG-02 | F1: módulo de almacenamiento, migración e imagen de producto en `[C1]`/`[C2]` | No empezado |
| IMG-03 | F2: web, subir y ver la imagen del producto (y CSP) | No empezado |
| IMG-04 | F3: app, mostrar imagen con caché | No empezado |
| IMG-05 | F4: foto de perfil en R2 (y primer uso del script de migración) | No empezado |
| IMG-06 | F5: comprobantes de egresos en R2 y cambio compatible de `[K4]` | No empezado |
| IMG-07 | F6: la app sube fotos desde el celular | Bloqueado (depende de IMG-02 e IMG-06) |
| IMG-08 | F7: quitar columnas base64 | Bloqueado (semanas después de IMG-05 e IMG-06) |
| IMG-09 | Actualizar la tarea T1 de la guía de la app cuando el contrato nuevo esté desplegado | Bloqueado (depende de IMG-06) |

## 8. Entrega al ejecutor (lo que debe leer quien implemente)
- **Fase a hacer ahora:** **F0** (decisiones y cuenta). **No empezar F1 hasta tener D3, D4, D5, D7, D10 y D11 respondidas.**
- **Ramas:** backend/web `feat/almacenamiento-imagenes`; app `feat/imagenes-en-la-app` (solo F3). **Nunca subir a `main` sin la aprobación de Lucho; en la app, PR en borrador y mezcla solo Lucho.**
- **Primer comando (F1, cuando toque):** en el backend, `git switch main && git pull && git switch -c feat/almacenamiento-imagenes`; leer antes `docs/contrato_api_app_tendero.md` (`[C1]`, `[C2]`, `[K4]`) y la skill `safe-migrations`.
- **Debe pasar antes de mezclar:** pruebas primero y vistas fallar; unitarias e integración puntuales en verde; **suite completa corrida por Lucho**; las mutaciones de cada fase DETECTADAS; contrato y ejemplos actualizados en el mismo cambio.
- **Detenerse y preguntar si:** hace falta cambiar o quitar un campo existente de un contrato (solo se añaden); la migración necesita algo más que columnas nulas; un token o credencial tendría que escribirse en un archivo del repositorio; `sharp` no instala en Render; la CSP ya es obligatoria y hay que tocarla; hay fotos que no se pueden decodificar durante la migración; el cambio de `[K4]` altera la huella de idempotencia de peticiones existentes.
- **Reglas que no cambian:** no cargar `config/database` con `node -e`; no lanzar otra prueba de integración mientras Lucho corre la suite; no editar `docs/planes/reglas_proyecto.md`; no afirmar lo que no se ejecutó; commits por hito y los planes y documentos se commitean y se suben como evidencia.
