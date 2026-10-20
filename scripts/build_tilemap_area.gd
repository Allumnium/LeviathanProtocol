extends Control

const GRID_SOURCE_ID := 0
const RED_SOURCE_ID := 1
const BLUE_SOURCE_ID := 2
const GREEN_SOURCE_ID := 3
const NO_SOURCE_ID := -1
const ERASE_SOURCE_ID := -2
const NO_CATEGORY := -1
const INVALID_CELL := Vector2i(-1, -1)
const MIN_ZOOM := 0.5
const MAX_ZOOM := 3.0
const ZOOM_STEP := 0.5

@export var tile_size := Vector2i(26, 26)
@export var map_dimensions := Vector2i(50, 50)
@export var grid_texture: Texture2D
@export var red_tile_texture: Texture2D
@export var blue_tile_texture: Texture2D
@export var green_tile_texture: Texture2D

@onready var pan_root: Node2D = $PanRoot
@onready var grid_layer: TileMapLayer = $PanRoot/GridLayer
@onready var placed_layer: TileMapLayer = $PanRoot/PlacedLayer
@onready var parts_layer: Node2D = $PanRoot/PartsLayer
@onready var preview_layer: TileMapLayer = $PanRoot/PreviewLayer
@onready var selector_row: HBoxContainer = $SelectorRow
@onready var red_build_button: TextureButton = $SelectorRow/RedBuildButton
@onready var blue_build_button: TextureButton = $SelectorRow/BlueBuildButton
@onready var green_build_button: TextureButton = $SelectorRow/GreenBuildButton
@onready var erase_build_button: TextureButton = $SelectorRow/EraseBuildButton
@onready var red_count_badge: PanelContainer = $SelectorRow/RedBuildButton/CountBadge
@onready var red_count_label: Label = $SelectorRow/RedBuildButton/CountBadge/CountLabel
@onready var blue_count_badge: PanelContainer = $SelectorRow/BlueBuildButton/CountBadge
@onready var blue_count_label: Label = $SelectorRow/BlueBuildButton/CountBadge/CountLabel
@onready var green_count_badge: PanelContainer = $SelectorRow/GreenBuildButton/CountBadge
@onready var green_count_label: Label = $SelectorRow/GreenBuildButton/CountBadge/CountLabel

var _selected_source_id := NO_SOURCE_ID
var _preview_cell := INVALID_CELL
var _preview_source_id := NO_SOURCE_ID
var _tile_set: TileSet
var _is_panning := false
var _is_placing := false
var _pan_buttons_held: Array[int] = []
var _last_pan_mouse_position := Vector2.ZERO
var _last_placed_cell := INVALID_CELL
var _initial_pan_position_set := false
var _part_patterns: Array[ShipPartPattern] = []
var _part_sprites: Dictionary[ShipPart, Sprite2D] = {}


func _ready() -> void:
	if tile_size.x <= 0 or tile_size.y <= 0:
		push_error("Build tile size must be positive.")
		set_process(false)
		set_process_input(false)
		return
	if map_dimensions.x <= 0 or map_dimensions.y <= 0:
		push_error("Build map dimensions must be positive.")
		set_process(false)
		set_process_input(false)
		return
	if not _create_tile_set():
		set_process(false)
		set_process_input(false)
		return

	grid_layer.tile_set = _tile_set
	placed_layer.tile_set = _tile_set
	preview_layer.tile_set = _tile_set
	_fill_grid()
	_part_patterns = _create_part_patterns()
	_rebuild_part_placeholders()
	GameState.tile_inventory_changed.connect(_refresh_tile_counts)
	_refresh_tile_counts()

	var selector_group := ButtonGroup.new()
	selector_group.allow_unpress = false
	red_build_button.button_group = selector_group
	blue_build_button.button_group = selector_group
	green_build_button.button_group = selector_group
	erase_build_button.button_group = selector_group

	red_build_button.toggled.connect(_on_build_button_toggled.bind(RED_SOURCE_ID))
	blue_build_button.toggled.connect(_on_build_button_toggled.bind(BLUE_SOURCE_ID))
	green_build_button.toggled.connect(_on_build_button_toggled.bind(GREEN_SOURCE_ID))
	erase_build_button.toggled.connect(_on_build_button_toggled.bind(ERASE_SOURCE_ID))

	resized.connect(_on_resized)
	call_deferred("_set_initial_pan_position")


