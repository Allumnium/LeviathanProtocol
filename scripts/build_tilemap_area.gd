extends Control

const GRID_SOURCE_ID := 0
const RED_SOURCE_ID := 1
const BLUE_SOURCE_ID := 2
const GREEN_SOURCE_ID := 3
const CORE_SOURCE_ID := 4
const FOURTH_SOURCE_ID := CORE_SOURCE_ID
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
const MIRROR_HANDLE_RADIUS := 9.0
const MIRROR_LINE_COLOR := Color(0.35, 0.9, 1.0, 0.9)
const MIRROR_HANDLE_COLOR := Color(0.04, 0.12, 0.16, 1.0)
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
@export var unrestricted_blueprints := false
@export var map_dimensions := MAX_MAP_DIMENSIONS
@export var grid_texture: Texture2D
@export var red_tile_texture: Texture2D
@export var blue_tile_texture: Texture2D
@export var green_tile_texture: Texture2D
@export var core_tile_texture: Texture2D

@onready var pan_root: Node2D = $PanRoot
@onready var background_starfield: BuildViewportStarfield = $BackgroundStars
@onready var grid_layer: TileMapLayer = $PanRoot/GridLayer
@onready var hull_polygon: Polygon2D = $PanRoot/HullPolygon
@onready var placed_layer: TileMapLayer = $PanRoot/PlacedLayer
@onready var parts_layer: Node2D = $PanRoot/PartsLayer
@onready var animation_layer: Node2D = $PanRoot/AnimationLayer
@onready var move_ghost_layer: TileMapLayer = $PanRoot/MoveGhostLayer
@onready var preview_layer: TileMapLayer = $PanRoot/PreviewLayer
@onready var selector_background: ColorRect = $SelectorBackground
@onready var selector_row: GridContainer = $SelectorRow
@onready var red_build_button: TextureButton = $SelectorRow/RedBuildButton
@onready var blue_build_button: TextureButton = $SelectorRow/BlueBuildButton
@onready var green_build_button: TextureButton = $SelectorRow/GreenBuildButton
@onready var core_build_button: TextureButton = $SelectorRow/CoreBuildButton
@onready var red_count_badge: PanelContainer = $SelectorRow/RedBuildButton/CountBadge
@onready var red_count_label: Label = $SelectorRow/RedBuildButton/CountBadge/CountLabel
@onready var blue_count_badge: PanelContainer = $SelectorRow/BlueBuildButton/CountBadge
@onready var blue_count_label: Label = $SelectorRow/BlueBuildButton/CountBadge/CountLabel
@onready var green_count_badge: PanelContainer = $SelectorRow/GreenBuildButton/CountBadge
@onready var green_count_label: Label = $SelectorRow/GreenBuildButton/CountBadge/CountLabel
@onready var core_count_badge: PanelContainer = $SelectorRow/CoreBuildButton/CountBadge
@onready var core_count_label: Label = $SelectorRow/CoreBuildButton/CountBadge/CountLabel
@onready var design_controls: VBoxContainer = $DesignControls
@onready var history_controls: HBoxContainer = $HistoryControls
@onready var save_design_button: Button = $DesignControls/SaveDesignButton
@onready var load_design_button: Button = $DesignControls/LoadDesignButton
@onready var save_design_dialog: PopupPanel = $SaveDesignDialog
@onready var save_design_name_input: LineEdit = (
	$SaveDesignDialog/Contents/ShipNameInput
)
@onready var save_design_status_label: Label = $SaveDesignDialog/Contents/StatusLabel
@onready var confirm_save_design_button: Button = (
	$SaveDesignDialog/Contents/Buttons/ConfirmSaveButton
)
@onready var cancel_save_design_button: TextureButton = (
	$SaveDesignDialog/CloseX
)
@onready var load_design_dialog: PopupPanel = $LoadDesignDialog

var undo_button: Button
var redo_button: Button
var _undo_states: Array[Dictionary] = []
var _redo_states: Array[Dictionary] = []
var _stroke_before: Dictionary = {}

var _selected_source_id := NO_SOURCE_ID
var _preview_cell := INVALID_CELL
var _preview_source_id := NO_SOURCE_ID
var _preview_mirror_half_step := -1
var _tile_set: TileSet
var _is_placing := false
var _is_erasing := false
var _is_panning := false
var _middle_pan_moved := false
var _middle_pan_start_position := Vector2.ZERO
var _middle_pan_last_position := Vector2.ZERO
var _pan_drag_button := MOUSE_BUTTON_NONE
var _is_moving_ship := false
var _ship_move_start_cell := INVALID_CELL
var _last_placed_cell := INVALID_CELL
var _last_erased_cell := INVALID_CELL
var _initial_pan_position_set := false
var _target_zoom := 1.0
var _zoom_anchor_position := Vector2.ZERO
var _zoom_anchor_map_position := Vector2.ZERO
var _zoom_anchor_active := false
var _part_patterns: Array[ShipPartPattern] = []
var auto_assemble := true
var assembly_menu: MenuButton
var crew_links_menu: PopupMenu
var recipe_matches: Array[Dictionary] = []
var recipe_preview_outlines: Array[Line2D] = []
var _part_sprites: Dictionary[ShipPart, Sprite2D] = {}
var _part_cell_outlines: Array[Panel] = []
var _locked_cells: Dictionary[Vector2i, bool] = {}
var _active_morph_count := 0
var _mirror_enabled := false
var _mirror_axis_half_step := 0
var _is_dragging_mirror := false
var _mirror_line: Line2D
var _mirror_handle_fill: Polygon2D
var _mirror_handle_ring: Line2D


