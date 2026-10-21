# Registro de hallazgos de la auditoría de bugs silenciosos (21-oct-2026)

**Alcance:** `app_tendero/lib/`. Se buscó con cinco criterios fijos: (1) excepciones tragadas, (2) `context`/`ref`/`setState` después de un `await`, (3) controladores sin liberar, (4) dinero con decimales y (5) datos que se descartan sin avisar.

**Regla de esta auditoría:** se arregló solo lo **pequeño**, con prueba primero y un commit `fix:` por cada uno. Lo que toca **dinero, sesión, contrato de la API, permisos o datos** NO se arregló: queda aquí con su evidencia y una recomendación, para que Lucho decida.

**Cómo se hizo (y qué tan firme es cada cosa):** un agente de solo lectura barrió `lib/` y entregó los hallazgos; yo **verifiqué leyendo el código** los marcados «verificado». Los demás son citas del agente que no he comprobado una por una. Nada de esto se ejecutó contra el servidor real: lo que depende de qué manda el backend está marcado.

---

## 1. Arreglado en esta rama

| ID | Qué pasaba | Arreglo | Prueba |
|---|---|---|---|
| 1.5 | `escaner_venta_screen.dart` (`_alConfirmar`) solo atrapaba `ErrorDeApi`. Con cualquier otra excepción (por ejemplo un producto con un campo de otro tipo, que lanza `TypeError` al leerlo) el escáner quedaba **pausado para siempre y sin decir nada**. *Verificado.* | Un `catch` final: avisa «No se pudo leer ese producto», sigue escaneando y reporta el error a Flutter (`FlutterError.reportError`) en vez de tragarlo. | `test/venta/ui/escaner_venta_error_inesperado_test.dart` (2 pruebas, vistas fallar antes). Mutaciones AU01 a AU03. |

---

## 2. NO arreglado: toca dinero, sesión, contrato, permisos o datos

Ordenados por riesgo. «Prob.» es la probabilidad de que ocurra si el servidor cumple el contrato.

### Alta
**5.1 `userId` / `tiendaId` caen a 0 si faltan** — `auth/auth_models.dart:63-64` (*verificado*): `userId: (json['userId'] as num?)?.toInt() ?? 0`, igual `tiendaId`.
- Efecto: las claves del carrito, de la venta pendiente y del gasto pendiente serían `carrito_v1_0_0`, `venta_pendiente_v1_0_0`… compartidas entre cuentas. El aislamiento por persona y tienda dejaría de funcionar y los notifiers no lo notan, porque comprueban `userId != null` y el modelo ya puso 0.
- Prob.: baja (el contrato manda ambos). Toca: sesión, dinero.
- Recomendación: que `InfoSesion.desdeJson` devuelva `null` (o lance `ErrorDeApi(respuestaInesperada)`) si falta alguno, igual que ya hace `ArqueoCaja.desdeJson`. Requiere pruebas con el fixture real `05_S4_session_info`.

### Media
**1.2 Un pendiente que no se puede leer se trata como «no hay pendiente»** — `venta/venta_providers.dart:147-151` y `egresos/egreso_notifier.dart:65-69` (*verificado el primero*): `try { pendiente = await _almacen.leer(clave); } on Object { pendiente = null; }`, sin comentario. Más `almacen_venta.dart` / `almacen_egreso.dart`: un JSON dañado devuelve `null`.
- Efecto: si la lectura falla, la fase queda `libre` y el Tendero puede cobrar o registrar de nuevo algo que quizá el servidor **ya registró** (duplicado). No hay aviso ni contador.
- Prob.: baja; impacto alto. Toca: dinero.
- Recomendación: ante un pendiente ilegible, mostrar «Quedó una operación sin poder leerse; revisa en la web antes de repetirla» en vez de seguir como si nada.

**5.2 `Producto.desdeJson` falla hacia lo permisivo** — `catalogo/producto.dart:52-60` (*verificado*): `estado ?? 'Disponible'`, `id ?? 0`, `precio ?? '0.00'`, `cantidad ?? 0`, `nivel_stock ?? 'ok'`.
- Efecto: un producto sin `estado` se puede vender; varios con `id == 0` chocan en el mapa por id del carrito; un precio ausente se ve como «sin precio».
- Prob.: baja. Toca: contrato de la API, dinero.
- Recomendación: descartar (y contar) o fallar en voz alta si faltan `id_producto`, `estado` o `precio`.

**5.3 Los elementos del catálogo que no son un mapa se descartan sin avisar** — `catalogo/catalogo_repository.dart:22-24` (*verificado*): `if (item is Map<String, dynamic>) Producto.desdeJson(item)`.
- Efecto: un producto «desaparece» del catálogo y, si estaba en el carrito, sale «ya no está en el catálogo». `clientes_repository.dart` hace lo contrario (falla en voz alta).
- Prob.: baja. Toca: datos, contrato.

