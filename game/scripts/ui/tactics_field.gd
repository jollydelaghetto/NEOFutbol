class_name TacticsField
extends Control

## Catálogo inmutable de posiciones vacías. Las coordenadas normalizadas son
## datos locales de presentación y no constituyen alineaciones ni tácticas
## persistidas. Los roles solo permiten comprobar la distribución visual.
const DEFAULT_FORMATION_ID = "4-4-2"
const FORMATION_IDS: Array[String] = ["4-4-2", "4-3-3", "4-2-3-1"]
const FORMATION_CATALOG: Dictionary = {
	"4-4-2": [
		{"slot_id": "442_gk", "role": "goalkeeper", "label": "POR", "point": Vector2(0.10, 0.50)},
		{"slot_id": "442_def_1", "role": "defender", "label": "DEF 1", "point": Vector2(0.30, 0.18)},
		{"slot_id": "442_def_2", "role": "defender", "label": "DEF 2", "point": Vector2(0.30, 0.39)},
		{"slot_id": "442_def_3", "role": "defender", "label": "DEF 3", "point": Vector2(0.30, 0.61)},
		{"slot_id": "442_def_4", "role": "defender", "label": "DEF 4", "point": Vector2(0.30, 0.82)},
		{"slot_id": "442_mid_1", "role": "midfielder", "label": "MED 1", "point": Vector2(0.55, 0.17)},
		{"slot_id": "442_mid_2", "role": "midfielder", "label": "MED 2", "point": Vector2(0.55, 0.39)},
		{"slot_id": "442_mid_3", "role": "midfielder", "label": "MED 3", "point": Vector2(0.55, 0.61)},
		{"slot_id": "442_mid_4", "role": "midfielder", "label": "MED 4", "point": Vector2(0.55, 0.83)},
		{"slot_id": "442_fwd_1", "role": "forward", "label": "DEL 1", "point": Vector2(0.80, 0.36)},
		{"slot_id": "442_fwd_2", "role": "forward", "label": "DEL 2", "point": Vector2(0.80, 0.64)},
	],
	"4-3-3": [
		{"slot_id": "433_gk", "role": "goalkeeper", "label": "POR", "point": Vector2(0.10, 0.50)},
		{"slot_id": "433_def_1", "role": "defender", "label": "DEF 1", "point": Vector2(0.30, 0.18)},
		{"slot_id": "433_def_2", "role": "defender", "label": "DEF 2", "point": Vector2(0.30, 0.39)},
		{"slot_id": "433_def_3", "role": "defender", "label": "DEF 3", "point": Vector2(0.30, 0.61)},
		{"slot_id": "433_def_4", "role": "defender", "label": "DEF 4", "point": Vector2(0.30, 0.82)},
		{"slot_id": "433_mid_1", "role": "midfielder", "label": "MED 1", "point": Vector2(0.55, 0.26)},
		{"slot_id": "433_mid_2", "role": "midfielder", "label": "MED 2", "point": Vector2(0.55, 0.50)},
		{"slot_id": "433_mid_3", "role": "midfielder", "label": "MED 3", "point": Vector2(0.55, 0.74)},
		{"slot_id": "433_fwd_1", "role": "forward", "label": "DEL 1", "point": Vector2(0.80, 0.20)},
		{"slot_id": "433_fwd_2", "role": "forward", "label": "DEL 2", "point": Vector2(0.80, 0.50)},
		{"slot_id": "433_fwd_3", "role": "forward", "label": "DEL 3", "point": Vector2(0.80, 0.80)},
	],
	"4-2-3-1": [
		{"slot_id": "4231_gk", "role": "goalkeeper", "label": "POR", "point": Vector2(0.09, 0.50)},
		{"slot_id": "4231_def_1", "role": "defender", "label": "DEF 1", "point": Vector2(0.27, 0.18)},
		{"slot_id": "4231_def_2", "role": "defender", "label": "DEF 2", "point": Vector2(0.27, 0.39)},
		{"slot_id": "4231_def_3", "role": "defender", "label": "DEF 3", "point": Vector2(0.27, 0.61)},
		{"slot_id": "4231_def_4", "role": "defender", "label": "DEF 4", "point": Vector2(0.27, 0.82)},
		{"slot_id": "4231_pivot_1", "role": "midfielder", "label": "PIV 1", "point": Vector2(0.45, 0.35)},
		{"slot_id": "4231_pivot_2", "role": "midfielder", "label": "PIV 2", "point": Vector2(0.45, 0.65)},
		{"slot_id": "4231_am_1", "role": "midfielder", "label": "MP 1", "point": Vector2(0.63, 0.22)},
		{"slot_id": "4231_am_2", "role": "midfielder", "label": "MP 2", "point": Vector2(0.63, 0.50)},
		{"slot_id": "4231_am_3", "role": "midfielder", "label": "MP 3", "point": Vector2(0.63, 0.78)},
		{"slot_id": "4231_fwd", "role": "forward", "label": "DEL", "point": Vector2(0.82, 0.50)},
	],
}