func _ready() -> void:
	focus_mode = Control.FOCUS_CLICK
	map_dimensions = Vector2i.ONE * GameState.build_area_size()
	GameState.build_area_changed.connect(_resize_build_area)
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
	move_ghost_layer.tile_set = _tile_set
	preview_layer.tile_set = _tile_set
	_create_mirror_line()
	_fill_grid()
	_part_patterns = ShipPartPattern.get_catalog()
	_restore_ship_tiles()
	_evaluate_part_patterns()
	GameState.tile_inventory_changed.connect(_refresh_tile_counts)
	_refresh_tile_counts()

	var selector_group := ButtonGroup.new()
	selector_group.allow_unpress = true
	red_build_button.button_group = selector_group
	blue_build_button.button_group = selector_group
	green_build_button.button_group = selector_group
	core_build_button.button_group = selector_group

	red_build_button.toggled.connect(_on_build_button_toggled.bind(RED_SOURCE_ID))
	blue_build_button.toggled.connect(_on_build_button_toggled.bind(BLUE_SOURCE_ID))
	green_build_button.toggled.connect(_on_build_button_toggled.bind(GREEN_SOURCE_ID))
	core_build_button.toggled.connect(_on_build_button_toggled.bind(CORE_SOURCE_ID))
	save_design_button.pressed.connect(_on_save_design_pressed)
	confirm_save_design_button.pressed.connect(_on_save_design_confirmed)
	cancel_save_design_button.pressed.connect(save_design_dialog.hide)
	save_design_name_input.text_submitted.connect(_on_save_design_name_submitted)
	load_design_button.pressed.connect(_on_load_design_pressed)
	load_design_dialog.design_selected.connect(_on_library_design_selected)
	GameState.ship_stats_changed.connect(_refresh_design_controls)
	GameState.part_transformations_changed.connect(_refresh_design_controls)
	GameState.research_changed.connect(_research_authorization_changed)
	undo_button = Button.new()
	redo_button = Button.new()
	undo_button.icon = _history_icon(false)
	redo_button.icon = _history_icon(true)
	for button in [undo_button, redo_button]:
		button.custom_minimum_size = Vector2(16, 16)
		_style_tiny_history_button(button)
		history_controls.add_child(button)
	undo_button.pressed.connect(_undo)
	redo_button.pressed.connect(_redo)
	GameState.part_transformations_changed.connect(_refresh_history_buttons)
	_refresh_history_buttons()
	_refresh_design_controls()
	_setup_assembly_menu()

	resized.connect(_on_resized)
	call_deferred("_set_initial_pan_position")


func _setup_assembly_menu() -> void:
	assembly_menu = MenuButton.new()
	assembly_menu.text = "ASSEMBLY"
	assembly_menu.custom_minimum_size.y = 22
	design_controls.add_child(assembly_menu)
	design_controls.move_child(assembly_menu, 0)
	var popup := assembly_menu.get_popup()
	crew_links_menu = PopupMenu.new()
	crew_links_menu.name = "CrewLinks"
	popup.add_child(crew_links_menu)
	popup.max_size = Vector2i(600, 280)
	popup.about_to_popup.connect(_refresh_assembly_menu)
	popup.id_pressed.connect(_assembly_action)
	popup.id_focused.connect(_preview_recipe)
	popup.popup_hide.connect(_clear_recipe_preview)
	_refresh_design_controls()


func _refresh_assembly_menu() -> void:
	var popup := assembly_menu.get_popup()
	popup.clear()
	popup.add_check_item("Auto-assemble loose tiles", 0)
	popup.set_item_checked(0, auto_assemble)
	popup.add_item("Assemble loose matches (largest first)", 1)
	popup.add_item("Disassemble all; keep material", 2)
	_refresh_crew_links()
	popup.add_submenu_item("Crew links (+12%, up to 3)", "CrewLinks", 5)
	popup.add_separator()
	popup.add_item("Loose-tile matches (hover to preview)", 4)
	popup.set_item_disabled(popup.item_count - 1, true)
	recipe_matches = MaterialRecipe.loose_matches(GameState.ship, _assembly_patterns(), _locked_cells)
	for index in range(mini(recipe_matches.size(), 32)):
		var candidate := recipe_matches[index]
		popup.add_item("%s (%d cells) at %d,%d" % [candidate.pattern.display_name, candidate.cells.size(), candidate.origin.x, candidate.origin.y], 100 + index)
	if recipe_matches.is_empty():
		popup.add_item("No loose-tile matches", 3)
		popup.set_item_disabled(popup.item_count - 1, true)


func _clear_recipe_preview() -> void:
	for outline in recipe_preview_outlines:
		outline.queue_free()
	recipe_preview_outlines.clear()


func _refresh_crew_links() -> void:
	crew_links_menu.clear()
	for child in crew_links_menu.get_children():
		child.free()
	var units: Array[Dictionary] = []
	for part in GameState.ship.parts:
		units.append({"part": part, "hp": 1.0})
	for source_index in range(units.size()):
		var source: ShipPart = units[source_index].part
		if source.type != ShipPart.Type.CREW_QUARTERS:
			continue
		var menu := PopupMenu.new()
		menu.name = "Source%d" % source_index
		crew_links_menu.add_child(menu)
		crew_links_menu.add_submenu_item("Crew at %d,%d" % [source.origin.x, source.origin.y], menu.name)
		menu.add_check_item("Automatic (component order)", 0)
		menu.set_item_checked(0, not source.crew_manual)
		menu.add_separator()
		var selected := AdjacencyRules.recipients(units, source_index)
		for index in range(units.size()):
			var target: ShipPart = units[index].part
			if not AdjacencyRules.eligible(target) or not AdjacencyRules.touches(source, target):
				continue
			menu.add_check_item("%s at %d,%d" % [GameDefinitions.equipment(target.type).display_name, target.origin.x, target.origin.y], 100 + index)
			menu.set_item_checked(menu.item_count - 1, selected.has(index))
			menu.set_item_disabled(menu.item_count - 1, selected.size() >= 3 and not selected.has(index))
		menu.id_pressed.connect(func(id: int) -> void: _crew_link_action(source_index, id))
		menu.id_focused.connect(func(id: int) -> void:
			_clear_recipe_preview()
			if id >= 100 and id - 100 < GameState.ship.parts.size():
				_outline_crew_part(GameState.ship.parts[id - 100]))
		menu.popup_hide.connect(_clear_recipe_preview)
	if crew_links_menu.item_count == 0:
		crew_links_menu.add_item("Assemble Crew Quarters beside equipment")
		crew_links_menu.set_item_disabled(0, true)


