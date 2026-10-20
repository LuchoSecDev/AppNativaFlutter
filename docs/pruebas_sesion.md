# Registro de pruebas de la sesión (paso 2)

Pruebas hechas con la app real en un celular, contra el servidor desplegado. Cada prueba nueva se agrega como una fila. Lo que corre sin celular (cliente HTTP, estado y pantallas) está cubierto por `flutter test`.

## Resultados

| Fecha | Prueba | Resultado |
|---|---|---|
| 4-oct-2026 | «Probar conexión con el servidor» (solo depuración) | **Pasó:** el servidor respondió con código 200. |
| 4-oct-2026 | Login de un Tendero de prueba contra el servidor real | **Pasó:** entró a la pantalla de inicio. |
| 4-oct-2026 | **Prueba A, cookie persistente:** cerrar la app del todo (quitarla de recientes), esperar unos minutos y reabrirla | **Pasó:** mostró «Conectando…» y entró directo al inicio, sin pedir contraseña. |
| 4-oct-2026 | **Prueba B, la sesión caduca:** cerrar la app del todo, esperar más de 30 minutos sin abrirla y reabrirla | **Pasó:** todo salió según lo previsto (pidió iniciar sesión de nuevo). |
| 4-oct-2026 | **Caja (paso 3):** con una caja ya abierta desde la web, entrar a la app | **Pasó:** mostró «Caja abierta», el efectivo inicial y la hora, con **Vender** activo. Además se vio el aviso del 409 (candado de una sesión caducada), que se corrigió en el servidor (rama `fix/candado-sesion-caducada`). |
| 4-oct-2026 | **Caja (paso 3):** abrir la caja desde la app | **Pasó** (reportado: «funciona bien»). |
| 4-oct-2026 | **Catálogo (paso 4.1):** consultar y buscar productos | **Pasó** (reportado). Solo se vio un producto con precio 0, que era un dato de la tienda y ya se corrigió. |
| 4-oct-2026 | **Carrito (paso 4.2):** agregar, cambiar cantidades, quitar, vaciar, persistencia | **Pasó** (reportado: «bien, sin fallos»). |

*(Reportado por el responsable de la prueba. Anotar el modelo del celular en las próximas filas.)*

## Pendiente de probar en celular: aviso de versión y actualización (P24-16, fase 1)
Necesita un APK que incluya esta rama (por ejemplo `1.0.1+2`) instalado a mano, y el servidor con las variables `APP_VERSION_CODE`, `APP_MIN_VERSION_CODE`, `APP_APK_URL` y `APP_APK_SHA256` (ver `docs/distribucion_app_beta.md` del backend). **Anotar el modelo del celular.**
1. **Versión al pie del inicio:** debe decir «StockPilot 1.0.1 (2)» (nombre y `versionCode`). Es la comprobación clave: confirma que el número que lee `package_info_plus` es el `versionCode` que se compara con el servidor.
2. **Nada publicado** (`APP_VERSION_CODE` sin definir): no aparece ningún aviso y todo funciona igual.
3. **Instalada = última** (`APP_VERSION_CODE=2`): tampoco aparece nada.
4. **Hay una versión nueva** (publicar `1.0.2+3`, `APP_VERSION_CODE=3`, mínima en 1): el inicio muestra «Hay una versión nueva de StockPilot (1.0.2)» con las notas. **Ahora no** lo quita hasta el próximo inicio de sesión. **Descargar** abre el navegador con la descarga del APK; al terminar, instalar encima (el celular pedirá permitir instalar desde el navegador): la app conserva la sesión y el pie dice «1.0.2 (3)».
5. **Actualización obligatoria** (`APP_MIN_VERSION_CODE=3` con la 2 instalada): aparece «Hay que actualizar la app» **en lugar del inicio**; no hay forma de llegar a **Vender** (el botón atrás no hace nada); **Descargar la versión nueva** funciona; **Cerrar sesión** lleva al login y, al volver a entrar, la pantalla reaparece.
6. **Descarga no configurada** (versión publicada pero sin `APP_APK_URL`): **Descargar** dice «Todavía no hay una versión para descargar», sin cerrar nada.
7. **Sin conexión al abrir** (modo avión después del login): la app entra normal; nunca se bloquea por no poder consultar la versión.
8. **Servidor dormido:** el inicio aparece sin esperar la consulta; el aviso, si corresponde, aparece después.
9. **Regresión:** abrir y cerrar caja, vender, escáner y refrescar funcionan igual.
10. **Otro celular:** repetir 1, 4 y 5 en un segundo teléfono (lo harán los compañeros).

