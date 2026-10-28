**NEOFutbol**

DOCUMENTO MAESTRO DE DISEÑO Y DESARROLLO

Manager de fútbol histórico con simulación arcade 2D en Godot

| **Versión**              | 1.1 · edición y publicación de contenidos    |
|--------------------------|----------------------------------------------|
| **Fecha**                | 28 de octubre de 2026                        |
| **Plataforma de salida** | Linux · escritorio                           |
| **Horizonte histórico**  | Temporadas 1982-83 a 2010-11 (29 escenarios) |

## VISIÓN

Recuperar la sensación de PC Fútbol 5.0: decisiones rápidas, profundidad suficiente para enganchar, temporadas históricas reconocibles y partidos en los que jugar sea divertido desde el primer minuto.

Referencia de diseño: PC Fútbol 5.0 y el comportamiento de mercado de PC Fútbol 4. No se presupone derecho a reutilizar marcas, gráficos, música, fotografías ni bases de datos de terceros.

# Índice de contenido

Esta estructura es navegable desde el panel de títulos de Word o LibreOffice. Los números identifican secciones, no páginas, de manera que el índice se mantiene estable al editar el documento.

<table>
<colgroup>
<col style="width: 50%" />
<col style="width: 50%" />
</colgroup>
<thead>
<tr>
<th><p>0. Resumen ejecutivo y decisiones iniciales</p>
<p>1. Visión de producto</p>
<p>2. Cobertura histórica y temporadas</p>
<p>3. Bucle de juego y progresión</p>
<p>4. Modos de juego</p>
<p>5. Simulador de fútbol 2D cenital</p>
<p>6. Gestión de club y economía</p>
<p>7. Bug de PC Fútbol 4</p>
<p>8. Datos históricos y fuentes</p>
<p>9. Modelo de futbolistas</p>
<p>10. Importación y editor de datos</p>
<p>11. Arquitectura, GitHub y CI</p></th>
<th><p>12. Interfaz retro-modernizada</p>
<p>13. Portabilidad multiplataforma</p>
<p>14. IA de despacho y mercado</p>
<p>15. Requisitos no funcionales y QA</p>
<p>16. Hitos, MVP y prioridades</p>
<p>17. Riesgos y mitigaciones</p>
<p>18. Licencia, propiedad intelectual y packs</p>
<p>19. Decisiones abiertas</p>
<p>20. Primera iteración</p>
<p>21. Fuentes consultadas</p>
<p>22. Glosario</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Revisión v1.1: incorpora repositorio público, licencia AGPL-3.0, editor de datos con importación masiva y packs visuales públicos/privados. Permisos y disponibilidad de datos históricos sujetos a verificación.

# 0. Resumen ejecutivo y decisiones iniciales

NEOFutbol será un juego de gestión futbolística offline-first, para un jugador, con temporadas históricas seleccionables, simulador 2D cenital y gestión deportiva/económica. La referencia principal será la experiencia de PC Fútbol 5.0, con una presentación modernizada y una implementación original.

| **Decisión** | **Criterio adoptado** |
|----|----|
| Motor | Godot 4.7.x estable; fijar versión exacta en el repositorio (la 4.7.2 era estable a 28/10/2026). |
| Lenguaje | GDScript y componentes de Godot; evitar C# como dependencia esencial si Web es objetivo. |
| Arquitectura | Núcleo de simulación separado de UI; datos históricos externos versionados por temporada. |
| Alcance temporal | 1982-83 a 2010-11 como interpretación inclusiva de “1982 a 2010”. |
| Juego | Partido interactivo 2D y resolución rápida con reglas compartidas. |
| Persistencia | Partidas guardadas versionadas y separadas de las bases de datos originales. |
| Fallo de mercado | Comportamiento retro deliberado, activado por defecto en modo Clásico. |
| Estrategia de entrega | Un escenario vertical completo antes de cargar las 29 temporadas. |
| Publicación | Repositorio público en la cuenta GitHub del desarrollador, proyecto NEOFutbol; commits, CI y releases trazables. |
| Licencia del código | GNU Affero General Public License v3.0 (AGPL-3.0-only), incluyendo el editor propio. |
| Editor de contenido | Editor oficial para fichas, clubes, temporadas, CSV e importación masiva de imágenes. |
| Packs de identidad | Pack público con nombres/recursos originales y autorizados; pack privado separado con datos y recursos originales solo de fuentes cuyo uso esté permitido. |

Estado de este documento: especificación para implementación, no afirmación de que ya existan plantillas completas o licencias de uso. Las valoraciones técnicas, estimaciones y límites se validarán durante el prototipo.

# 1. Visión de producto

## 1.1 Pilares de diseño

- Nostalgia funcional: navegación por iconos, pantallas de gestión de alta densidad informativa y ritmo de temporada ágil.

- Historia jugable: comenzar en un año elegido y alterar su curso; los datos iniciales son históricos, el futuro se simula.

- Accesibilidad arcade: controles inmediatos y delanteros peligrosos; el jugador no debe necesitar dominar técnicas complejas para marcar.

- Profundidad opcional: cuatro variantes de control y una carrera de entrenador con reputación, ofertas y despidos.

- Modularidad: nuevos años, reglas, idiomas, ligas, estilos de interfaz y plataformas sin reescribir el motor.

## 1.2 Público y experiencia

Destinado a aficionados a los managers clásicos, a la historia del fútbol español y a los juegos accesibles. Una sesión breve debe permitir gestionar una jornada y disputar un partido; una sesión larga, cerrar una temporada con fichajes, ascensos y competiciones europeas.

## 1.3 Fuera del alcance de la primera versión

Multijugador online, simulador 3D, editor de estadios, licencias oficiales automáticas, mercado mundial exhaustivo, comentarios hablados con voces reales y adaptación del editor a móvil. El editor de base de datos con importación CSV e imágenes SÍ es requisito del proyecto y forma parte de las entregas prioritarias.

# 2. Cobertura histórica y estructura de temporadas

## 2.1 Escenarios iniciales

El selector principal mostrará 29 temporadas desde 1982-83 hasta 2010-11. Cada una es un punto de partida independiente: equipos, plantillas, edades, competiciones y reglas corresponden al año seleccionado. Si se inicia 1982-83 y se progresa, no se cargarán automáticamente los fichajes reales de 1983-84: la historia pasará a ser alternativa.

Cada pack tendrá manifest con identificador de temporada, fecha de inicio, reglas, equipos, jugadores, competiciones, calendario y trazabilidad de fuentes. La compatibilidad de guardados se comprueba por versión de pack y versión de esquema.

## 2.2 Competiciones incluidas

| **Ámbito** | **Competiciones / criterio de implementación** |
|----|----|
| España | Primera, Segunda, Segunda B (grupos variables), Copa del Rey y Supercopa de España cuando aplique. |
| Europa | Copa de Europa / Champions League; Copa UEFA / Europa League; Recopa hasta su desaparición; Supercopa UEFA. |
| Ampliables | Intertoto y otros torneos de época como packs opcionales, tras verificar acceso, formato, participantes y fechas. |
| Adversarios internacionales | Plantillas históricas licenciables cuando existan. Si faltan, dataset secundario etiquetado; no atribuir estadísticas inventadas a personas reales. |

## 2.3 Motor de reglamentos por temporada

| **Periodo / excepción** | **Regla a parametrizar** | **Prueba histórica** |
|----|----|----|
| 1982-83 | Victoria = 2 puntos; Primera con 18 equipos / 34 jornadas. | Clasificación histórica de Athletic Club con 50 puntos. |
| 1986-87 | Primera y Segunda con segunda fase; Segunda B con 1 grupo de 22. | Composición de fases y consecuencia de ascensos/descensos. |
| Desde 1987-88 | Segunda B reorganizada en 4 grupos (con excepciones posteriores). | Generador de grupos por temporada, no constante global. |
| 1995-96 y 1996-97 | Primera con 22 clubes y 42 jornadas; 3 puntos por victoria desde 1995-96. | Calendario con 462 partidos y tabla de 3 puntos. |
| Europa 1992+ | Copa de Europa evoluciona a Champions League; formato por edición. | Fases y plazas según reglamento de la edición. |
| Europa 1999 / 2009 | Fin de Recopa en 1999; Copa UEFA se denomina Europa League desde 2009-10. | Inexistencia de Recopa tras 1998-99; nombre/estructura 2009-10. |

