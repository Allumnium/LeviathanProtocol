extends Control

const GRID_SOURCE_ID := 0
const RED_SOURCE_ID := 1
const BLUE_SOURCE_ID := 2
const GREEN_SOURCE_ID := 3
const NO_SOURCE_ID := -1
const NO_CATEGORY := -1
const INVALID_CELL := Vector2i(-1, -1)
const MAX_MAP_DIMENSIONS := Vector2i(30, 30)
const MIN_ZOOM := 0.25
const MAX_ZOOM := 3.0
const ZOOM_STEP := 0.1
const ZOOM_SMOOTHING := 12.0
const KEYBOARD_PAN_SPEED := 420.0
const MIDDLE_PAN_DRAG_THRESHOLD := 4.0
const PART_TRANSFORM_DURATION := 0.75
const PART_FLASH_START_INTERVAL := 0.15
const PART_FLASH_END_INTERVAL := 0.02
const PLACE_SFX: AudioStream = preload("res://assets/audio/sfx/place.wav")
const MORPH_SFX: AudioStream = preload("res://assets/audio/sfx/morph.mp3")
const PART_FLASH_PURPLE := Color(0.72, 0.2, 1.0, 0.85)
const PART_FLASH_YELLOW := Color(1.0, 0.88, 0.0, 0.85)
const PART_FLASH_WHITE := Color(1.0, 1.0, 1.0, 0.85)
const BUILD_AREA_BACKGROUND_COLOR := Color(0.035, 0.045, 0.055, 1.0)

@export var tile_size := Vector2i(26, 26)
@export var map_dimensions := MAX_MAP_DIMENSIONS
@export var grid_texture: Texture2D
@export var red_tile_texture: Texture2D
@export var blue_tile_texture: Texture2D
@export var green_tile_texture: Texture2D

@onready var pan_root: Node2D = $PanRoot
@onready var background_starfield: BuildViewportStarfield = $BackgroundStars
@onready var grid_layer: TileMapLayer = $PanRoot/GridLayer
@onready var hull_polygon: Polygon2D = $PanRoot/HullPolygon
@onready var placed_layer: TileMapLayer = $PanRoot/PlacedLayer
@onready var parts_layer: Node2D = $PanRoot/PartsLayer
@onready var animation_layer: Node2D = $PanRoot/AnimationLayer
@onready var preview_layer: TileMapLayer = $PanRoot/PreviewLayer
@onready var selector_background: ColorRect = $SelectorBackground
@onready var red_build_button: TextureButton = $SelectorRow/RedBuildButton
@onready var blue_build_button: TextureButton = $SelectorRow/BlueBuildButton
@onready var green_build_button: TextureButton = $SelectorRow/GreenBuildButton
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
var _is_placing := false
var _is_erasing := false
var _is_panning := false
var _middle_pan_moved := false
var _middle_pan_start_position := Vector2.ZERO
var _middle_pan_last_position := Vector2.ZERO
var _last_placed_cell := INVALID_CELL
var _last_erased_cell := INVALID_CELL
var _initial_pan_position_set := false
var _target_zoom := 1.0
var _zoom_anchor_position := Vector2.ZERO
var _zoom_anchor_map_position := Vector2.ZERO
var _zoom_anchor_active := false
var _part_patterns: Array[ShipPartPattern] = []
var _part_sprites: Dictionary[ShipPart, Sprite2D] = {}
var _part_cell_outlines: Array[Panel] = []
var _locked_cells: Dictionary[Vector2i, bool] = {}
var _active_morph_count := 0


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
	if (
		map_dimensions.x > MAX_MAP_DIMENSIONS.x
		or map_dimensions.y > MAX_MAP_DIMENSIONS.y
	):
		push_error("Build map dimensions cannot exceed 30 by 30.")
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
	_part_patterns = ShipPartPattern.get_catalog()
	_restore_ship_tiles()
	_evaluate_part_patterns()
	GameState.tile_inventory_changed.connect(_refresh_tile_counts)
	_refresh_tile_counts()

	var selector_group := ButtonGroup.new()
	selector_group.allow_unpress = false
	red_build_button.button_group = selector_group
	blue_build_button.button_group = selector_group
	green_build_button.button_group = selector_group

	red_build_button.toggled.connect(_on_build_button_toggled.bind(RED_SOURCE_ID))
	blue_build_button.toggled.connect(_on_build_button_toggled.bind(BLUE_SOURCE_ID))
	green_build_button.toggled.connect(_on_build_button_toggled.bind(GREEN_SOURCE_ID))

	resized.connect(_on_resized)
	call_deferred("_set_initial_pan_position")