## Pendiente de probar en celular: cierre de caja con arqueo previo (paso 5)
Necesita el backend con `[K5]` desplegado (rama `feat/caja-arqueo-previo`). Con la caja abierta y algunas ventas en efectivo, un egreso y, si se puede, una venta con tarjeta. **Contrastar siempre en la web** (historial de caja).
1. **Botón «Cerrar caja»** en la tarjeta de la caja del inicio (solo con la caja abierta).
2. **Paso 1:** el campo solo admite números (máximo 9 dígitos). Sin escribir nada, **Ver arqueo** pide el monto. El **0** es válido.
3. **Paso 2 (arqueo, no cierra nada):** muestra fondo inicial, ventas en efectivo, abonos, egresos, **«Debería haber»**, **«Tú contaste»** y **Cuadra / Sobra / Falta** con su color. Comprobar que la cuenta coincide con la web y que **la venta con tarjeta NO suma**. La caja sigue abierta (se ve en la web).
4. **Recontar:** vuelve al campo con lo escrito; se puede cambiar y volver a ver el arqueo.
5. **Confirmar cierre:** comprobante «Caja cerrada» con el arqueo final; **Volver al inicio**: la tarjeta dice «Caja cerrada» y **Vender** queda bloqueado. En la web el cierre aparece con el monto confirmado.
6. **Algo cambia mientras se revisa:** en el paso 2, registrar otra venta en efectivo desde la web y confirmar: avisa «Mientras revisabas se registró un movimiento» y muestra el arqueo FINAL.
7. **Caja cerrada en la web a mitad del cierre:** al ver el arqueo o al confirmar, dice que no hay caja abierta y el inicio se actualiza solo.
8. **Sin conexión:** al pedir el arqueo, mensaje claro y se puede reintentar. Al confirmar con la red cortada: **no reenvía el cierre**; consulta la caja y dice si se cerró o si sigue abierta. Si tampoco hay red: «sin confirmar» con el botón **Comprobar** (nunca «Confirmar» otra vez).
9. **Venta sin confirmar:** con un cobro sin resolver (cortar la red al cobrar), **Ver arqueo** y **Confirmar cierre** deben negarse y pedir resolverlo primero.
10. **Salir a media revisión** y volver a entrar: empieza de cero (paso 1, campo vacío).
11. **Desglose por método de pago:** en el paso 2 y en el comprobante aparece «Lo vendido en el turno, por método de pago». Hacer en el turno una venta en efectivo, una con tarjeta, una por transferencia y una fiada: cada una en su línea, con su número de ventas y su total, y las de tarjeta, transferencia y fiado marcadas **«no entra al cajón»**. El efectivo del desglose coincide con «+ Ventas en efectivo». Un turno sin ventas dice «Sin ventas en este turno». Contrastar con el historial de caja de la web (columna «Por método de pago»).

