# Pack sintético de temporada para desarrollo

## Objetivo y aislamiento

El directorio `data/dev/seasons/1982-83/` contiene un escenario permanente para
probar el recorrido Menú → Selector histórico → Consulta de temporada →
Clasificación y calendario → Regreso. Está separado de `data/seasons`: el
arranque normal conserva el catálogo histórico y no descubre este pack.

El identificador temporal `1982-83` se utiliza únicamente para ejercitar el
contrato técnico vigente. El contenido no representa la temporada histórica
1982-83, no acredita datos históricos y no reemplaza el pack incompleto de
`data/seasons/1982-83/`.

Todos los clubes, jugadores, identificadores, partidos y reglas de este
escenario son originales y fueron creados específicamente para desarrollo. El
campo `checksum` del manifest es un marcador de versión legible; no es una
verificación criptográfica ni afirma que se haya verificado la procedencia.

## Contenido

El pack contiene los cinco archivos que consume `SeasonSessionLoader`:

- `manifest.json`: esquema, procedencia sintética y marcador no criptográfico.
- `rules.json`: una liga de cuatro clubes, tres jornadas y una vuelta.
- `clubs.json`: cuatro clubes ficticios con identificadores `dev_*`.
- `players.json`: cuatro jugadores ficticios, uno asociado a cada club.
- `fixtures.json`: los seis emparejamientos de la liga, sin resultados iniciales.

Solo existe una competición (`dev_synthetic_league`), una fase
(`dev_regular`) y un grupo (`dev_group_a`).

## Activación

Godot 4.7.2 separa sus opciones de los argumentos de usuario mediante `--`.
El proyecto consulta estos últimos con `OS.get_cmdline_user_args()`. Desde la
raíz del repositorio, el modo se activa así:

```bash
/workspace/.neofutbol-tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64 \
  --path . -- --dev-season-pack
```

Para una comprobación headless limitada:

```bash
/workspace/.neofutbol-tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64 \
  --headless --path . --quit-after 30 -- --dev-season-pack
```

El argumento debe aparecer después del separador `--`. Abrir el proyecto en el
editor, pulsar F6/F5 o arrancarlo sin ese argumento no activa el pack.

Con el modo activo, el selector utiliza `res://data/dev/seasons`. La pantalla
muestra `MODO DESARROLLO — DATOS SINTÉTICOS` durante el menú, el selector y la
consulta deportiva. El flujo de demostración continúa siendo independiente.

## Recorrido

1. Arrancar con el argumento de desarrollo.
2. Elegir **Seleccionar temporada**.
3. Mantener seleccionada `1982-83` y pulsar **Consultar temporada**.
4. Consultar la clasificación inicial de cuatro clubes y las tres jornadas.
5. Volver a temporadas y después al menú.

La consulta no crea una carrera, no añade resultados y no guarda una partida.

## Exportación y límites

Las pruebas headless comprueban carga, navegación, etiquetas, clasificación,
calendario y retornos; no validan composición visual, contraste ni tamaños en
una ventana real.

Godot trata los JSON leídos con `FileAccess` como archivos de datos del pack.
Antes de distribuir una exportación debe verificarse que el preset incluya
explícitamente los JSON necesarios como recursos no importados. El preset
actual usa `export_filter="all_resources"` y no declara un `include_filter`;
esta tarea no cambia la configuración de exportación. También debe decidirse
si un build público debe excluir `data/dev/` o incluirlo solo en artefactos de
desarrollo. La activación por argumento no sustituye esa política de
empaquetado.