func _exit_tree() -> void:
	if _active_morph_count > 0:
		GameState.ship.clear_transitioning_parts()
	while _active_morph_count > 0:
		_active_morph_count -= 1
		GameState.end_part_transformation()


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


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_pan_with_keyboard(delta)
		_update_zoom(delta)
	_update_preview()


func _input(event: InputEvent) -> void:
	var motion_event := event as InputEventMouseMotion
	if motion_event != null:
		var local_motion_event := make_input_local(motion_event) as InputEventMouseMotion
		if local_motion_event == null:
			return
		var local_mouse_position := local_motion_event.position
		if _is_panning:
			if not _middle_pan_moved:
				if (
					local_mouse_position.distance_to(_middle_pan_start_position)
					<= MIDDLE_PAN_DRAG_THRESHOLD
				):
					_middle_pan_last_position = local_mouse_position
					return
				_middle_pan_moved = true
				_pan_by(local_mouse_position - _middle_pan_start_position)
			else:
				_pan_by(local_mouse_position - _middle_pan_last_position)
			_middle_pan_last_position = local_mouse_position
			_clear_preview()
			return
		if _is_placing:
			_place_at_local_position(local_mouse_position)
		elif _is_erasing:
			_erase_at_local_position(local_mouse_position)
		_update_preview_at(local_mouse_position)
		return

	var mouse_button_event := event as InputEventMouseButton
	if mouse_button_event == null:
		return
	if mouse_button_event.button_index == MOUSE_BUTTON_MIDDLE:
		var local_mouse_button_event := (
			make_input_local(mouse_button_event) as InputEventMouseButton
		)
		if local_mouse_button_event == null:
			return
		var local_mouse_position := local_mouse_button_event.position
		if mouse_button_event.pressed:
			if (
				not is_visible_in_tree()
				or not _is_mouse_over_build_area(local_mouse_position)
				or _is_mouse_over_selector_area(local_mouse_position)
			):
				return
			_is_placing = false
			_is_erasing = false
			_last_placed_cell = INVALID_CELL
			_last_erased_cell = INVALID_CELL
			_is_panning = true
			_middle_pan_moved = false
			_middle_pan_start_position = local_mouse_position
			_middle_pan_last_position = local_mouse_position
			_clear_preview()
			accept_event()
		elif _is_panning:
			_is_panning = false
			if (
				not _middle_pan_moved
				and _is_mouse_over_build_area(local_mouse_position)
				and not _is_mouse_over_selector_area(local_mouse_position)
			):
				_pick_tile_at(_get_cell_at_local_position(local_mouse_position))
			accept_event()
		return
	if mouse_button_event.pressed:
		return
	if mouse_button_event.button_index == MOUSE_BUTTON_LEFT:
		_is_placing = false
		_last_placed_cell = INVALID_CELL
	elif mouse_button_event.button_index == MOUSE_BUTTON_RIGHT:
		_is_erasing = false
		_last_erased_cell = INVALID_CELL