## Pendiente de probar en celular: cobro en efectivo (paso 4, subpaso 3)
Con la caja abierta y productos en el carrito. **Cada prueba que toca el dinero se contrasta en la web** (ventas, stock y arqueo).
1. **Cobro normal:** **Cobrar...** → **Efectivo** (desde la T6 el botón abre primero la hoja «¿Cómo vas a cobrar?») → «Verificando los precios…» → total correcto. Escribir un monto mayor: aparece «Cambio: $…». **Confirmar cobro** → comprobante «Venta registrada», con el número, el efectivo recibido y el cambio. En la web: la venta existe **una sola vez**, con el canal «app», y el stock bajó.
2. **Monto exacto:** el botón escribe el total (redondeado al peso siguiente si tiene centavos); el cambio es $0.
3. **Efectivo insuficiente:** con menos del total aparece «Faltan $…» y **Confirmar cobro** está bloqueado.
4. **Nueva venta:** tras el comprobante, **Nueva venta** deja el carrito vacío. También probar el botón **atrás** en el comprobante: al volver a entrar a **Vender** no debe reaparecer.
5. **Precio cambiado desde la web:** subir o bajar un precio en la web (sin refrescar la app) y pulsar **Cobrar**: debe avisar «El total cambió…» y cobrar con el precio nuevo. En la web, la venta queda con ese precio.
6. **Sin conexión al abrir Cobrar** (modo avión): «No se pudo verificar los precios…», sin campo para cobrar. Con conexión, **Reintentar** continúa.
7. **Sin conexión después de Confirmar** (apagar la red justo al confirmar): «Registrando la venta…» y, tras unos 7 segundos (la app reintenta a los 2 y a los 5), «sin confirmar», con **Reintentar** y **Cancelar este cobro**. Encender la red y **Reintentar**: comprobante. **En la web debe haber UNA sola venta**, no dos. Si se alcanzó a registrar la primera vez, el comprobante dice «ya estaba registrada».
8. **Cerrar la app con una venta sin confirmar:** reabrir; el inicio avisa «Hay una venta sin confirmar». **Vender** → **Reintentar** → comprobante, una sola venta en la web.
9. **Sesión caducada al cobrar** (esperar más de 30 minutos con la app abierta y confirmar): vuelve al login; al entrar con la misma cuenta, el carrito sigue y la venta aparece como sin confirmar. **Reintentar** la registra una sola vez.
10. **Cancelar este cobro:** advierte que, si la venta sí se había registrado, cobrar de nuevo la duplica. Con «Volver» no pasa nada.
11. **Caja cerrada desde la web** antes de confirmar: debe mostrar «Debes abrir tu caja antes de realizar ventas.» y bloquear **Vender**.
12. **Stock insuficiente:** bajar el stock en la web por debajo de lo que hay en el carrito y cobrar: el servidor lo rechaza con el nombre del producto; el carrito se conserva.
13. **Cierre de caja (web o servidor):** el efectivo de las ventas cobradas desde la app debe sumar en el arqueo.

