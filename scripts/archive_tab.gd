extends Control

const BOLD_FONT = preload("res://assets/fonts/GameFont_bold.ttf")
const ROW_PANEL_STYLE = preload("res://assets/ui/panels/compact_panel_nine_patch.tres")
const PATTERN_DIAGRAM_SIZE := 20.0
const PATTERN_CELL_GAP := 1

@onready var archive_rows: VBoxContainer = $ArchiveScroll/ArchiveRows

var _part_patterns: Array[ShipPartPattern] = []
var _part_images: Array[TextureRect] = []
var _part_name_labels: Array[Label] = []
var _part_description_labels: Array[Label] = []
var _part_pattern_grids: Array[GridContainer] = []


func _ready() -> void:
	GameState.discovered_parts_changed.connect(_on_discovered_parts_changed)
	for pattern in ShipPartPattern.get_catalog():
		archive_rows.add_child(_create_entry(pattern))
	_refresh_discovery_masks()


func _create_entry(pattern: ShipPartPattern) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 64)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override("panel", ROW_PANEL_STYLE)

	var contents := HBoxContainer.new()
	contents.add_theme_constant_override("separation", 4)
	row.add_child(contents)

	var left_content := HBoxContainer.new()
	left_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_content.size_flags_stretch_ratio = 1.0
	left_content.add_theme_constant_override("separation", 4)
	contents.add_child(left_content)

	var image_center := CenterContainer.new()
	image_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	image_center.size_flags_stretch_ratio = 1.0
	left_content.add_child(image_center)

	var image := TextureRect.new()
	image.custom_minimum_size = Vector2(40, 40)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture = pattern.preview_texture
	if image.texture == null:
		push_error("No Archive image is assigned for %s." % pattern.display_name)
	image_center.add_child(image)

	var pattern_center := CenterContainer.new()
	pattern_center.custom_minimum_size = Vector2(PATTERN_DIAGRAM_SIZE, PATTERN_DIAGRAM_SIZE)
	pattern_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pattern_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pattern_center.size_flags_stretch_ratio = 1.0
	pattern_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_content.add_child(pattern_center)

	var pattern_grid := _create_pattern_grid(pattern)
	pattern_center.add_child(pattern_grid)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.size_flags_stretch_ratio = 1.0
	details.add_theme_constant_override("separation", 2)
	contents.add_child(details)

	var name_label := Label.new()
	name_label.text = pattern.display_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_override("font", BOLD_FONT)
	name_label.add_theme_font_size_override("font_size", 12)
	details.add_child(name_label)

	var description_label := Label.new()
	description_label.text = _get_stats_description(pattern)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description_label.add_theme_font_size_override("font_size", 10)
	details.add_child(description_label)

	_part_patterns.append(pattern)
	_part_images.append(image)
	_part_name_labels.append(name_label)
	_part_description_labels.append(description_label)
	_part_pattern_grids.append(pattern_grid)
	return row


func _get_stats_description(pattern: ShipPartPattern) -> String:
	var description_lines: Array[String] = []
	_append_stat_contribution(description_lines, "Shields", pattern.stats.shields)
	_append_stat_contribution(description_lines, "Integrity", pattern.stats.integrity)
	_append_stat_contribution(description_lines, "Weight", pattern.stats.weight)
	_append_stat_contribution(description_lines, "Thrust", pattern.stats.thrust)

	for index in range(pattern.stats.weapons.size()):
		var weapon := pattern.stats.weapons[index]
		var weapon_details: Array[String] = []
		var fire_rate := weapon.get_fire_rate_per_second()
		if not is_zero_approx(fire_rate):
			weapon_details.append("Fire rate: %.2f shots/sec" % fire_rate)
		if not is_zero_approx(weapon.damage_per_shot):
			weapon_details.append(
				"Damage/shot: %s" % _format_stat_value(weapon.damage_per_shot)
			)
		if weapon.projectiles_per_activation != 0:
			var shot_word := "shot" if weapon.projectiles_per_activation == 1 else "shots"
			weapon_details.append(
				"Shots/activation: %d %s"
				% [weapon.projectiles_per_activation, shot_word]
			)
		var weapon_dps := weapon.get_dps()
		if not is_zero_approx(weapon_dps):
			weapon_details.append("DPS: %s" % _format_signed_stat_value(weapon_dps))

		if not weapon_details.is_empty():
			var weapon_description := ""
			for detail in weapon_details:
				if not weapon_description.is_empty():
					weapon_description += ", "
				weapon_description += detail
			description_lines.append("Weapon %d: %s" % [index + 1, weapon_description])

	return "\n".join(description_lines)