**5.4 y 5.5 La caja abierta se puede leer como cerrada** — `caja/caja_repository.dart:19` (*verificado*): `if (cuerpo['active'] != true) return null;`; y `caja/caja_models.dart:24-26`: `idSesion ?? 0`, `montoApertura ?? '0.00'`, `fechaApertura ?? ''`.
- Efecto: una respuesta sin `active` o con otra forma se interpreta como «caja cerrada»; con la caja abierta se muestra «La caja ya no está abierta» (falso). Una `fecha_apertura` vacía apaga el aviso de «caja abierta de un día anterior»; «Efectivo inicial» muestra $0 aunque el dato falte.
- Prob.: baja. Toca: dinero, contrato.
- Recomendación: tratar `active` ausente como respuesta inesperada, y exigir `fecha_apertura` e `id_sesion`.

**1.3 Un `TypeError` deja colgado el login, la apertura o el cierre de caja** — `auth/auth_providers.dart:81, 101, 124, 166, 193`, `caja/caja_providers.dart:156-186`, `caja/cierre_providers.dart:131, 200, 292` (*citas del agente, sin verificar*): todos los `catch` son `on ErrorDeApi`; los `desdeJson` usan `as String?`, que lanza `TypeError` si el tipo cambia.
- Efecto: el estado se queda en «en trabajo» hasta reiniciar la app (botón «Ingresar» en espera). Prob.: baja. Toca: sesión, dinero.
- Recomendación: en cada notifier, un `catch` final que devuelva el estado a «reposo» con un mensaje y reporte el error (como el arreglo 1.5).

**1.4 El catálogo se puede quedar «cargando» para siempre** — `catalogo/catalogo_providers.dart:95-114` (*sin verificar*): solo atrapa `ErrorDeApi`; con un `TypeError` en `Producto.desdeJson` el spinner no termina y no hay botón de reintento. Toca: datos, contrato. Misma recomendación que 1.3.

**1.1 `rethrow` sin dónde registrarse** — `venta/venta_providers.dart:340-352`, `egresos/egreso_notifier.dart:210-222` (*sin verificar*): el comentario dice «se relanza para que quede registrado», pero no existe `FlutterError.onError`, `PlatformDispatcher.onError` ni `runZonedGuarded` en `lib/`; en release el error se pierde. El estado sí queda en «sin confirmar», así que la persona no se engaña. Toca: dinero.
- Recomendación: un registro global de errores en `main()` (decisión de Lucho: qué servicio o qué archivo).

**4.1 El arqueo usa `double` para el dinero** — `caja/caja_models.dart:166-167` (*verificado*): `valor is num && valor.isFinite ? (valor * 100).round() : null`. Es el único camino de dinero que no pasa por `centavosDeImporte`.
- Efecto: (a) con más de 2 decimales redondea sin avisar; (b) si el servidor manda un importe del arqueo como **texto** (`"50000.00"`, como sí hace `monto_apertura`), `valor is num` es falso, se descarta el arqueo entero y **no se puede cerrar la caja**. El contrato dice que son números, así que hoy funciona. *No pude comprobar qué manda realmente el backend.*
- Prob.: baja. Toca: dinero, contrato.

**5.7 Un `rol` o un tope ausentes desactivan el tope de egresos en la app** — `auth/auth_models.dart:66-67` junto con `egresos/egreso_reglas.dart` (*sin verificar*): `limiteEgresoTendero ?? '0.00'`, `rol ?? ''`; 0 o ilegible significa «no frenar». El servidor igual decide. Toca: permisos, dinero.

**5.8 Un solo cliente con saldo negativo hace fallar toda la lista de fiado** — `clientes/cliente.dart:67-70` y `clientes_repository.dart:25` (*sin verificar*). Es ruidoso, no silencioso, pero bloquea el fiado. *No pude verificar si el backend puede devolver saldos negativos.* Toca: dinero, contrato.