func _outline_crew_part(part: ShipPart) -> void:
	for cell in part.get_occupied_cells():
		var outline := Line2D.new()
		outline.position = Vector2(cell) * Vector2(tile_size)
		outline.points = PackedVector2Array([Vector2.ZERO, Vector2(tile_size.x, 0), Vector2(tile_size), Vector2(0, tile_size.y), Vector2.ZERO])
		outline.width = 2
		outline.default_color = Color("88ddec")
		animation_layer.add_child(outline)
		recipe_preview_outlines.append(outline)


func _crew_link_action(source_index: int, id: int) -> void:
	if GameState.active_part_transformations > 0 or source_index >= GameState.ship.parts.size():
		return
	var source := GameState.ship.parts[source_index]
	if source.type != ShipPart.Type.CREW_QUARTERS:
		return
	var before := _history_state()
	if id == 0:
		source.crew_manual = false
		source.crew_recipients.clear()
	elif id >= 100 and id - 100 < GameState.ship.parts.size():
		var target := GameState.ship.parts[id - 100]
		if not AdjacencyRules.eligible(target) or not AdjacencyRules.touches(source, target):
			return
		if not source.crew_manual:
			var units: Array[Dictionary] = []
			for part in GameState.ship.parts:
				units.append({"part": part, "hp": 1.0})
			for index in AdjacencyRules.recipients(units, source_index):
				source.crew_recipients.append(GameState.ship.parts[index].origin - source.origin)
			source.crew_manual = true
		# Editing may have removed a formerly selected component. Such stale
		# references must not consume the three available choices in this editor.
		var current: Array[Vector2i] = []
		for part in GameState.ship.parts:
			var offset := part.origin - source.origin
			if source.crew_recipients.has(offset) and AdjacencyRules.eligible(part) and AdjacencyRules.touches(source, part):
				current.append(offset)
		source.crew_recipients.assign(current)
		var relative := target.origin - source.origin
		if source.crew_recipients.has(relative):
			source.crew_recipients.erase(relative)
		elif source.crew_recipients.size() < 3:
			source.crew_recipients.append(relative)
	_record_change(before)
	GameState.ship_stats_changed.emit()


func _preview_recipe(id: int) -> void:
	_clear_recipe_preview()
	var index := id - 100
	if index < 0 or index >= recipe_matches.size():
		return
	for cell: Vector2i in recipe_matches[index].cells:
		var outline := Line2D.new()
		outline.position = Vector2(cell) * Vector2(tile_size)
		outline.points = PackedVector2Array([Vector2.ZERO, Vector2(tile_size.x, 0), Vector2(tile_size), Vector2(0, tile_size.y), Vector2.ZERO])
		outline.width = 2.0
		outline.default_color = Color(1.0, 0.85, 0.25)
		animation_layer.add_child(outline)
		recipe_preview_outlines.append(outline)


func _assembly_action(id: int) -> void:
	if GameState.active_part_transformations > 0:
		return
	if id == 0:
		auto_assemble = not auto_assemble
		return
	var before := _history_state()
	if id == 1:
		_evaluate_part_patterns(true)
	elif id == 2:
		auto_assemble = false
		GameState.ship.clear_parts()
		_evaluate_part_patterns()
	elif id >= 100 and id - 100 < recipe_matches.size():
		var candidate := recipe_matches[id - 100]
		_try_morph_pattern(candidate.origin, candidate.pattern, Vector2i(candidate.turns, 1 if candidate.flipped else 0))
	else:
		return
	while GameState.active_part_transformations > 0:
		await GameState.part_transformations_changed
	_restore_loaded_ship_design()
	GameState.ship_stats_changed.emit()
	_record_change(before)


func move_controls_to(container: VBoxContainer) -> void:
	selector_background.hide()
	selector_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selector_background.set_process_input(false)
	selector_background.set_process_unhandled_input(false)
	selector_background.set_process_unhandled_key_input(false)

	selector_row.reparent(container)
	design_controls.reparent(container)
	for controls in [selector_row, design_controls]:
		controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	design_controls.size_flags_vertical = Control.SIZE_SHRINK_END
	for button in [red_build_button, blue_build_button, green_build_button, core_build_button]:
		button.custom_minimum_size = Vector2(36, 36)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for button in [save_design_button, load_design_button]:
		button.custom_minimum_size = Vector2(0, 30)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _history_icon(point_right: bool) -> Texture2D:
	var image := Image.new()
	var transform := ' transform="translate(28 0) scale(-1 1)"' if point_right else ""
	var svg := (
		'<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 28 28">'
		+ '<path%s d="M12 7H8V2L1 9l7 7v-5h4c5 0 8 3 8 8 0 2-.5 4-1.5 6 3-2.5 4.5-5.5 4.5-9 0-5-4-9-11-9z" fill="#cfdee4"/>' % transform
		+ "</svg>"
	)
	image.load_svg_from_string(svg)
	return ImageTexture.create_from_image(image)