## Pendiente de probar en celular: tarjeta, transferencia y fiado (T6)
**Nada de esto se ha probado en un celular:** hasta ahora solo corren las pruebas automáticas (servidor falso). Con la caja abierta y productos en el carrito. **Todo lo que toca dinero se contrasta en la web** (ventas, clientes y arqueo). Anotar el modelo del celular.
1. **La hoja de métodos:** **Cobrar...** abre «¿Cómo vas a cobrar?» con Efectivo, Tarjeta, Transferencia y Fiado. Se ve completa en una pantalla pequeña, con la barra de gestos del sistema, y se cierra al elegir. Los botones se alcanzan con el pulgar. El botón sigue bloqueado sin caja abierta o con productos con problemas.
2. **Tarjeta:** elegirla → «Verificando los precios…» → total → **Confirmar pago recibido** → comprobante «Venta registrada». En la web: la venta existe **una sola vez**, con método «Tarjeta» y canal «app».
3. **Transferencia:** igual que la 2, con método «Transferencia». El texto de la pantalla nombra el método (no debe verse «MetodoPago…»).
4. **Tarjeta y transferencia no suman al cajón:** hacer una de cada una y una en efectivo; en el arqueo del cierre aparecen en su línea del desglose, marcadas «no entra al cajón», y el efectivo esperado solo cambia por la venta en efectivo.
5. **Fiado, lista de clientes:** **Fiado** trae los clientes de la tienda. Nombres con tilde y «ñ» (Doña…) se leen bien. Para cada uno, «Debe $…» y el cupo coinciden **en pesos** con el módulo de clientes de la web. Un cupo 0 dice «sin tope».
6. **Buscador:** escribir parte del nombre, en mayúsculas y en minúsculas, y con el teclado del celular; la lista filtra. La **X** borra la búsqueda. Con una lista larga se puede desplazar.
7. **Fiado dentro del cupo:** elegir el cliente → «Total de la compra», «Debe ahora», «Quedaría debiendo» y «Cupo» → **Confirmar fiado** → comprobante. En la web: la venta queda **Pendiente**, con el cliente elegido, y el saldo del cliente sube justo el total.
8. **Justo en el cupo:** con un cliente al que le queden exactamente $X de cupo, fiar una compra de $X: debe dejar. Con $1 más: **Confirmar fiado** bloqueado y el mensaje «supera el cupo».
9. **Saldo que cambia en la web:** abrir la pantalla de fiado, volver al carrito, **registrar un abono o una venta fiada a ese cliente desde la web**, y volver a abrir Fiado: debe mostrar el saldo nuevo (la lista se trae de nuevo cada vez). Si no se vuelve a abrir y el servidor rechaza por cupo, se ve el mensaje del servidor y el carrito sigue.
10. **Sin conexión:** (a) modo avión al abrir Fiado: mensaje de conexión y **Reintentar**; (b) modo avión justo al **Confirmar fiado**: «sin confirmar»; al volver la red, **Reintentar** registra **una sola** venta, **con el mismo cliente** (verificar en la web que no hay dos ventas ni dos aumentos de saldo).
11. **Cerrar la app con un fiado sin confirmar:** reabrir; el inicio avisa; **Reintentar** registra la venta con el cliente correcto, una sola vez.
12. **Cambio de cuenta:** cerrar sesión y entrar con un Administrador o Tendero de **otra tienda**: la lista de Fiado muestra solo los clientes de esa tienda.
13. **Precio cambiado desde la web** con tarjeta, transferencia y fiado: avisa «El total cambió…» y cobra con el precio nuevo.
14. **Lo que la app NO verifica:** con tarjeta y transferencia el sistema registra lo que el Tendero confirma; no comprueba que el pago haya llegado (P24-06, pendiente de decisión). Decir esto en la demostración.

