extends Control

const RED_MATERIAL_TEXTURE = preload("res://assets/ui/icons/red_square.png")
const BLUE_MATERIAL_TEXTURE = preload("res://assets/ui/icons/blue_square.png")
const GREEN_MATERIAL_TEXTURE = preload("res://assets/ui/icons/green_square.png")
const CORE_MATERIAL_TEXTURE = preload("res://assets/core.png")
const THRUSTER_TEXTURE = preload("res://assets/thruster_s.png")
const LARGE_THRUSTER_TEXTURE = preload("res://assets/thruster_l.png")
const TILE_SIZE := 44.0
const GRID_MARGIN := 12.0
const GRID_GAP := 4.0
const MATERIAL_TILE_SIZE := 26.0
const PATTERN_CELL_GAP := 1
const ARCHIVE_PART_ORDER := [
	ShipPart.Type.SINGLE_PLATE,
	ShipPart.Type.ARMOR_BLOCK,
	ShipPart.Type.MINI_TURRET,
	ShipPart.Type.LASER,
	ShipPart.Type.DOUBLE_LASER,
	ShipPart.Type.THRUSTER,
	ShipPart.Type.LARGE_THRUSTER,
	ShipPart.Type.COMMAND_CENTER,
	ShipPart.Type.SHIELD,
]

@onready var archive_grid: GridContainer = $GridCenter/ArchiveGrid

var _part_patterns: Array[ShipPartPattern] = []
var _part_images: Array[TextureRect] = []
var _question_labels: Array[Label] = []
var _part_buttons: Array[Button] = []
var _progress_label: Label
var _details: VBoxContainer
var _selected_index := 0
var _grid_layout_refresh_queued := false


func _ready() -> void:
	GameState.discovered_parts_changed.connect(_on_discovered_parts_changed)
	resized.connect(_queue_grid_layout_refresh)
	var button_group := ButtonGroup.new()
	button_group.allow_unpress = false
	for pattern in _get_ordered_catalog():
		archive_grid.add_child(_create_part_button(pattern, button_group))
	_refresh_discovery_masks()
	_queue_grid_layout_refresh()


func _get_ordered_catalog() -> Array[ShipPartPattern]:
	var catalog := ShipPartPattern.get_catalog()
	var ordered: Array[ShipPartPattern] = []
	for part_type in ARCHIVE_PART_ORDER:
		for pattern in catalog:
			if pattern.part_type == part_type:
				ordered.append(pattern)
	for pattern in catalog:
		if not ordered.has(pattern):
			ordered.append(pattern)
	return ordered

func bind_external_panels(progress_label: Label, details: VBoxContainer) -> void:
	_progress_label = progress_label
	_details = details
	_refresh_progress()
	_show_selected_details()


func _create_part_button(pattern: ShipPartPattern, button_group: ButtonGroup) -> Button:
	var index := _part_patterns.size()
	var button := Button.new()
	button.custom_minimum_size = Vector2.ONE * TILE_SIZE
	button.toggle_mode = true
	button.button_group = button_group
	_apply_compact_button_style(button)
	button.pressed.connect(_on_part_button_pressed.bind(index))
	var image := TextureRect.new()
	image.anchor_left = 0.25
	image.anchor_top = 0.25
	image.anchor_right = 0.75
	image.anchor_bottom = 0.75
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture = pattern.preview_texture
	match pattern.part_type:
		ShipPart.Type.THRUSTER:
			image.texture = THRUSTER_TEXTURE
		ShipPart.Type.LARGE_THRUSTER:
			image.texture = LARGE_THRUSTER_TEXTURE
	if image.texture == null:
		push_error("No Archive image is assigned for %s." % pattern.display_name)
	button.add_child(image)
	var question := Label.new()
	question.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	question.mouse_filter = Control.MOUSE_FILTER_IGNORE
	question.add_theme_color_override("font_color", Color.WHITE)
	question.add_theme_color_override("font_outline_color", Color.BLACK)
	question.add_theme_constant_override("outline_size", 2)
	question.text = "?"
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(question)
	_part_patterns.append(pattern)
	_part_images.append(image)
	_question_labels.append(question)
	_part_buttons.append(button)
	if index == 0:
		button.button_pressed = true
	return button


func _queue_grid_layout_refresh() -> void:
	if _grid_layout_refresh_queued:
		return
	_grid_layout_refresh_queued = true
	_refresh_grid_layout.call_deferred()


func _refresh_grid_layout() -> void:
	_grid_layout_refresh_queued = false
	var item_count := _part_buttons.size()
	if item_count == 0:
		return
	var available := Vector2(
		maxf(size.x - GRID_MARGIN, 1.0),
		maxf(size.y - GRID_MARGIN, 1.0)
	)
	var best_columns := 1
	var best_tile_size := 0.0
	for columns in range(1, item_count + 1):
		var rows := ceili(float(item_count) / float(columns))
		var width_per_tile := (
			available.x - GRID_GAP * float(columns - 1)
		) / float(columns)
		var height_per_tile := (
			available.y - GRID_GAP * float(rows - 1)
		) / float(rows)
		var candidate_size := minf(TILE_SIZE, minf(width_per_tile, height_per_tile))
		if candidate_size > best_tile_size:
			best_tile_size = candidate_size
			best_columns = columns
	archive_grid.columns = best_columns
	best_tile_size = maxf(best_tile_size, 1.0)
	for index in range(_part_buttons.size()):
		_part_buttons[index].custom_minimum_size = Vector2.ONE * best_tile_size


