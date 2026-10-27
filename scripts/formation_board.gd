extends Control

signal selection_changed

const SPACING := 65.0
const MIN_VIEW_SCALE := 0.1
const MAX_VIEW_SCALE := 3.0
const ZOOM_FACTOR := 1.2
const KEYBOARD_PAN_SPEED := 260.0
const FORMATION_ASPECT_RATIO := 0.5
const FORMATION_AREA_PADDING := 64.0
const FORMATION_EDGE_MARGIN := 28.0
const MIN_FORMATION_HEIGHT := 440.0
const FORMATION_BOUNDARY_COLOR := Color(0.55, 0.68, 0.76, 0.8)
const MIN_BOUNDARY_VISIBLE_PIXELS := 24.0
const FORMATION_NAMES: Array[String] = [
	"ECHELON (V)", "LINE", "DOUBLE LINE", "STAGGERED", "WEDGE", "HALF CIRCLE", "NONE",
]
const NONE_FORMATION_INDEX := 6
const HALF_CIRCLE_MAX_ARC := deg_to_rad(145.0)
const HALF_CIRCLE_ANGLE_STEP := deg_to_rad(24.0)
var selected: FleetShip
var selected_ships: Array[FleetShip] = []
var dragging := false
var previews: Dictionary = {}
var view_center := Vector2.ZERO
var view_scale := 1.0
var drag_offset := Vector2.ZERO
var drag_position := Vector2.ZERO
var group_drag_start := Vector2.ZERO
var group_drag_offset := Vector2.ZERO
var group_start_positions: Dictionary = {}
var box_selecting := false
var selection_box_start := Vector2.ZERO
var selection_box_end := Vector2.ZERO
var camera_panning := false
var camera_pan_last := Vector2.ZERO
var formation_button: Button
var formation_heading: Label
var formation_index := 0
var last_fleet_size := -1
var preserve_camera_on_sync := false

func _ready() -> void:
	custom_minimum_size = Vector2(160, 90)
	clip_contents = true
	formation_index = clampi(GameState.fleet_formation_index, 0, FORMATION_NAMES.size() - 1)
	formation_heading = Label.new()
	formation_heading.name = "FormationHeading"
	formation_heading.text = "FORMATION"
	formation_heading.position = Vector2(6.0, 5.0)
	formation_heading.add_theme_font_size_override("font_size", 11)
	formation_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	formation_heading.z_index = 10
	add_child(formation_heading)
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
	_sync_ships()
	formation_button.move_to_front()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or GameState.is_modal_ui_open():
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
	_clamp_view_center()
	_layout_ships()


func _cycle_formation() -> void:
	formation_index = (formation_index + 1) % FORMATION_NAMES.size()
	GameState.fleet_formation_index = formation_index
	formation_button.text = FORMATION_NAMES[formation_index]
	if formation_index == NONE_FORMATION_INDEX:
		return
	preserve_camera_on_sync = true
	_apply_formation()


func _apply_formation(notify_change: bool = true, fit_view: bool = true) -> void:
	if GameState.fleet.is_empty() or formation_index == NONE_FORMATION_INDEX:
		return
	var positions := _formation_positions(GameState.fleet.size(), formation_index)
	positions = _fit_positions_to_boundary(positions)
	positions.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		if not is_equal_approx(a.x, b.x):
			return a.x > b.x
		return absf(a.y) < absf(b.y))
	var ordered := _strategic_ship_order()
	for index in range(ordered.size()):
		ordered[index].formation = positions[index]
	if notify_change:
		GameState.fleet_changed.emit()
	elif fit_view:
		_fit()
	else:
		_layout_ships()


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
			return a.get_stats(GameState.laser_upgrade_level, GameState.energy_efficiency()).dps > b.get_stats(GameState.laser_upgrade_level, GameState.energy_efficiency()).dps)
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
		4: # Mirror Echelon so the point and opening face the opposite direction.
			positions.append(Vector2.ZERO)
			var depth := 1
			while positions.size() < count:
				positions.append(Vector2(depth, -depth))
				if positions.size() < count:
					positions.append(Vector2(depth, depth))
				depth += 1
		5: # A rounded wedge spread along no more than 145 degrees of a circle.
			if count == 1:
				positions.append(Vector2.ZERO)
			else:
				var sweep := minf(HALF_CIRCLE_MAX_ARC, HALF_CIRCLE_ANGLE_STEP * (count - 1))
				var angle_step := sweep / float(count - 1)
				# Choose a radius that keeps adjacent ships one formation unit apart.
				var radius := 1.0 / (2.0 * sin(angle_step * 0.5))
				for index in range(count):
					var angle := -sweep * 0.5 + angle_step * index
					positions.append(Vector2(
						radius * (1.0 - cos(angle)),
						radius * sin(angle)
					))
	return positions