func _create_tile_set() -> bool:
	var tile_set := TileSet.new()
	tile_set.tile_size = tile_size

	var grid_source := _create_atlas_source(grid_texture, "grid")
	var red_source := _create_atlas_source(red_tile_texture, "red")
	var blue_source := _create_atlas_source(blue_tile_texture, "blue")
	var green_source := _create_atlas_source(green_tile_texture, "green")
	if grid_source == null or red_source == null or blue_source == null or green_source == null:
		return false

	tile_set.add_source(grid_source, GRID_SOURCE_ID)
	tile_set.add_source(red_source, RED_SOURCE_ID)
	tile_set.add_source(blue_source, BLUE_SOURCE_ID)
	tile_set.add_source(green_source, GREEN_SOURCE_ID)
	_tile_set = tile_set
	grid_layer.tile_set = tile_set
	placed_layer.tile_set = tile_set
	preview_layer.tile_set = tile_set
	return true


func _create_atlas_source(texture: Texture2D, texture_name: String) -> TileSetAtlasSource:
	if texture == null:
		push_error("The %s build texture is not assigned." % texture_name)
		return null

	var cell_texture := _fit_texture_to_cell(texture, texture_name)
	if cell_texture == null:
		return null

	var source := TileSetAtlasSource.new()
	source.texture = cell_texture
	source.texture_region_size = tile_size
	source.create_tile(Vector2i.ZERO)
	return source


func _fit_texture_to_cell(texture: Texture2D, texture_name: String) -> Texture2D:
	var source_image := texture.get_image()
	if source_image == null or source_image.is_empty():
		push_error("Could not read the %s build texture." % texture_name)
		return null
	if source_image.get_width() > tile_size.x or source_image.get_height() > tile_size.y:
		push_error(
			"The %s build texture must fit within the configured tile size (%s)."
			% [texture_name, tile_size]
		)
		return null

	var cell_image := Image.create(tile_size.x, tile_size.y, false, Image.FORMAT_RGBA8)
	cell_image.fill(Color.TRANSPARENT)
	var offset := Vector2i(
		floori(float(tile_size.x - source_image.get_width()) / 2.0),
		floori(float(tile_size.y - source_image.get_height()) / 2.0)
	)
	cell_image.blit_rect(
		source_image,
		Rect2i(Vector2i.ZERO, source_image.get_size()),
		offset
	)
	return ImageTexture.create_from_image(cell_image)


func _fill_grid() -> void:
	grid_layer.clear()
	for y in range(map_dimensions.y):
		for x in range(map_dimensions.x):
			grid_layer.set_cell(Vector2i(x, y), GRID_SOURCE_ID, Vector2i.ZERO)


func _process(_delta: float) -> void:
	_update_preview()


func _input(event: InputEvent) -> void:
	var motion_event := event as InputEventMouseMotion
	if motion_event != null:
		var local_motion_event := make_input_local(motion_event) as InputEventMouseMotion
		if local_motion_event == null:
			return
		var local_mouse_position := local_motion_event.position
		if _is_panning:
			pan_root.position += local_mouse_position - _last_pan_mouse_position
			_last_pan_mouse_position = local_mouse_position
			_clamp_pan_position()
			get_viewport().set_input_as_handled()
		elif _is_placing:
			_place_at_local_position(local_mouse_position)
		_update_preview_at(local_mouse_position)
		return

	var mouse_button_event := event as InputEventMouseButton
	if mouse_button_event == null or mouse_button_event.pressed:
		return
	if mouse_button_event.button_index == MOUSE_BUTTON_LEFT:
		_is_placing = false
		_last_placed_cell = INVALID_CELL
	if (
		mouse_button_event.button_index == MOUSE_BUTTON_RIGHT
		or mouse_button_event.button_index == MOUSE_BUTTON_MIDDLE
	):
		_pan_buttons_held.erase(mouse_button_event.button_index)
		_is_panning = not _pan_buttons_held.is_empty()


