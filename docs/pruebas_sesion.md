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

*(Reportado por el responsable de la prueba. Anotar el modelo del celular en las próximas filas.)*

## Pendiente de probar en celular: carrito (paso 4, subpaso 2)
- Con la caja abierta, **Vender** abre el carrito. Vacío: «El carrito está vacío».
- **Agregar producto** abre el buscador; al tocar uno vuelve al carrito con la línea, el total y el aviso «Agregado: …».
- **Más** y **Menos** cambian la cantidad y el total; **Menos** no baja de 1; **Más** no pasa del stock y avisa.
- **Quitar** y **Vaciar carrito** (con confirmación).
- Un producto **agotado** o **sin precio (0)** no se puede agregar y explica por qué.
- **Persistencia:** con productos en el carrito, cerrar la app del todo y reabrirla: el carrito sigue ahí y el inicio dice «Carrito: N unidades · $total».
- **Sesión caducada a mitad de una venta:** al volver a entrar con la MISMA cuenta, el carrito se recupera. Con OTRA cuenta no se ve.
- Cambiar un precio o el stock desde la web y refrescar el catálogo: el total del carrito debe cambiar solo.

## Pendiente de probar en celular: catálogo (paso 4, subpaso 1)
- Desde el inicio, **Consultar productos**: debe mostrar los productos de la tienda con precio en pesos y stock, ordenados por nombre.
- **Buscar:** escribir parte de un nombre (con y sin tildes, en mayúsculas o minúsculas), una categoría, un código interno y un código de barras. Con varias palabras, cada una debe aparecer.
- Un producto **agotado** debe verse marcado «Agotado»; uno **inactivo** no debe aparecer.
- Tocar un producto muestra sus datos, y «Código de barras: sin asociar» si no tiene.
- **Tirar para actualizar** con y sin conexión (modo avión): sin conexión debe conservar la lista y avisar.
- Con un catálogo grande (cientos de productos) comprobar que escribir no se siente lento.

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