## Pendiente de probar en celular: registrar gastos de caja chica (T1)
**Nada de esto se ha probado en un celular:** hasta ahora solo corren las pruebas automáticas (servidor falso). Con una cuenta de **Tendero de una tienda de prueba**, la caja abierta, y la web abierta con el **Administrador de la misma tienda** (historial de egresos de caja) para contrastar. **Todo lo que toca dinero se contrasta en la web.** Anotar el modelo del celular.
1. **El botón:** en la tarjeta «Caja abierta» aparece **Registrar gasto** junto a **Cerrar caja**. Con la caja cerrada **no** aparece.
2. **El formulario:** el botón **Registrar gasto** está bloqueado hasta tener monto, motivo (5 o más caracteres) y una categoría elegida. El monto abre el teclado numérico, solo admite dígitos y hasta 9. Las seis categorías (Proveedor menor, Insumos / Bolsas, Transporte, Limpieza, Servicios, Otro) se ven completas, sin cortarse, y ninguna viene elegida. Se ve «Tu tope por gasto es $…» y **coincide con el tope de la tienda en la web**.
3. **Un gasto normal:** registrar $10.000, «Bolsas y hielo», «Otro». Sale el comprobante con **Gasto n.º…**, el monto, la categoría, el motivo y «Queda pendiente de aprobación del Administrador», con una **vibración media** al aparecer. **Listo** vuelve al inicio. **En la web:** el gasto aparece **UNA sola vez**, en estado «Registrado», con el mismo monto, motivo y categoría.
4. **El cierre de caja:** cerrar la caja. En el arqueo, **«− Egresos (gastos)»** incluye ese gasto y el «Debería haber» baja exactamente ese monto (también con el gasto aún pendiente de aprobación).
5. **El tope:** un gasto **igual al tope** se puede registrar; con **un peso más** el botón se bloquea y avisa «Supera tu tope…». Cambiar el tope en la web, cerrar sesión y volver a entrar: la app muestra el tope nuevo.
6. **Rechazo del servidor:** cerrar la caja **desde la web**, volver a la app (sin actualizar) y registrar un gasto: aparece el mensaje del servidor («No hay ninguna caja abierta…»), con una **vibración fuerte**, **lo escrito se conserva** y la tarjeta de caja pasa a «Caja cerrada».
7. **Sin conexión al confirmar** (modo avión justo al pulsar **Registrar gasto**): «Registrando el gasto…» y, tras unos 7 segundos (la app reintenta a los 2 y a los 5), **«sin confirmar»** con el gasto a la vista, **Reintentar** y **Cancelar este gasto**. **No** ofrece registrar de nuevo. Encender la red y **Reintentar**: comprobante (si alcanzó a registrarse la primera vez dice «ya estaba registrado»). **En la web debe haber UN solo gasto**, no dos.
8. **Cerrar la app con un gasto sin confirmar:** repetir el 7 y, antes de reintentar, cerrar la app del todo (quitarla de recientes) y reabrirla con red. La tarjeta dice **«Gasto sin confirmar»**; al abrirlo, **Reintentar** → comprobante, y en la web **un solo gasto**.
9. **Cancelar este gasto:** advierte que, si el servidor sí lo había registrado, registrarlo otra vez lo duplicaría. **Volver** no cambia nada; **Cancelar el gasto** vuelve al formulario en blanco.
10. **Salir y volver:** con el formulario a medias, ir atrás y volver a abrirlo: **conserva** monto, motivo y categoría. Después de registrar un gasto, o al cambiar de cuenta, empieza **en blanco**.
11. **Sesión caducada** (esperar más de 30 minutos con la app abierta y registrar): vuelve al login; al entrar con la misma cuenta, el gasto aparece como sin confirmar y **Reintentar** lo registra **una sola vez**.
12. **Cambio de cuenta:** cerrar sesión y entrar con otra cuenta (otra tienda): no se ve el formulario a medias ni el gasto sin confirmar de la anterior.
13. **Administrador** (si se prueba con esa cuenta): no se menciona ningún tope y se puede registrar un monto grande.
14. **El teclado y la mano:** el campo de monto y el de motivo no quedan tapados por el teclado; el botón **Registrar gasto** se alcanza con el pulgar, en una pantalla pequeña y con la barra de gestos.
15. **Lo que solo un celular real muestra:** la vibración (si se siente, si molesta, si el ajuste «vibración al tocar» del sistema la apaga) y el aspecto. **Lo que NO tiene este registro:** foto del comprobante (decisión D1 del plan de T1) y una lista de los gastos ya registrados (el contrato no tiene una consulta para el Tendero).