func _style_tiny_history_button(button: Button) -> void:
	button.theme_type_variation = &"TinyIconButton"


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
	var core_source := _create_atlas_source(core_tile_texture, "core")
	if grid_source == null or red_source == null or blue_source == null or green_source == null or core_source == null:
		return false

	tile_set.add_source(grid_source, GRID_SOURCE_ID)
	tile_set.add_source(red_source, RED_SOURCE_ID)
	tile_set.add_source(blue_source, BLUE_SOURCE_ID)
	tile_set.add_source(green_source, GREEN_SOURCE_ID)
	tile_set.add_source(core_source, CORE_SOURCE_ID)
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
		if not _keyboard_navigation_blocked() and get_viewport().gui_get_focus_owner() in [null, self]:
			_pan_with_keyboard(delta)
		_update_zoom(delta)
	_refresh_mirror_visuals()
	_update_preview()


func _keyboard_navigation_blocked() -> bool:
	if GameState.is_modal_ui_open() or save_design_dialog.visible or load_design_dialog.visible:
		return true
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _input(event: InputEvent) -> void:
	var motion_event := event as InputEventMouseMotion
	if motion_event != null:
		var local_motion_event := make_input_local(motion_event) as InputEventMouseMotion
		if local_motion_event == null:
			return
		var local_mouse_position := local_motion_event.position
		if _is_dragging_mirror:
			_set_mirror_axis_from_local_position(local_mouse_position)
			accept_event()
			return
		if _is_moving_ship:
			_update_ship_move_ghost(_get_cell_at_local_position(local_mouse_position))
			_clear_preview()
			return
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
	if mouse_button_event.button_index == MOUSE_BUTTON_LEFT:
		var mirror_local_event := make_input_local(mouse_button_event) as InputEventMouseButton
		if mirror_local_event != null:
			if (
				mouse_button_event.pressed
				and _mirror_enabled
				and not _keyboard_navigation_blocked()
				and _is_mouse_over_mirror_handle(mirror_local_event.position)
			):
				_is_dragging_mirror = true
				_is_placing = false
				_is_erasing = false
				_clear_preview()
				accept_event()
				return
			if not mouse_button_event.pressed and _is_dragging_mirror:
				_set_mirror_axis_from_local_position(mirror_local_event.position)
				_is_dragging_mirror = false
				accept_event()
				return
	if (
		mouse_button_event.button_index == MOUSE_BUTTON_LEFT
		and (_selected_source_id == NO_SOURCE_ID or _is_moving_ship)
	):
		var local_event := make_input_local(mouse_button_event) as InputEventMouseButton
		if local_event == null:
			return
		var local_position := local_event.position
		if mouse_button_event.pressed:
			if not is_visible_in_tree() or not _is_mouse_over_build_area(local_position):
				return
			_ship_move_start_cell = _get_cell_at_local_position(local_position)
			if _ship_move_start_cell == INVALID_CELL:
				return
			_is_moving_ship = true
			_update_ship_move_ghost(_ship_move_start_cell)
			_clear_preview()
			accept_event()
		elif _is_moving_ship:
			var end_cell := _get_cell_at_local_position(local_position)
			_is_moving_ship = false
			move_ghost_layer.clear()
			if end_cell != INVALID_CELL:
				_move_ship_by(end_cell - _ship_move_start_cell)
			_ship_move_start_cell = INVALID_CELL
			accept_event()
		return
	var is_pan_drag_event := mouse_button_event.button_index == MOUSE_BUTTON_MIDDLE
	if is_pan_drag_event:
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
			_pan_drag_button = mouse_button_event.button_index
			_middle_pan_moved = false
			_middle_pan_start_position = local_mouse_position
			_middle_pan_last_position = local_mouse_position
			_clear_preview()
			accept_event()
		elif _is_panning:
			_is_panning = false
			if (
				mouse_button_event.button_index == MOUSE_BUTTON_MIDDLE
				and not _middle_pan_moved
				and _is_mouse_over_build_area(local_mouse_position)
				and not _is_mouse_over_selector_area(local_mouse_position)
			):
				_pick_tile_at(_get_cell_at_local_position(local_mouse_position))
			_pan_drag_button = MOUSE_BUTTON_NONE
			accept_event()
		return
	if mouse_button_event.pressed:
		return
	if mouse_button_event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_finish_stroke()
	if mouse_button_event.button_index == MOUSE_BUTTON_LEFT:
		_is_placing = false
		_last_placed_cell = INVALID_CELL
	elif mouse_button_event.button_index == MOUSE_BUTTON_RIGHT:
		_is_erasing = false
		_last_erased_cell = INVALID_CELL


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		grab_focus()
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
			_begin_stroke()
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

	_begin_stroke()
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
	var changed := _apply_selected_tool_at(cell)
	var mirrored_cell := _get_mirrored_cell(cell)
	if mirrored_cell != INVALID_CELL:
		changed = _apply_selected_tool_at(mirrored_cell) or changed
	if not changed:
		return
	AudioManager.play_sfx(PLACE_SFX)
	_evaluate_part_patterns()


func _apply_selected_tool_at(cell: Vector2i) -> bool:
	if not _is_cell_in_build_area(cell):
		return false
	if _locked_cells.has(cell):
		return false

	var existing_category := GameState.ship.get_tile_category_at(cell)
	var category := _get_category_for_source_id(_selected_source_id)
	if category == NO_CATEGORY:
		return false
	if existing_category == category:
		return false
	GameState.ship.set_tile_at(cell, category)
	placed_layer.set_cell(cell, _selected_source_id, Vector2i.ZERO)
	return true


func _remove_tile_at(cell: Vector2i) -> void:
	var changed := _remove_tile_at_single(cell)
	var mirrored_cell := _get_mirrored_cell(cell)
	if mirrored_cell != INVALID_CELL:
		changed = _remove_tile_at_single(mirrored_cell) or changed
	if changed:
		_evaluate_part_patterns()


