class_name GraphView
extends Control

signal destination_selected(node_id: int)
signal travel_finished

const NODE_SIZE := Vector2(28.0, 28.0)
const NODE_HIT_RADIUS := 24.0
const WORLD_SIZE := Vector2(1800.0, 420.0)
const MIN_ZOOM := 0.2
const MAX_ZOOM := 3.0
const ZOOM_FACTOR := 1.15
const KEYBOARD_PAN_SPEED := 300.0
const DRAG_THRESHOLD := 4.0
const SECTOR_STAR_TEXTURE: Texture2D = preload("res://assets/star1.png")
const STAR_FRAME_COUNT := 6
const STAR_FRAME_SIZE := Vector2(32.0, 29.0)
const STAR_FRAMES_PER_SECOND := 6.0
const STAR_CLICK_DURATION := 0.8
const FLEET_PREVIEW_SCRIPT = preload("res://scripts/fleet_ship_preview.gd")

var current_node_id := 0
var selected_node_id := -1
var camera_position := WORLD_SIZE * 0.5
var camera_zoom := 1.0
var stars := PackedVector2Array()
var _dragging := false
var _drag_moved := false
var _drag_start := Vector2.ZERO
var _elapsed_time := 0.0
var _node_click_remaining: Dictionary = {}
var _fleet_preview
var _traveling := false
var _travel_elapsed := 0.0
var _travel_duration := 2.0
var _travel_start := Vector2.ZERO
var _travel_end := Vector2.ZERO
var _ship_world_position := Vector2.ZERO
var _ship_rotation := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(queue_redraw)
	var random := RandomNumberGenerator.new()
	random.seed = 4815
	for index in range(450):
		stars.append(Vector2(
			random.randf_range(-1800.0, 1800.0),
			random.randf_range(-1400.0, 1400.0)
		))
	_fleet_preview = FLEET_PREVIEW_SCRIPT.new()
	_fleet_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fleet_preview)
	_refresh_fleet_preview()
	GameState.fleet_changed.connect(_refresh_fleet_preview)
	queue_redraw()


func set_current_node(node_id: int) -> void:
	current_node_id = node_id
	selected_node_id = -1
	_reset_camera()
	_ship_world_position = _node_center(current_node_id)
	_ship_rotation = 0.0
	_update_fleet_preview_transform()
	queue_redraw()


func _process(delta: float) -> void:
	if _traveling:
		_travel_elapsed = minf(_travel_elapsed + delta, _travel_duration)
		var progress := _travel_elapsed / _travel_duration
		var eased_progress := progress * progress * (3.0 - 2.0 * progress)
		_ship_world_position = _travel_start.lerp(_travel_end, eased_progress)
		_update_fleet_preview_transform()
		if is_equal_approx(_travel_elapsed, _travel_duration):
			_traveling = false
			travel_finished.emit()
	if not is_visible_in_tree():
		return
	_elapsed_time += delta
	for node_id in _node_click_remaining.keys():
		var remaining := float(_node_click_remaining[node_id]) - delta
		if remaining <= 0.0:
			_node_click_remaining.erase(node_id)
		else:
			_node_click_remaining[node_id] = remaining
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	)
	if not direction.is_zero_approx():
		camera_position += direction.normalized() * KEYBOARD_PAN_SPEED * delta / camera_zoom
	_update_fleet_preview_transform()
	queue_redraw()


func world_transform() -> Transform2D:
	return Transform2D(
		0.0,
		Vector2.ONE * camera_zoom,
		0.0,
		size * 0.5 - camera_position * camera_zoom
	)


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return world_transform().affine_inverse() * screen_position


func _reset_camera() -> void:
	camera_position = _node_center(current_node_id)
	camera_zoom = clampf(
		minf(size.y / WORLD_SIZE.y, 1.0),
		MIN_ZOOM,
		1.0
	)


func start_travel(destination_node_id: int, duration: float = 2.0) -> void:
	_travel_start = _node_center(current_node_id)
	_travel_end = _node_center(destination_node_id)
	_ship_world_position = _travel_start
	_ship_rotation = (_travel_end - _travel_start).angle()
	_travel_duration = maxf(duration, 0.01)
	_travel_elapsed = 0.0
	_traveling = true
	_update_fleet_preview_transform()


func _refresh_fleet_preview() -> void:
	if _fleet_preview == null:
		return
	_fleet_preview.owned = _representative_ship()
	_fleet_preview.visible = _fleet_preview.owned != null
	_fleet_preview.queue_redraw()
	_update_fleet_preview_transform()


func _representative_ship() -> FleetShip:
	for design_name in GameState.fleet_design_slots:
		if design_name.is_empty():
			continue
		for owned in GameState.fleet:
			if _ship_type_name(owned.display_name) == design_name:
				return owned
	return null


func _ship_type_name(display_name: String) -> String:
	var pieces := display_name.rsplit(" ", true, 1)
	return pieces[0] if pieces.size() == 2 and pieces[1].is_valid_int() else display_name


