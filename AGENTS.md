# Instrucciones para agentes — NEOFutbol

NEOFutbol es un manager de fútbol histórico desarrollado en Godot 4.7.2 con GDScript, destinado inicialmente a Linux.

1. Utilizar docs/design/NEOFutbol_GDD_TDD_v1.1.md como especificación principal del proyecto. Consultar las secciones relevantes antes de diseñar o implementar funcionalidades. El archivo docs/design/NEOFutbol_Documento_Diseno_y_Desarrollo_v1.1.docx es el documento original de referencia. Si existe alguna ambigüedad o contradicción, comunicarla al usuario antes de tomar decisiones.
2. Utilizar Godot 4.7.2 y GDScript, con el renderizador Compatibility.
3. Mantener `project.godot` en la raíz y respetar las carpetas `game/`, `tools/`, `data/`, `content/`, `tests/` y `docs/`.
4. Separar la lógica de negocio y simulación de las escenas de interfaz.
5. Utilizar identificadores estables para clubes, jugadores y temporadas.
6. Mantener separados los datos históricos, los atributos de juego y los recursos visuales.
7. No introducir contenido privado ni material de terceros sin permisos de distribución en el repositorio.
8. Mantener la licencia AGPL-3.0-only prevista para el código.
9. Antes de modificar código, explicar brevemente los cambios previstos.
10. Trabajar en pasos pequeños. No avanzar a la siguiente tarea hasta recibir la confirmación del usuario.
11. Ejecutar las comprobaciones disponibles después de cada cambio y comunicar errores o limitaciones.
12. No ejecutar `git commit`, `git push`, eliminar archivos ni instalar dependencias sin autorización expresa del usuario.
13. Consultar documentación oficial actualizada cuando se necesite verificar una API o comportamiento.
14. Responder siempre en español.
