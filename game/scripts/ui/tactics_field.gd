class_name TacticsField
extends Control

## Posiciones vacías de referencia para la maqueta 4-4-2. Estas coordenadas
## normalizadas pertenecen exclusivamente a la presentación y no constituyen
## una alineación, una táctica persistida ni un modelo deportivo.
const REFERENCE_POSITIONS: Array[Dictionary] = [
	{"slot_id": "gk", "role": "goalkeeper", "label": "POR", "point": Vector2(0.10, 0.50)},
	{"slot_id": "def_1", "role": "defender", "label": "DEF 1", "point": Vector2(0.30, 0.18)},
	{"slot_id": "def_2", "role": "defender", "label": "DEF 2", "point": Vector2(0.30, 0.39)},
	{"slot_id": "def_3", "role": "defender", "label": "DEF 3", "point": Vector2(0.30, 0.61)},
	{"slot_id": "def_4", "role": "defender", "label": "DEF 4", "point": Vector2(0.30, 0.82)},
	{"slot_id": "mid_1", "role": "midfielder", "label": "MED 1", "point": Vector2(0.55, 0.17)},
	{"slot_id": "mid_2", "role": "midfielder", "label": "MED 2", "point": Vector2(0.55, 0.39)},
	{"slot_id": "mid_3", "role": "midfielder", "label": "MED 3", "point": Vector2(0.55, 0.61)},
	{"slot_id": "mid_4", "role": "midfielder", "label": "MED 4", "point": Vector2(0.55, 0.83)},
	{"slot_id": "fwd_1", "role": "forward", "label": "DEL 1", "point": Vector2(0.80, 0.36)},
	{"slot_id": "fwd_2", "role": "forward", "label": "DEL 2", "point": Vector2(0.80, 0.64)},
]

const FIELD_COLOR = Color("174f3a")
const LINE_COLOR = Color("d8eee5")
const MARKER_COLOR = Color("19a9ad")
const MARKER_BORDER_COLOR = Color("b9fff4")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	resized.connect(queue_redraw)


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
	var font = get_theme_default_font()
	for slot in REFERENCE_POSITIONS:
		var marker_center = _marker_center(pitch, slot.point)
		var radius = _marker_radius(pitch)
		draw_circle(marker_center, radius, MARKER_COLOR)
		draw_arc(marker_center, radius, 0.0, TAU, 32, MARKER_BORDER_COLOR, 2.0)
		var label_size = font.get_string_size(slot.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(
			font, marker_center + Vector2(-label_size.x * 0.5, 4.0),
			slot.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE
		)


func get_reference_positions() -> Array[Dictionary]:
	return REFERENCE_POSITIONS.duplicate(true)


func get_pitch_rect() -> Rect2:
	var margin = maxf(10.0, minf(size.x, size.y) * 0.04)
	return Rect2(Vector2(margin, margin), size - Vector2(margin * 2.0, margin * 2.0))


func get_marker_rects() -> Array[Dictionary]:
	var pitch = get_pitch_rect()
	var radius = _marker_radius(pitch)
	var markers: Array[Dictionary] = []
	for slot in REFERENCE_POSITIONS:
		var center = _marker_center(pitch, slot.point)
		markers.append({
			"slot_id": slot.slot_id,
			"role": slot.role,
			"rect": Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)),
		})
	return markers


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
