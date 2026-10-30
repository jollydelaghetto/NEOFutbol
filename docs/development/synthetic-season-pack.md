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

## Exportaciones pública y de desarrollo

El proyecto define dos presets Linux:

- `Linux-Public`: incluye los JSON existentes de `data/seasons/` y excluye
  completamente `data/dev/`, pruebas, herramientas y documentación.
- `Linux-Development`: incluye los JSON históricos y los cinco JSON del pack
  permanente, pero también excluye pruebas, herramientas y documentación.

Las salidas predeterminadas son diferentes:

- `build/public/NEOFutbol.x86_64`
- `build/development/NEOFutbol-dev.x86_64`

El argumento `--dev-season-pack` no basta por sí solo para activar el modo. El
menú comprueba primero que estén disponibles `manifest.json`, `rules.json`,
`clubs.json`, `players.json` y `fixtures.json` bajo la raíz de desarrollo. Si
falta cualquiera, conserva `res://data/seasons`, no muestra la advertencia
sintética y comunica `development_pack_unavailable`. Así, una exportación
pública sigue siendo utilizable aunque reciba el argumento por error.

## Verificación reproducible de paquetes

`tools/verify_export_packages.sh` utiliza ambos presets para generar ZIP de
datos reales mediante `--export-pack`, inspecciona sus listados y comprueba:

- que ambos contienen los recursos del juego y todos los JSON históricos que
  existen en el árbol fuente;
- que el paquete público no contiene ninguna ruta `data/dev/`;
- que el paquete de desarrollo contiene los cinco JSON sintéticos;
- que pruebas y herramientas no se distribuyen en ninguna variante.

Desde la raíz del repositorio:

```bash
GODOT_BIN=/ruta/a/Godot_v4.7.2-stable_linux.x86_64 \
  tools/verify_export_packages.sh /tmp/neofutbol-exports
```

Los ZIP son paquetes de proyecto generados por Godot con los mismos presets y
filtros usados para los PCK. Son inspeccionables con `unzip -Z1`. Si también
están instaladas las plantillas oficiales de exportación 4.7.2, se pueden
generar y arrancar los ejecutables y PCK Linux con:

```bash
GODOT_BIN=/ruta/a/Godot_v4.7.2-stable_linux.x86_64 \
VERIFY_RELEASE_BINARIES=1 \
  tools/verify_export_packages.sh /tmp/neofutbol-exports
```

El workflow `Export Validation` descarga y verifica tanto Godot como las
plantillas oficiales, genera las dos variantes, examina sus ZIP equivalentes y
arranca cada ejecutable con y sin `--dev-season-pack`. No publica artefactos ni
crea releases.

El pack histórico `data/seasons/1982-83` sigue incompleto por diseño y no
contiene `fixtures.json`. La comprobación exige sus cuatro JSON presentes y
todos los demás JSON históricos que se añadan al repositorio; no inventa el
archivo ausente ni modifica datos históricos.

## Límites de la validación

Las pruebas headless comprueban carga, navegación, etiquetas, clasificación,
calendario, contenido de paquetes y retornos; no validan composición visual,
contraste ni tamaños en una ventana real. Los paquetes generados por CI son
temporales y se eliminan con el runner.