func _gui_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	var mouse_button_event := event as InputEventMouseButton
	if mouse_button_event == null or not mouse_button_event.pressed:
		return
	var local_mouse_position := mouse_button_event.position
	if _is_mouse_over_selector_area(local_mouse_position):
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

	if mouse_button_event.button_index == MOUSE_BUTTON_RIGHT:
		if _is_mouse_over_build_area(local_mouse_position):
			_is_placing = false
			_last_placed_cell = INVALID_CELL
			_is_erasing = true
			_last_erased_cell = INVALID_CELL
			_erase_at_local_position(local_mouse_position)
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
		_apply_line(_last_placed_cell, target_cell, false)
	_last_placed_cell = target_cell


func _erase_at_local_position(local_mouse_position: Vector2) -> void:
	var cell := _get_cell_at_local_position(local_mouse_position)
	if cell == INVALID_CELL:
		_last_erased_cell = INVALID_CELL
		return
	_erase_to_cell(cell)


func _erase_to_cell(target_cell: Vector2i) -> void:
	if target_cell == _last_erased_cell:
		return
	if _last_erased_cell == INVALID_CELL:
		_remove_tile_at(target_cell)
	else:
		_apply_line(_last_erased_cell, target_cell, true)
	_last_erased_cell = target_cell


func _apply_line(start_cell: Vector2i, end_cell: Vector2i, erase_tiles: bool) -> void:
	var x := start_cell.x
	var y := start_cell.y
	var delta_x := absi(end_cell.x - start_cell.x)
	var delta_y := absi(end_cell.y - start_cell.y)
	var step_x := 1 if start_cell.x < end_cell.x else -1
	var step_y := 1 if start_cell.y < end_cell.y else -1
	var line_error := delta_x - delta_y

	while true:
		var cell := Vector2i(x, y)
		if erase_tiles:
			_remove_tile_at(cell)
		else:
			_apply_selected_tool(cell)
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
	if _locked_cells.has(cell):
		return

	var existing_category := GameState.ship.get_tile_category_at(cell)
	var category := _get_category_for_source_id(_selected_source_id)
	if category == NO_CATEGORY:
		return
	if existing_category == category:
		return
	if not GameState.try_consume_tile(category):
		return
	if existing_category != NO_CATEGORY:
		GameState.refund_tile(existing_category)
	GameState.ship.set_tile_at(cell, category)
	placed_layer.set_cell(cell, _selected_source_id, Vector2i.ZERO)
	AudioManager.play_sfx(PLACE_SFX)
	_evaluate_part_patterns()


func _remove_tile_at(cell: Vector2i) -> void:
	if cell == INVALID_CELL or _locked_cells.has(cell):
		return

	var category := GameState.ship.get_tile_category_at(cell)
	if category == NO_CATEGORY:
		return

	GameState.ship.remove_tile_at(cell)
	GameState.refund_tile(category)
	placed_layer.erase_cell(cell)
	_evaluate_part_patterns()


func _pick_tile_at(cell: Vector2i) -> void:
	if cell == INVALID_CELL:
		return

	var category := GameState.ship.get_tile_category_at(cell)
	if category == NO_CATEGORY:
		return
	var source_id := _get_source_id_for_category(category)
	if source_id == NO_SOURCE_ID:
		return

	_is_placing = false
	_last_placed_cell = INVALID_CELL
	match source_id:
		RED_SOURCE_ID:
			red_build_button.button_pressed = true
		BLUE_SOURCE_ID:
			blue_build_button.button_pressed = true
		GREEN_SOURCE_ID:
			green_build_button.button_pressed = true
		_:
			return
	_selected_source_id = source_id
	_update_preview()


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


func _evaluate_part_patterns() -> void:
	_clear_part_placeholders()
	_restore_ship_tiles()
	_refresh_ship_hull()
	GameState.ship.clear_parts()
	for pattern in _part_patterns:
		if pattern.tile_categories.size() != pattern.cell_offsets.size():
			continue
		for y in range(map_dimensions.y):
			for x in range(map_dimensions.x):
				_try_morph_pattern(Vector2i(x, y), pattern)
	GameState.ship_stats_changed.emit()


