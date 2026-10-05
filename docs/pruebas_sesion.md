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
