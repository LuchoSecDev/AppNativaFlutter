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
1. **Cobro normal:** **Cobrar en efectivo** → «Verificando los precios…» → total correcto. Escribir un monto mayor: aparece «Cambio: $…». **Confirmar cobro** → comprobante «Venta registrada», con el número, el efectivo recibido y el cambio. En la web: la venta existe **una sola vez**, con el canal «app», y el stock bajó.
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