Las excepciones anteriores son ejemplos verificados; el catálogo de cambios, desempates, cupos de extranjeros, sustituciones, sanciones, filiales, ascensos y reglas UEFA deberá auditarse año por año antes de declarar un pack “históricamente validado”.

## 2.4 Calendario y reglas deportivas

- Calendario real: conservar fecha, jornada, rival y competición cuando existan datos legales reutilizables; usar calendario generado si el universo alternativo altera participantes.

- Ascensos y descensos: reglamentos por edición, incluidas promociones y restricciones de filiales; nunca codificar un valor fijo “3 equipos”.

- Empates en tabla: desempates oficiales configurables por competición y temporada; resolver con una lista ordenada de criterios.

- Reglas de partido: número de sustituciones, suspensión por tarjetas, duración, ventanas y cupos contextualizados por época.

- Plazas europeas: asignación histórica, efecto de vencedores de copa y cambios reglamentarios, con validación por fuente UEFA/RSSSF.

# 3. Bucle de juego y progresión

## 3.1 Bucle principal

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr>
<th>Seleccionar temporada → Elegir modo y equipo → Despacho<br />
↓<br />
Revisar agenda / mensajes / clasificación / finanzas<br />
↓<br />
Plantilla y tácticas → Mercado / entrenamiento / renovaciones<br />
↓<br />
Avanzar fecha → Eventos IA → Preparar partido<br />
↓<br />
Jugar en 2D | Simular rápido | Ver resumen<br />
↓<br />
Resultado → Lesiones / sanciones / ingresos / reputación<br />
↺ hasta cierre de temporada → premios / ascensos / Europa</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 3.2 Estados del calendario

Cada avance ejecuta una cola determinista de eventos: vencimiento de contrato, ofertas, entrenamientos, lesiones, sanciones, nóminas, entradas, partidos y decisiones directivas. El sistema debe poder pausar y deshacer solo hasta el último guardado, sin volver a disparar eventos ya procesados.

## 3.3 Comienzo, continuidad y final

La elección de temporada define el estado inicial; las temporadas futuras son generadas. Liga Manager no tiene fecha de fin obligatoria. Liga Promanager continúa hasta retirada voluntaria o un límite técnico amplio, con historial completo de cargos, trofeos, fichajes, clasificaciones y despidos.

# 4. Modos de juego

## 4.1 Liga Manager

Permite dirigir cualquier club de Primera, Segunda o Segunda B disponible en el año inicial durante tantas campañas como se quiera. El nivel de intervención se elige al crear partida y puede modificarse desde opciones, conservando registro del cambio.

| **Función** | **Entrenador** | **Manager** | **Presidente** | **Total** |
|----|----|----|----|----|
| Alineaciones / tácticas | Manual | Manual | Semiauto | Manual |
| Renovaciones | Auto | Auto | Manual | Manual |
| Finanzas | Auto | Manual | Manual | Manual |
| Fichajes | Manual\* | Manual | Manual | Manual |
| Entrenamiento / decisiones | Manual | Manual | Semiauto\* | Manual |

\* Propuesta de detalle de implementación: las finanzas y renovaciones siguen exactamente las automatizaciones solicitadas; las facultades no definidas en la directriz se plantean como opciones configurables, no como hechos históricos cerrados.

Automatización = agente explícito que toma decisiones observables, con parámetros y mensajes de qué acciones realizó. Nunca debe generar transferencias o renovaciones imposibles por falta de dinero o cupos.

## 4.2 Liga Promanager

- El personaje comienza como entrenador de caché bajo y recibe una oferta de un equipo modesto de Segunda B del año seleccionado.

- La directiva fija objetivos medibles (clasificación, permanencia, ascenso, estabilidad económica, desarrollo de plantilla) y un umbral de paciencia.

- Cumplir objetivos mejora reputación y acceso a clubes fuertes; incumplirlos provoca advertencias, despido, reducción de caché y nuevas ofertas acordes al historial.

- El historial incluye campañas, clubes, trofeos, fichajes destacados, temporadas completas, objetivos y valoraciones directivas.

- El usuario acepta/rechaza contratos y puede continuar en el club; la IA gestiona candidatos y vacantes sin bloquear el progreso.

## 4.3 Partido amistoso

Selección libre de dos equipos disponibles en el catálogo de la temporada, equipación, táctica, once inicial, duración y dificultad. Sin economía, transferencias, calendario ni impacto en partidas de liga. Acceso directo al simulador interactivo; opción de partido IA contra IA para pruebas.

## 4.4 Selección y persistencia de modo

Al crear partida se guardan modo, año, club/carrera, control de automatizaciones, dificultad arcade, semilla RNG, reglas históricas, licencia de pack y configuración del exploit retro. Los amistosos se pueden jugar sin guardar carrera.

# 5. Simulador de fútbol 2D cenital

## 5.1 Fantasía jugable

Partidos con once jugadores por equipo, cámara cenital fija o seguimiento ligero, sprites legibles, marcador, minimapa opcional, balón visible y ritmo rápido. El foco es “meter goles con buenas jugadas”, no reproducir al milímetro un simulador televisivo.

## 5.2 Principios de jugabilidad

- Primer contacto: moverse, pasar, centrar y tirar con pocos botones; selección automática del jugador útil.

- Ayudas: pases orientados hacia compañero, desmarques inteligentes, control de balón asistido y disparos con margen generoso.

- Dificultad: Novato, Clásico, Experto y Personalizado; la dificultad modifica presión, tiempo de reacción y ayudas, no solo la puntería rival.

- Goles: objetivo orientativo de prototipado de 2–5 goles del usuario por partido en Clásico con buen equipo y manejo básico; medir en tests, no garantizar marcador.

- Ritmo: 2×45 minutos de reloj virtual, opción de encuentros condensados (~6–12 minutos reales, ajustable).

- Partidos modernos e históricos comparten base de física, pero permiten estilos tácticos dependientes de atributos y era.

## 5.3 Controles propuestos (remapeables)

| **Acción** | **Teclado** | **Mando** | **Táctil futuro** |
|----|----|----|----|
| Mover jugador | WASD / flechas | Stick izquierdo | Stick virtual |
| Pase raso / seleccionar | J | A / cruz | Botón pase |
| Pase largo / centro | K | X / cuadrado | Botón centro |
| Disparo | L (mantener potencia) | B / círculo | Botón tiro |
| Sprint / presión | Mayús | Gatillo | Botón mantener |
| Cambio de jugador | Espacio | RB / R1 | Botón cambio |
| Pausa y táctica | Esc | Start | Menú contextual |

## 5.4 Modelo de partido

Entidad MatchState con reloj, tiempo añadido, posesión, posición/velocidad del balón, estado de 22 actores, órdenes tácticas, árbitro y eventos. Motor a pasos fijos de física (p. ej., 60 Hz) y UI interpolada; se probará rendimiento a 30/60 FPS con la misma lógica de decisiones.

Movimientos por máquina de estados: reposo, buscar espacio, marcar, interceptar, recibir, conducir, pasar, tirar, despejar, disputar y celebrar. Separar la decisión táctica (cada cierto intervalo) del movimiento físico (cada tick).

## 5.5 IA sobre el césped

- Defensa: selección de cobertura, marcaje zonal o individual, línea defensiva, presión por cercanía, reacción razonable a pases al hueco.

- Ataque: buscar apoyo al portador, ocupar bandas, rupturas, disparar con ocasiones favorables y centros cuando la zona es rentable.

- Porteros: posición respecto a balón/portería, blocaje y paradas con probabilidad influida por atributo, distancia y velocidad; evitar “porteros infalibles”.

- Tácticas: formaciones de época (4-4-2, 4-3-3, 5-3-2, etc.), mentalidad, presión, ritmo, amplitud, marcajes y lanzadores.

- Juego justo: la IA no conocerá el destino de un disparo antes de la acción ni modificará atributos secretos para forzar derrotas.

## 5.6 Simulación rápida

La simulación de partido no interactiva reutiliza valoraciones de equipos, tácticas, desgaste, lesiones, suspensiones, ventaja de campo, aleatoriedad y un registro de eventos. No necesita ejecutar toda la física 2D; debe producir resultados estadísticamente calibrados por época y contar con una interfaz común de resultados y eventos.

## 5.7 Métricas de equilibrio

