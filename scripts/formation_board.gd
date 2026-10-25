extends Control

signal selection_changed

const SPACING := 65.0
const MIN_VIEW_SCALE := 0.25
const MAX_VIEW_SCALE := 3.0
const ZOOM_FACTOR := 1.2
const KEYBOARD_PAN_SPEED := 260.0
const FORMATION_NAMES: Array[String] = ["ECHELON (V)", "LINE", "DOUBLE LINE", "STAGGERED", "WEDGE"]
var selected: FleetShip
var dragging := false
var previews: Dictionary = {}
var view_center := Vector2.ZERO
var view_scale := 1.0
var drag_offset := Vector2.ZERO
var drag_position := Vector2.ZERO
var camera_panning := false
var camera_pan_last := Vector2.ZERO
var formation_button: Button
var formation_index := 0
var last_fleet_size := -1

func _ready() -> void:
	custom_minimum_size = Vector2(160, 90)
	clip_contents = true
	formation_button = Button.new()
	formation_button.name = "FormationButton"
	formation_button.custom_minimum_size = Vector2(112, 24)
	formation_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	formation_button.offset_left = -116.0
	formation_button.offset_top = 4.0
	formation_button.offset_right = -4.0
	formation_button.offset_bottom = 28.0
	formation_button.add_theme_font_size_override("font_size", 9)
	formation_button.text = FORMATION_NAMES[formation_index]
	formation_button.pressed.connect(_cycle_formation)
	add_child(formation_button)
	GameState.fleet_changed.connect(_sync_ships)
	resized.connect(_fit)
	_apply_formation(false)
	_sync_ships()
	formation_button.move_to_front()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is TextEdit:
		return
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0
	if direction.is_zero_approx():
		return
	view_center += direction.normalized() * KEYBOARD_PAN_SPEED * delta / view_scale
	_layout_ships()


func _cycle_formation() -> void:
	formation_index = (formation_index + 1) % FORMATION_NAMES.size()
	formation_button.text = FORMATION_NAMES[formation_index]
	_apply_formation()


func _apply_formation(notify_change: bool = true) -> void:
	if GameState.fleet.is_empty():
		return
	var positions := _formation_positions(GameState.fleet.size(), formation_index)
	positions.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		if not is_equal_approx(a.x, b.x):
			return a.x > b.x
		return absf(a.y) < absf(b.y))
	var ordered := _strategic_ship_order()
	for index in range(ordered.size()):
		ordered[index].formation = positions[index]
	if notify_change:
		GameState.fleet_changed.emit()
	else:
		_fit()


func _strategic_ship_order() -> Array[FleetShip]:
	var remaining: Array[FleetShip] = []
	remaining.assign(GameState.fleet)
	var ordered: Array[FleetShip] = []
	ordered.resize(remaining.size())
	var front_index := 0
	var back_index := remaining.size() - 1
	while not remaining.is_empty():
		remaining.sort_custom(func(a: FleetShip, b: FleetShip) -> bool:
			return a.get_stats(GameState.laser_upgrade_level).integrity > b.get_stats(GameState.laser_upgrade_level).integrity)
		ordered[front_index] = remaining.pop_front()
		front_index += 1
		if remaining.is_empty():
			break
		remaining.sort_custom(func(a: FleetShip, b: FleetShip) -> bool:
			return a.get_stats(GameState.laser_upgrade_level).dps > b.get_stats(GameState.laser_upgrade_level).dps)
		ordered[back_index] = remaining.pop_front()
		back_index -= 1
	return ordered


