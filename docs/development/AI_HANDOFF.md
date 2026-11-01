# Traspaso de desarrollo para una IA — NEOFutbol

**Estado comprobado:** 1 de noviembre de 2026.
**Rama de referencia integrada:** `main`, commit `76df4ac67d762a8beb1b244167d930187bd3c5ea` (PR #40).
**Último trabajo integrado:** [PR #40](https://github.com/jollydelaghetto/NEOFutbol/pull/40), fusionado mediante squash en `76df4ac`. No hay una tarea funcional posterior aprobada en este traspaso.
**Naturaleza:** fotografía de situación y criterios de continuidad, no modificación de los requisitos de producto. Antes de programar, volver a comprobar `main`, PR abiertos y CI.

> **Si eres la IA que retoma el proyecto:** lee primero [`AGENTS.md`](../../AGENTS.md), después este archivo, el [GDD/TDD v1.1](../design/NEOFutbol_GDD_TDD_v1.1.md) en las secciones pertinentes y, por último, el código y las pruebas que vas a cambiar. El GDD define el producto deseado; este documento aclara **qué existe realmente**. No confundas lo diseñado, lo probado y lo integrado.

## 1. Visión y decisiones de producto

NEOFutbol es un **manager de fútbol histórico para un jugador**, inicialmente en **Linux**, implementado con **Godot 4.7.2 Stable + GDScript**, renderizador **Compatibility**, que aspira a combinar:

- Gestión de club ágil y accesible, inspirada funcionalmente en los managers clásicos (en especial la experiencia de PC Fútbol 5.0), **sin reutilizar material protegido**.
- Temporadas históricas seleccionables entre **1982-83 y 2010-11** (29 escenarios previstos), con normas propias de cada edición y una **historia alternativa** a partir del inicio elegido.
- Gestión deportiva y económica; más adelante, partidos arcade **2D cenitales** y simulación rápida.
- Interfaz de escritorio informativa, estética azul noche/cian, navegación por teclado, foco predecible y **una sola acción de retorno visible** por pantalla.
- Arquitectura que separe **lógica deportiva**, **datos históricos**, **atributos de videojuego**, **identidad/presentación** y **escenas UI**.

**Prioridad acordada durante el prototipado:** avanzar por capacidades pequeñas, testeables y revisadas; no intentar todas las temporadas ni un juego completo a la vez. La primera experiencia ha sido un flujo de **club → Despacho → consultas de Plantilla/Tácticas/Clasificación/Calendario** sobre un **pack sintético explícito**, antes de abordar alineaciones, partidos y economía.

**No des por existente** cualquier función citada como futura en el GDD.

## 2. Estado REAL integrado en main

### 2.1 Experiencia de usuario y pantallas

| Área | Estado verificado en `main` |
| --- | --- |
| Menú principal / demostración | Existen y tienen pruebas. |
| Selector histórico | Presenta las 29 temporadas contempladas; el catálogo no implica que haya 29 packs completos. |
| Consulta deportiva / clasificación / calendario | Funcionales con la sesión de desarrollo; no son un juego de temporada completo. |
| Selección de club dirigido | Funcional para los cuatro clubes del pack sintético (PR #36). |
| Despacho del entrenador | Muestra contexto, agenda y accesos a consulta; no ofrece todavía una carrera completa (PR #35). |
| Plantilla | Consulta de jugadores realmente cargados para el club; solo lectura, sin atributos inventados (PR #37). |
| Tácticas: campo | Campo 2D dibujado con Godot; once **posiciones vacías**, sin `player_id` ni efectos deportivos (PR #38). |
| Tácticas: selector | Referencias visuales **4-4-2, 4-3-3 y 4-2-3-1**; cambio local, no persistente (PR #39). |
| Tácticas: seleccionar una posición | **Integrado en main (PR #40):** clic sobre un marcador, selección por teclado, resaltado y panel informativo. Selección solo visual, sin `player_id` ni guardado. |
| Mercado / Avanzar día desde Despacho | Controles pendientes o deshabilitados; no fingir que funcionan. |
| Alineación, once titular, suplentes, asignación de jugadores | **Pendientes**. |
| Motor de partido 2D arcade, carrera completa y economía integrada | **Pendientes**, aunque existen servicios deportivos aislados. |

Archivos de entrada: `project.godot` → `game/scenes/main_menu.tscn` y `game/scripts/ui/main_menu.gd`. Pantallas relevantes: `manager_club_selection`, `manager_office`, `manager_squad`, `manager_tactics`, `season_selection` y `season_overview` (`.tscn` + `.gd`). El dibujo está en `game/scripts/ui/tactics_field.gd`.

La sesión se prepara con `SeasonSessionLoader.prepare_session()`, se conserva en `MainMenu._office_session` y pasa contexto validado a las vistas. No crear un cargador JSON por pantalla ni otra fuente de verdad para el club seleccionado. Las vistas de Plantilla/Tácticas deben limitarse a presentar datos de sesión.

### 2.2 Lógica deportiva, modelos y tests

Ya existen servicios y pruebas para catálogo/carga de temporada, reglas y validación de datos, calendario, clasificación, resultados/correcciones, avance de rondas y persistencia del **estado deportivo**. Por ejemplo:

- `game/scripts/services/season_catalog_service.gd`
- `game/scripts/services/season_session_loader.gd`
- `game/scripts/services/season_controller.gd`
- `game/scripts/services/calendar_service.gd`, `league_calendar_generator.gd`
- `game/scripts/services/standings_service.gd`
- `game/scripts/services/round_progression_service.gd`
- `game/scripts/services/match_result_correction_service.gd`
- `game/scripts/services/sporting_state_persistence_service.gd`

**Precaución:** que estos servicios existan y tengan pruebas unitarias **no significa** que el Despacho permita avanzar jornadas ni que exista un simulador de partidos o un guardado de carrera completo. Revisar contratos y pruebas del servicio concreto antes de integrarlo con UI.

Modelos y parsers residen en `game/scripts/data/` y otras carpetas de infraestructura. Conservar `season_id`, `club_id`, `player_id`, `competition_id`, etc. como identificadores estables. Los objetos de jugador distinguen `historical_data`, `game_data` y `metadata`; no rellenar campos ausentes por comodidad.

### 2.3 Datos: demostración sintética versus historia real

- Pack **exclusivo de desarrollo:** `data/dev/seasons/1982-83/`, con `manifest.json`, `rules.json`, `clubs.json`, `players.json`, `fixtures.json`.
- Contiene una liga sintética: **cuatro clubes ficticios**, **un jugador ficticio por club**, **seis partidos sin resultado** y **tres jornadas**. Clubes: **Aurora Unión**, **Bruma Atlético**, **Cometa FC**, **Duna Deportivo**.
- Jugadores sintéticos: **Ariel Norte**, **Berto Niebla**, **Ciro Estela** y **Dario Arena**. Son marcadores para probar la interfaz, **no** plantillas suficientes ni futbolistas históricos.
- Su `historical_data` y `game_data` no contienen datos deportivos reales: no atribuir edad, posición, habilidad, presupuesto o estadísticas inventadas.
- Pack histórico público `data/seasons/1982-83/`: **incompleto por diseño**; contiene `manifest.json`, `rules.json`, `clubs.json` y `players.json`, pero **no** `fixtures.json`. No es un escenario jugable completo.
- El modo de desarrollo se activa solo mediante `-- --dev-season-pack`, con aviso `MODO DESARROLLO — DATOS SINTÉTICOS`. No activarlo silenciosamente en el arranque normal.
- `Linux-Public` **excluye** `data/dev/`; `Linux-Development` sí permite los cinco JSON sintéticos. La separación se verifica en CI. Consultar [la guía específica](synthetic-season-pack.md).

En distribución pública **no** incluir escudos, fotos, bases de datos o recursos con derechos no verificados. Los datos públicos, identidades intercambiables y licencias siguen las reglas del GDD. El código mantiene **AGPL-3.0-only**.

## 3. Punto exacto del relevo: PR #40 integrado

**Último PR funcional integrado:** [#40 — Selección interactiva de posiciones tácticas](https://github.com/jollydelaghetto/NEOFutbol/pull/40), fusionado mediante squash en `76df4ac67d762a8beb1b244167d930187bd3c5ea`.

- Implementa la selección de cualquiera de las once **posiciones vacías** con ratón o teclado; resalta la posición e informa de su `slot_id`, etiqueta, línea y estado «Sin jugador asignado».
- Recorre el foco **Selector de formación → Campo → Volver al Despacho**; el cambio de formación limpia la selección. Los tres esquemas siguen siendo 4-4-2, 4-3-3 y 4-2-3-1.
- Resuelve los dos hallazgos P2 de la revisión inicial: un clic vacío no debe seleccionar al portero y el panel debe desplazar sus detalles para mantenerlos accesibles por teclado.
- Las pruebas del HEAD revisado usaron entrada real del `Viewport`, geometría en 1000×700 y 800×560, y navegación por teclado.
- Validación antes de la fusión: **28 suites / 7.327 comprobaciones**; Godot CI, GDScript CI y Export Validation completaron correctamente.
- No introduce asignación de jugadores, alineaciones persistentes, simulación ni cambios del estado deportivo.

**Pendiente:** revisión visual con una ventana real de Godot en un hito de interfaz; las pruebas headless no la reemplazan. **No hay una nueva tarea funcional aprobada:** pedir al usuario el siguiente alcance antes de implementar.

## 4. Cómo desarrollar y verificar en local

### Entorno

- **Godot:** versión **4.7.2 Stable**, binario estándar (no .NET), renderizador Compatibility.
- **Lenguaje:** GDScript.
- **Plataforma inicial:** Linux.
- **Control de versiones:** GitHub, rama principal `main`, PR por tarea.
- El binario `godot` debe estar en `PATH` o sustituirse por la ruta real. No asumir que un path de CI o del equipo anterior existe en el nuevo ordenador.

Desde la raíz del repositorio:

```bash
git status --short --branch
godot --version
godot --headless --path . --import
godot --headless --path . --script tests/unit/test_manager_tactics.gd
godot --headless --path . --quit-after 30
godot --headless --path . --quit-after 30 -- --dev-season-pack
```

Para probar una suite diferente, sustituir su ruta bajo `tests/unit/test_*.gd`.

Una comprobación reproducible de todas las suites (con salida `PASS` y fallo inmediato) es:

```bash
set -euo pipefail
while IFS= read -r -d '' test_file; do
  echo "=== $test_file ==="
  godot --headless --path . --script "$test_file"
done < <(find tests/unit -type f -name 'test_*.gd' -print0 | sort -z)
```

**Nota:** el pipeline de GitHub también comprueba diagnósticos de error, resultado final de cada suite, sintaxis/importación y contenido de los paquetes. No sustituir CI por el mero código de salida. Comprobar las acciones reales bajo `.github/workflows/`.

Comprobación de exportación, **solo cuando proceda** y con las dependencias oficiales instaladas:

```bash
GODOT_BIN=godot tools/verify_export_packages.sh /tmp/neofutbol-export-review
```

No utilizar como salida una carpeta de datos personales ni sobrescribir archivos preexistentes. El script tiene validaciones de preservación.

### Evidencia del último main revisado

- Commit `76df4ac` tras integrar PR #40.
- **28 suites / 7.327 comprobaciones** verificadas en GDScript CI del HEAD fusionado.
- **Godot CI, GDScript CI y Export Validation: success.**
- No se han validado exhaustivamente con ventana gráfica los popups, la composición visual, el escalado, lectores de interfaz ni gamepad. Las pruebas headless **no** sustituyen esa revisión.

## 5. Disciplina de trabajo acordada

1. **Una tarea funcional cada vez.** El usuario aprueba el alcance; el agente implementa, prueba y abre un PR; se revisan diff y CI; el usuario autoriza la fusión. No empezar el siguiente bloque antes de cerrar el anterior.
2. El usuario **no quiere abrir Godot para probar cada micro-PR**. Priorizar tests reproducibles y CI; reservar validaciones manuales para hitos visuales o dudas concretas.
3. Trabajar en ramas dedicadas, jamás directamente sobre `main`; no fusionar, hacer `push --force`, crear releases ni instalar dependencias sin la autorización pertinente.
4. Antes de cambiar código, inspeccionar implementaciones, escenas, datos y pruebas **reales**. No seguir ciegamente ejemplos de un modelo o una sugerencia antigua.
5. No asumir comportamiento de Godot: contrastar APIs y eventos con documentación oficial actual de la versión aplicable. Si no se puede validar un aspecto, declararlo.
6. Mantener estado aislado y retornos seguros: contexto validado, sin vistas duplicadas, sin señales conectadas varias veces, foco coherente y un único retorno visible.
7. Usar errores estructurados (`{"ok": bool, "data": ..., "errors": [...]}`) cuando corresponda a los contratos existentes, sin quebrar compatibilidad.
8. Exigir pruebas para estado normal y modo sintético, datos ausentes, fallo de configuración, rutas de teclado, preservación del controlador y ausencia de guardados no pedidos.
9. En código o documentación pública: cero secretos, datos privados, material de terceros no autorizado o estadísticas inventadas.
10. Al comunicar avances: separar **implementado**, **probado automáticamente**, **revisado visualmente** y **pendiente**. Informar siempre los hashes revisados.

Todo esto complementa, no sustituye, [`AGENTS.md`](../../AGENTS.md).

## 6. Orden de continuidad sugerido (NO aprobado automáticamente)

**A. PR #40 completado.** Su selección de posiciones está integrada y probada en CI. No repetir este trabajo.

**B. Revisar conjuntamente la interfaz cuando resulte oportuno.** Probar visualmente menú → club → Despacho → Plantilla/Tácticas, cambio entre tres formaciones, enfoque por teclado, clic vacío, seleccionador y panel desplazable. No fingir que estas comprobaciones ya se hicieron.

**C. Preparar la asignación de jugadores a posiciones (nueva tarea a definir).** Antes de diseñar el contrato, inspeccionar `PlayerSeason`, qué campos contienen realmente los packs y cómo manejar una plantilla incompleta de **un jugador por club**. No inventar once futbolistas ni requisitos posicionales; valorar primero una asignación visual temporal y sus estados vacíos, con aprobación de alcance.

**D. Integrar un bucle de temporada mínimo**, después de estabilizar modelo y UX: avanzar una jornada con operaciones deportivas explícitas, calendario/tabla coherentes, guardado/versionado y flujo de retorno. Aprovechar servicios probados, sin afirmar que ya están conectados.

**E. Ampliar más adelante** mercado, economía, reglas de época, importación de datos con procedencia, simulación rápida y partido arcade 2D, según prioridades del GDD y nuevas decisiones del usuario.

**Importante:** la «mecánica retro» de la sección 7 del GDD y los 29 escenarios históricos son **requisitos/diseño**, no funcionalidades ya disponibles. No adelantar su implementación sin una tarea aprobada.

## 7. Archivos que leer al reanudar

1. [`AGENTS.md`](../../AGENTS.md): normas y permisos.
2. [`docs/design/NEOFutbol_GDD_TDD_v1.1.md`](../design/NEOFutbol_GDD_TDD_v1.1.md): especificación del producto; original [DOCX](../design/NEOFutbol_Documento_Diseno_y_Desarrollo_v1.1.docx).
3. [`README.md`](../../README.md): visión y entrada general.
4. [`docs/development/synthetic-season-pack.md`](synthetic-season-pack.md): aislamiento, activación, exportación.
5. [`docs/development/ui-navigation-audit.md`](ui-navigation-audit.md): auditoría histórica del PR #33; **sus totales de suites son de ese momento**.
6. `game/scripts/ui/main_menu.gd`, `manager_office.gd`, `manager_squad.gd`, `manager_tactics.gd`, `tactics_field.gd`.
7. `game/scripts/services/season_session_loader.gd` y `season_controller.gd`.
8. `tests/unit/test_manager_tactics.gd` y las suites relacionadas con lo que vayas a modificar.
9. `.github/workflows/ci.yml`, `godot-ci.yml`, `export-validation.yml`.
10. [PR #40](https://github.com/jollydelaghetto/NEOFutbol/pull/40) y su revisión, ya integrados, como referencia para el manejo de foco y selección.

## 8. Instrucción breve para un agente local nuevo

> Estás continuando NEOFutbol. Antes de editar, lee AGENTS.md, docs/development/AI_HANDOFF.md y las secciones pertinentes del GDD v1.1. Inspecciona main y los PR abiertos; el PR #40 ya está integrado en main mediante `76df4ac`. No crees datos históricos ni jugadores ficticios adicionales sin una tarea autorizada. Trabaja en una rama por cambio, conserva el aislamiento del pack sintético, ejecuta las pruebas Godot headless y respeta el flujo de aprobación. Pide al usuario la siguiente tarea concreta si no existe una aprobada. Contesta en español.

---

**Mantenimiento:** al fusionar un PR significativo, actualizar esta fotografía (fecha, commit de `main`, PR abierto, cobertura CI y lo implementado). Nunca poner una cifra de pruebas sin indicar a qué commit corresponde. El documento maestro v1.1 permanece como fuente de requisitos; los avances de implementación se registran aquí.