| **Métrica** | **Meta de validación inicial** |
|----|----|
| Goles usuario (Clásico) | 2–5 por partido como franja aspiracional de disfrute en sesiones de prueba. |
| Tasa de pases | El usuario novato completa la mayoría de pases sencillos no presionados. |
| Disparos y porteros | Ocasiones claras tienen probabilidad alta, pero no certeza de gol. |
| Simulado vs. jugado | Clasificaciones plausibles para la misma plantilla; no resultados idénticos. |
| Rendimiento | 60 FPS objetivo en Linux; 30 FPS aceptables en móviles modestos en un futuro. |
| Accesibilidad | Legibilidad del balón, colores diferenciables, controles remapeables y tutorial breve. |

# 6. Gestión de club y economía

## 6.1 Módulos de gestión

| **Módulo** | **Mínimo funcional** | **Extensión posterior** |
|----|----|----|
| Plantilla | Alineación, suplentes, posiciones, cansancio, sanciones. | Roles, química, moral avanzada, mentores. |
| Tácticas | Formaciones y órdenes básicas por línea. | Editor de jugadas y ajustes por rival. |
| Entrenamiento | Carga semanal y mejora/forma. | Staff, instalaciones, especialización. |
| Mercado | Listado, ofertas, ventas, compras y renovaciones. | Cesiones y cláusulas específicas por época. |
| Finanzas | Presupuesto, salarios, taquilla, premios, fichajes. | Patrocinadores, estadio, deuda detallada. |
| Directiva | Objetivos, confianza, advertencias. | Políticas de club, elecciones de presidente. |
| Cantera | Regeneración básica de jugadores jóvenes. | Red mundial de ojeadores. |
| Noticias | Buzón de eventos y resultados. | Prensa dinámica, narrativas personalizadas. |

## 6.2 Economía de época

El juego mantendrá importes en enteros de “unidad económica interna” y mostrará divisa local por temporada. Pesetas hasta la transición histórica al euro; las conversiones son de interfaz y no deben alterar saldos ni romper partidas. Presupuestos, traspasos y salarios antiguos se reconstruirán como valores de jugabilidad si no hay fuentes comparables; nunca se etiquetarán como hechos históricos.

## 6.3 Fichajes y negociación

Cada negociación conserva un identificador, club vendedor/comprador, jugador ofertado, precio, caducidad, estado y respuesta IA. La IA pondera demanda posicional, salario, presupuesto, reputación, objetivos y valor de jugador. El modo retro aplica una excepción deliberada y aislada de este flujo (sección 7).

# 7. Mecánica obligatoria: bug de PC Fútbol 4

## 7.1 Comportamiento exacto buscado

NEOFutbol replicará la explotación que permite poner a un futbolista valioso a la venta y, tras recibir una oferta por él, seleccionar otro futbolista propio de menor valor justo antes de confirmar. El comprador paga la oferta original, pero se lleva al jugador sustituto. El jugador inicialmente ofertado permanece en el club.

## 7.2 Secuencia canónica de aceptación

> 1\. El usuario pone al jugador A a la venta por un valor alto.
>
> 2\. Un club controlado por IA ofrece una cantidad X por A; la oferta se conserva sin cambios.
>
> 3\. Antes de cerrar la operación, el usuario pulsa “Cambiar jugador” y selecciona al jugador B, más barato.
>
> 4\. El sistema permite confirmar en modo retro sin recalcular X ni exigir una nueva negociación.
>
> 5\. Se descuenta B de la plantilla y se acredita X al presupuesto del usuario; A sigue en la plantilla.
>
> 6\. El historial señala que la operación fue una “venta retro” para que sea trazable y no parezca corrupción del guardado.

| **Ejemplo de prueba (ficticio)** | **Antes** | **Después** |
|----|----|----|
| Plantilla | A (valor de juego 10 M) + B (0,5 M) | A permanece; B sale |
| Oferta recibida | 8 M por A | 8 M ingresados por B |
| Comprador | Pretendía adquirir A | Recibe B |
| Estado de contrato | A y B contratados | A contratado; B transferido |

## 7.3 Implementación técnica

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr>
<th>TransferOffer { offer_id, buyer_id, original_player_id, offered_amount,<br />
status, expires_at }<br />
SellConfirmation { offer_id, selected_player_id }<br />
<br />
si classic_market_exploit == true:<br />
validate(selected_player_id pertenece a vendedor y es transferible)<br />
final_player_id = selected_player_id<br />
final_price = TransferOffer.offered_amount # NO recalcular<br />
si classic_market_exploit == false:<br />
exigir selected_player_id == original_player_id<br />
final_price = TransferOffer.offered_amount<br />
confirmar_transaccion_atomica(final_player_id, final_price, buyer_id)</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Importante: la excepción no debe permitir duplicación por doble clic, saldos negativos por reintentos, venta múltiple del mismo jugador, cambios a futbolistas ajenos ni corrupción de estados. El exploit económico se conserva; los errores de integridad no.

## 7.4 Configuración

Nuevo juego → Ajustes de nostalgia → “Mercado clásico (bug PC Fútbol 4)” activado por defecto. En modo “Mercado corregido” se obliga a vender exactamente al destinatario de la oferta. La preferencia se guarda en la partida y no se cambia silenciosamente tras una actualización.

# 8. Datos históricos: fuentes, permisos y calidad

## 8.1 Principio de adquisición

No se asumirán permisos de scraping, redistribución o explotación comercial porque una web muestre datos públicamente. Cada conector debe registrar condiciones, atribución, alcance, versión y licencia/contrato. La navegación de páginas se limita a evaluación; la extracción sistemática requiere autorización o una vía explícitamente permitida.

## 8.2 Matriz de fuentes a evaluar

| **Fuente** | **Uso previsto** | **Nota de integración** |
|----|----|----|
| BDFutbol / API BDFutbol | Plantillas, biografías, calendarios, resultados, clasificaciones, cupos por edición. | Fuente prioritaria; ofrece API autenticada y exportaciones a medida. Negociar derechos de uso/redistribución. |
| FootballDatabase.eu | Contrastar plantillas, altas/bajas, trayectorias y fechas. | Cobertura histórica útil; verificar condiciones de reutilización. |
| FBref | Temporadas, clasificaciones y algunos partidos / estadísticas de época. | La cobertura y métricas no son uniformes; revisar términos y límites. |
| Football-Data.co.uk | Resultados de Primera desde 1993-94 y Segunda en temporadas disponibles. | CSV de apoyo; no cubre todo el intervalo solicitado. |
| RSSSF | Verificar clasificaciones, campeones, formatos y competiciones europeas. | Contraste histórico, no fuente única de plantillas. |
| UEFA / fuentes oficiales | Formatos, fechas y resultados de competiciones europeas. | Reglamentos por edición y posibles restricciones de contenido. |
| StatsBomb / hudl open-data | Partidos y eventos selectivos para calibrar comportamiento. | Conjunto parcial pensado para análisis; atribución y acuerdo de uso obligatorios. |
| Transfermarkt | Movimientos, valores de referencia, carreras. | Uso sujeto a autorización; valoración actual/histórica no equivale a atributo jugable. |
| WhoScored, SofaScore, FotMob | Contraste para temporadas recientes con cobertura disponible. | No presumir datos 1982-2010 completos ni permiso para importar. |
| Understat | Calibración xG de épocas recientes, fuera de la mayor parte del periodo. | No prioritaria para reconstrucción de 1982-2010. |
| FootyStats, Futbolme | Resultados y clasificación donde exista cobertura comprobada. | Validar disponibilidad, legalidad y coherencia por edición. |

## 8.3 Jerarquía de evidencia

> 1\. Primera opción: API licenciada, archivo oficial o base con permiso de redistribución explícito.
>
> 2\. Segunda opción: contrastar datos públicos y obtener permiso o fuentes alternativas reutilizables.
>
> 3\. Tercera opción: reconstrucción manual documentada mediante referencias verificables.
>
> 4\. Cuarta opción: atributos jugables estimados, identificados como estimaciones y sujetos a revisión.

## 8.4 Semáforo de calidad por pack

| **Estado** | **Definición** | **Condición para publicación** |
|----|----|----|
| Verificado | Equipos, clasificación, calendario y plantillas contrastados. | Referencia y permisos documentados. |
| Parcial | Información real incompleta (minutos, asistencias, lesiones...). | Campos desconocidos marcados nulos; estimaciones identificadas. |
| Provisional | Contiene una reconstrucción orientativa. | Advertencia dentro del selector de temporada. |
| Bloqueado | Fuente sin autorización o conflicto de licencia. | No distribuir el contenido hasta resolverlo. |

# 9. Modelo de futbolistas y generación de atributos