func _remove_tile_at_single(cell: Vector2i) -> bool:
	if not _is_cell_in_build_area(cell) or _locked_cells.has(cell):
		return false

	var category := GameState.ship.get_tile_category_at(cell)
	if category == NO_CATEGORY:
		return false

	GameState.ship.remove_tile_at(cell)
	placed_layer.erase_cell(cell)
	return true


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
		CORE_SOURCE_ID:
			core_build_button.button_pressed = true
		_:
			return
	_selected_source_id = source_id
	_update_preview()


func _refresh_tile_counts() -> void:
	red_count_badge.hide()
	blue_count_badge.hide()
	green_count_badge.hide()
	core_count_badge.hide()


func _resize_build_area() -> void:
	map_dimensions = Vector2i.ONE * GameState.build_area_size()
	_mirror_axis_half_step = clampi(_mirror_axis_half_step, 0, map_dimensions.y * 2)
	_fill_grid()
	_refresh_mirror_visuals()
	_initial_pan_position_set = false
	_set_initial_pan_position()


func _evaluate_part_patterns(force_assembly := false) -> void:
	_clear_part_placeholders()
	_restore_ship_tiles()
	_refresh_ship_hull()
	# Editing unrelated material must not replace already assembled identities.
	var intact: Array[ShipPart] = []
	for part in GameState.ship.parts:
		var pattern := _get_pattern_for_part(part)
		if pattern == null:
			continue
		var valid := true
		for index in range(part.cell_offsets.size()):
			if GameState.ship.get_tile_category_at(part.origin + part.cell_offsets[index]) != pattern.tile_categories[index]:
				valid = false
				break
		if valid:
			intact.append(part)
	GameState.ship.parts = intact
	for part in intact:
		var pattern := _get_pattern_for_part(part)
		var orientation := part.get_transform(pattern)
		_add_part_placeholder(part, pattern, orientation.x, orientation.y == 1)
	var ordered := _assembly_patterns()
	ordered.sort_custom(func(a: ShipPartPattern, b: ShipPartPattern) -> bool: return a.cell_offsets.size() > b.cell_offsets.size())
	for pattern in ordered:
		if not auto_assemble and not force_assembly:
			break
		if pattern.tile_categories.size() != pattern.cell_offsets.size():
			continue
		for origin in _candidate_origins(pattern):
			_try_morph_pattern(origin, pattern, Vector2i(-1, 0), true)
	GameState.ship_stats_changed.emit()


func _candidate_origins(pattern: ShipPartPattern) -> Array[Vector2i]:
	# A match must anchor its first recipe cell on matching loose material.
	# Preserve the old row/column order without visiting every empty grid cell.
	var candidates: Dictionary = {}
	for turns in range(4 if pattern.can_rotate else 1):
		for flip in range(2):
			var offsets := pattern.get_offsets_for_transform(turns, flip == 1)
			for cell: Vector2i in GameState.ship.tiles:
				if GameState.ship.tiles[cell] != pattern.tile_categories[0] or _locked_cells.has(cell) or GameState.ship.get_part_at(cell) != null:
					continue
				var origin: Vector2i = cell - offsets[0]
				if _is_cell_in_build_area(origin):
					candidates[origin] = true
	var result: Array[Vector2i] = []
	result.assign(candidates.keys())
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x)
	return result


func _try_morph_pattern(
	origin: Vector2i,
	pattern: ShipPartPattern,
	orientation_hint := Vector2i(-1, 0),
	authorization_checked := false
) -> bool:
	# _assembly_patterns already authorized the full scan. Do not rebuild the
	# catalog and grants for every empty grid origin on every painted tile.
	if not authorization_checked and not unrestricted_blueprints and not GameState.is_equipment_available(pattern.part_type, pattern.rank):
		return false
	var rotation_count := 4 if pattern.can_rotate else 1
	for quarter_turns in range(rotation_count):
		for flip_index in range(2):
			if orientation_hint.x >= 0 and orientation_hint != Vector2i(quarter_turns, flip_index):
				continue
			var horizontally_flipped := flip_index == 1
			var cell_offsets := pattern.get_offsets_for_transform(
				quarter_turns, horizontally_flipped
			)
			if not _matches_pattern(origin, pattern, cell_offsets):
				continue

			var part := ShipPart.new(
				pattern.part_type,
				pattern.category,
				origin,
				cell_offsets,
				pattern.stats,
				pattern.get_hidden_tile_offsets_for_transform(
					quarter_turns, horizontally_flipped
				),
				quarter_turns,
				horizontally_flipped,
				pattern.rank
			)
			if GameState.has_discovered_part(part.type):
				if not GameState.ship.add_part(part):
					push_error("Could not add a matched part to the ship.")
					return false
				_add_part_placeholder(
					part, pattern, quarter_turns, horizontally_flipped
				)
			else:
				_begin_part_transformation(part)
			return true
	return false


func _assembly_patterns() -> Array[ShipPartPattern]:
	var result: Array[ShipPartPattern] = []
	var grants := GameState.research_grants()
	for pattern in _part_patterns:
		# These patterns already came from the implemented catalog. Read the
		# current authorization once rather than rebuilding it per pattern.
		if unrestricted_blueprints or (grants.equipment_ids.has(pattern.definition_id) and pattern.rank <= int(grants.ranks.get(pattern.definition_id, 0))):
			result.append(pattern)
	return result