### Baja
- **4.2** `ui/dinero.dart:21-25` (`importeDeCentavos`): `assert(centavos >= 0)`; el «Debería haber» del arqueo puede ser negativo si los egresos superan el efectivo → pantalla roja en debug y signo perdido en release para −1 a −99 centavos. Toca: dinero (arqueo).
- **4.3** `ui/dinero.dart:11`: la expresión rechaza más de 2 decimales y negativos; un precio `"12000.000"` se ve como «sin precio» (mensaje engañoso). Toca: dinero, contrato.
- **4.4** `ui/formato.dart` con `producto.dart:57`: un precio `4500.5` se muestra `$4.500,5`. Presentación de dinero.
- **4.5** La conversión pesos → centavos se hace a mano (`* 100`) en 6 sitios (`venta_models.dart:74`, `cobrar_efectivo_screen.dart`, `venta_providers.dart:276`, `egreso_reglas.dart:45`, `formulario_de_egreso.dart:70`): hoy es correcto; un helper evitaría un factor 100 equivocado.
- **4.6** `producto.dart:58`: `cantidad` se trunca con `.toInt()` (2,5 → 2) sin avisar.
- **5.6** `carrito/carrito_models.dart:122`: las líneas sin precio suman 0; el total mostrado en el inicio y el escáner es menor al real mientras haya una (el cobro sí queda bloqueado).
- **2.1, 2.2, 2.3** `ref.read(...)` después de `await showDialog` sin comprobar que el widget siga montado, en «vaciar carrito», «cancelar el cobro sin confirmar» y «cancelar el gasto sin confirmar» (`carrito/ui/carrito_screen.dart` — hoy `dialogos_del_carrito.dart` tras el PR #5 —, `egresos/ui/gasto_sin_confirmar.dart:37-39`). *Sin verificar* si Riverpod 3 lanza en un widget desmontado. Tocan carrito y dinero, y la 2.1/2.2 chocan con el refactor del PR #5: conviene arreglarlas después de mezclarlo.
- **1.6** Futuros sin `await` ni manejo: `ui/refrescar.dart:62`, `venta/ui/escaner_venta_screen.dart:203`, `auth/ui/login_screen.dart:46-48` y varios `unawaited(...cargar())`; solo atrapan `ErrorDeApi`.

### Criterio 3 (controladores sin liberar)
Sin hallazgos: todos los `TextEditingController`, `MobileScannerController`, `AnimationController`, observadores y suscripciones tienen su `dispose()`/`cancel()`.

---

## 3. Vistos de paso (fuera de los cinco criterios)
- `ui/reloj.dart:5`: `ahoraProvider` calcula `DateTime.now()` una sola vez. Con la app abierta pasada la medianoche, «hoy/ayer» y el aviso de caja de un día anterior quedan desfasados. Toca: caja.
- Cerrar sesión sin red (`auth/auth_repository.dart:127-129`): la cookie persistida puede seguir válida en el servidor y restablecer la sesión al reabrir. Documentado como deliberado, pero es lo que más conviene revisar. Toca: sesión.
- Al caducar la sesión, las rutas empujadas (por ejemplo `CarritoScreen`) quedan encima de `AuthGate`; no hay `popUntil`. *No ejecutado.*
- Código muerto: `EgresoRechazado.claveReutilizada` se asigna y nadie lo lee; `Cliente.cupoDisponibleCentavos` tampoco se usa.
- Las `catch` vacías **deliberadas y comentadas** (almacenes, borrados de pendientes, versión instalada, caja sin red…) se revisaron y no se cuentan como bug.

---

## 4. Hallazgos que ya estaban anotados antes de esta auditoría
1. **EAN-13 inválido en una prueba.** El código `7709990000012` de `test/catalogo/ui/buscar_producto_pantalla_test.dart` tiene mal el dígito verificador. *Calculado:* los 12 primeros dígitos suman 94 con pesos 1 y 3, así que el dígito correcto es **6** (`7709990000016`). Hoy no rompe nada porque la app no valida el dígito; sería un problema si se empezara a validar.
2. **Comentario desactualizado en el backend.** `database/init_pg.sql:166` (repo del backend, no se tocó) lista las categorías de egreso como `'Proveedor', 'Insumos', 'Transporte', 'Otro'`; la app usa seis (Proveedor menor, Insumos / Bolsas, Transporte, Limpieza, Servicios, Otro). *Verificado* que el comentario dice eso.
3. **Copias sin versionar de documentos del backend en `docs/` de este repo (público):** `contrato_api_app_tendero.md`, `guia_construccion_app.md`, `guia_entorno_app.md`, `propuesta_tecnica_app_flutter.md`. *Verificado* que `guia_entorno_app.md` contiene una dirección de servidor de producción: **no commitear esas copias**. Recomendación: borrarlas o añadirlas a `.gitignore`; la fuente es el repo del backend.

---

## 5. Lo que no se pudo verificar
- No se ejecutó la app ni se probó en celular.
- Lo que depende de qué manda el servidor real (4.1, 5.5, 5.8 y los `desdeJson`) se juzgó por el contrato, no contra el backend.
- La auditoría no leyó `test/` para ver qué ya está cubierto.
- De `ficha_de_producto`, `piezas_de_pantalla`, `selector_pago_screen`, `piezas_de_cobro`, las pantallas de 2FA y el cambio de clave solo se hicieron búsquedas, no lectura completa.