func _gui_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	var mouse_button_event := event as InputEventMouseButton
	if mouse_button_event == null or not mouse_button_event.pressed:
		return
	var local_mouse_position := mouse_button_event.position
	if _is_mouse_over_selector_row(local_mouse_position):
		return

	if mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if _is_mouse_over_build_area(local_mouse_position):
			_zoom_at(local_mouse_position, ZOOM_STEP)
			accept_event()
		return
	if mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if _is_mouse_over_build_area(local_mouse_position):
			_zoom_at(local_mouse_position, -ZOOM_STEP)
			accept_event()
		return

	if (
		mouse_button_event.button_index == MOUSE_BUTTON_RIGHT
		or mouse_button_event.button_index == MOUSE_BUTTON_MIDDLE
	):
		if _is_mouse_over_build_area(local_mouse_position):
			if not _pan_buttons_held.has(mouse_button_event.button_index):
				_pan_buttons_held.append(mouse_button_event.button_index)
			_is_panning = true
			_last_pan_mouse_position = local_mouse_position
			accept_event()
		return

	if mouse_button_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _selected_source_id == NO_SOURCE_ID:
		return

	var cell := _get_cell_at_local_position(local_mouse_position)
	if cell == INVALID_CELL:
		return

	_is_placing = true
	_last_placed_cell = INVALID_CELL
	_paint_to_cell(cell)
	accept_event()


func _place_at_local_position(local_mouse_position: Vector2) -> void:
	var cell := _get_cell_at_local_position(local_mouse_position)
	if cell == INVALID_CELL:
		_last_placed_cell = INVALID_CELL
		return
	_paint_to_cell(cell)


func _paint_to_cell(target_cell: Vector2i) -> void:
	if target_cell == _last_placed_cell:
		return
	if _last_placed_cell == INVALID_CELL:
		_apply_selected_tool(target_cell)
	else:
		_paint_line(_last_placed_cell, target_cell)
	_last_placed_cell = target_cell


func _paint_line(start_cell: Vector2i, end_cell: Vector2i) -> void:
	var x := start_cell.x
	var y := start_cell.y
	var delta_x := absi(end_cell.x - start_cell.x)
	var delta_y := absi(end_cell.y - start_cell.y)
	var step_x := 1 if start_cell.x < end_cell.x else -1
	var step_y := 1 if start_cell.y < end_cell.y else -1
	var line_error := delta_x - delta_y

	while true:
		_apply_selected_tool(Vector2i(x, y))
		if x == end_cell.x and y == end_cell.y:
			break

		var doubled_error := line_error * 2
		if doubled_error > -delta_y:
			line_error -= delta_y
			x += step_x
		if doubled_error < delta_x:
			line_error += delta_x
			y += step_y


func _apply_selected_tool(cell: Vector2i) -> void:
	var existing_source_id := placed_layer.get_cell_source_id(cell)
	if _selected_source_id == ERASE_SOURCE_ID:
		if existing_source_id != NO_SOURCE_ID:
			var existing_category := _get_category_for_source_id(existing_source_id)
			if existing_category != NO_CATEGORY:
				GameState.refund_tile(existing_category)
		placed_layer.erase_cell(cell)
		_remove_ship_part_at(cell)
	else:
		var category := _get_category_for_source_id(_selected_source_id)
		if category == NO_CATEGORY:
			return
		if existing_source_id == _selected_source_id:
			_evaluate_part_patterns()
			return
		if not GameState.try_consume_tile(category):
			return
		if existing_source_id != NO_SOURCE_ID:
			var existing_category := _get_category_for_source_id(existing_source_id)
			if existing_category != NO_CATEGORY:
				GameState.refund_tile(existing_category)
		_remove_ship_part_at(cell)
		placed_layer.set_cell(cell, _selected_source_id, Vector2i.ZERO)
	_evaluate_part_patterns()


func _refresh_tile_counts() -> void:
	_set_tile_count(
		red_count_badge,
		red_count_label,
		GameState.get_available_tile_count(ShipPart.Category.OFFENSE)
	)
	_set_tile_count(
		blue_count_badge,
		blue_count_label,
		GameState.get_available_tile_count(ShipPart.Category.DEFENSE)
	)
	_set_tile_count(
		green_count_badge,
		green_count_label,
		GameState.get_available_tile_count(ShipPart.Category.SPECIAL)
	)


func _set_tile_count(badge: PanelContainer, label: Label, count: int) -> void:
	label.text = str(count)
	badge.show()