func _research_authorization_changed() -> void:
	# Authorization updates available choices, never assembled or loose material.
	recipe_matches.clear()
	_clear_recipe_preview()
	if assembly_menu != null and assembly_menu.get_popup().visible:
		_refresh_assembly_menu()
	_refresh_design_controls()


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
		ShipPart.Category.CORE:
			return CORE_SOURCE_ID
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
		CORE_SOURCE_ID:
			return ShipPart.Category.CORE
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
		ShipPart.Category.CORE:
			return core_tile_texture
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
	var hull := Ship.create_hull_polygon(GameState.ship.get_tile_cells())
	for index in range(hull.size()):
		hull[index] *= Vector2(tile_size)
	hull_polygon.polygon = hull


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
	quarter_turns: int,
	horizontally_flipped: bool = false
) -> void:
	var texture := _get_texture_for_part(part)
	if texture == null:
		return

	var visual_cells: Array[Vector2i] = []
	for offset in pattern.get_visual_offsets_for_transform(
		quarter_turns, horizontally_flipped
	):
		visual_cells.append(part.origin + offset)
	if visual_cells.is_empty():
		push_error("Cannot display a ship part with no visual cells.")
		return

	for offset in pattern.get_hidden_tile_offsets_for_transform(
		quarter_turns, horizontally_flipped
	):
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
	if not unrestricted_blueprints and not GameState.is_equipment_available(part.type, part.rank):
		return
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
	if unrestricted_blueprints or GameState.is_equipment_available(part.type, part.rank):
		GameState.ship.add_part(part)
	_evaluate_part_patterns()
	_active_morph_count -= 1
	GameState.end_part_transformation()


func _get_texture_for_part(part: ShipPart) -> Texture2D:
	var pattern := _get_pattern_for_part(part)
	if pattern == null:
		return null
	if pattern.preview_texture == null:
		push_error("No preview texture is assigned for %s." % pattern.display_name)
		return null
	return pattern.preview_texture


func _get_pattern_for_part(part: ShipPart) -> ShipPartPattern:
	for pattern in _part_patterns:
		if pattern.part_type == part.type and pattern.rank == part.rank:
			return pattern
	push_error("Unknown ship part type: %s" % part.type)
	return null


func _refresh_design_controls() -> void:
	var can_change_design := GameState.active_part_transformations == 0
	save_design_button.disabled = not can_change_design or GameState.ship.tiles.is_empty()
	var problem := GameState.design_research_error(GameState.ship)
	load_design_button.disabled = not can_change_design
	if assembly_menu != null:
		assembly_menu.disabled = not can_change_design


func _on_save_design_pressed() -> void:
	if not GameState.current_ship_design_name.is_empty():
		var error_message := GameState.save_current_ship_design(
			GameState.current_ship_design_name
		)
		if error_message.is_empty():
			_saved_feedback()
			return
		save_design_status_label.text = error_message
		save_design_name_input.text = GameState.current_ship_design_name
		save_design_dialog.popup_centered()
		save_design_name_input.grab_focus()
		return

	save_design_status_label.text = ""
	save_design_name_input.text = ""
	save_design_dialog.popup_centered()
	save_design_name_input.grab_focus()


func _on_save_design_name_submitted(submitted_name: String) -> void:
	save_design_name_input.text = submitted_name
	_on_save_design_confirmed()


func _on_save_design_confirmed() -> void:
	var error_message := GameState.save_current_ship_design(
		save_design_name_input.text
	)
	if not error_message.is_empty():
		save_design_status_label.text = error_message
		save_design_name_input.grab_focus()
		return
	save_design_dialog.hide()
	_saved_feedback()


func _saved_feedback() -> void:
	save_design_button.text = "SAVED"
	var button: WeakRef = weakref(save_design_button)
	get_tree().create_timer(1.8).timeout.connect(func() -> void:
		var control: Button = button.get_ref()
		if is_instance_valid(control):
			control.text = "SAVE")


func _on_load_design_pressed() -> void:
	load_design_dialog.open_library("LOAD", _validate_library_design)


func _validate_library_design(saved_ship: Ship) -> String:
	return "Upgrade the build area to load this design." if not GameState.design_fits_build_area(saved_ship) else ""


func _on_library_design_selected(design_name: String, _design: Ship) -> void:
	_on_load_saved_design_pressed(design_name)


func _on_load_saved_design_pressed(design_name: String) -> void:
	var before := _history_state()
	if not GameState.load_saved_ship_design(design_name):
		load_design_dialog.status_label.text = (
			"Could not load this design. Check the build area size."
		)
		load_design_dialog.status_label.visible = true
		return

	_record_change(before)
	_restore_loaded_ship_design()


func _restore_loaded_ship_design() -> void:
	_clear_preview()
	_clear_part_placeholders()
	_locked_cells.clear()
	_restore_ship_tiles()
	_refresh_ship_hull()

	for part in GameState.ship.parts:
		var pattern := _get_pattern_for_part(part)
		if pattern == null:
			continue
		var transform := part.get_transform(pattern)
		if transform.x < 0:
			push_error("Could not determine the rotation for %s." % pattern.display_name)
			continue
		_add_part_placeholder(part, pattern, transform.x, transform.y == 1)


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
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
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


func _move_ship_by(cell_offset: Vector2i) -> bool:
	if cell_offset == Vector2i.ZERO or GameState.ship.tiles.is_empty():
		return false
	var moved_tiles: Dictionary[Vector2i, int] = {}
	for cell in GameState.ship.tiles:
		var moved_cell: Vector2i = cell + cell_offset
		if (
			moved_cell.x < 0
			or moved_cell.y < 0
			or moved_cell.x >= map_dimensions.x
			or moved_cell.y >= map_dimensions.y
		):
			return false
		moved_tiles[moved_cell] = GameState.ship.tiles[cell]
	var before := _history_state()
	GameState.ship.tiles = moved_tiles
	for part in GameState.ship.parts:
		part.origin += cell_offset
	_evaluate_part_patterns()
	_record_change(before)
	return true