func _sync_ships() -> void:
	var previous_fleet_size := last_fleet_size
	var fleet_size_changed := previous_fleet_size >= 0 and previous_fleet_size != GameState.fleet.size()
	var fleet_size_increased := previous_fleet_size >= 0 and GameState.fleet.size() > previous_fleet_size
	last_fleet_size = GameState.fleet.size()
	if fleet_size_changed and formation_index != NONE_FORMATION_INDEX:
		_apply_formation(false, false)
	elif fleet_size_changed:
		_clamp_fleet_to_boundary()
	for preview in previews.values():
		remove_child(preview)
		preview.queue_free()
	previews.clear()
	for owned in GameState.fleet:
		var preview := preload("res://scripts/fleet_ship_preview.gd").new()
		preview.owned = owned
		if GameState.campaign_active and not GameState.is_ship_deployed(owned):
			preview.modulate = Color(0.5, 0.5, 0.5, 0.6)
		previews[owned] = preview
		add_child(preview)
	if formation_button != null:
		formation_button.move_to_front()
	if not GameState.fleet.has(selected):
		selected = null if GameState.fleet.is_empty() else GameState.fleet[0]
	selected_ships = selected_ships.filter(func(ship: FleetShip) -> bool:
		return GameState.fleet.has(ship))
	if selected != null and selected_ships.is_empty():
		selected_ships.append(selected)
	selection_changed.emit()
	if preserve_camera_on_sync or fleet_size_changed:
		preserve_camera_on_sync = false
		if fleet_size_increased:
			_zoom_out_to_fit_fleet()
		_layout_ships()
	else:
		_fit()


func _zoom_out_to_fit_fleet() -> void:
	if GameState.fleet.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return
	var available_half := Vector2(
		maxf(size.x * 0.5 - 8.0, 1.0),
		maxf(size.y * 0.5 - 8.0, 1.0)
	)
	var required_half_extent := Vector2.ONE
	for owned in GameState.fleet:
		var offset := (owned.formation * SPACING - view_center).abs()
		required_half_extent.x = maxf(required_half_extent.x, offset.x + 28.0)
		required_half_extent.y = maxf(required_half_extent.y, offset.y + 28.0)
	var fitting_scale := minf(
		available_half.x / required_half_extent.x,
		available_half.y / required_half_extent.y
	)
	view_scale = maxf(minf(view_scale, fitting_scale), MIN_VIEW_SCALE)
	_clamp_view_center()

func _fit() -> void:
	if dragging or camera_panning:
		return
	var bounds := _formation_bounds()
	view_center = Vector2.ZERO
	if not GameState.fleet.is_empty():
		view_center = _fleet_centroid()
	bounds = bounds.grow(8.0)
	custom_minimum_size.y = clampf(bounds.size.y, 64.0, 90.0)
	var required_half_extent := Vector2(
		maxf(absf(bounds.position.x - view_center.x), absf(bounds.end.x - view_center.x)),
		maxf(absf(bounds.position.y - view_center.y), absf(bounds.end.y - view_center.y))
	)
	view_scale = minf(
		maxf(size.x, 1.0) / (required_half_extent.x * 2.0),
		maxf(size.y, 1.0) / (required_half_extent.y * 2.0)
	)
	view_scale = minf(view_scale, 1.0)
	_clamp_view_center()
	_layout_ships()


func _fleet_centroid() -> Vector2:
	if GameState.fleet.is_empty():
		return Vector2.ZERO
	var centroid := Vector2.ZERO
	for owned in GameState.fleet:
		centroid += owned.formation * SPACING
	return centroid / float(GameState.fleet.size())