## Alias de compatibilidad para el contrato inicial del PR #38.
const REFERENCE_POSITIONS: Array = FORMATION_CATALOG[DEFAULT_FORMATION_ID]

const FIELD_COLOR = Color("174f3a")
const LINE_COLOR = Color("d8eee5")
const MARKER_COLOR = Color("19a9ad")
const MARKER_BORDER_COLOR = Color("b9fff4")
const SELECTED_MARKER_COLOR = Color("f5b942")
const SELECTED_RING_COLOR = Color("fff1a8")
const FOCUS_COLOR = Color("78e7da")

signal selection_changed(position)
signal position_confirmed(position: Dictionary)

var _formation_id := DEFAULT_FORMATION_ID
var _selected_slot_id := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	resized.connect(queue_redraw)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(queue_redraw)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		var slot_id = _slot_at_position(event.position)
		if not slot_id.is_empty():
			select_slot(slot_id)
			grab_focus()
		accept_event()
		return
	if event.is_action_pressed("ui_left"):
		_navigate_selection(Vector2.LEFT)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		_navigate_selection(Vector2.RIGHT)
		accept_event()
	elif event.is_action_pressed("ui_up"):
		_navigate_selection(Vector2.UP)
		accept_event()
	elif event.is_action_pressed("ui_down"):
		_navigate_selection(Vector2.DOWN)
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		if _selected_slot_id.is_empty():
			_select_first_position()
		var selected = get_selected_position()
		if selected != null:
			position_confirmed.emit(selected)
		accept_event()


func _draw() -> void:
	var pitch = get_pitch_rect()
	if pitch.size.x <= 0.0 or pitch.size.y <= 0.0:
		return
	draw_rect(pitch, FIELD_COLOR, true)
	draw_rect(pitch, LINE_COLOR, false, 2.0)
	var halfway_x = pitch.position.x + pitch.size.x * 0.5
	draw_line(
		Vector2(halfway_x, pitch.position.y),
		Vector2(halfway_x, pitch.end.y), LINE_COLOR, 2.0
	)
	var center = pitch.get_center()
	var center_radius = pitch.size.y * 0.14
	draw_arc(center, center_radius, 0.0, TAU, 64, LINE_COLOR, 2.0)
	draw_circle(center, 3.0, LINE_COLOR)
	_draw_penalty_area(pitch, true)
	_draw_penalty_area(pitch, false)
	_draw_goal(pitch, true)
	_draw_goal(pitch, false)
	if has_focus():
		draw_rect(pitch.grow(4.0), FOCUS_COLOR, false, 3.0)
	var font = get_theme_default_font()
	for slot in FORMATION_CATALOG[_formation_id]:
		var marker_center = _marker_center(pitch, slot.point)
		var radius = _marker_radius(pitch)
		var is_selected: bool = slot.slot_id == _selected_slot_id
		if is_selected:
			draw_arc(marker_center, radius + 5.0, 0.0, TAU, 40, SELECTED_RING_COLOR, 3.0)
		draw_circle(
			marker_center, radius,
			SELECTED_MARKER_COLOR if is_selected else MARKER_COLOR
		)
		draw_arc(marker_center, radius, 0.0, TAU, 32, MARKER_BORDER_COLOR, 2.0)
		var label_size = font.get_string_size(slot.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(
			font, marker_center + Vector2(-label_size.x * 0.5, 4.0),
			slot.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE
		)


func set_formation(formation_id: String) -> Dictionary:
	if not FORMATION_CATALOG.has(formation_id):
		return {
			"ok": false,
			"data": null,
			"errors": [{
				"code": "unknown_reference_formation",
				"formation_id": formation_id,
				"message": "La formación de referencia solicitada no existe.",
			}],
		}
	if _formation_id != formation_id:
		_formation_id = formation_id
		clear_selection()
	queue_redraw()
	return {
		"ok": true,
		"data": {
			"formation_id": _formation_id,
			"position_count": FORMATION_CATALOG[_formation_id].size(),
		},
		"errors": [],
	}


func get_formation_id() -> String:
	return _formation_id


## Devuelve una copia defensiva de la posición seleccionada o null.
func get_selected_position() -> Variant:
	var selected = _position_by_slot(_selected_slot_id)
	return null if selected.is_empty() else selected.duplicate(true)


## Selecciona una posición de la formación visible. Un identificador desconocido
## conserva la última selección válida y devuelve un diagnóstico estructurado.
func select_slot(slot_id: String) -> Dictionary:
	var selected = _position_by_slot(slot_id)
	if selected.is_empty():
		return {
			"ok": false,
			"data": null,
			"errors": [{
				"code": "unknown_tactical_position",
				"slot_id": slot_id,
				"formation_id": _formation_id,
				"message": "La posición táctica solicitada no existe en la formación.",
			}],
		}
	if _selected_slot_id != slot_id:
		_selected_slot_id = slot_id
		queue_redraw()
		selection_changed.emit(selected.duplicate(true))
	return {"ok": true, "data": selected.duplicate(true), "errors": []}


func clear_selection() -> Dictionary:
	if not _selected_slot_id.is_empty():
		_selected_slot_id = ""
		queue_redraw()
		selection_changed.emit(null)
	return {"ok": true, "data": null, "errors": []}


func get_reference_positions(formation_id: String = "") -> Array[Dictionary]:
	var requested = _formation_id if formation_id.is_empty() else formation_id
	var positions: Array[Dictionary] = []
	if not FORMATION_CATALOG.has(requested):
		return positions
	for slot in FORMATION_CATALOG[requested]:
		positions.append(slot.duplicate(true))
	return positions


func get_pitch_rect() -> Rect2:
	var margin = maxf(10.0, minf(size.x, size.y) * 0.04)
	return Rect2(Vector2(margin, margin), size - Vector2(margin * 2.0, margin * 2.0))


func get_marker_rects() -> Array[Dictionary]:
	var pitch = get_pitch_rect()
	var radius = _marker_radius(pitch)
	var markers: Array[Dictionary] = []
	for slot in FORMATION_CATALOG[_formation_id]:
		var center = _marker_center(pitch, slot.point)
		markers.append({
			"slot_id": slot.slot_id,
			"role": slot.role,
			"rect": Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)),
		})
	return markers


