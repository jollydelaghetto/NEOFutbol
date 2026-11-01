# NEOFutbol

NEOFutbol es un proyecto de manager de fútbol histórico con gestión deportiva y económica y partidos arcade 2D cenitales, destinado inicialmente a Linux. Su diseño toma como referencia la experiencia de los managers clásicos, con una implementación y recursos propios o autorizados.

## Visión y objetivos

El objetivo es combinar decisiones de gestión ágiles, profundidad opcional y partidos accesibles. Cada temporada histórica será un punto de partida para construir una historia alternativa mediante las decisiones del jugador.

El alcance previsto abarca las temporadas de 1982-83 a 2010-11. El desarrollo prioriza una temporada completa y jugable antes de ampliar el catálogo a los 29 escenarios. Los datos y recursos de cada temporada estarán sujetos a validación y permisos de uso y distribución.

La arquitectura separará la lógica de negocio y simulación de las escenas de interfaz, y mantendrá diferenciados los datos históricos, los atributos de juego y los recursos visuales mediante identificadores estables.

## Estado actual (1 de noviembre de 2026)

El proyecto dispone de un **prototipo técnico de gestión**, todavía **no es un juego completo ni una temporada histórica jugable**.

En `main` (commit de referencia `76df4ac`, PR #40) ya funcionan sobre un **pack sintético de desarrollo**: selección de club, Despacho, consulta de Plantilla, clasificación y calendario, y Tácticas con un campo 2D, selector de formaciones de referencia **4-4-2, 4-3-3 y 4-2-3-1**, y **selección de posiciones con ratón y teclado**. Las posiciones están vacías y ni las formaciones ni las selecciones se guardan o producen efectos deportivos. Existen además servicios y pruebas de carga, calendario, resultados, clasificación, rondas y estado deportivo; **no todos están integrados en la experiencia del entrenador**.

La selección interactiva de posiciones quedó integrada con el [PR #40](https://github.com/jollydelaghetto/NEOFutbol/pull/40). La **asignación de jugadores** continúa pendiente. El primer escenario histórico público sigue incompleto, mientras que los cuatro clubes del pack de desarrollo son ficticios.

**Para retomar el desarrollo:** leer primero [`AGENTS.md`](AGENTS.md) y [**el documento de traspaso para IA**](docs/development/AI_HANDOFF.md). Este último diferencia módulos terminados, pruebas verificadas, riesgos y trabajo pendiente; es una fotografía fechada, no sustituye la inspección del repositorio actual.

La última regresión verificada en `main` para este documento suma **28 suites y 7.327 comprobaciones**, con Godot CI, GDScript CI y Export Validation superados. La validación visual exhaustiva sigue pendiente.

## Ejecutar el prototipo

Con Godot **4.7.2 Stable** disponible como `godot` y desde la raíz del repositorio:

```bash
godot --path . -- --dev-season-pack
```

Esto habilita **solo** el escenario sintético de cuatro clubes. El arranque habitual (`godot --path .`) no activa datos de desarrollo.

Para importar y lanzar una suite de pruebas headless:

```bash
godot --headless --path . --import
godot --headless --path . --script tests/unit/test_manager_tactics.gd
```

La CI ejecuta todas las suites de `tests/unit/test_*.gd` y valida las exportaciones pública y de desarrollo. Consultar el [documento de traspaso](docs/development/AI_HANDOFF.md) antes de realizar cambios.

## Características previstas

Las siguientes capacidades describen el alcance previsto. Algunas tienen prototipos o servicios parciales, pero la mayoría requiere integración antes de considerarse jugable:

- Juego para un jugador con funcionamiento prioritariamente sin conexión.
- Selección de temporadas históricas con reglas y competiciones por edición, centradas en el fútbol español y las competiciones europeas correspondientes.
- Liga Manager, carrera Liga Promanager y partidos amistosos.
- Gestión de plantillas, tácticas, entrenamientos, contratos, fichajes y finanzas.
- Partidos arcade 2D cenitales y resolución rápida de encuentros.
- Calendario, clasificaciones, ascensos, descensos y continuidad entre temporadas.
- Partidas guardadas versionadas.
- Editor de datos con importación masiva de CSV e imágenes, validación y reversión de cambios.
- Paquetes históricos y paquetes de identidad intercambiables mediante IDs estables.

## Tecnologías

- **Motor:** Godot 4.7.2.
- **Lenguaje:** GDScript.
- **Renderizador:** Compatibility.

## Plataformas previstas

**Linux de escritorio es la plataforma inicial.** El diseño contempla posteriormente Windows y macOS, y después Android, iOS y Web, sujetos a pruebas y adaptación. Estas plataformas futuras no representan versiones disponibles.

## Estructura básica del repositorio

```text
NEOFutbol/
├── project.godot         # Configuración del proyecto Godot
├── game/                # Escenas, lógica del juego e interfaz
│   ├── scenes/
│   └── scripts/
├── tools/               # Herramientas de edición e importación
│   ├── data_editor/
│   └── importers/
├── data/                # Esquemas y datos históricos autorizados
│   ├── schema/
│   └── seasons/
├── content/
│   └── public/          # Recursos destinados a distribución pública
├── tests/               # Pruebas de lógica e integración
│   ├── unit/
│   └── integration/
├── docs/                # Diseño, arquitectura, datos y licencias
│   ├── design/
│   ├── architecture/
│   ├── data/
│   └── licenses/
├── AGENTS.md            # Instrucciones de trabajo para agentes
├── LICENSE              # Licencia del código
└── README.md
```

Las carpetas establecen la organización del desarrollo; su presencia no implica que sus módulos o contenidos ya estén implementados.

## Documentos de diseño

- [GDD/TDD v1.1 en Markdown](docs/design/NEOFutbol_GDD_TDD_v1.1.md): especificación principal del proyecto, con el alcance, la arquitectura y los hitos previstos.
- [Documento original de diseño y desarrollo v1.1](docs/design/NEOFutbol_Documento_Diseno_y_Desarrollo_v1.1.docx): referencia original en formato Word.
- [Traspaso de desarrollo para IA](docs/development/AI_HANDOFF.md): estado integrado, historial de PR, arquitectura, pruebas y siguientes hitos.
- [Pack sintético de desarrollo](docs/development/synthetic-season-pack.md): activación, alcance y aislamiento en exportaciones.

## Contenido público y paquetes privados

El diseño separa los datos históricos y parámetros de juego (`SeasonData`) de los nombres, retratos, escudos y otros recursos de presentación (`IdentityPack`). Ambos se relacionarán mediante IDs estables, para permitir cambios de identidad sin alterar la simulación ni las partidas.

El contenido público de `content/public/` deberá ser original, de dominio público o contar con permisos y licencias compatibles con su distribución. Los datos históricos también requerirán procedencia y permisos documentados.

Los paquetes privados serán locales y se mantendrán fuera del repositorio y de los artefactos públicos. Solo podrán utilizar material cuyo uso esté permitido; su carácter privado no concede derechos sobre recursos de terceros. Este repositorio no debe incluir recursos protegidos sin autorización de distribución.

La carga y selección de estos paquetes son funcionalidades previstas, todavía pendientes de implementación.

## Licencia

El código propio de NEOFutbol se licencia bajo **GNU Affero General Public License versión 3 únicamente**, con identificador SPDX **AGPL-3.0-only**. Consulta el texto completo en [LICENSE](LICENSE).

Los datos y recursos visuales tendrán sus propias licencias y permisos documentados; no adquieren automáticamente la licencia del código.