func _create_part_patterns() -> Array[ShipPartPattern]:
	var patterns: Array[ShipPartPattern] = []
	patterns.append(
		ShipPartPattern.new(
			ShipPart.Type.ARMOR_BLOCK,
			ShipPart.Category.DEFENSE,
			[
				Vector2i(0, 0),
				Vector2i(1, 0),
				Vector2i(0, 1),
				Vector2i(1, 1),
			]
		)
	)
	patterns.append(
		ShipPartPattern.new(
			ShipPart.Type.LASER,
			ShipPart.Category.OFFENSE,
			[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
		)
	)
	return patterns


func _evaluate_part_patterns() -> void:
	for pattern in _part_patterns:
		var source_id := _get_source_id_for_category(pattern.category)
		if source_id == NO_SOURCE_ID:
			continue
		for y in range(map_dimensions.y):
			for x in range(map_dimensions.x):
				_try_morph_pattern(Vector2i(x, y), pattern, source_id)


func _try_morph_pattern(
	origin: Vector2i,
	pattern: ShipPartPattern,
	source_id: int
) -> bool:
	var rotation_count := 4 if pattern.can_rotate else 1
	for quarter_turns in range(rotation_count):
		var cell_offsets := pattern.get_offsets_for_rotation(quarter_turns)
		if not _matches_pattern(origin, cell_offsets, source_id):
			continue

		var part := ShipPart.new(pattern.part_type, pattern.category, origin, cell_offsets)
		if not GameState.ship.add_part(part):
			push_error("Could not add a matched part to the ship.")
			return false
		for cell in part.get_occupied_cells():
			placed_layer.erase_cell(cell)
		_add_part_placeholder(part)
		return true
	return false


func _matches_pattern(
	origin: Vector2i,
	cell_offsets: Array[Vector2i],
	source_id: int
) -> bool:
	for offset in cell_offsets:
		var cell := origin + offset
		if (
			cell.x < 0
			or cell.y < 0
			or cell.x >= map_dimensions.x
			or cell.y >= map_dimensions.y
			or placed_layer.get_cell_source_id(cell) != source_id
		):
			return false
	return true


func _get_source_id_for_category(category: int) -> int:
	match category:
		ShipPart.Category.OFFENSE:
			return RED_SOURCE_ID
		ShipPart.Category.DEFENSE:
			return BLUE_SOURCE_ID
		ShipPart.Category.SPECIAL:
			return GREEN_SOURCE_ID
		_:
			push_error("Unknown ship part category: %s" % category)
			return NO_SOURCE_ID


func _get_category_for_source_id(source_id: int) -> int:
	match source_id:
		RED_SOURCE_ID:
			return ShipPart.Category.OFFENSE
		BLUE_SOURCE_ID:
			return ShipPart.Category.DEFENSE
		GREEN_SOURCE_ID:
			return ShipPart.Category.SPECIAL
		_:
			push_error("Unknown build tile source ID: %s" % source_id)
			return NO_CATEGORY


func _get_texture_for_category(category: int) -> Texture2D:
	match category:
		ShipPart.Category.OFFENSE:
			return red_tile_texture
		ShipPart.Category.DEFENSE:
			return blue_tile_texture
		ShipPart.Category.SPECIAL:
			return green_tile_texture
		_:
			push_error("Unknown ship part category: %s" % category)
			return null


func _rebuild_part_placeholders() -> void:
	for part in GameState.ship.parts:
		_add_part_placeholder(part)


func _add_part_placeholder(part: ShipPart) -> void:
	var texture := _get_texture_for_category(part.category)
	if texture == null:
		return

	var cells := part.get_occupied_cells()
	if cells.is_empty():
		push_error("Cannot display a ship part with no occupied cells.")
		return

	var minimum_x := cells[0].x
	var minimum_y := cells[0].y
	var maximum_x := cells[0].x
	var maximum_y := cells[0].y
	for cell in cells:
		minimum_x = mini(minimum_x, cell.x)
		minimum_y = mini(minimum_y, cell.y)
		maximum_x = maxi(maximum_x, cell.x)
		maximum_y = maxi(maximum_y, cell.y)

	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	sprite.position = (
		grid_layer.map_to_local(Vector2i(minimum_x, minimum_y))
		+ grid_layer.map_to_local(Vector2i(maximum_x, maximum_y))
	) * 0.5
	sprite.scale = Vector2(
		float((maximum_x - minimum_x + 1) * tile_size.x) / texture.get_width(),
		float((maximum_y - minimum_y + 1) * tile_size.y) / texture.get_height()
	)
	parts_layer.add_child(sprite)
	_part_sprites[part] = sprite


func _remove_ship_part_at(cell: Vector2i) -> void:
	var part := GameState.ship.remove_part_at(cell)
	if part == null:
		return
	if _part_sprites.has(part):
		_part_sprites[part].queue_free()
		_part_sprites.erase(part)


func _zoom_at(local_mouse_position: Vector2, zoom_delta: float) -> void:
	var current_zoom := pan_root.scale.x
	var next_zoom := clampf(current_zoom + zoom_delta, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(current_zoom, next_zoom):
		return

	var map_position := (local_mouse_position - pan_root.position) / current_zoom
	pan_root.scale = Vector2.ONE * next_zoom
	pan_root.position = local_mouse_position - map_position * next_zoom
	_clamp_pan_position()
	_update_preview_at(local_mouse_position)


func _on_build_button_toggled(is_selected: bool, source_id: int) -> void:
	_is_placing = false
	_last_placed_cell = INVALID_CELL
	if is_selected:
		_selected_source_id = source_id
	elif _selected_source_id == source_id:
		_selected_source_id = NO_SOURCE_ID
	_update_preview()


func _get_cell_under_mouse() -> Vector2i:
	return _get_cell_at_local_position(get_local_mouse_position())


func _get_cell_at_local_position(local_mouse_position: Vector2) -> Vector2i:
	if not Rect2(Vector2.ZERO, size).has_point(local_mouse_position):
		return INVALID_CELL
	if _is_mouse_over_selector_row(local_mouse_position):
		return INVALID_CELL

	var canvas_mouse_position := get_global_transform_with_canvas() * local_mouse_position
	var layer_mouse_position := (
		grid_layer.get_global_transform_with_canvas().affine_inverse() * canvas_mouse_position
	)
	var cell := grid_layer.local_to_map(layer_mouse_position)
	if (
		cell.x < 0
		or cell.y < 0
		or cell.x >= map_dimensions.x
		or cell.y >= map_dimensions.y
	):
		return INVALID_CELL
	return cell


func _is_mouse_over_build_area(local_mouse_position: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(local_mouse_position)


func _is_mouse_over_selector_row(local_mouse_position: Vector2) -> bool:
	var canvas_mouse_position := get_global_transform_with_canvas() * local_mouse_position
	var row_mouse_position := (
		selector_row.get_global_transform_with_canvas().affine_inverse() * canvas_mouse_position
	)
	return Rect2(Vector2.ZERO, selector_row.size).has_point(row_mouse_position)


func _update_preview() -> void:
	_update_preview_at(get_local_mouse_position())


func _update_preview_at(local_mouse_position: Vector2) -> void:
	if (
		_selected_source_id == NO_SOURCE_ID
		or _selected_source_id == ERASE_SOURCE_ID
		or not is_visible_in_tree()
	):
		_clear_preview()
		return

	var cell := _get_cell_at_local_position(local_mouse_position)
	if cell == INVALID_CELL:
		_clear_preview()
		return
	if cell == _preview_cell and _selected_source_id == _preview_source_id:
		return

	preview_layer.clear()
	preview_layer.set_cell(cell, _selected_source_id, Vector2i.ZERO)
	_preview_cell = cell
	_preview_source_id = _selected_source_id


func _clear_preview() -> void:
	if _preview_cell == INVALID_CELL:
		return
	preview_layer.clear()
	_preview_cell = INVALID_CELL
	_preview_source_id = NO_SOURCE_ID


func _set_initial_pan_position() -> void:
	if _initial_pan_position_set or size.x <= 0.0 or size.y <= 0.0:
		return
	var map_size := Vector2(map_dimensions.x * tile_size.x, map_dimensions.y * tile_size.y) * pan_root.scale
	pan_root.position = (size - map_size) / 2.0
	_initial_pan_position_set = true
	_clamp_pan_position()


func _on_resized() -> void:
	if _initial_pan_position_set:
		_clamp_pan_position()
	else:
		_set_initial_pan_position()


func _clamp_pan_position() -> void:
	var map_size := Vector2(map_dimensions.x * tile_size.x, map_dimensions.y * tile_size.y) * pan_root.scale
	var position_limits := size - map_size
	var minimum_position := Vector2(
		minf(0.0, position_limits.x),
		minf(0.0, position_limits.y)
	)
	var maximum_position := Vector2(
		maxf(0.0, position_limits.x),
		maxf(0.0, position_limits.y)
	)
	pan_root.position = Vector2(
		clampf(pan_root.position.x, minimum_position.x, maximum_position.x),
		clampf(pan_root.position.y, minimum_position.y, maximum_position.y)
	)