func _update_ship_move_ghost(target_cell: Vector2i) -> void:
	move_ghost_layer.clear()
	if target_cell == INVALID_CELL or _ship_move_start_cell == INVALID_CELL:
		return
	var cell_offset := target_cell - _ship_move_start_cell
	for cell in GameState.ship.tiles:
		var moved_cell: Vector2i = cell + cell_offset
		if (
			moved_cell.x < 0
			or moved_cell.y < 0
			or moved_cell.x >= map_dimensions.x
			or moved_cell.y >= map_dimensions.y
		):
			move_ghost_layer.clear()
			return
		var source_id := _get_source_id_for_category(GameState.ship.tiles[cell])
		if source_id != NO_SOURCE_ID:
			move_ghost_layer.set_cell(moved_cell, source_id, Vector2i.ZERO)


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
	if not selector_background.visible:
		return false
	var canvas_mouse_position := get_global_transform_with_canvas() * local_mouse_position
	var background_mouse_position := (
		selector_background.get_global_transform_with_canvas().affine_inverse()
		* canvas_mouse_position
	)
	if Rect2(Vector2.ZERO, selector_background.size).has_point(background_mouse_position):
		return true

	var design_controls_mouse_position := (
		design_controls.get_global_transform_with_canvas().affine_inverse()
		* canvas_mouse_position
	)
	return Rect2(Vector2.ZERO, design_controls.size).has_point(
		design_controls_mouse_position
	)


func _create_mirror_line() -> void:
	_mirror_axis_half_step = map_dimensions.y
	_mirror_line = Line2D.new()
	_mirror_line.default_color = MIRROR_LINE_COLOR
	_mirror_line.antialiased = false
	_mirror_line.z_index = 40
	pan_root.add_child(_mirror_line)

	_mirror_handle_fill = Polygon2D.new()
	_mirror_handle_fill.color = MIRROR_HANDLE_COLOR
	_mirror_handle_fill.z_index = 41
	_mirror_handle_fill.polygon = _circle_points(MIRROR_HANDLE_RADIUS, 20, false)
	pan_root.add_child(_mirror_handle_fill)

	_mirror_handle_ring = Line2D.new()
	_mirror_handle_ring.default_color = MIRROR_LINE_COLOR
	_mirror_handle_ring.antialiased = false
	_mirror_handle_ring.closed = true
	_mirror_handle_ring.z_index = 42
	_mirror_handle_ring.points = _circle_points(MIRROR_HANDLE_RADIUS, 20, true)
	pan_root.add_child(_mirror_handle_ring)
	_refresh_mirror_visuals()


func _circle_points(radius: float, point_count: int, close_shape: bool) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := point_count + 1 if close_shape else point_count
	for index in range(count):
		var angle := TAU * float(index % point_count) / float(point_count)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _toggle_mirror_line() -> void:
	_mirror_enabled = not _mirror_enabled
	_is_dragging_mirror = false
	_clear_preview()
	_refresh_mirror_visuals()
	_update_preview()


func _refresh_mirror_visuals() -> void:
	if _mirror_line == null:
		return
	var visible_now := _mirror_enabled and is_visible_in_tree()
	_mirror_line.visible = visible_now
	_mirror_handle_fill.visible = visible_now
	_mirror_handle_ring.visible = visible_now
	if not visible_now:
		return
	var zoom := maxf(pan_root.scale.x, 0.001)
	var axis_y := float(_mirror_axis_half_step) * float(tile_size.y) * 0.5
	var grid_width := float(map_dimensions.x * tile_size.x)
	var handle_offset := (MIRROR_HANDLE_RADIUS + 5.0) / zoom
	var handle_position := Vector2(grid_width + handle_offset, axis_y)
	_mirror_line.width = 2.0 / zoom
	_mirror_line.points = PackedVector2Array([
		Vector2(0.0, axis_y),
		handle_position,
	])
	_mirror_handle_fill.position = handle_position
	_mirror_handle_ring.position = handle_position
	_mirror_handle_fill.scale = Vector2.ONE / zoom
	_mirror_handle_ring.scale = Vector2.ONE / zoom
	_mirror_handle_ring.width = 2.0


func _set_mirror_axis_from_local_position(local_mouse_position: Vector2) -> void:
	var canvas_position := get_global_transform_with_canvas() * local_mouse_position
	var pan_position := (
		pan_root.get_global_transform_with_canvas().affine_inverse() * canvas_position
	)
	var next_half_step := roundi(pan_position.y * 2.0 / float(tile_size.y))
	_mirror_axis_half_step = clampi(next_half_step, 0, map_dimensions.y * 2)
	_clear_preview()
	_refresh_mirror_visuals()


func _is_mouse_over_mirror_handle(local_mouse_position: Vector2) -> bool:
	if not _mirror_enabled:
		return false
	var canvas_position := get_global_transform_with_canvas() * local_mouse_position
	var pan_position := (
		pan_root.get_global_transform_with_canvas().affine_inverse() * canvas_position
	)
	var axis_y := float(_mirror_axis_half_step) * float(tile_size.y) * 0.5
	var grid_width := float(map_dimensions.x * tile_size.x)
	var handle_offset := (MIRROR_HANDLE_RADIUS + 5.0) / maxf(pan_root.scale.x, 0.001)
	var handle_position := Vector2(grid_width + handle_offset, axis_y)
	var radius_in_world := (MIRROR_HANDLE_RADIUS + 4.0) / maxf(pan_root.scale.x, 0.001)
	return pan_position.distance_to(handle_position) <= radius_in_world


func _get_mirrored_cell(cell: Vector2i) -> Vector2i:
	if not _mirror_enabled or not _is_cell_in_build_area(cell):
		return INVALID_CELL
	var mirrored_cell := Vector2i(cell.x, _mirror_axis_half_step - cell.y - 1)
	if mirrored_cell == cell or not _is_cell_in_build_area(mirrored_cell):
		return INVALID_CELL
	return mirrored_cell


