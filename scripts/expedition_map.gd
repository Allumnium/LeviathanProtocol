extends Control

# Informational strategic map bound to the live expedition: discovered
# locations, the fleet's real position, its planned route and fuel range.
# Destinations are still chosen through the departure dialog.
signal location_selected(id: String)

const STATION_TEXTURE: Texture2D = preload("res://assets/space_station.png")
const PlaceholderAssets = preload("res://scripts/placeholders.gd")
const REGIONS := [Vector2(-120.0, 780.0), Vector2(780.0, 1600.0), Vector2(1600.0, 2200.0)]

var camera_position := Vector2(380, 0)
var camera_zoom := 0.0
# Frame all discovered locations until the player pans or zooms the map.
var user_moved := false
var selected_id := ""
var starfield: Control
var _dragging := false
var _drag_moved := false
var _pulse := 0.0
var _flagship_texture: Texture2D

func _ready() -> void:
	clip_contents = true
	focus_mode = FOCUS_NONE
	starfield = load("res://scripts/main_menu_starfield.gd").new()
	starfield.stationary = true
	starfield.set_area(GameState.run_seed, 0)
	starfield.show_behind_parent = true
	starfield.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(starfield)
	starfield.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for owned: HangarShip in GameState.fleet:
		if owned.flagship:
			_flagship_texture = SurfaceArt.diffuse(owned.art_texture)
	resized.connect(_fit_default)
	_fit_default.call_deferred()

func _fit_default() -> void:
	if user_moved or size.x <= 0.0:
		return
	var simulation = GameState.expedition_simulation
	if simulation == null:
		return
	var bounds := Rect2(simulation.state.position_nu, Vector2.ZERO)
	for id: String in simulation.state.discovered_location_ids:
		var location: Dictionary = simulation.locations.get(id, {})
		if not location.is_empty():
			bounds = bounds.expand(_position(location))
	var margin := Vector2(60, 40)
	camera_zoom = clampf(minf((size.x - margin.x * 2) / maxf(bounds.size.x, 1.0),
			(size.y - margin.y * 2) / maxf(bounds.size.y, 1.0)), 0.15, 5.0)
	camera_position = bounds.get_center()
	queue_redraw()

func to_screen(point: Vector2) -> Vector2:
	return size * 0.5 + (point - camera_position) * camera_zoom

func _process(delta: float) -> void:
	if is_visible_in_tree():
		_pulse = fmod(_pulse + delta, 2.0)
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var anchor: Vector2 = camera_position + (event.position - size * 0.5) / camera_zoom
			camera_zoom = clampf(camera_zoom * (1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), 0.15, 5.0)
			camera_position = anchor - (event.position - size * 0.5) / camera_zoom
			user_moved = true
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				_dragging = true
				_drag_moved = false
			else:
				_dragging = false
				if event.button_index == MOUSE_BUTTON_LEFT and not _drag_moved:
					_select_at(event.position)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		if event.relative.length() > 0.5:
			_drag_moved = true
			user_moved = true
		camera_position -= event.relative / camera_zoom
		accept_event()

func _select_at(point: Vector2) -> void:
	var simulation = GameState.expedition_simulation
	if simulation == null:
		return
	var best := ""
	var best_distance := 18.0
	for id: String in simulation.state.discovered_location_ids:
		var location: Dictionary = simulation.locations.get(id, {})
		if location.is_empty():
			continue
		var distance := to_screen(_position(location)).distance_to(point)
		if distance < best_distance:
			best = id
			best_distance = distance
	if best != selected_id:
		selected_id = best
		AudioManager.play_ui_sfx(&"detail")
		location_selected.emit(best)

func _position(location: Dictionary) -> Vector2:
	return Vector2(location.position[0], location.position[1])

