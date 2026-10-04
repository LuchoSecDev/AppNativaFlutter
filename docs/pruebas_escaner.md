# Registro de pruebas del escáner (paso 1)

El «listo cuando» del paso 1 exige un criterio escrito y pruebas en **dos celulares reales distintos**. Este archivo es el registro; cada prueba nueva se agrega como una fila.

**Estado:** en curso. Falta completar con otros celulares y con etiquetas difíciles (quien continúe el paso).

## Resultados

| Fecha | Celular | Situación | Resultado |
|---|---|---|---|
| 4-oct-2026 | Samsung Galaxy S23 | Dos productos con **códigos distintos** dentro del mismo recuadro, celular en horizontal | **No lee ninguno.** |
| 4-oct-2026 | Samsung Galaxy S23 | Dos productos con el **mismo código** dentro del mismo recuadro, celular en horizontal | **Lee el código.** |

## Cómo interpretar el resultado
- Que no lea cuando hay dos códigos distintos en el recuadro es un comportamiento **seguro**: la app confirma un código solo tras 3 lecturas iguales seguidas (`ScanStabilizer`), y si el lector alterna entre dos códigos distintos la cuenta se reinicia cada vez. Es mejor no leer que registrar el producto equivocado. *(Explicación inferida del código; no se midió.)*
- Con dos códigos iguales no hay ambigüedad, así que lee. Esto es lo correcto: es el mismo producto.
- El resultado depende del orden en que el lector entrega los códigos de cada imagen (el código toma el primero de la lista). Si en otro celular ese orden fuera siempre el mismo, podría leer siempre el mismo de los dos. **Hay que repetir esta prueba en cada celular.**

## Pendiente de probar
- Un solo producto, en vertical y en horizontal.
- Etiquetas difíciles: pequeñas, curvas, arrugadas, con brillo, con poca luz.
- Un código fuera del recuadro y otro dentro (verifica `scanWindow`).
- Al menos un **segundo celular** de otra marca o gama.
- Criterio de aceptación del equipo (por ejemplo, cuántas etiquetas de un lote se leen y en cuánto tiempo): **por definir y anotar aquí**.