func _on_focus_entered() -> void:
	if _selected_slot_id.is_empty():
		_select_first_position()
	queue_redraw()


func _select_first_position() -> void:
	var positions: Array = FORMATION_CATALOG[_formation_id]
	if not positions.is_empty():
		select_slot(positions[0].slot_id)


func _slot_at_position(local_position: Vector2) -> String:
	for marker in get_marker_rects():
		var center: Vector2 = marker.rect.get_center()
		var radius: float = marker.rect.size.x * 0.5
		if center.distance_to(local_position) <= radius:
			return marker.slot_id
	return ""


func _position_by_slot(slot_id: String) -> Dictionary:
	if slot_id.is_empty():
		return {}
	for slot in FORMATION_CATALOG[_formation_id]:
		if slot.slot_id == slot_id:
			return slot
	return {}


## Elige el candidato del semiplano solicitado ponderando primero la cercanía
## visual y después el desvío perpendicular. slot_id resuelve empates de forma
## estable, sin convertirlo en un criterio deportivo.
func _navigate_selection(direction: Vector2) -> void:
	if _selected_slot_id.is_empty():
		_select_first_position()
		return
	var current = _position_by_slot(_selected_slot_id)
	if current.is_empty():
		_select_first_position()
		return
	var best_slot_id := ""
	var best_score := INF
	for candidate in FORMATION_CATALOG[_formation_id]:
		if candidate.slot_id == _selected_slot_id:
			continue
		var delta: Vector2 = candidate.point - current.point
		var forward = delta.dot(direction)
		if forward <= 0.0001:
			continue
		var perpendicular = absf(delta.cross(direction))
		var score = delta.length() + perpendicular * 2.0
		if score < best_score - 0.0001 or (
				is_equal_approx(score, best_score) and candidate.slot_id < best_slot_id):
			best_score = score
			best_slot_id = candidate.slot_id
	if not best_slot_id.is_empty():
		select_slot(best_slot_id)


func _draw_penalty_area(pitch: Rect2, left: bool) -> void:
	var area_size = Vector2(pitch.size.x * 0.16, pitch.size.y * 0.46)
	var x = pitch.position.x if left else pitch.end.x - area_size.x
	var area = Rect2(Vector2(x, pitch.get_center().y - area_size.y * 0.5), area_size)
	draw_rect(area, LINE_COLOR, false, 2.0)


func _draw_goal(pitch: Rect2, left: bool) -> void:
	var depth = pitch.size.x * 0.025
	var goal_height = pitch.size.y * 0.18
	var x = pitch.position.x - depth if left else pitch.end.x
	var goal = Rect2(Vector2(x, pitch.get_center().y - goal_height * 0.5),
		Vector2(depth, goal_height))
	draw_rect(goal, LINE_COLOR, false, 2.0)


func _marker_center(pitch: Rect2, point: Vector2) -> Vector2:
	return pitch.position + Vector2(pitch.size.x * point.x, pitch.size.y * point.y)


func _marker_radius(pitch: Rect2) -> float:
	return clampf(minf(pitch.size.x, pitch.size.y) * 0.045, 8.0, 18.0)