## Pendiente de probar en celular: estado del producto (leyendas y productos vencidos)
**Nada de esto se ha probado en un celular:** hasta ahora solo corren las pruebas automáticas (servidor falso; los ejemplos con vencidos y sobrestock están **fabricados** a partir del contrato, el servidor real aún no ha dado uno). Con una cuenta de **Tendero de una tienda de prueba** y la web abierta con el **Administrador** para preparar los productos (fechas de vencimiento en la ficha del producto) y para contrastar las leyendas con las de la web. Anotar el modelo del celular.
1. **Preparar en la web** (tienda de prueba): un producto **vencido hace unos días y con unidades**, uno que **venza hoy**, uno que venza en **3 días**, uno en **20 días**, uno con **sobrestock** (la web lo marca), uno **agotado**, uno con nivel **«Pedir más»**, uno **«Por agotarse»**, uno **pausado** y uno normal sin novedad.
2. **«Consultar productos»:** cada producto muestra **las mismas leyendas y colores que la web**: Vencido (rojo sólido), Vence hoy / mañana / en N días (rojo suave hasta 7 días; ámbar de 8 a 30), Sobrestock (azul), Agotado y Por agotarse (rojo suave), Pedir más (ámbar), Suficiente (verde, solo si nada lo contradice). El pausado **no aparece** en la lista. **Mantener presionada** una leyenda muestra la ayuda de la web (por ejemplo «Venció hace 3 días: retíralo de la venta»).
3. **La ficha:** tocar el producto vencido: la leyenda **Vencido** y debajo, escrita, «Venció hace N días: retíralo de la venta». Con la letra legible en un celular pequeño y con varias leyendas a la vez (que no se corten ni se salgan de la pantalla).
4. **Carrito, «Buscar manualmente»:** tocar el producto **vencido** avisa «está vencido y no se puede vender» y **se queda en el buscador**; el que **vence hoy** sí se agrega.
5. **Escáner:** escanear el código del producto vencido: aviso «está vencido y no se puede vender» y **no** se agrega; el que vence hoy se agrega. (La cámara real solo se prueba en un celular.)
6. **Un producto que vence con el carrito armado:** agregar un producto, y desde la web ponerle una fecha de vencimiento pasada; actualizar la lista en la app: la línea del carrito dice «Este producto está vencido… Quítalo del carrito» y **«Cobrar...» está bloqueado**; al quitarla se puede cobrar el resto. Contrastar: sin el bloqueo, el servidor habría rechazado **todo** el carrito con 400 `PRODUCTO_VENCIDO`.
7. **Lo que NO se ha probado:** el cambio de día (un producto «vence hoy» que pasa a vencido a medianoche con la lista ya descargada: el servidor es quien decide y lo rechazaría; al actualizar la lista la app lo bloquea) y la letra grande del sistema.

## Pendiente de probar en celular: actualizar la caja y los productos (cambios hechos en la web)
La app no se entera sola de lo que pasa en la web: vuelve a preguntar al servidor en estos momentos.
1. **Cerrar la caja en la web y volver a la app** (dejarla en segundo plano y traerla de vuelta): el inicio debe pasar solo a «Caja cerrada», con el aviso «se cerró desde otro lugar», y **Vender** quedar bloqueado. Sin cerrar la app.
2. **Abrir la caja en la web y volver a la app:** debe pasar a «Caja abierta» y habilitar **Vender**.
3. **Tirar hacia abajo** en el inicio: actualiza la caja y los productos.
4. **Botón de actualizar** (flecha circular) en la tarjeta de la caja, con la caja abierta y con la caja cerrada.
5. **En el carrito:** botón de actualizar en la barra: avisa «Actualizado.» y refleja una caja cerrada (el escáner y el cobro se bloquean).
6. **En «Consultar productos» y en «Elegir producto»:** botón de actualizar en la barra (además de tirar hacia abajo). Cambiar un precio o un stock en la web y comprobar que aparece.
7. **Sin conexión** (modo avión) al volver a la app o al actualizar: no debe marcar la caja como cerrada ni como error; si fue con el botón, avisa «No se pudo actualizar. Revisa tu conexión.».
8. **Cobrar con la caja ya cerrada en la web** (sin haber actualizado): el servidor lo rechaza con «Debes abrir tu caja antes de realizar ventas.» y la app actualiza la caja sola.
9. **Sesión caducada** (más de 30 minutos en segundo plano): al volver, debe llevar al login con su aviso, sin quedarse colgada.