## 9.1 Datos históricos frente a atributos de videojuego

La base guardará separadamente los hechos documentados (por ejemplo, fecha de nacimiento, club y goles) y los valores de jugabilidad (tiro, pase o aceleración). Para muchas temporadas antiguas no existen métricas observables completas; atribuir cifras “exactas” a todos los futbolistas sería engañoso.

## 9.2 Campos mínimos por jugador-temporada

| **Clase** | **Campos** |
|----|----|
| Identidad | player_id estable, nombre público, fecha de nacimiento cuando conste, nacionalidad, pierna hábil si se conoce. |
| Temporada | season_id, club_id, fecha de alta/baja, dorsal si existe, posición primaria/alternativas. |
| Rendimiento real | partidos, titularidades, minutos (nullable), goles, asistencias (nullable), tarjetas, y fuente por valor. |
| Juego (0–100) | técnica, pase, visión, tiro, definición, velocidad, aceleración, resistencia, fuerza, marcaje, entrada, colocación, portería. |
| Economía | valor de juego, salario, fin de contrato, precio estimado de mercado; todos independientes de datos históricos sin evidencia. |
| Confianza | observado / derivado / estimado, puntuación de confianza y fecha de revisión. |
| Presentación | nombre mostrado por época, país/escudo licenciados u originales, foto si hay derechos; fallback con iniciales. |

## 9.3 Algoritmo inicial de atributos (propuesta)

Normalizar estadísticas por minutos cuando estén disponibles, con percentiles dentro de posición, liga y temporada, y corregir muestras pequeñas por regresión a la media. Los roles de cancha requieren pesos distintos; el goleador no debe dominar necesariamente en pase ni un defensa en velocidad.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr>
<th>atributo = clamp(<br />
media_por_posicion_y_epoca<br />
+ peso_dato * desviacion_estadistica_normalizada<br />
+ ajuste_manual_documentado, 1, 99<br />
)<br />
confianza = función(cobertura_fuentes, muestra_minutos, consistencia, revisión)<br />
si faltan estadísticas: usar arquetipo/posición/edad; marcar "ESTIMADO"</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

La generación debe ser reproducible: cada atributo almacena versión de algoritmo y semilla si incluye variación. Un pequeño panel interno permitirá revisar estrellas y futbolistas modestos antes de publicar un pack.

## 9.4 Desarrollo, retirada y regeneración

Después del inicio histórico de cada campaña, los atributos evolucionan por edad, entrenamiento, minutos, forma, lesiones, potencial y aleatoriedad limitada. No se duplicará al mismo jugador en nuevos clubes. Los jugadores jóvenes generados tendrán identificadores distintos y origen “generado”; podrán coexistir con futbolistas históricos disponibles en el escenario.

## 9.5 Procedencia campo a campo

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr>
<th>FieldEvidence { entity_id, field_name, season_id, source_id,<br />
original_value, normalized_value,<br />
evidence_kind, confidence, checked_at }</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Ejemplo: “goles_1982_83 = 12” puede ser dato verificado; “definición = 84” es un cálculo o estimación del videojuego. La interfaz puede ofrecer un icono discreto para mostrar la procedencia.

# 10. Importación, mantenimiento y editor de datos

## 10.1 ETL controlado fuera de Godot

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr>
<th>Fuente autorizada → Descarga / importación manual → Raw inmutable<br />
→ Parser de origen → Normalización de clubes y personas<br />
→ Deduplicación (identidades y alias) → Validadores históricos<br />
→ Catálogo SQLite de desarrollo → Exportador JSON por temporada<br />
→ Pack con manifest + hash → Pruebas Godot → Publicación</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

SQLite se recomienda para herramientas de preparación y auditoría, no como dependencia obligatoria del juego exportado a Web. En runtime, usar packs de datos de solo lectura y FileAccess para guardados, con interfaces que permitan cambiar el formato más adelante.

## 10.2 Reglas de identidad y migración

- ID interno estable e independiente del ID en un proveedor externo; tablas de aliases y enlaces a cada fuente.

- Clubes con nombres cambiantes, fusiones, desapariciones, filiales y estadios por época; no fusionar por similitud de texto.

- Identidades de jugadores homónimos resueltas por nombre, fecha de nacimiento, trayectoria y evidencia adicional.

- Campos desconocidos = null, nunca cero; separar “no jugó” de “no consta su número de partidos”.

- Registro de importación y validadores: clubes duplicados, jugador en dos equipos a la misma fecha sin traspaso, fechas no válidas y partidos desbalanceados.

- Números auditables: 1982-83 Primera = 18 equipos, 34 jornadas, 306 encuentros; 1995-96 = 22, 42, 462 encuentros.

## 10.3 Pack histórico (estructura recomendada)

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr>
<th>data/seasons/1982-83/<br />
manifest.json # schema_version, sources, checksum<br />
rules.json # puntuación, sustituciones, promociones...<br />
clubs.json # identidades y afiliación de temporada<br />
players.json # datos históricos y atributos de juego<br />
contracts.json # valores lúdicos de arranque<br />
competitions.json # cupos, fases, reglamentos<br />
fixtures.json # fechas / partidos / jornadas<br />
validation_report.json # huecos y fuentes</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 10.4 Estrategia de carga

Solo se carga en memoria el pack de la temporada elegida y las plantillas internacionales necesarias. Los packs pueden distribuirse por lotes con checksum y controles de compatibilidad. Un instalador offline podrá incluir las 29 temporadas; una versión Web futura necesitará descarga diferida y caché para contener peso inicial.

## 10.5 Editor oficial de base de datos y contenido

La base de datos será fácilmente editable sin necesidad de modificar código ni regenerar el juego a mano. Habrá un editor de escritorio oficial, independiente del cliente de juego, desarrollado preferentemente como proyecto Godot de herramientas, con el pipeline Python/SQLite como backend opcional de importación y validación. La edición se efectúa sobre un workspace y se exporta a paquetes reproducibles; no se edita directamente una partida guardada.

| **Función obligatoria** | **Comportamiento y criterio de aceptación** |
|----|----|
| Fichas y tablas | Altas, bajas, edición, búsquedas, filtros y operaciones múltiples para jugadores, clubes, plantillas, temporadas, competiciones, reglas, contratos y estadísticas. |
| Importar CSV masivo | Elegir uno o muchos CSV; detectar delimitador y codificación; asignar columnas a campos; vista previa; importar por temporada y entidad; crear/actualizar/saltar registros. |
| Imágenes en bloque | Importar carpetas completas de escudos, retratos, equipaciones e iconos; relacionar por ID estable, nombre de fichero o tabla CSV; miniaturas y vista previa del resultado. |
| Normalización de imágenes | Validar PNG/WebP/JPEG, dimensiones y proporciones, generar miniaturas y recursos derivados sin destruir originales; detectar ausencias y duplicados. |
| Control de calidad | Validación de IDs, equipos, referencias, formatos, contratos y calendarios; registrar procedencia, atribución y permiso de redistribución por recurso. |
| Edición segura | Vista previa de diferencias, copia de seguridad, deshacer lotes, informes de errores y guardado por transacciones; ningún dato se pierde en una importación fallida. |
| Intercambio | Exportar e importar paquetes completos, packs de temporada y packs solo de apariencia; esquema y versiones documentados. |

## 10.6 Especificación de CSV e importación masiva

- UTF-8 por defecto, con detección y selección manual de codificación; delimitadores coma, punto y coma o tabulador; comillas, fechas, nulos y decimales configurables.

- La primera pantalla mostrará filas de muestra, correspondencias de columnas, claves (player_id, club_id, season_id), filas nuevas, actualizadas, omitidas y conflictivas.

- Plantillas CSV publicadas y exportables desde el editor, por ejemplo players.csv, clubs.csv, memberships.csv, attributes.csv, fixtures.csv, appearances.csv y content_aliases.csv.

- Modo de simulación (dry-run) y posterior confirmación; informe por fila y posibilidad de revertir todo el lote.

- Las imágenes podrán mapearse con un images.csv (entity_type, entity_id, season_id, kind, filename, copyright_status, source, license) o con patrones de nombres configurables.

- Importar un CSV nuevo no podrá sobrescribir silenciosamente ajustes manuales: elegir prioridad y conservar historial de cambios.

```text
# players.csv (formato simplificado del editor)
player_id;season_id;club_id;display_name;position;shooting
player_0001;1982-83;club_001;Jugador Ejemplo;DEL;82
```

