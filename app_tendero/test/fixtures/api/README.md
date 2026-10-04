# Ejemplos reales de la API (fixtures)

Estos archivos son **copias** de `docs/ejemplos_app_tendero/` del repositorio del backend (`StockPilot`): peticiones y respuestas reales del servidor, con datos inventados. Las pruebas los usan para simular el servidor sin red ni celular.

- Solo se copian los que las pruebas necesitan.
- **Si la API cambia, hay que volver a copiarlos** desde el backend. El contrato (`docs/contrato_api_app_tendero.md` del backend) es la fuente de verdad.
- Los valores como `<token CSRF: …>` son marcadores, no tokens reales.