## Pendiente de probar en celular: escáner en la venta (paso 4, subpaso 4)
Con la caja abierta. Lo que **solo** se ve con la cámara real es lo más importante de esta lista.
1. **Primer producto:** con el carrito **vacío** debe verse **Escanear producto** (activo con caja abierta; bloqueado y con «Abre la caja para escanear» sin caja). También aparece con el carrito con productos, junto a **Buscar manualmente**.
2. **Producto conocido:** escanear una etiqueta: aparece «Agregado: …», la cámara **sigue escaneando** y el panel inferior muestra «Carrito: N unidades · $total».
3. **Doble lectura (la prueba clave):** dejar el MISMO producto frente a la cámara 5 a 10 segundos. Debe sumar **una sola** unidad. Retirarlo más de 1,5 s y volver a mostrarlo: suma **otra**. Si se suman unidades de más, subir `silencioParaRepetirProducto` en `escaner_venta_screen.dart`; si cuesta escanear dos unidades iguales seguidas, bajarlo.
4. **Dos productos distintos seguidos:** se agregan los dos, sin esperar.
5. **Agotado o sin precio (0):** no se agrega y dice por qué.
6. **Etiqueta propia con `codigo` (SKU)** en Code 128 o QR, sin código de barras comercial: lo encuentra igual.
7. **Código desconocido:** aparece «Código no encontrado». **Cancelar** vuelve a escanear. **Vincular** abre la lista; al elegir un producto dice «Vinculado y agregado…». Comprobar en la web que el producto tiene ahora ese código, y que al escanearlo otra vez lo encuentra.
8. **Vincular un producto agotado:** el vínculo se hace y avisa que no se pudo agregar.
9. **Código que ya pertenece a otro producto:** muestra «Ese código ya pertenece a …» y no agrega nada.
10. **Volver atrás** en la lista de vincular: no se vincula nada y se sigue escaneando.
11. **Modo avión** al escanear: mensaje claro de conexión; al volver la red, el mismo código se puede escanear de inmediato.
12. **Listo, volver al carrito:** el carrito muestra lo escaneado y el total correcto; cobrar funciona como antes.
13. **Regresión:** **Probar el escáner** (la pantalla de diagnóstico del inicio y del login) debe leer un código y mostrarlo con «Escanear otro», igual que en el paso 1: ahora comparte con la venta la vista de la cámara.
14. **Otro celular:** repetir 2, 3 y 13 en un segundo teléfono (lo harán los compañeros).

## Pendiente de probar en celular: caja (paso 3), lo que falta
- **Caja cerrada:** al entrar con una cuenta sin caja abierta, el inicio dice «Caja cerrada», el botón **Vender** está bloqueado y aparece «Abre la caja para vender».
- **Abrir caja:** escribir un monto (por ejemplo 50000), confirmar el aviso «Vas a abrir la caja con $50.000. ¿Es correcto?». Debe volver al inicio con «Caja abierta», «Efectivo inicial: $50.000» y **Vender** activo.
- **Abrir con 0** también debe funcionar.
- **Persistencia:** con la caja abierta, cerrar la app del todo y reabrirla (dentro de 30 minutos): debe seguir mostrando «Caja abierta».
- **Caja abierta desde la web:** abrirla desde la web con la misma cuenta y entrar a la app: debe mostrarla abierta. Intentar abrirla de nuevo desde la app debe decir «Ya tenías una caja abierta».
- **Sin conexión al abrir:** modo avión al confirmar la apertura debe mostrar un mensaje claro, sin dejar la caja en un estado dudoso.
- **Aviso «Tu sesión terminó»:** con la caja ya consultada, esperar más de 30 minutos con la app abierta, tocar **Reintentar** o abrir la caja: debe volver al login con ese aviso.
- **Cambio de cuenta:** cerrar sesión y entrar con otra cuenta: no debe verse la caja de la anterior ni un instante.

## Pendiente de probar (sesión)
- **Dos dispositivos con la misma cuenta (409):** iniciar sesión en un segundo celular y comprobar que ofrece «Cerrar la otra sesión» y que la primera sesión queda cerrada.
- **Aviso «Tu sesión terminó»** con la app abierta: se podrá probar cuando exista una pantalla que haga peticiones (caja).
- **Primer cambio de contraseña:** con una cuenta nueva (contraseña temporal).
- **Segundo factor:** con un Administrador que tenga el 2FA activo.
- **Sin conexión:** modo avión al pulsar «Ingresar» debe mostrar un mensaje claro, no quedarse cargando.