func _on_part_button_pressed(index: int) -> void:
	_selected_index = index
	_show_selected_details()


func _show_selected_details() -> void:
	if _details == null or _part_patterns.is_empty():
		return
	for child in _details.get_children():
		_details.remove_child(child)
		child.queue_free()
	var pattern := _part_patterns[_selected_index]
	var discovered := GameState.has_discovered_part(pattern.part_type)
	var header := Label.new()
	header.text = pattern.display_name.to_upper() if discovered else "UNDISCOVERED"
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_child(header)
	if not discovered:
		var undiscovered := Label.new()
		undiscovered.text = "Discover this component to reveal its details."
		undiscovered.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		undiscovered.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_details.add_child(undiscovered)
		return
	var pattern_center := CenterContainer.new()
	_details.add_child(pattern_center)
	pattern_center.add_child(_create_pattern_grid(pattern))
	_details.add_child(_create_stats_description(pattern))


func _create_stats_description(pattern: ShipPartPattern) -> VBoxContainer:
	var description := VBoxContainer.new()
	description.add_theme_constant_override("separation", 4)
	_append_stat_contribution(description, "Shields", pattern.stats.shields)
	_append_stat_contribution(description, "Integrity", pattern.stats.integrity * ShipStats.INTEGRITY_MULTIPLIER)
	_append_stat_contribution(description, "Thrust", pattern.stats.thrust)
	var total_dps := 0.0
	for weapon in pattern.stats.weapons:
		total_dps += weapon.get_dps()
	_append_stat_contribution(description, "DPS", total_dps)
	return description


func _append_stat_contribution(description: VBoxContainer, stat_name: String, value: float) -> void:
	if not is_zero_approx(value):
		description.add_child(StatDisplayRow.new(stat_name, value, _format_signed_stat_value(value), 10))


func _format_signed_stat_value(value: float) -> String:
	var formatted := _format_stat_value(value)
	return "+" + formatted if value > 0.0 else formatted


func _format_stat_value(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.2f" % value


func _apply_compact_button_style(button: Button) -> void:
	button.theme_type_variation = &"ArchiveButton"


func _create_pattern_grid(pattern: ShipPartPattern) -> GridContainer:
	var grid := GridContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", PATTERN_CELL_GAP)
	grid.add_theme_constant_override("v_separation", PATTERN_CELL_GAP)
	if pattern.cell_offsets.is_empty() or pattern.tile_categories.size() != pattern.cell_offsets.size():
		push_error("Archive pattern %s has an invalid tile layout." % pattern.display_name)
		return grid
	var min_x := pattern.cell_offsets[0].x
	var max_x := min_x
	var min_y := pattern.cell_offsets[0].y
	var max_y := min_y
	for offset in pattern.cell_offsets:
		min_x = mini(min_x, offset.x); max_x = maxi(max_x, offset.x)
		min_y = mini(min_y, offset.y); max_y = maxi(max_y, offset.y)
	var columns := max_x - min_x + 1
	grid.columns = columns
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell_index := pattern.cell_offsets.find(Vector2i(x, y))
			var cell := TextureRect.new()
			cell.custom_minimum_size = Vector2.ONE * MATERIAL_TILE_SIZE
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			cell.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			cell.texture = _get_material_texture(pattern.tile_categories[cell_index]) if cell_index >= 0 else null
			grid.add_child(cell)
	return grid


func _get_material_texture(category: int) -> Texture2D:
	match category:
		ShipPart.Category.OFFENSE: return RED_MATERIAL_TEXTURE
		ShipPart.Category.DEFENSE: return BLUE_MATERIAL_TEXTURE
		ShipPart.Category.SPECIAL: return GREEN_MATERIAL_TEXTURE
		ShipPart.Category.CORE: return CORE_MATERIAL_TEXTURE
		_: return null


func _on_discovered_parts_changed() -> void:
	_refresh_discovery_masks()
	_show_selected_details()
	if is_visible_in_tree(): GameState.mark_discoveries_viewed()


func _refresh_discovery_masks() -> void:
	for index in range(_part_images.size()):
		var discovered := GameState.has_discovered_part(_part_patterns[index].part_type)
		_part_images[index].modulate = Color.WHITE if discovered else Color.BLACK
		_question_labels[index].visible = not discovered
	_refresh_progress()


func _refresh_progress() -> void:
	if _progress_label == null: return
	var discovered_count := 0
	for pattern in _part_patterns:
		if GameState.has_discovered_part(pattern.part_type): discovered_count += 1
	_progress_label.text = "%d of %d parts discovered" % [discovered_count, _part_patterns.size()]