func _is_cell_in_build_area(cell: Vector2i) -> bool:
	return (
		cell != INVALID_CELL
		and cell.x >= 0
		and cell.y >= 0
		and cell.x < map_dimensions.x
		and cell.y < map_dimensions.y
	)


func _update_preview() -> void:
	_update_preview_at(get_local_mouse_position())


func _update_preview_at(local_mouse_position: Vector2) -> void:
	if (
		_selected_source_id == NO_SOURCE_ID
		or _get_category_for_source_id(_selected_source_id) == NO_CATEGORY
		or _is_erasing
		or _is_panning
		or _is_dragging_mirror
		or not is_visible_in_tree()
	):
		_clear_preview()
		return

	var cell := _get_cell_at_local_position(local_mouse_position)
	if cell == INVALID_CELL or _locked_cells.has(cell):
		_clear_preview()
		return
	if (
		cell == _preview_cell
		and _selected_source_id == _preview_source_id
		and _preview_mirror_half_step == (_mirror_axis_half_step if _mirror_enabled else -1)
	):
		return

	preview_layer.clear()
	preview_layer.set_cell(cell, _selected_source_id, Vector2i.ZERO)
	var mirrored_cell := _get_mirrored_cell(cell)
	if mirrored_cell != INVALID_CELL and not _locked_cells.has(mirrored_cell):
		preview_layer.set_cell(mirrored_cell, _selected_source_id, Vector2i.ZERO)
	_preview_cell = cell
	_preview_source_id = _selected_source_id
	_preview_mirror_half_step = _mirror_axis_half_step if _mirror_enabled else -1


func _clear_preview() -> void:
	if _preview_cell == INVALID_CELL and preview_layer.get_used_cells().is_empty():
		return
	preview_layer.clear()
	_preview_cell = INVALID_CELL
	_preview_source_id = NO_SOURCE_ID
	_preview_mirror_half_step = -1


func _set_initial_pan_position() -> void:
	if _initial_pan_position_set or size.x <= 0.0 or size.y <= 0.0:
		return
	var world_map_size := Vector2(
		map_dimensions.x * tile_size.x,
		map_dimensions.y * tile_size.y
	)
	var usable_start := Vector2(size.x * 0.17 + 8.0, 8.0)
	var usable_size := Vector2(maxf(size.x - usable_start.x - 68.0, 1.0), maxf(size.y - 16.0, 1.0))
	_target_zoom = clampf(minf(usable_size.x / world_map_size.x, usable_size.y / world_map_size.y), MIN_ZOOM, 1.0)
	pan_root.scale = Vector2.ONE * _target_zoom
	var map_size := world_map_size * pan_root.scale
	pan_root.position = usable_start + (usable_size - map_size) / 2.0
	_initial_pan_position_set = true
	_clamp_pan_position()
	background_starfield.configure(world_map_size, size, MIN_ZOOM)


func _on_resized() -> void:
	_initial_pan_position_set = false
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


func _history_state() -> Dictionary:
	return {"design": GameState.ship.to_design_data(), "name": GameState.current_ship_design_name}

func _begin_stroke() -> void:
	_finish_stroke()
	_stroke_before = _history_state()

func _finish_stroke() -> void:
	if not _stroke_before.is_empty():
		_record_change(_stroke_before)
		_stroke_before = {}

func _record_change(before: Dictionary) -> void:
	if before == _history_state():
		return
	_undo_states.append(before)
	if _undo_states.size() > 100:
		_undo_states.pop_front()
	_redo_states.clear()
	_refresh_history_buttons()

func _refresh_history_buttons() -> void:
	if undo_button == null:
		return
	undo_button.disabled = _undo_states.is_empty() or GameState.active_part_transformations > 0
	redo_button.disabled = _redo_states.is_empty() or GameState.active_part_transformations > 0

func _restore_history(state: Dictionary) -> void:
	_is_placing = false
	_is_erasing = false
	_last_placed_cell = INVALID_CELL
	_last_erased_cell = INVALID_CELL
	GameState.ship = Ship.new()
	GameState.ship.load_design_data(state.design)
	GameState.current_ship_design_name = state.name
	_clear_preview()
	_restore_loaded_ship_design()
	GameState.ship_stats_changed.emit()
	_refresh_history_buttons()

func _undo() -> void:
	if GameState.active_part_transformations > 0:
		return
	_finish_stroke()
	if _undo_states.is_empty():
		return
	_redo_states.append(_history_state())
	_restore_history(_undo_states.pop_back())

func _redo() -> void:
	if GameState.active_part_transformations > 0:
		return
	_finish_stroke()
	if _redo_states.is_empty():
		return
	_undo_states.append(_history_state())
	_restore_history(_redo_states.pop_back())

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _keyboard_navigation_blocked():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		_deselect_material()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_M:
		_toggle_mirror_line()
		get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed:
		if event.keycode == KEY_Z:
			_undo()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Y:
			_redo()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_S and not save_design_button.disabled:
			_on_save_design_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_L and not load_design_button.disabled:
			_on_load_design_pressed()
			get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_1: _select_material_button(red_build_button)
		KEY_2: _select_material_button(blue_build_button)
		KEY_3: _select_material_button(green_build_button)
		KEY_4: _select_material_button(core_build_button)
		_: return
	get_viewport().set_input_as_handled()


func _select_material_button(button: TextureButton) -> void:
	if not button.disabled:
		button.button_pressed = not button.button_pressed


func _deselect_material() -> void:
	_is_placing = false
	_last_placed_cell = INVALID_CELL
	for button in [red_build_button, blue_build_button, green_build_button, core_build_button]:
		button.button_pressed = false
	_selected_source_id = NO_SOURCE_ID
	_clear_preview()