func _update_fleet_preview_transform() -> void:
	if _fleet_preview == null:
		return
	var preview_size := Vector2.ONE * 21.0 * camera_zoom
	_fleet_preview.size = preview_size
	_fleet_preview.pivot_offset = preview_size * 0.5
	_fleet_preview.position = world_transform() * _ship_world_position - preview_size * 0.5
	_fleet_preview.rotation = _ship_rotation


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK, true)
	draw_set_transform_matrix(world_transform())
	for star in stars:
		draw_circle(star, 1.0, Color(0.3, 0.4, 0.5, 0.65))
	var reachable_nodes := GameState.get_reachable_nodes(current_node_id)

	for edge in GameState.GRAPH_EDGES:
		var edge_color := Color(0.32, 0.32, 0.32)
		if current_node_id == edge.x:
			edge_color = Color(0.48, 0.48, 0.48)
		if GameState.visited_nodes.has(edge.x) and GameState.visited_nodes.has(edge.y):
			edge_color = Color(0.22, 0.58, 0.66)
		_draw_arrow(edge.x, edge.y, edge_color)

	for node_id in range(GameState.NODE_POSITIONS.size()):
		var center := _node_center(node_id)
		var star_color := Color(0.58, 0.58, 0.62)

		if GameState.visited_nodes.has(node_id):
			star_color = Color(0.35, 0.68, 0.76)
		if reachable_nodes.has(node_id):
			star_color = Color(0.62, 0.82, 0.88)
		if node_id == current_node_id:
			star_color = Color(0.35, 0.9, 1.0)
		if node_id == selected_node_id:
			star_color = Color(1.0, 0.78, 0.3)
		_draw_sector_star(node_id, center, star_color)


func _draw_sector_star(node_id: int, center: Vector2, tint: Color) -> void:
	var twinkle := 0.5 + 0.5 * sin(_elapsed_time * (1.25 + node_id * 0.11) + node_id * 1.73)
	var click_progress := float(_node_click_remaining.get(node_id, 0.0)) / STAR_CLICK_DURATION
	var click_pulse := click_progress * click_progress
	var scale := (0.88 + twinkle * 0.16) * (1.0 + click_pulse * 0.75)
	var brightness := 0.62 + twinkle * 0.38
	var sprite_size := Vector2(
		NODE_SIZE.x * scale,
		NODE_SIZE.x * scale * STAR_FRAME_SIZE.y / STAR_FRAME_SIZE.x
	)
	var frame_index := (
		floori(_elapsed_time * STAR_FRAMES_PER_SECOND + node_id * 1.37)
		% STAR_FRAME_COUNT
	)
	var source_rect := Rect2(
		Vector2(frame_index * STAR_FRAME_SIZE.x, 0.0),
		STAR_FRAME_SIZE
	)
	draw_circle(center, NODE_SIZE.x * 0.72 * scale, Color(tint.r, tint.g, tint.b, 0.08 * brightness))
	draw_texture_rect_region(
		SECTOR_STAR_TEXTURE,
		Rect2(center - sprite_size * 0.5, sprite_size),
		source_rect,
		Color(tint.r, tint.g, tint.b, brightness)
	)


func _gui_input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null:
		if mouse_button.pressed and mouse_button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var world_under_cursor := _screen_to_world(mouse_button.position)
			var factor := ZOOM_FACTOR if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_FACTOR
			camera_zoom = clampf(camera_zoom * factor, MIN_ZOOM, MAX_ZOOM)
			camera_position = world_under_cursor - (mouse_button.position - size * 0.5) / camera_zoom
			queue_redraw()
			accept_event()
			return
		if mouse_button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if mouse_button.pressed:
				_dragging = true
				_drag_moved = false
				_drag_start = mouse_button.position
				accept_event()
				return
			if _dragging:
				_dragging = false
				if not _drag_moved and mouse_button.button_index == MOUSE_BUTTON_LEFT:
					_select_node_at(_screen_to_world(mouse_button.position))
				accept_event()
				return

	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion == null or not _dragging:
		return
	if not _drag_moved and mouse_motion.position.distance_to(_drag_start) >= DRAG_THRESHOLD:
		_drag_moved = true
	if _drag_moved:
		camera_position -= mouse_motion.relative / camera_zoom
		queue_redraw()
	accept_event()


func _select_node_at(world_position: Vector2) -> void:
	var nearest_node := -1
	var nearest_distance := NODE_HIT_RADIUS
	for node_id in range(GameState.NODE_POSITIONS.size()):
		var distance := _node_center(node_id).distance_to(world_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest_node = node_id
	if nearest_node < 0:
		return
	_node_click_remaining[nearest_node] = STAR_CLICK_DURATION
	queue_redraw()
	for node_id in GameState.get_reachable_nodes(current_node_id):
		if node_id == nearest_node:
			selected_node_id = node_id
			queue_redraw()
			destination_selected.emit(node_id)
			return


func _node_center(node_id: int) -> Vector2:
	var normalized_position: Vector2 = GameState.NODE_POSITIONS[node_id]
	return Vector2(WORLD_SIZE.x * normalized_position.x, WORLD_SIZE.y * normalized_position.y)


func _draw_arrow(from_node_id: int, to_node_id: int, color: Color) -> void:
	var from_position := _node_center(from_node_id)
	var to_position := _node_center(to_node_id)
	var direction := (to_position - from_position).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var tip := to_position - direction * (NODE_SIZE.x / 2.0 + 1.0)
	var arrow_base := tip - direction * 8.0
	var line_start := from_position + direction * (NODE_SIZE.x / 2.0 + 1.0)

	draw_line(line_start, arrow_base, color, 2.0, true)
	var arrowhead := PackedVector2Array([
		tip,
		arrow_base + perpendicular * 4.0,
		arrow_base - perpendicular * 4.0,
	])
	draw_colored_polygon(arrowhead, color)