func _append_stat_contribution(
	description_lines: Array[String],
	stat_name: String,
	value: float
) -> void:
	if is_zero_approx(value):
		return
	description_lines.append(
		"%s: %s" % [stat_name, _format_signed_stat_value(value)]
	)


func _format_signed_stat_value(value: float) -> String:
	var formatted_value := _format_stat_value(value)
	if value > 0.0:
		return "+" + formatted_value
	return formatted_value


func _format_stat_value(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.2f" % value


func _create_pattern_grid(pattern: ShipPartPattern) -> GridContainer:
	var pattern_grid := GridContainer.new()
	pattern_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pattern_grid.add_theme_constant_override("h_separation", PATTERN_CELL_GAP)
	pattern_grid.add_theme_constant_override("v_separation", PATTERN_CELL_GAP)

	if pattern.cell_offsets.is_empty():
		push_error("Archive pattern %s has no cells." % pattern.display_name)
		return pattern_grid
	if pattern.tile_categories.size() != pattern.cell_offsets.size():
		push_error("Archive pattern %s has an invalid tile layout." % pattern.display_name)
		return pattern_grid

	var minimum_x := pattern.cell_offsets[0].x
	var maximum_x := pattern.cell_offsets[0].x
	var minimum_y := pattern.cell_offsets[0].y
	var maximum_y := pattern.cell_offsets[0].y
	for offset in pattern.cell_offsets:
		minimum_x = mini(minimum_x, offset.x)
		maximum_x = maxi(maximum_x, offset.x)
		minimum_y = mini(minimum_y, offset.y)
		maximum_y = maxi(maximum_y, offset.y)

	var column_count := maximum_x - minimum_x + 1
	var row_count := maximum_y - minimum_y + 1
	var available_width := PATTERN_DIAGRAM_SIZE - PATTERN_CELL_GAP * (column_count - 1)
	var available_height := PATTERN_DIAGRAM_SIZE - PATTERN_CELL_GAP * (row_count - 1)
	var cell_size := maxf(
		1.0,
		minf(available_width / column_count, available_height / row_count)
	)
	pattern_grid.columns = column_count

	for y in range(minimum_y, maximum_y + 1):
		for x in range(minimum_x, maximum_x + 1):
			var offset := Vector2i(x, y)
			var cell_index := pattern.cell_offsets.find(offset)
			var cell := ColorRect.new()
			cell.custom_minimum_size = Vector2.ONE * cell_size
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.color = (
				_get_pattern_cell_color(pattern.tile_categories[cell_index])
				if cell_index >= 0
				else Color.TRANSPARENT
			)
			pattern_grid.add_child(cell)

	return pattern_grid


func _get_pattern_cell_color(category: int) -> Color:
	match category:
		ShipPart.Category.OFFENSE:
			return Color(0.92, 0.2, 0.2)
		ShipPart.Category.DEFENSE:
			return Color(0.2, 0.45, 0.95)
		ShipPart.Category.SPECIAL:
			return Color(0.2, 0.82, 0.35)
		_:
			push_error("Unknown tile category in Archive pattern: %s" % category)
			return Color.WHITE


func _on_discovered_parts_changed() -> void:
	_refresh_discovery_masks()
	if is_visible_in_tree():
		GameState.mark_discoveries_viewed()


func _refresh_discovery_masks() -> void:
	for index in range(_part_images.size()):
		var is_discovered := GameState.has_discovered_part(_part_patterns[index].part_type)
		_part_images[index].modulate = Color.WHITE if is_discovered else Color.BLACK
		_part_name_labels[index].text = (
			_part_patterns[index].display_name if is_discovered else "???"
		)
		_part_description_labels[index].visible = is_discovered
		_part_pattern_grids[index].visible = is_discovered