```text
# images.csv
entity_type;entity_id;kind;filename;license
player;player_0001;portrait;portraits/player_0001.png;CC0-1.0
```

## 10.7 Packs históricos, packs de identidad y compatibilidad

Separar los hechos históricos y parámetros de jugabilidad (SeasonData) de la capa de nombres, retratos, escudos y demás recursos de presentación (IdentityPack). Un ID interno inmutable relaciona ambos. El selector de packs debe permitir sustituir toda la identidad pública por la privada —y viceversa— sin editar los archivos de temporada ni romper fichajes, contratos, resultados o partidas.

```text
data/seasons/1982-83/... # reglas y datos con IDs estables
content/public/manifest.json # paquete libre/publicable
content/public/overrides/players.csv # player_id -> display_name
content/public/images/players/... # arte original/autorizado
content/public/images/clubs/...

# Fuera del repositorio / instalación personal:
~/.local/share/neofutbol/private-packs/originales.neopack
# manifest: id, schema_version, edition, license, sha256, required_seasons
# prioridad: pack activo -> fallback público -> silueta/placeholder
```

- Todos los paquetes llevan manifest versionado, identificador único, compatibilidad mínima/máxima de juego, hash de integridad y metadatos de derechos y atribución.

- El loader debe comprobar límites de tamaño, rutas seguras, archivos permitidos, IDs desconocidos, incompatibilidades y recursos ausentes; advertir sin inutilizar el juego.

- Activar un paquete será una operación explícita en Ajustes → Contenido; al cambiarlo se refrescan cachés y se conserva la identidad lógica de las entidades.

- Los guardados referencian IDs de futbolistas y clubes y la versión del paquete, no nombres de pantalla o rutas absolutas de imágenes.

- No mezclar el paquete de temporada con el paquete de identidad: así se pueden cambiar escudos y nombres sin duplicar las estadísticas de 29 temporadas.

# 11. Arquitectura en Godot, GitHub y CI

## 11.1 Componentes y límites

| **Capa** | **Responsabilidad** | **No debe hacer** |
|----|----|----|
| Presentación (Scenes/Control) | Pantallas, widgets, navegación, HUD y entradas. | Modificar reglas de negocio directamente. |
| GameApplication | Cambios de pantalla, inyección de dependencias, estados de modo. | Calcular mercado, puntos o traspasos. |
| Domain / Simulation | Contratos de datos, calendario, mercado, economía, partidos, carrera y reglas. | Depender de nodos gráficos o de un sistema operativo. |
| Infrastructure | Lectura de packs, serialización, configuración, adaptadores de archivos. | Alojar la IA del juego ni la lógica de UX. |
| Content tools (Python) | ETL, validación, empaquetado y reportes reproducibles. | Estar incluidos en el ejecutable final. |

## 11.2 Autoloads y servicios propuestos

- GameSession: campaña activa, modo, selección y fecha.

- NavigationService: transiciones y retorno entre pantallas.

- SeasonRepository: consultar packs, búsqueda y manifest.

- RuleEngine: consultar configuración y fases históricas.

- TransferService: ofertas y confirmación atómica, incluida regla retro.

- CalendarService: cola de eventos y avances de fecha.

- MatchService: ejecutar partido rápido o preparar simulador 2D.

- SaveService: versión del esquema, migraciones y escritura segura.

- SettingsService: entrada, accesibilidad, audio y modos clásicos.

## 11.3 Estructura inicial del repositorio

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr>
<th>NEOFutbol/<br />
godot/project.godot<br />
godot/scenes/ui/{main_menu,manager,match,shared}/<br />
godot/scenes/match/{field,actor,ball,hud}/<br />
godot/scripts/domain/{season,team,player,contract,rules}/<br />
godot/scripts/simulation/{calendar,market,economy,match,career}/<br />
godot/scripts/services/{save,data,settings,navigation}/<br />
godot/assets/{themes,fonts,audio,sprites}/<br />
data/schema/<br />
data/seasons/<br />
tools/etl/<br />
tests/{unit,integration,fixtures,regression}/<br />
docs/{design,architecture,data,licenses}/<br />
.github/workflows/</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 11.4 Modelo de entidades (resumen)

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr>
<th>Person (player_id) ↔︎ PlayerSeason (player_id, season_id, club_id)<br />
Club (club_id) ↔︎ ClubSeason (club_id, season_id, division_id)<br />
CompetitionEdition (competition_id, season_id)<br />
Stage → Group → Fixture → MatchResult<br />
Contract (player_id, club_id, starts_at, ends_at, wages)<br />
TransferOffer → TransferEvent<br />
ManagerCareer → Appointment → Objective → SeasonHistory<br />
SaveGame → SeasonSnapshot / EventLog</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 11.5 Eventos y atomicidad

Las acciones de economía emiten eventos con identificador único y quedan registradas antes de actualizar la pantalla. Transferencias = transacción indivisible: comprobar propietario, dinero/cupos, transferir jugador, ajustar saldos, marcar oferta consumida y publicar evento. En caso de error, no se modifica ninguna entidad.

## 11.6 Partidas guardadas

Formato versionado con cabecera, datos comprimidos, manifest de packs, checksum y backup rotatorio. Escritura a fichero temporal + renombrado atómico cuando el sistema lo permita. Opciones: guardado manual, autosave de fin de jornada y tres ranuras de recuperación; migraciones automáticas con copia de seguridad.

## 11.7 Repositorio GitHub público y flujo de trabajo

Requisito explícito: crear y subir el repositorio de NEOFutbol a la cuenta GitHub del desarrollador desde la primera iteración, con rama principal main y código, documentación y assets públicos versionados. El nombre propuesto del repositorio es NEOFutbol; la URL real se fijará al crearlo. Subir el proyecto no implica publicar el paquete privado ni los datos sin licencia.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr>
<th>NEOFutbol/<br />
project.godot<br />
game/ # escenas, lógica y UI<br />
tools/data_editor/ # editor oficial y sus pruebas<br />
tools/importers/ # parsers y validaciones<br />
data/seasons/ # datasets con permiso de redistribución<br />
content/public/ # único pack incluido en GitHub<br />
tests/ # pruebas de reglas y packs<br />
docs/ # GDD/TDD, schema, fuentes, derechos<br />
.github/workflows/ # CI y comprobación de contenido<br />
.gitignore<br />
LICENSE # texto completo de AGPLv3<br />
README.md<br />
CONTRIBUTING.md<br />
THIRD_PARTY_NOTICES.md<br />
CONTENT_LICENSES.md</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 11.8 Exclusiones, controles de publicación y CI

- El paquete privado nunca formará parte del árbol del repositorio. Debe ubicarse fuera de la copia de trabajo y permanecer fuera de los artefactos de releases, pruebas públicas, cachés y adjuntos de incidencias.

- Añadir .gitignore para carpetas de trabajo privadas y extensiones \*.private.neopack; recordar que .gitignore NO elimina del historial archivos ya versionados.

- Usar una lista de archivos permitidos para GitHub Actions y releases: código, docs, tests, pack público y datos autorizados. El pipeline falla si encuentra rutas reservadas, imágenes no autorizadas o manifest con publicación prohibida.

- CI: lint/tests de GDScript y herramientas, validador de CSV y schema, pruebas de importación por lotes y de conmutación de paquetes, exportación Linux y comprobación de licencias.

- Previo a cada git push y release: revisión de git status, git diff --cached, git ls-files, firmas/checksums de los packs y escaneo de archivos binarios/metadata sensible; si se filtrase algo, retirar y tratar el historial remoto como expuesto.

# 12. Interfaz: PC Fútbol 5.0 modernizado

## 12.1 Lenguaje visual

El objetivo es reproducir el patrón de experiencia —despacho, botones icónicos, paneles funcionales, muchas estadísticas en poco espacio— y no copiar píxel por píxel elementos sujetos a derechos. Diseño propio con paleta azul noche, cian/verde, grises de escritorio, ribetes metálicos discretos y tipografía moderna legible.

## 12.2 Pantallas imprescindibles

