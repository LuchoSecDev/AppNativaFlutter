# Reglas y Recomendaciones del Proyecto

1. **Contrato antes que código**: Antes de escribir un cliente de API, copia el ejemplo real del backend (`docs/ejemplos_app_tendero/`) a `test/fixtures/api/` y escribe la prueba contra ese archivo. Nunca inventes la forma de una respuesta.
2. **«Todo pasa» no basta**: Declara qué cubren las pruebas y qué no. Una pantalla de 400 líneas sin pruebas no está «verificada» aunque `flutter test` salga en verde.
3. **Mutaciones**: Tras escribir pruebas, rompe el arreglo a propósito y comprueba que alguna falla. Si ninguna falla, la prueba no prueba nada.
4. **Alcance y duplicación**: No copies y pegues una pantalla; extrae lo común. No modifiques una pantalla que ya estaba validada (como la de diagnóstico) sin decirlo.
5. **Recorre el flujo completo**: Antes de dar por terminado, recorre el flujo como el usuario: ¿se puede escanear el primer producto? ¿qué pasa si la cámara sigue apuntando al producto?
6. **No afirmes lo que no ejecutaste**: Si algo solo se prueba en celular, dilo en lugar de escribir «todo está en orden».
7. **Dinero y ramas**: Los cambios que tocan dinero o datos llevan prueba antes del arreglo. Merge y push, solo con la aprobación del usuario.
