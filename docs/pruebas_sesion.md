# Registro de pruebas de la sesión (paso 2)

Pruebas hechas con la app real en un celular, contra el servidor desplegado. Cada prueba nueva se agrega como una fila. Lo que corre sin celular (cliente HTTP, estado y pantallas) está cubierto por `flutter test`.

## Resultados

| Fecha | Prueba | Resultado |
|---|---|---|
| 4-oct-2026 | «Probar conexión con el servidor» (solo depuración) | **Pasó:** el servidor respondió con código 200. |
| 4-oct-2026 | Login de un Tendero de prueba contra el servidor real | **Pasó:** entró a la pantalla de inicio. |
| 4-oct-2026 | **Prueba A, cookie persistente:** cerrar la app del todo (quitarla de recientes), esperar unos minutos y reabrirla | **Pasó:** mostró «Conectando…» y entró directo al inicio, sin pedir contraseña. |
| 4-oct-2026 | **Prueba B, la sesión caduca:** cerrar la app del todo, esperar más de 30 minutos sin abrirla y reabrirla | **Pasó:** todo salió según lo previsto (pidió iniciar sesión de nuevo). |

*(Reportado por el responsable de la prueba. Anotar el modelo del celular en las próximas filas.)*

## Pendiente de probar en celular: caja (paso 3)
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