| **Pantalla** | **Contenido y navegación** |
|----|----|
| Menú principal | Nueva partida, cargar, amistoso, ajustes, créditos y fuente/licencias. |
| Nueva partida | Modo, temporada, división/club, nivel de automatización y exploit clásico. |
| Despacho | Barra de módulos lateral, agenda próxima jornada, noticias, estado económico y clasificación. |
| Plantilla | Tabla ordenable, fichas, comparador de atributos, contratos, estado físico. |
| Tácticas | Campo cenital con arrastre de posiciones, banquillo y órdenes tácticas. |
| Mercado | Buscador, filtros, ofertas, cartera de negociaciones, venta y sustitución retro. |
| Finanzas | Tesorería, salarios, ingresos, gastos, evolución anual y límites. |
| Competiciones | Tabla de ligas, calendario, cuadro de copa, Europa y resultados pasados. |
| Carrera | Objetivos, caché, ofertas, historial de temporadas y logros. |
| Partido | Campo 2D, marcador, reloj, panel de cambios, pausa y resultado. |
| Configuración | Controles, escala, accesibilidad, sonido, idiomas, nostalgia y ayuda. |

## 12.3 Layout de escritorio sugerido

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr>
<th>┌────────────────────────────────────────────────────────────────┐<br />
│ NEOFutbol 82-83 [Despacho] [Plantilla] [Tácticas] [Mercado]│<br />
├─────────────┬──────────────────────────────────────────────────┤<br />
│ LATERAL │ ÁREA PRINCIPAL │<br />
│ Agenda │ Tabla / Campo táctico / Ficha / Competición │<br />
│ Noticias │ │<br />
│ Directiva │ Panel contextual + acciones │<br />
│ Finanzas │ │<br />
├─────────────┴──────────────────────────────────────────────────┤<br />
│ Próximo partido | Presupuesto | Reputación | AVANZAR DÍA │<br />
└────────────────────────────────────────────────────────────────┘</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 12.4 Escalabilidad de pantalla

Diseño base 1600×900 (16:9) adaptable a 1366×768, 1920×1080, 2560×1440 y formatos ultrapanorámicos. Paneles laterales plegables, tablas con scroll y tamaños de letra escalables al 125/150/200 %. Para pantallas táctiles, navegación por pestañas y áreas de pulsación mayores, no una simple reducción del escritorio.

## 12.5 Reglas de UX

- Acciones peligrosas con confirmación y resumen (“Vender B por la oferta original de A”).

- Se puede volver al despacho desde cualquier módulo sin perder edición no confirmada.

- Estado de carga visible al abrir packs; búsquedas y filtros mantienen el foco y la selección.

- Tipografía no depende exclusivamente del pixel-art; soporte de teclado, mando y lector de interfaz cuando sea viable.

- Notificaciones agrupadas por fecha y prioridad; evitar mensajes modales repetitivos al avanzar el calendario.

# 13. Portabilidad y decisiones multiplataforma

## 13.1 Requisitos de arquitectura

Para preservar Web como destino, usar GDScript como lógica principal y renderer Compatibility desde la fase de pruebas. El soporte de C# en Godot 4 no permite actualmente exportar a Web, y componentes nativos como GDExtension introducen limitaciones adicionales; cualquier módulo crítico debe tener alternativa multiplataforma.

| **Plataforma** | **Prioridad** | **Criterio técnico / integración** |
|----|----|----|
| Linux | Lanzamiento | Wayland/X11, paquetes distribuibles y guardado bajo user://. |
| Windows | Futura | Prueba de rutas y exportación, mandos y ventanas de DPI alto. |
| macOS | Futura | Exportación para Intel/Apple Silicon, firma/notarización y archivos. |
| Android | Futura | Toque, pantallas pequeñas, pausa/reanudación, consumo de batería. |
| iOS | Futura | Mac con Xcode para exportar, firma, gestos y gestión de estado. |
| Web | Futura | WebAssembly/WebGL 2 + Compatibility, sin C#, streaming de packs y almacenamiento web. |

## 13.2 Abstracciones

- InputAdapter: teclado, ratón, gamepad, táctil sin suposiciones dentro de MatchState.

- FileStore: lectura de packs y escritura user://; futuro backend para almacenamiento web.

- DisplayProfile: escritorio/ultrapanorámico/táctil con configuración de escala.

- PlatformFeatures: rutas, compartir, abrir URLs, notificaciones y capacidades de la plataforma.

- DataPackProvider: almacenamiento incluido o descarga diferida con validación de versiones.

# 14. IA de despacho, economía y mercado

## 14.1 Oponentes y actividad del mundo

Cada club no dirigido ejecuta un plan de temporada (objetivo, presupuesto, prioridades de fichajes, formación preferida, paciencia con el entrenador). Los agentes realizan negociaciones discretas, renovaciones, ventas e incorporación de jóvenes con una frecuencia acotada para no saturar el buzón ni bloquear las simulaciones.

## 14.2 Dificultad del manager

Separar dificultad de gestión (rivales más eficaces, directivas exigentes, presupuesto más estrecho) de dificultad de partido (marcaje, porteros, ayudas). Un jugador puede elegir simulación arcade fácil y carrera Promanager exigente.

## 14.3 Determinismo y rendimiento

Las decisiones de IA deben ser reproducibles con semilla para test y depuración. Utilizar trabajos incrementales por jornada y presupuestos máximos por frame; realizar pruebas de avance de cien temporadas sintéticas sin intervención de usuario.

# 15. Requisitos no funcionales y pruebas

## 15.1 Rendimiento y estabilidad

| **Área** | **Criterio de aceptación del prototipo** |
|----|----|
| Inicio | Menú interactivo sin cargar todos los packs históricos. |
| Tiempo de avance | Jornada ordinaria ágil; el cronómetro objetivo se fijará tras medir equipos y eventos reales. |
| Partido | No requiere red; simulador jugable en 60 FPS en PC objetivo. |
| Memoria | No se conserva en RAM la base de 29 años; caché por temporada. |
| Fiabilidad | Las transferencias y contratos no admiten duplicados, y el guardado recupera la última jornada. |
| Pruebas | Unitarias de reglas, integración de calendario, snapshots y smoke de exportación. |
| Localización | Textos y números traducibles, fechas y divisas formateadas por región. |

## 15.2 Matriz mínima de QA

> 1\. Crear Liga Manager en 1982-83; terminar temporada, ascender/descender y empezar otra.
>
> 2\. Crear Liga Promanager en Segunda B, incumplir objetivo, ser despedido y aceptar oferta nueva.
>
> 3\. Jugar amistoso interactivo y simular dos IA sin alterar ninguna carrera.
>
> 4\. Comprobar 1986-87 con fases especiales y Segunda B de grupo único.
>
> 5\. Comprobar 1995-96 con 3 puntos por victoria y 42 jornadas.
>
> 6\. Probar finales de competición europea, elegibilidad y arrastre entre temporadas.
>
> 7\. Ejecutar exploit de mercado con A y B, cancelación, doble clic, caducidad y saldo negativo.
>
> 8\. Cargar guardado después de actualización de esquema y después de cambiar pack compatible.
>
> 9\. Validar navegación por teclado, gamepad, escalado 150 % y monitor ultrapanorámico.
>
> 10\. Exportar Linux en CI y, al menos, validar preparación de Web/Windows en cada release.

11\. Importar dos CSV de futbolistas y clubes con actualización, claves duplicadas y nulos; revisar previsualización y rollback.

12\. Importar 500+ imágenes en bloque, incluidas variantes defectuosas; validar mapeo por IDs, miniaturas y licencias.

13\. Conmutar pack público y privado local en una partida guardada: mismas identidades, cambios solo visuales, sin errores de enlace.

14\. Comprobar que el paquete público no contiene imágenes, nombres ni archivos del paquete privado y que CI bloquea filtraciones.

15\. Exportar juego y editor bajo AGPLv3 con código fuente y textos de terceros necesarios; verificar manifest y atribuciones.

## 15.3 Pruebas automáticas de integridad de datos

Para cada edición: suma de partidos local/visitante, ausencia de equipos duplicados, puntos finales recalculados, promociones válidas, jornadas completas, equilibrio de calendarios, fechas monotónicas cuando proceda, y recuentos de plantillas; los reportes se versionan junto al pack.

# 16. Hitos, MVP y prioridades

## 16.1 Entregas de trabajo

