# NEOFutbol

NEOFutbol es un proyecto de manager de fútbol histórico con gestión deportiva y económica y partidos arcade 2D cenitales, destinado inicialmente a Linux. Su diseño toma como referencia la experiencia de los managers clásicos, con una implementación y recursos propios o autorizados.

## Visión y objetivos

El objetivo es combinar decisiones de gestión ágiles, profundidad opcional y partidos accesibles. Cada temporada histórica será un punto de partida para construir una historia alternativa mediante las decisiones del jugador.

El alcance previsto abarca las temporadas de 1982-83 a 2010-11. El desarrollo prioriza una temporada completa y jugable antes de ampliar el catálogo a los 29 escenarios. Los datos y recursos de cada temporada estarán sujetos a validación y permisos de uso y distribución.

La arquitectura separará la lógica de negocio y simulación de las escenas de interfaz, y mantendrá diferenciados los datos históricos, los atributos de juego y los recursos visuales mediante identificadores estables.

## Estado actual

El proyecto está en fase de configuración y desarrollo inicial.

La base existente incluye `project.godot` en la raíz, la configuración del renderizador Compatibility, las carpetas básicas del repositorio y la documentación de diseño. Todavía no hay funcionalidades jugables implementadas.

## Características previstas

Las siguientes características forman parte del diseño y no están implementadas actualmente:

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

## Contenido público y paquetes privados

El diseño separa los datos históricos y parámetros de juego (`SeasonData`) de los nombres, retratos, escudos y otros recursos de presentación (`IdentityPack`). Ambos se relacionarán mediante IDs estables, para permitir cambios de identidad sin alterar la simulación ni las partidas.

El contenido público de `content/public/` deberá ser original, de dominio público o contar con permisos y licencias compatibles con su distribución. Los datos históricos también requerirán procedencia y permisos documentados.

Los paquetes privados serán locales y se mantendrán fuera del repositorio y de los artefactos públicos. Solo podrán utilizar material cuyo uso esté permitido; su carácter privado no concede derechos sobre recursos de terceros. Este repositorio no debe incluir recursos protegidos sin autorización de distribución.

La carga y selección de estos paquetes son funcionalidades previstas, todavía pendientes de implementación.

## Licencia

El código propio de NEOFutbol se licencia bajo **GNU Affero General Public License versión 3 únicamente**, con identificador SPDX **AGPL-3.0-only**. Consulta el texto completo en [LICENSE](LICENSE).

Los datos y recursos visuales tendrán sus propias licencias y permisos documentados; no adquieren automáticamente la licencia del código.
