# Instrucciones para agentes — NEOFutbol

NEOFutbol es un manager de fútbol histórico desarrollado en Godot 4.7.2 con GDScript, destinado inicialmente a Linux.

## Especificación y arquitectura

1. Utilizar `docs/design/NEOFutbol_GDD_TDD_v1.1.md` como especificación principal del proyecto y consultar sus secciones relevantes. El archivo `docs/design/NEOFutbol_Documento_Diseno_y_Desarrollo_v1.1.docx` es el original de referencia. Ante ambigüedades que afecten al diseño, seguridad, licencias o compatibilidad, consultar al usuario.
2. Utilizar Godot 4.7.2 y GDScript, con el renderizador Compatibility.
3. Mantener `project.godot` en la raíz y respetar las carpetas `game/`, `tools/`, `data/`, `content/`, `tests/` y `docs/`.
4. Separar la lógica de negocio y simulación de las escenas de interfaz.
5. Utilizar identificadores estables para clubes, jugadores y temporadas.
6. Mantener separados los datos históricos, los atributos de juego y los recursos visuales.
7. No introducir contenido privado ni material de terceros sin permisos de distribución en el repositorio, ramas, commits, pull requests, pruebas públicas o artefactos CI.
8. Mantener la licencia AGPL-3.0-only prevista para el código.
9. Consultar documentación oficial actualizada cuando se necesite verificar una API o comportamiento.
10. Responder siempre en español.

## Autonomía dentro de tareas aprobadas

11. Trabajar únicamente dentro del alcance de la tarea aprobada. Antes de comenzar, comunicar brevemente el plan, los archivos previstos y las comprobaciones; no pedir confirmación por cada edición rutinaria. Si surge una decisión que cambia alcance o requisitos, detenerse y consultar.
12. Para cada tarea, crear o reutilizar una rama dedicada desde la base indicada. No desarrollar directamente en `main`. Si hay cambios locales sin confirmar o trabajo concurrente, no sobrescribirlos ni hacer reset; comunicar el conflicto.
13. Dentro del alcance aprobado se permite crear y modificar código, tests, documentación, archivos de datos de prueba autorizados y ejecutar verificaciones locales sin pedir autorización individual.
14. Ejecutar pruebas y validaciones pertinentes después de los cambios; indicar qué se ejecutó, qué falló y qué no pudo comprobarse. No declarar pruebas superadas sin haberlas ejecutado.
15. Se permiten `git add`, `git commit` y `git push` **únicamente en la rama de tarea**, así como abrir o actualizar un pull request contra `main`, sin pedir permiso para cada operación, siempre que el usuario haya aprobado la tarea y la conexión/entorno dispongan de los permisos correspondientes.
16. Antes de subir cambios revisar `git status`, `git diff --cached` y archivos versionados para evitar credenciales, datos personales, paquetes privados o contenido sin licencia. No hacer `git push --force` ni reescribir historial sin autorización expresa.
17. Al finalizar, compartir resumen de archivos, pruebas, commit(s), enlace al PR si existe y riesgos o limitaciones. Esperar la aprobación del usuario antes de iniciar **una tarea nueva**.

## Acciones que requieren autorización expresa

18. Nunca fusionar un pull request a `main`, escribir directamente en `main`, modificar protecciones de ramas, lanzar releases o publicar paquetes sin aprobación explícita del usuario.
19. Solicitar autorización antes de eliminar archivos existentes de importancia, realizar cambios destructivos, migraciones irreversibles, instalar dependencias nuevas, ejecutar comandos con privilegios o modificar licencias, permisos, CI de publicación o políticas de seguridad.
20. No incorporar ni publicar packs privados, secretos, fotografías, escudos o datasets con derechos no verificados, incluso con autorización genérica para programar. Ante dudas sobre licencias o procedencia, detener la publicación.
21. Estas instrucciones orientan al agente; **no sustituyen** los permisos y políticas de aprobación del entorno Codex/GitHub. Nunca intentar eludir controles técnicos o de seguridad.