| **Hito** | **Entregable** | **Puerta de calidad** |
|----|----|----|
| H0 · Base técnica | Repositorio GitHub público, AGPLv3, .gitignore, CI, esquema de datos y estructura del editor. | Proyecto exportable; push verificado; exclusiones privadas y validadores mínimos correctos. |
| H1 · Vertical slice | 1982-83 Primera, club jugable, calendario, despacho y editor inicial (CSV + importación masiva de imágenes). | Una jornada jugable; editor importa, valida, revierte y exporta un pack de ejemplo. |
| H2 · Partido 2D | 11v11 simple, porteros, pase, tiro, goles, IA, amistoso. | Se puede jugar un encuentro completo y marcar de manera accesible. |
| H3 · Manager básico | Plantillas, contratos, fichajes, finanzas, tácticas, temporada completa. | Cambio de temporada coherente; exploit retro y modo corregido probados. |
| H4 · Carrera y divisiones | Segunda, Segunda B, Promanager, objetivos, historial. | Promoción/despido y ofertas coherentes. |
| H5 · Historia y Europa | 29 packs revisados, excepciones de reglas, copas UEFA/España. | Validadores aprobados por edición y derechos de los datos resueltos. |
| H6 · Pulido y Linux | UI retro-modernizada, configuración de packs, paquete público publicable y paquete personal local, empaquetado Linux. | Release público sin datos privados; pack personal generado e instalado solo localmente desde material de uso autorizado. |
| H7 · Ports | Pruebas en Windows/macOS, luego Android/iOS/Web. | Smoke tests y ajustes por pantalla / almacenamiento. |

## 16.2 MVP propuesto

MVP no equivale a prometer las 29 temporadas terminadas: exige una experiencia de 1 temporada íntegra con datos y reglas fiables. Los escenarios 1986-87, 1995-96 y 2009-10 se incorporan después como packs de regresión antes del lote masivo, por sus cambios estructurales y de época.

## 16.3 Backlog priorizado