func _draw() -> void:
	var simulation = GameState.expedition_simulation
	if simulation == null or camera_zoom <= 0.0:
		return
	var state = simulation.state
	var font := get_theme_font("font", "Label")
	var line := get_theme_color("font_color", "Label")
	# Act regions: unlocked space is faintly lit, locked space is shaded.
	var unlocked_acts := 2 if state.flags.get("leviathan_protocol", false) else 1
	for index in range(REGIONS.size()):
		var region: Vector2 = REGIONS[index]
		var left := to_screen(Vector2(region.x, -400)).x
		var right := to_screen(Vector2(region.y, 400)).x
		var rect := Rect2(Vector2(left, 0), Vector2(right - left, size.y))
		if index < unlocked_acts:
			draw_rect(rect, Color(0.2, 0.55, 0.65, 0.05))
		else:
			draw_rect(rect, Color(0, 0, 0, 0.45))
		draw_line(Vector2(right, 0), Vector2(right, size.y), Color(line, 0.15), 1.0)
	# Fuel range.
	var fleet := to_screen(state.position_nu)
	var range_nu: float = state.fuel / float(simulation.tuning.fuel_per_nav_unit)
	draw_arc(fleet, range_nu * camera_zoom, 0, TAU, 96, Color(0.45, 0.85, 1.0, 0.25), 1.0)
	# Planned route and retained detour return.
	if not state.destination_location_id.is_empty():
		var target := to_screen(_position(simulation.locations[state.destination_location_id]))
		_dashed(fleet, target, Color(0.45, 0.95, 1.0, 0.9))
		if not state.return_destination_id.is_empty():
			var back := to_screen(_position(simulation.locations[state.return_destination_id]))
			_dashed(target, back, Color(1.0, 1.0, 1.0, 0.3))
	var placed_labels: Array[Rect2] = []
	var label_font_size := get_theme_font_size("font_size", "HeaderResearch")
	for id: String in state.discovered_location_ids:
		var known: Dictionary = simulation.locations.get(id, {})
		if not known.is_empty():
			var reserve := 18.0 if known.kind == "station" else 10.0
			placed_labels.append(Rect2(to_screen(_position(known)) - Vector2.ONE * reserve * 0.5, Vector2.ONE * reserve))
	for id: String in state.discovered_location_ids:
		var location: Dictionary = simulation.locations.get(id, {})
		if location.is_empty():
			continue
		var point := to_screen(_position(location))
		var accessible: bool = simulation.location_accessible(location)
		var tint := Color.WHITE if accessible else Color(1, 1, 1, 0.35)
		var icon := 18.0 if location.kind == "station" else 10.0
		var texture: Texture2D = STATION_TEXTURE if location.kind == "station" else PlaceholderAssets.art()
		draw_texture_rect(texture, Rect2(point - Vector2.ONE * icon * 0.5, Vector2.ONE * icon), false, tint)
		if id == selected_id:
			draw_arc(point, icon * 0.9, 0, TAU, 32, Color(1, 1, 1, 0.9), 1.0)
		if location.kind == "gate" and accessible and not GameState.completed:
			draw_arc(point, icon * (1.0 + 0.3 * absf(_pulse - 1.0)), 0, TAU, 32, Color(1.0, 0.45, 0.4, 0.8), 1.0)
		var label: String = location.name
		if id in state.visited_location_ids and location.kind != "station":
			var mark := point + Vector2(icon * 0.45, -icon * 0.55)
			draw_polyline(PackedVector2Array([mark, mark + Vector2(2, 2), mark + Vector2(6, -3)]), Color("6be38a"), 1.0)
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size)
		var below := Rect2(point + Vector2(-text_size.x * 0.5, icon * 0.5 + 1), text_size)
		var above := Rect2(point + Vector2(-text_size.x * 0.5, -icon * 0.5 - 1 - text_size.y), text_size)
		var spot := Rect2()
		for candidate: Rect2 in [below, above]:
			if not placed_labels.any(func(other: Rect2) -> bool: return other.intersects(candidate)):
				spot = candidate
				break
		if spot.size == Vector2.ZERO and id != selected_id:
			continue
		if spot.size == Vector2.ZERO:
			spot = below
		placed_labels.append(spot)
		draw_string(font, spot.position + Vector2(0, font.get_ascent(label_font_size)), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size, Color(line, 0.9 if accessible else 0.4))
	# Fleet marker, pointing along the active course.
	var heading := Vector2.UP
	if not state.destination_location_id.is_empty():
		var delta: Vector2 = _position(simulation.locations[state.destination_location_id]) - state.position_nu
		if delta.length() > 0.001:
			heading = delta.normalized()
	if _flagship_texture != null:
		draw_set_transform(fleet, heading.angle() + PI * 0.5, Vector2.ONE)
		draw_texture_rect(_flagship_texture, Rect2(Vector2(-7, -8), Vector2(14, 16)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(fleet, 5, Color(0.45, 0.95, 1.0))
	draw_arc(fleet, 11 + 2 * absf(_pulse - 1.0), 0, TAU, 32, Color(0.45, 0.95, 1.0, 0.6), 1.0)

func _dashed(from: Vector2, to: Vector2, color: Color) -> void:
	var length := from.distance_to(to)
	if length <= 1.0:
		return
	var direction := (to - from) / length
	var cursor := 0.0
	while cursor < length:
		var end := minf(cursor + 8.0, length)
		draw_line(from + direction * cursor, from + direction * end, color, 1.5)
		cursor += 14.0