func _screen_position(owned: FleetShip) -> Vector2:
	var world := owned.formation * SPACING
	if dragging and selected_ships.has(owned):
		world = group_start_positions.get(owned, world) + group_drag_offset
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
	var world_bounds := _formation_bounds()
	var boundary_rect := Rect2(
		(world_bounds.position - view_center) * view_scale + size * 0.5,
		world_bounds.size * view_scale
	)
	draw_rect(boundary_rect, Color(0.015, 0.02, 0.025, 0.55), true)
	draw_rect(boundary_rect, FORMATION_BOUNDARY_COLOR, false, 1.0)
	for owned in selected_ships:
		var outline := _ship_outline(owned)
		if outline.size() >= 3:
			# Keep the selection stroke on physical pixel centers. Fractional
			# vertices combined with a 1.5 px line made opposite hull edges
			# rasterize at visibly different thicknesses at some zoom levels.
			for point_index in range(outline.size()):
				outline[point_index] = outline[point_index].round()
			outline.append(outline[0])
			draw_polyline(outline, Color.WHITE, 2.0, true)
	if box_selecting:
		var selection_rect := Rect2(selection_box_start, selection_box_end - selection_box_start).abs()
		draw_rect(selection_rect, Color(1.0, 1.0, 1.0, 0.12), true)
		draw_rect(selection_rect, Color.WHITE, false, 1.0)


func _ship_outline(owned: FleetShip) -> PackedVector2Array:
	var cells: Array[Vector2i] = []
	var ship_center := _screen_position(owned)
	for unit in owned.units:
		if unit.hp <= 0.0:
			continue
		for cell in unit.cells:
			cells.append(cell)
	var outline := Ship.create_hull_polygon(cells)
	for index in range(outline.size()):
		outline[index] = ship_center + (
			(outline[index] - owned.center) * owned.cell_size * view_scale
		)
	return outline

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
		var clicked_ship := _ship_at(event.position)
		selected = clicked_ship
		if clicked_ship != null:
			if not selected_ships.has(clicked_ship):
				selected_ships = [clicked_ship]
		else:
			selected_ships.clear()
		selection_changed.emit()
		if selected != null:
			dragging = true
			group_drag_start = (event.position - size * 0.5) / view_scale + view_center
			group_drag_offset = Vector2.ZERO
			group_start_positions.clear()
			for ship in selected_ships:
				group_start_positions[ship] = ship.formation * SPACING
			queue_redraw()
			accept_event()
		else:
			box_selecting = true
			selection_box_start = event.position
			selection_box_end = event.position
			queue_redraw()
			accept_event()

func _input(event: InputEvent) -> void:
	if camera_panning:
		if event is InputEventMouseMotion:
			var local_position := get_local_mouse_position()
			view_center -= (local_position - camera_pan_last) / view_scale
			_clamp_view_center()
			camera_pan_last = local_position
			_layout_ships()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
			camera_panning = false
			get_viewport().set_input_as_handled()
		return
	if box_selecting:
		if event is InputEventMouseMotion:
			selection_box_end = get_local_mouse_position()
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			box_selecting = false
			var selection_rect := Rect2(selection_box_start, selection_box_end - selection_box_start).abs()
			selected_ships.clear()
			for owned in GameState.fleet:
				if selection_rect.has_point(_screen_position(owned)):
					selected_ships.append(owned)
			selected = selected_ships[0] if not selected_ships.is_empty() else null
			selection_changed.emit()
			queue_redraw()
			get_viewport().set_input_as_handled()
		return
	if not dragging:
		return
	if event is InputEventMouseMotion:
		var current_world := (get_local_mouse_position() - size * 0.5) / view_scale + view_center
		group_drag_offset = _clamp_group_offset_to_boundary(current_world - group_drag_start)
		_layout_ships()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		_move_selected_group(group_drag_offset)
		get_viewport().set_input_as_handled()


func _move_selected_group(world_offset: Vector2) -> void:
	if world_offset.is_zero_approx():
		_layout_ships()
		return
	world_offset = _clamp_group_offset_to_boundary(world_offset)
	var destinations: Dictionary = {}
	for ship in selected_ships:
		destinations[ship] = (group_start_positions[ship] + world_offset) / SPACING
	for destination in destinations.values():
		for other in GameState.fleet:
			if selected_ships.has(other):
				continue
			if destination.distance_to(other.formation) < 0.8:
				group_drag_offset = Vector2.ZERO
				_layout_ships()
				return
	for ship in selected_ships:
		ship.formation = destinations[ship]
	preserve_camera_on_sync = true
	GameState.fleet_changed.emit()