func _try_morph_pattern(
	origin: Vector2i,
	pattern: ShipPartPattern
) -> bool:
	var rotation_count := 4 if pattern.can_rotate else 1
	for quarter_turns in range(rotation_count):
		var cell_offsets := pattern.get_offsets_for_rotation(quarter_turns)
		if not _matches_pattern(origin, pattern, cell_offsets):
			continue

		var part := ShipPart.new(
			pattern.part_type,
			pattern.category,
			origin,
			cell_offsets,
			pattern.stats,
			pattern.get_hidden_tile_offsets_for_rotation(quarter_turns)
		)
		if GameState.has_discovered_part(part.type):
			if not GameState.ship.add_part(part):
				push_error("Could not add a matched part to the ship.")
				return false
			_add_part_placeholder(part, pattern, quarter_turns)
		else:
			_begin_part_transformation(part)
		return true
	return false


func _matches_pattern(
	origin: Vector2i,
	pattern: ShipPartPattern,
	cell_offsets: Array[Vector2i]
) -> bool:
	for index in range(cell_offsets.size()):
		var offset := cell_offsets[index]
		var cell := origin + offset
		var source_id := _get_source_id_for_category(pattern.tile_categories[index])
		if (
			cell.x < 0
			or cell.y < 0
			or cell.x >= map_dimensions.x
			or cell.y >= map_dimensions.y
			or source_id == NO_SOURCE_ID
			or _locked_cells.has(cell)
			or placed_layer.get_cell_source_id(cell) != source_id
			or GameState.ship.get_part_at(cell) != null
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


func _restore_ship_tiles() -> void:
	placed_layer.clear()
	for cell in GameState.ship.get_tile_cells():
		var category := GameState.ship.get_tile_category_at(cell)
		var source_id := _get_source_id_for_category(category)
		if source_id == NO_SOURCE_ID:
			continue
		placed_layer.set_cell(cell, source_id, Vector2i.ZERO)


func _refresh_ship_hull() -> void:
	var points := PackedVector2Array()
	var half_tile_size := Vector2(tile_size) * 0.5
	for cell in GameState.ship.get_tile_cells():
		var center := grid_layer.map_to_local(cell)
		points.append(center - half_tile_size)
		points.append(Vector2(center.x + half_tile_size.x, center.y - half_tile_size.y))
		points.append(center + half_tile_size)
		points.append(Vector2(center.x - half_tile_size.x, center.y + half_tile_size.y))

	hull_polygon.polygon = Geometry2D.convex_hull(points)


func _clear_part_placeholders() -> void:
	for sprite in _part_sprites.values():
		sprite.queue_free()
	_part_sprites.clear()
	for cell_outline in _part_cell_outlines:
		cell_outline.queue_free()
	_part_cell_outlines.clear()


func _add_part_placeholder(
	part: ShipPart,
	pattern: ShipPartPattern,
	quarter_turns: int
) -> void:
	var texture := _get_texture_for_part(part)
	if texture == null:
		return

	var visual_cells: Array[Vector2i] = []
	for offset in pattern.get_visual_offsets_for_rotation(quarter_turns):
		visual_cells.append(part.origin + offset)
	if visual_cells.is_empty():
		push_error("Cannot display a ship part with no visual cells.")
		return

	for offset in pattern.get_hidden_tile_offsets_for_rotation(quarter_turns):
		var cell := part.origin + offset
		placed_layer.erase_cell(cell)
		if is_zero_approx(pattern.hidden_tile_outline_color.a):
			continue

		var cell_outline := Panel.new()
		cell_outline.position = grid_layer.map_to_local(cell) - Vector2(tile_size) * 0.5
		cell_outline.size = Vector2(tile_size)
		cell_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var outline_style := StyleBoxFlat.new()
		outline_style.bg_color = BUILD_AREA_BACKGROUND_COLOR
		outline_style.draw_center = true
		outline_style.border_color = pattern.hidden_tile_outline_color
		outline_style.set_border_width_all(2)
		cell_outline.add_theme_stylebox_override("panel", outline_style)
		parts_layer.add_child(cell_outline)
		_part_cell_outlines.append(cell_outline)

	var minimum_x := visual_cells[0].x
	var minimum_y := visual_cells[0].y
	var maximum_x := visual_cells[0].x
	var maximum_y := visual_cells[0].y
	for cell in visual_cells:
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


func _begin_part_transformation(part: ShipPart) -> void:
	if not GameState.ship.add_transitioning_part(part):
		push_error("Could not track the transitioning ship part.")
		return

	var cells := part.get_occupied_cells()
	var highlights: Array[ColorRect] = []
	_clear_preview()
	for cell in cells:
		_locked_cells[cell] = true
		var highlight := ColorRect.new()
		highlight.position = grid_layer.map_to_local(cell) - Vector2(tile_size) * 0.5
		highlight.size = Vector2(tile_size)
		highlight.color = PART_FLASH_PURPLE
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		animation_layer.add_child(highlight)
		highlights.append(highlight)

	_active_morph_count += 1
	GameState.begin_part_transformation()
	GameState.discover_part(part.type)
	AudioManager.play_sfx(MORPH_SFX)

	var tween := create_tween()
	var elapsed := 0.0
	var flash_index := 0
	while elapsed < PART_TRANSFORM_DURATION:
		var interval := lerpf(
			PART_FLASH_START_INTERVAL,
			PART_FLASH_END_INTERVAL,
			elapsed / PART_TRANSFORM_DURATION
		)
		var phase_duration := minf(interval, PART_TRANSFORM_DURATION - elapsed)
		var flash_color: Color
		match flash_index % 3:
			0:
				flash_color = PART_FLASH_PURPLE
			1:
				flash_color = PART_FLASH_YELLOW
			_:
				flash_color = PART_FLASH_WHITE
		tween.tween_callback(_set_morph_highlights_color.bind(highlights, flash_color))
		tween.tween_interval(phase_duration)
		elapsed += phase_duration
		flash_index += 1
	tween.tween_callback(_complete_part_transformation.bind(part, cells, highlights))


func _set_morph_highlights_color(highlights: Array[ColorRect], color: Color) -> void:
	for highlight in highlights:
		if is_instance_valid(highlight):
			highlight.color = color


func _complete_part_transformation(
	part: ShipPart,
	cells: Array[Vector2i],
	highlights: Array[ColorRect]
) -> void:
	for highlight in highlights:
		if is_instance_valid(highlight):
			highlight.hide()
			highlight.queue_free()
	for cell in cells:
		_locked_cells.erase(cell)

	GameState.ship.remove_transitioning_part(part)
	_evaluate_part_patterns()
	_active_morph_count -= 1
	GameState.end_part_transformation()


func _get_texture_for_part(part: ShipPart) -> Texture2D:
	for pattern in _part_patterns:
		if pattern.part_type != part.type:
			continue
		if pattern.preview_texture == null:
			push_error("No preview texture is assigned for %s." % pattern.display_name)
			return null
		return pattern.preview_texture

	push_error("Unknown ship part type: %s" % part.type)
	return null




func _zoom_at(local_mouse_position: Vector2, zoom_delta: float) -> void:
	var next_zoom := clampf(_target_zoom + zoom_delta, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(_target_zoom, next_zoom):
		return

	_zoom_anchor_position = local_mouse_position
	_zoom_anchor_map_position = (
		local_mouse_position - pan_root.position
	) / pan_root.scale.x
	_target_zoom = next_zoom
	_zoom_anchor_active = true


func _update_zoom(delta: float) -> void:
	var current_zoom := pan_root.scale.x
	if is_equal_approx(current_zoom, _target_zoom):
		_zoom_anchor_active = false
		return

	var interpolation := 1.0 - exp(-ZOOM_SMOOTHING * delta)
	var next_zoom := lerpf(current_zoom, _target_zoom, interpolation)
	if absf(next_zoom - _target_zoom) < 0.001:
		next_zoom = _target_zoom

	pan_root.scale = Vector2.ONE * next_zoom
	if _zoom_anchor_active:
		pan_root.position = _zoom_anchor_position - _zoom_anchor_map_position * next_zoom
	_clamp_pan_position()
	if is_equal_approx(next_zoom, _target_zoom):
		_zoom_anchor_active = false


func _pan_with_keyboard(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_D):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_W):
		direction.y += 1.0
	if Input.is_key_pressed(KEY_S):
		direction.y -= 1.0
	if direction.is_zero_approx():
		return

	_pan_by(direction.normalized() * KEYBOARD_PAN_SPEED * delta)


func _pan_by(offset: Vector2) -> void:
	var previous_position := pan_root.position
	pan_root.position += offset
	_clamp_pan_position()
	if _zoom_anchor_active:
		_zoom_anchor_position += pan_root.position - previous_position


func _on_build_button_toggled(is_selected: bool, source_id: int) -> void:
	_is_placing = false
	_last_placed_cell = INVALID_CELL
	if is_selected:
		_selected_source_id = source_id
	elif _selected_source_id == source_id:
		_selected_source_id = NO_SOURCE_ID
	_update_preview()


func _get_cell_at_local_position(local_mouse_position: Vector2) -> Vector2i:
	if not Rect2(Vector2.ZERO, size).has_point(local_mouse_position):
		return INVALID_CELL
	if _is_mouse_over_selector_area(local_mouse_position):
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


func _is_mouse_over_selector_area(local_mouse_position: Vector2) -> bool:
	var canvas_mouse_position := get_global_transform_with_canvas() * local_mouse_position
	var background_mouse_position := (
		selector_background.get_global_transform_with_canvas().affine_inverse()
		* canvas_mouse_position
	)
	return Rect2(Vector2.ZERO, selector_background.size).has_point(background_mouse_position)


func _update_preview() -> void:
	_update_preview_at(get_local_mouse_position())


func _update_preview_at(local_mouse_position: Vector2) -> void:
	if (
		_selected_source_id == NO_SOURCE_ID
		or _is_erasing
		or _is_panning
		or not is_visible_in_tree()
	):
		_clear_preview()
		return

	var cell := _get_cell_at_local_position(local_mouse_position)
	if cell == INVALID_CELL or _locked_cells.has(cell):
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
	var world_map_size := Vector2(
		map_dimensions.x * tile_size.x,
		map_dimensions.y * tile_size.y
	)
	var map_size := world_map_size * pan_root.scale
	pan_root.position = (size - map_size) / 2.0
	_initial_pan_position_set = true
	_clamp_pan_position()
	background_starfield.configure(world_map_size, size, MIN_ZOOM)


func _on_resized() -> void:
	if _initial_pan_position_set:
		_clamp_pan_position()
	else:
		_set_initial_pan_position()


func _clamp_pan_position() -> void:
	var map_size := Vector2(map_dimensions.x * tile_size.x, map_dimensions.y * tile_size.y) * pan_root.scale
	var position_limits := size - map_size
	var viewport_center := size * 0.5
	var minimum_position := Vector2(
		minf(minf(0.0, position_limits.x), viewport_center.x - map_size.x),
		minf(minf(0.0, position_limits.y), viewport_center.y - map_size.y)
	)
	var maximum_position := Vector2(
		maxf(maxf(0.0, position_limits.x), viewport_center.x),
		maxf(maxf(0.0, position_limits.y), viewport_center.y)
	)
	pan_root.position = Vector2(
		clampf(pan_root.position.x, minimum_position.x, maximum_position.x),
		clampf(pan_root.position.y, minimum_position.y, maximum_position.y)
	)