| **Prioridad** | **Trabajo** | **Hecho cuando...** |
|----|----|----|
| P0 | Definir schema, identificadores y \`RuleEngine\` por edición. | Dos temporadas de prueba se cargan sin condiciones duras por año. |
| P0 | Desarrollar motor de calendario y clasificación. | Jornadas correctas y puntos ajustados a cada temporada. |
| P0 | Crear vertical slice de partido 2D con tiro y gol. | Flujo partido–resultado–despacho completo. |
| P0 | Prototipar UI del despacho y selector histórico. | Navegación de todos los módulos principales. |
| P1 | TransferService y bug retro parametrizado. | Pruebas automatizadas de operación A→B. |
| P1 | IA de fichajes, objetivos y reputación. | Una temporada Promanager simula ofertas/despido. |
| P1 | Pipeline BDFutbol y contraste histórico. | Pack 1982-83 con trazabilidad documentada. |
| P2 | Copas y Europa completa. | Competiciones correctas por edición. |
| P2 | Ports móviles/web, optimización y mods. | Exportación y UX adaptadas a plataforma. |
| P0 | Repositorio GitHub público + AGPLv3 + separación privada desde el inicio. | Primer push, LICENSE y CI; no existen recursos privados versionados. |
| P0 | Editor con CRUD, plantillas y CSV + importación masiva de imágenes. | Carga 500+ imágenes, previsualiza cambios, detecta conflictos y revierte lotes. |
| P0 | IdentityPack intercambiable por ID y manifest versionado. | Cambiar paquete público/privado de prueba no altera contratos ni guardados. |
| P1 | Informe de derechos y validación de pack público en CI. | Rechaza material no autorizado o paquetes privados en builds y releases. |

# 17. Riesgos y medidas de mitigación

| **Riesgo** | **Impacto** | **Mitigación** |
|----|----|----|
| Licencias de datos, escudos, fotos y marcas | Alto | Negociar permisos, usar recursos propios, empaquetar únicamente datasets autorizados. |
| 29 temporadas × tres divisiones | Alto | ETL automatizado, validadores y entregas por packs con estado de calidad. |
| Variación histórica de reglas | Alto | Motor declarativo y test fixtures por año y competición. |
| UI “clon” de producto existente | Alto | Replicar patrones de uso, no copiar pantallas, bitmaps, código ni audio. |
| Simulación 2D demasiado compleja | Alto | Arcade mínimo primero, métricas de diversión, probar con usuarios. |
| Núcleo incompatible con Web | Medio/alto | GDScript, Compatibility, evitar C# y dependencias nativas críticas. |
| Exploit intencionado rompe la economía | Medio | Separar bug nostálgico de validaciones atómicas y marcar la partida retro. |
| Datos históricos incompletos | Alto | Nulls y etiquetas observados/derivados/estimados; fallback explícito. |
| Crecimiento ilimitado de partidas | Medio | Serialización por snapshots y log compacto, migraciones y backups. |
| Alias y retratos demasiado similares a personas/escudos reales | Alto | La similitud no neutraliza copyright, marca ni imagen personal; diseños originales, revisión caso a caso y alternativas ficticias no confundibles. |
| Filtración de pack privado en Git / release | Alto | Mantener fuera del repositorio, ignore + escaneo de staging y CI, allowlist de publicación y pruebas de no filtración. |
| Desincronización de IDs al cambiar packs | Medio/alto | IDs estables, overlays de presentación, fallback, checksums, pruebas con partidas guardadas. |

# 18. Licencia, propiedad intelectual y packs

El objetivo “clon de PC Fútbol 5.0” se interpreta como referencia de mecánicas y experiencia, no como permiso para reutilizar elementos protegidos del juego original. El nombre final, branding, pantallas, sonidos, música, iconos, ilustraciones y código deben ser propios o tener licencias compatibles con la distribución planeada. Logos oficiales, equipaciones y fotografías requieren revisión individual; los nombres y datos biográficos no garantizan por sí solos derechos de explotación de compilaciones ajenas.

Política de contenido: solo se publicarán recursos originales, de dominio público o con licencias/autorizaciones efectivamente compatibles. Se registrará procedencia y permisos de nombres, recursos y datasets. NEOFutbol dispondrá de dos paquetes intercambiables: público y privado. La distinción no exime de cumplir derechos de terceros.

## 18.1 Licencia principal GNU AGPL versión 3

El código propio de NEOFutbol —juego, editor oficial, importadores y herramientas distribuidas— se publicará bajo GNU Affero General Public License versión 3, con identificador SPDX AGPL-3.0-only, archivo LICENSE completo y avisos de autoría en los archivos pertinentes. Se documentará cómo compilar y obtener el código fuente correspondiente de las versiones distribuidas, y las obligaciones de la AGPL para modificaciones usadas de forma interactiva por red cuando resulten aplicables. Los recursos y datos no adquieren automáticamente AGPL por ir en la misma carpeta: se documentan sus licencias específicas.

## 18.2 Paquetes de contenido: edición pública y edición privada

| **Paquete** | **Qué incluye** | **Destino / restricciones** |
|----|----|----|
| Público (predeterminado) | Nombres de fantasía y recursos de diseño independiente; p. ej., “Roberto Larcos” como alias hipotético de referencia. Retratos, escudos y equipaciones originales o debidamente autorizados. | Se versiona en GitHub y se entrega con el juego solo después de verificar que nombres, diseños, marcas y derechos de imagen no produzcan infracciones o confusión. |
| Privado (personal) | Overlays con nombres auténticos, fotografías, insignias y otros recursos reales únicamente a partir de material que el titular pueda utilizar legalmente. | Paquete local externo para uso personal; no se sube al GitHub, releases, CI, documentación pública ni sistema de distribución. No implica derecho de obtener o copiar recursos sin autorización. |

Entregable obligatorio: generar efectivamente los dos paquetes a partir del mismo conjunto de IDs. El pack público incluirá alias y gráficos publicables; el pack privado tendrá nombres originales y recursos reales que el usuario aporte o cuyo uso esté permitido. Se almacenará solo en un directorio local externo y se probará su activación sin alterar la base de datos común.

## 18.3 Nombres ficticios y revisión de derechos

Ejemplo de nomenclatura: “Roberto Carlos” → “Roberto Larcos”. Es una convención creativa sugerida, NO una fórmula que por sí sola permita eludir derechos. Los nombres, de forma aislada, no se protegen igual que una fotografía o una ilustración; sin embargo, pueden surgir derechos de marca, imagen, competencia desleal o riesgo de confusión. También han de sustituirse recursos visuales protegidos, y el nuevo diseño debe ser original, no una modificación superficial de una fotografía, escudo o sprite ajeno.

- Mantener una tabla de alias ID estable → nombre público / nombre privado; no codificar nombres de personas reales en escenas, tests públicos o textos incluidos en el repositorio.

- La identidad ficticia puede evocar una época o estilo pero debe poder identificarse como obra propia, sin explotar escudos reales ni identidades personales de forma engañosa.

- Antes de publicar, revisar los casos más reconocibles, logos, nombres de clubes, insignias, jugadores, camisetas, tipografías, música y elementos visuales para evitar infracciones y confusión.

- Datos puramente fácticos y compilaciones de datos requieren análisis separado: acceso a sitios web no equivale a permiso de extraer o redistribuir una base de datos; revisar derechos sui generis aplicables y términos de uso.

- En el paquete privado, no incorporar descargas automatizadas de material sin licencia ni distribuir el pack mediante enlaces públicos o repositorios.

## 18.4 Barreras técnicas entre los paquetes

- Por defecto el build y cualquier clon de GitHub solo conocen el IdentityPack público; el pack privado se instala manualmente en una ruta de usuario externa y se selecciona en Ajustes.

- Nada del paquete privado se usa como recurso de compilación esencial, fixture de prueba público, vista previa de GitHub, captura de documentación o material de marketing.

- El editor permite importar y exportar los dos packs pero etiqueta cada archivo como publicable, privado o bloqueado; la exportación pública falla ante recursos de licencia dudosa.

- Una comprobación automática de CI y un informe local de prepublicación verifican lista de archivos, rutas, metadatos, hashes y referencias de manifest; no basta con .gitignore.

Esta sección define una política técnica de publicación; no constituye una opinión jurídica sobre cada nombre o recurso concreto. Si hay dudas, utilizar contenido original plenamente diferenciado y obtener autorización.

# 19. Decisiones abiertas y supuestos documentados

| **Tema** | **Supuesto inicial / propuesta para validar** |
|----|----|
| Fin de periodo | Se incluyen 1982-83 a 2010-11. Si “hasta 2010” significase última 2009-10, solo se ajusta el catálogo. |
| Mundo simulado | España completa (1.ª, 2.ª, 2.ª B) con equipos europeos necesarios para cruces continentales. |
| Plantillas internacionales | Datos completos donde haya licencia; equipos de prueba generados claramente marcados donde no. |
| Mercado clásico | Explotación PC Fútbol 4 activada en partidas Clásicas y disponible opcionalmente en otras. |
| Moneda | Cálculos en unidades internas y presentación de pesetas/euros por época. |
| Duración de partido | Reloj 90 minutos con tiempo real configurable para fomentar sesiones cortas. |
| Progresión | Historia alternativa tras el inicio, sin cargar resultados o fichajes futuros reales automáticamente. |
| Modos online | No previstos para v1; guardar arquitectura de dominio desacoplada por si se estudian. |
| Filosofía UI | Inspiración reconocible sin reproducir imágenes, textos distintivos ni diseños pixel-exactos de terceros. |

# 20. Primera iteración de desarrollo: tareas concretas

El arranque debe demostrar una ruta jugable y verificable, no comenzar copiando miles de fichas sin diseño de datos.

> 1\. Crear repositorio Godot 4.7.2, configuración de exportación Linux y directorios descritos en la sección 11.
>
> 2\. Definir \`SeasonManifest\`, \`CompetitionRules\`, \`ClubSeason\`, \`PlayerSeason\`, \`MatchFixture\` y \`TransferOffer\` con archivos de ejemplo.
>
> 3\. Desarrollar parser de pack 1982-83 y pruebas de Primera: 18 equipos, 34 jornadas, 2 puntos por victoria; comprobar resultado final de muestra.
>
> 4\. Construir menú principal + selector de 1982-83 / pack de prueba + pantalla Despacho con agenda y tabla.
>
> 5\. Crear escenario 2D mínimo con un balón, dos porterías, jugador controlado, portero IA y gol; luego escalar a 11v11.
>
> 6\. Implementar \`CalendarService\` y \`MatchService\` para jugar/simular una jornada y volver al despacho.
>
> 7\. Diseñar la interfaz de venta y prueba automatizada del bug retro sin necesidad de un mercado IA completo.
>
> 8\. Documentar permisos y solicitar al proveedor seleccionado exportaciones históricas reproducibles antes de cualquier ingestión masiva.

9\. Crear el repositorio público NEOFutbol en GitHub, añadir LICENSE AGPL-3.0-only, README, .gitignore y CI; realizar primer push con solo contenido permitido.

10\. Implementar editor mínimo: altas/cambios de jugador y club, plantillas CSV, importación en bloque de imágenes, validación y reversión.

11\. Implementar ContentPackProvider con ID estable y dos paquetes de prueba no sujetos a terceros; probar selección, fallback y cambios sin corruptela en partidas.

12\. Añadir comprobación previa a publicación que rechace cualquier paquete privado, contenido restringido o carente de procedencia verificable.

# 21. Referencias y fuentes consultadas

Consulta documental realizada el 28 de octubre de 2026. Estas referencias permiten verificar factibilidad, cobertura o reglas; no sustituyen una licencia de uso ni constituyen un dataset histórico ya recopilado.

**\[01\] Godot: archivo de versiones (4.7.2 estable en agosto de 2026)\**
https://godotengine.org/download/archive/

**\[02\] Godot 4.7: opciones de exportación\**
https://docs.godotengine.org/en/4.7/tutorials/export/index.html

**\[03\] Godot: exportación Web (restricciones de C# y WebGL 2)\**
https://docs.godotengine.org/es/4.x/tutorials/export/exporting_for_web.html

**\[04\] Godot 4.7: exportación a iOS con Xcode\**
https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html

**\[05\] BDFutbol: ligas históricas\**
https://www.bdfutbol.com/es/t/t.html

**\[06\] BDFutbol: Primera División 1982-83\**
https://www.bdfutbol.com/es/t/t1982-83.html

**\[07\] API BDFutbol: documentación de endpoints\**
https://www.api-bdfutbol.com/es/documentacion/

**\[08\] Football-Data: ficheros españoles y cobertura 1993-94+\**
https://football-data.co.uk/spainm.php

**\[09\] StatsBomb Open Data / hudl: contenido y condiciones\**
https://github.com/hudl/open-data

**\[10\] RSSSF: archivo de competiciones europeas\**
https://www.rsssf.org/ec/ecomp.html

**\[11\] RSSSF: tablas Primera España 1979–1989\**
https://www.rsssf.org/tabless/spanhist7989.html

**\[12\] RSSSF: campeones de Segunda B por grupo\**
https://www.rsssf.org/tabless/span3champ.html

**\[13\] UEFA: historia de reorganizaciones Europa (1992, 1999, 2009)\**
https://es.uefa.com/news-media/news/0211-0f8a33f3ff11-66037883e11c-1000--uefa-decada-de-los-90-y-el-nuevo-milenio/

**\[14\] 1986-87: Segunda fase especial en Primera y Segunda\**
https://www.arefepedia.es/web/Cuadrantes/temp1987.html

**\[15\] FBref: temporadas históricas de La Liga\**
https://fbref.com/en/comps/12/history/La-Liga-Seasons

**\[16\] FootballDatabase: movimientos 1983-84\**
https://dv.footballdatabase.eu/es/competicion/fichajes/246-primera_division/1983-1984

\[17\] GNU: texto oficial de GNU AGPLv3\
https://www.gnu.org/licenses/agpl-3.0.html

\[18\] GitHub Docs: excluir archivos y limitaciones de .gitignore\
https://docs.github.com/en/get-started/git-basics/ignoring-files

# 22. Glosario mínimo

| **Término** | **Definición** |
|----|----|
| GDD | Game Design Document: experiencia, alcance, reglas y modos de juego. |
| TDD | Technical Design Document: arquitectura, interfaces y criterios técnicos. |
| Pack histórico | Archivo versionado de una temporada con datos, fuentes y reglas. |
| Vertical slice | Pequeña sección completamente jugable que valida el producto final. |
| ETL | Extracción, transformación y carga de datos autorizados. |
| Snapshot | Estado consolidado de partida usado para guardado y recuperación. |
| Exploit retro | Comportamiento económico intencionadamente fiel al bug solicitado. |
| IA | Sistema de decisiones de clubes o jugadores controlados por el juego. |
| Editor de datos | Herramienta de escritorio para crear, revisar e importar masivamente registros CSV e imágenes. |
| IdentityPack | Paquete versionado de nombres, retratos, escudos y recursos visuales intercambiable sin cambiar IDs. |
| Pack público | Contenido original o autorizado, preparado para publicación y versionado en GitHub. |
| Pack privado | Overlay local separado del repositorio y no distribuido; no exime de licencias de terceros. |
| AGPL-3.0-only | Licencia GNU Affero GPL versión 3 aplicable al código propio del proyecto. |