func _formation_bounds() -> Rect2:
	var total_ship_area := 0.0
	for owned in GameState.fleet:
		var footprint := _ship_footprint(owned)
		total_ship_area += footprint.x * footprint.y
	var height := maxf(
		MIN_FORMATION_HEIGHT,
		sqrt(maxf(total_ship_area, 1.0) * FORMATION_AREA_PADDING / FORMATION_ASPECT_RATIO)
	)
	var dimensions := Vector2(height * FORMATION_ASPECT_RATIO, height)
	return Rect2(-dimensions * 0.5, dimensions)


func _ship_footprint(owned: FleetShip) -> Vector2:
	if owned.design == null or owned.design.tiles.is_empty():
		return Vector2.ONE * FORMATION_EDGE_MARGIN * 2.0
	var cells := owned.design.get_tile_cells()
	var minimum := cells[0]
	var maximum := cells[0]
	for cell in cells:
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
		maximum.x = maxi(maximum.x, cell.x)
		maximum.y = maxi(maximum.y, cell.y)
	return Vector2(maximum - minimum + Vector2i.ONE) * owned.cell_size


func _fit_positions_to_boundary(positions: Array[Vector2]) -> Array[Vector2]:
	if positions.is_empty():
		return positions
	var centroid := Vector2.ZERO
	for position in positions:
		centroid += position * SPACING
	centroid /= float(positions.size())
	var required_half := Vector2.ONE
	for position in positions:
		var offset := (position * SPACING - centroid).abs()
		required_half.x = maxf(required_half.x, offset.x)
		required_half.y = maxf(required_half.y, offset.y)
	var available_half := _formation_bounds().size * 0.5 - Vector2.ONE * FORMATION_EDGE_MARGIN
	var scale_factor := minf(
		1.0,
		minf(available_half.x / required_half.x, available_half.y / required_half.y)
	)
	var fitted: Array[Vector2] = []
	for position in positions:
		fitted.append((position * SPACING - centroid) * scale_factor / SPACING)
	return fitted


func _clamp_group_offset_to_boundary(requested_offset: Vector2) -> Vector2:
	if selected_ships.is_empty():
		return requested_offset
	var bounds := _formation_bounds().grow(-FORMATION_EDGE_MARGIN)
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for ship in selected_ships:
		var position: Vector2 = group_start_positions.get(ship, ship.formation * SPACING)
		minimum.x = minf(minimum.x, position.x)
		minimum.y = minf(minimum.y, position.y)
		maximum.x = maxf(maximum.x, position.x)
		maximum.y = maxf(maximum.y, position.y)
	requested_offset.x = clampf(requested_offset.x,
		bounds.position.x - minimum.x, bounds.end.x - maximum.x)
	requested_offset.y = clampf(requested_offset.y,
		bounds.position.y - minimum.y, bounds.end.y - maximum.y)
	return requested_offset


func _clamp_fleet_to_boundary() -> void:
	var bounds := _formation_bounds().grow(-FORMATION_EDGE_MARGIN)
	for owned in GameState.fleet:
		var world := owned.formation * SPACING
		world.x = clampf(world.x, bounds.position.x, bounds.end.x)
		world.y = clampf(world.y, bounds.position.y, bounds.end.y)
		owned.formation = world / SPACING


func _zoom_at(screen_position: Vector2, factor: float) -> void:
	var world_under_cursor := (screen_position - size * 0.5) / view_scale + view_center
	view_scale = clampf(view_scale * factor, MIN_VIEW_SCALE, MAX_VIEW_SCALE)
	view_center = world_under_cursor - (screen_position - size * 0.5) / view_scale
	_clamp_view_center()
	_layout_ships()


func _clamp_view_center() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or view_scale <= 0.0:
		return
	var bounds := _formation_bounds()
	var viewport_half := size / (view_scale * 2.0)
	var minimum_visible_world := MIN_BOUNDARY_VISIBLE_PIXELS / view_scale
	view_center.x = clampf(
		view_center.x,
		bounds.position.x - viewport_half.x + minimum_visible_world,
		bounds.end.x + viewport_half.x - minimum_visible_world
	)
	view_center.y = clampf(
		view_center.y,
		bounds.position.y - viewport_half.y + minimum_visible_world,
		bounds.end.y + viewport_half.y - minimum_visible_world
	)
