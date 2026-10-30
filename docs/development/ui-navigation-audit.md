# Auditoría automatizada de interfaz y navegación

Fecha: 30 de octubre de 2026
Versión auditada: Godot 4.7.2, rama `test/ui-navigation-audit`

## Alcance ejecutado

La auditoría cubre las pantallas actualmente funcionales: `MainMenu`,
`SeasonSelection` y `SeasonOverview`. Comprueba el arranque normal, el modo de
desarrollo explícito, el rechazo de un pack sintético ausente, la demostración,
el catálogo de 29 temporadas, la consulta sintética, el calendario, los
retornos y la recuperación de un fallo controlado de sesión.

Las pruebas inspeccionan visibilidad efectiva mediante `is_visible_in_tree()`,
propietario de foco mediante `gui_get_focus_owner()`, recuento y ciclo de vida
de vistas, conexiones de señales, resultados deportivos y archivos de
guardado. Tab, Mayús+Tab, Enter y las flechas de `ItemList` se inyectan como
`InputEventKey` mediante `Input.parse_input_event()`.

Se contrastó el comportamiento con la documentación oficial de Godot 4.7.2:

- [`Control` y `grab_focus()`](https://docs.godotengine.org/en/4.7/classes/class_control.html#class-control-method-grab-focus)
- [`Viewport.gui_get_focus_owner()`](https://docs.godotengine.org/en/4.7/classes/class_viewport.html#class-viewport-method-gui-get-focus-owner)
- [`Input.parse_input_event()`](https://docs.godotengine.org/en/4.7/classes/class_input.html#class-input-method-parse-input-event)
- [`CanvasItem.is_visible_in_tree()`](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html#class-canvasitem-method-is-visible-in-tree)
- [`Node.queue_free()`](https://docs.godotengine.org/en/4.7/classes/class_node.html#class-node-method-queue-free)

## Defectos reproducidos

### UI-NAV-001 — Foco ausente tras arranque y transiciones

- **Gravedad:** media; la interfaz podía usarse con ratón, pero el teclado no
  tenía un punto de partida visible o predecible.
- **Pasos:** arrancar el menú y consultar `gui_get_focus_owner()`; abrir una
  demostración o selector; regresar y volver a consultarlo.
- **Esperado:** una acción válida y visible recibe el foco en cada estado.
- **Observado:** el propietario era `null` al arrancar, al abrir contenido y al
  regresar.
- **Prueba:** `test_ui_navigation_audit.gd` verifica el foco del menú, selector,
  consulta, recuperación de error y retornos.
- **Corrección:** `MainMenu` asigna foco a demostración, retorno o lista según
  el estado; los fallos restauran el foco del selector.

### UI-NAV-002 — Orden Tab no priorizaba la consulta disponible

- **Gravedad:** baja; no bloqueaba la navegación, pero añadía un paso y hacía
  depender el recorrido del orden accidental de nodos.
- **Pasos:** abrir el selector con el pack sintético, mantener seleccionada la
  temporada consultable y pulsar Tab desde la lista.
- **Esperado:** enfocar `Consultar temporada`; si la consulta está
  deshabilitada, omitirla y enfocar `Volver al menú`.
- **Observado:** `Volver al menú` recibía el foco incluso cuando la consulta
  estaba habilitada.
- **Prueba:** la suite usa Tab con una temporada disponible y con otra no
  disponible, además de Mayús+Tab para el recorrido inverso.
- **Corrección:** `SeasonSelection` define un ciclo de foco dinámico que cambia
  cuando `ConsultButton.disabled` cambia.

### UI-NAV-003 — Dos acciones de retorno visibles en el selector

- **Gravedad:** baja; ambas conducían al menú, pero presentaban acciones
  redundantes y podían generar dudas sobre su alcance.
- **Pasos:** abrir el selector histórico desde el menú.
- **Esperado:** una única acción visible para regresar.
- **Observado:** coexistían el retorno global del encabezado y el retorno
  interno del selector.
- **Prueba:** la suite exige que el retorno global esté oculto en el selector y
  visible en `SeasonOverview`, donde no existe un retorno interno.
- **Corrección:** `MainMenu` muestra el retorno global solo para demostración y
  consulta, y utiliza el botón interno mientras el selector está activo.

Ningún defecto observado requirió modificar servicios, modelos, datos,
parsers, persistencia o reglas deportivas.

## Escenarios automatizados

La suite `tests/unit/test_ui_navigation_audit.gd` contiene 52 comprobaciones y
cubre:

- estado y foco iniciales en modo normal y de desarrollo;
- visibilidad exclusiva de menú, selector y consulta;
- catálogo normal de 29 temporadas y pack sintético explícito;
- Tab, Mayús+Tab, Enter y flechas sobre menú, botones e `ItemList`;
- acción deshabilitada, selección consultable y advertencias sintéticas;
- pulsaciones consecutivas y una única solicitud de consulta;
- ausencia de vistas y conexiones duplicadas;
- cambio determinista de jornada y retorno con selección conservada;
- fallo de carga que conserva el selector válido, muestra diagnóstico y
  restaura controles y foco;
- demostración repetida sin instancias ni resultados adicionales;
- rechazo de un pack de desarrollo ausente con catálogo histórico utilizable;
- ausencia de resultados históricos inventados y de nuevos guardados.

Las suites existentes siguen cubriendo configuraciones inválidas y calendarios
vacíos, mixtos o sin jornada, además de mutaciones defensivas y errores de
lectura y validación.

## Evidencia ejecutada

- Nueva suite: `PASS: 52 comprobaciones`.
- Siete suites relacionadas: 340 comprobaciones superadas.
- Regresión completa: 24 suites y 6.990 comprobaciones superadas con
  `4.7.2.stable.official.ed1daf0bf`.
- Importación, sintaxis de las tres pantallas y de la suite, arranque normal y
  arranque con `--dev-season-pack`: código cero y sin diagnósticos de error.
- El descubrimiento de CI usa `find tests/unit -name 'test_*.gd'`, por lo que la
  nueva suite se incorpora automáticamente sin cambiar workflows.
- Los resultados de GitHub Actions se consignan en el pull request de esta
  auditoría.

## Límites y riesgos pendientes

El modo headless no permite validar con suficiente fiabilidad el popup de
`OptionButton`: al inyectar Enter, su `PopupMenu` no llega a mostrarse y no
procesa la flecha posterior. La lógica de cambio de jornada se comprueba
mediante `item_selected`, pero el recorrido teclado completo del popup queda
pendiente de una prueba con ventana gráfica.

Tampoco se ha realizado una validación visual de indicadores de foco, contraste,
recorte, escalado 125–200 %, resoluciones objetivo ni ultrapanorámicas. La
navegación con mando y lector de interfaz requiere dispositivos o herramientas
de accesibilidad fuera de esta fase. No se afirma que esos puntos estén
validados.

## Recomendaciones

1. Ejecutar una revisión manual reproducible con ventana gráfica para el popup
   de jornadas y los indicadores visuales de foco.
2. Añadir pruebas de captura a las resoluciones y escalas definidas en el GDD
   cuando exista infraestructura gráfica estable en CI.
3. Evaluar navegación con mando y accesibilidad como una fase separada, con un
   contrato explícito de entradas y sin alterar el mapa global durante esta
   auditoría.