func _formation_positions(count: int, pattern: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	match pattern:
		0: # A forward point with two arms trailing behind it.
			positions.append(Vector2.ZERO)
			var depth := 1
			while positions.size() < count:
				positions.append(Vector2(-depth, -depth))
				if positions.size() < count:
					positions.append(Vector2(-depth, depth))
				depth += 1
		1:
			var half_height := (count - 1) * 0.5
			for index in range(count):
				positions.append(Vector2(0.0, index - half_height))
		2:
			var left_count := ceili(count / 2.0)
			var right_count := count - left_count
			for index in range(count):
				var column := index % 2
				var row := index / 2
				var column_count := left_count if column == 0 else right_count
				positions.append(Vector2(-float(column), row - (column_count - 1) * 0.5))
		3:
			var half_height := (count - 1) * 0.5
			for index in range(count):
				positions.append(Vector2(-0.65 if index % 2 == 0 else 0.65, index - half_height))
		4: # Broad front ranks taper toward the rear.
			var columns := ceili(sqrt(float(count)))
			var index := 0
			while index < count:
				var depth := index / columns
				var row_count := mini(columns, count - index)
				for row in range(row_count):
					positions.append(Vector2(-depth, row - (row_count - 1) * 0.5))
					index += 1
	return positions

func _sync_ships() -> void:
	var fleet_size_changed := last_fleet_size >= 0 and last_fleet_size != GameState.fleet.size()
	last_fleet_size = GameState.fleet.size()
	if fleet_size_changed:
		_apply_formation(false)
	for preview in previews.values():
		remove_child(preview)
		preview.queue_free()
	previews.clear()
	for owned in GameState.fleet:
		var preview := preload("res://scripts/fleet_ship_preview.gd").new()
		preview.owned = owned
		previews[owned] = preview
		add_child(preview)
	if formation_button != null:
		formation_button.move_to_front()
	if not GameState.fleet.has(selected):
		selected = null if GameState.fleet.is_empty() else GameState.fleet[0]
	selection_changed.emit()
	_fit()

func _fit() -> void:
	if dragging or camera_panning:
		return
	var bounds := Rect2(-Vector2(50, 20), Vector2(100, 40))
	if not GameState.fleet.is_empty():
		bounds = Rect2(GameState.fleet[0].formation * SPACING, Vector2.ZERO)
		for owned in GameState.fleet:
			bounds = bounds.expand(owned.formation * SPACING)
	bounds = bounds.grow(40.0)
	view_center = bounds.get_center()
	custom_minimum_size.y = clampf(bounds.size.y, 64.0, 90.0)
	view_scale = minf(maxf(size.x, 1.0) / bounds.size.x, maxf(size.y, 1.0) / bounds.size.y)
	view_scale = minf(view_scale, 1.0)
	_layout_ships()

func _screen_position(owned: FleetShip) -> Vector2:
	var world := drag_position if dragging and owned == selected else owned.formation * SPACING
	return (world - view_center) * view_scale + size * 0.5

func _layout_ships() -> void:
	for owned in previews:
		var preview: Control = previews[owned]
		preview.size = Vector2.ONE * 56.0 * view_scale
		preview.position = _screen_position(owned) - preview.size * 0.5
		preview.queue_redraw()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.2, 0.25), false)
	if selected != null and previews.has(selected):
		draw_rect(Rect2(_screen_position(selected) - Vector2.ONE * 28.0 * view_scale, Vector2.ONE * 56.0 * view_scale), Color(0.4, 0.85, 1.0), false)

func _ship_at(point: Vector2) -> FleetShip:
	for owned in GameState.fleet:
		if Rect2(_screen_position(owned) - Vector2.ONE * 28.0 * view_scale, Vector2.ONE * 56.0 * view_scale).has_point(point):
			return owned
	return null

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := ZOOM_FACTOR if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_FACTOR
			_zoom_at(event.position, factor)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			camera_panning = true
			camera_pan_last = event.position
			accept_event()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected = _ship_at(event.position)
		selection_changed.emit()
		if selected != null:
			dragging = true
			drag_position = selected.formation * SPACING
			drag_offset = drag_position - ((event.position - size * 0.5) / view_scale + view_center)
		queue_redraw()
		accept_event()

func _input(event: InputEvent) -> void:
	if camera_panning:
		if event is InputEventMouseMotion:
			var local_position := get_local_mouse_position()
			view_center -= (local_position - camera_pan_last) / view_scale
			camera_pan_last = local_position
			_layout_ships()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
			camera_panning = false
			get_viewport().set_input_as_handled()
		return
	if not dragging:
		return
	if event is InputEventMouseMotion:
		drag_position = (get_local_mouse_position() - size * 0.5) / view_scale + view_center + drag_offset
		_layout_ships()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		GameState.move_ship(selected, drag_position / SPACING)
		_fit()
		get_viewport().set_input_as_handled()


func _zoom_at(screen_position: Vector2, factor: float) -> void:
	var world_under_cursor := (screen_position - size * 0.5) / view_scale + view_center
	view_scale = clampf(view_scale * factor, MIN_VIEW_SCALE, MAX_VIEW_SCALE)
	view_center = world_under_cursor - (screen_position - size * 0.5) / view_scale
	_layout_ships()
