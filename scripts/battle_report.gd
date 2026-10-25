extends PanelContainer

signal closed

const MATERIAL_ICONS: Array[Texture2D] = [
	preload("res://assets/ui/icons/red_square.png"),
	preload("res://assets/ui/icons/blue_square.png"),
	preload("res://assets/ui/icons/green_square.png"),
	preload("res://assets/core.png"),
]
const MATERIAL_CREDIT_VALUES: Array[int] = [
	Ship.RED_TILE_CREDIT_COST,
	Ship.BLUE_TILE_CREDIT_COST,
	Ship.GREEN_TILE_CREDIT_COST,
	Ship.CORE_TILE_CREDIT_COST,
]
const CREDIT_ICON: Texture2D = preload("res://assets/credits.png")
const MATERIAL_REVEAL_SOUND: AudioStream = preload("res://assets/audio/sfx/dialogue_type.mp3")
const REWARD_REVEAL_DURATION := 3.0
const DAMAGE_DEALT_COLOR := Color(0.92, 0.24, 0.2)
const DAMAGE_DEFLECTED_COLOR := Color(0.3, 0.66, 1.0)
const REPAIR_DAMAGE_COLOR := Color(1.0, 0.66, 0.16)

var _reward_items: Array[Control] = []
var _reward_reveal_elapsed := 0.0
var _next_reward_icon := 0
var _reward_reveal_interval := REWARD_REVEAL_DURATION


func show_report(
	entries: Array[Dictionary],
	outcome: String,
	gained_materials: Array[int],
	credits_gained: int = 0
) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 40
	offset_top = 24
	offset_right = -40
	offset_bottom = -24
	var column := VBoxContainer.new()
	add_child(column)
	_add_title(column, outcome, credits_gained)
	_add_material_rewards(column, gained_materials)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var slot_summaries := _summarize_by_slot(entries)
	for summary in slot_summaries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		rows.add_child(row)
		var preview := preload("res://scripts/fleet_ship_preview.gd").new()
		preview.owned = summary.ship
		preview.custom_minimum_size = Vector2(76, 76)
		row.add_child(preview)
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 2)
		row.add_child(details)
		var summary_line := HBoxContainer.new()
		summary_line.add_theme_constant_override("separation", 4)
		details.add_child(summary_line)
		var name_label := Label.new()
		name_label.text = summary.name
		name_label.add_theme_font_size_override("font_size", 11)
		summary_line.add_child(name_label)
		if summary.destroyed > 0:
			var destroyed_label := Label.new()
			destroyed_label.text = "· %d DESTROYED" % summary.destroyed
			destroyed_label.add_theme_font_size_override("font_size", 11)
			destroyed_label.add_theme_color_override("font_color", DAMAGE_DEALT_COLOR)
			summary_line.add_child(destroyed_label)
		details.add_child(StatDisplayRow.new(
			"DAMAGE DEALT", summary.damage, "%.1f" % summary.damage,
			9, true, null, DAMAGE_DEALT_COLOR
		))
		if summary.deflected > 0.0:
			details.add_child(StatDisplayRow.new(
				"DAMAGE DEFLECTED", summary.deflected, str(roundi(summary.deflected)),
				9, true, null, DAMAGE_DEFLECTED_COLOR
			))
		if summary.repair_damage > 0.0:
			details.add_child(StatDisplayRow.new(
				"REPAIRS NEEDED", summary.repair_damage, str(roundi(summary.repair_damage)),
				9, true, null, REPAIR_DAMAGE_COLOR
			))
	var button_center := CenterContainer.new()
	column.add_child(button_center)
	var accept_button := Button.new()
	accept_button.name = "AcceptButton"
	accept_button.text = "ACCEPT"
	accept_button.custom_minimum_size = Vector2(112, 34)
	accept_button.add_theme_font_size_override("font_size", 10)
	preload("res://scripts/fleet_panel.gd").compact_button(accept_button)
	accept_button.pressed.connect(func() -> void: closed.emit())
	button_center.add_child(accept_button)


func _process(delta: float) -> void:
	if _next_reward_icon >= _reward_items.size():
		return
	_reward_reveal_elapsed += delta
	while _reward_reveal_elapsed >= _reward_reveal_interval and _next_reward_icon < _reward_items.size():
		_reward_reveal_elapsed -= _reward_reveal_interval
		_reveal_next_reward()


func _input(event: InputEvent) -> void:
	if (
		_next_reward_icon >= _reward_items.size()
		or not visible
		or not (event is InputEventMouseButton)
		or not event.pressed
		or event.button_index != MOUSE_BUTTON_LEFT
	):
		return
	while _next_reward_icon < _reward_items.size():
		_reveal_next_reward(false)
	AudioManager.play_sfx(MATERIAL_REVEAL_SOUND)
	get_viewport().set_input_as_handled()


func _reveal_next_reward(play_sound := true) -> void:
	_reward_items[_next_reward_icon].modulate.a = 1.0
	if play_sound:
		AudioManager.play_sfx(MATERIAL_REVEAL_SOUND)
	_next_reward_icon += 1


func _add_title(parent: VBoxContainer, outcome: String, credits_gained: int) -> void:
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 4)
	parent.add_child(title_row)
	var title := Label.new()
	title.text = outcome
	title.add_theme_font_size_override("font_size", 14)
	title_row.add_child(title)
	if credits_gained <= 0:
		return
	var credit_icon := TextureRect.new()
	credit_icon.custom_minimum_size = Vector2(18, 18)
	credit_icon.texture = CREDIT_ICON
	credit_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	credit_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_row.add_child(credit_icon)
	var credit_amount := Label.new()
	credit_amount.text = str(credits_gained)
	credit_amount.add_theme_font_size_override("font_size", 12)
	title_row.add_child(credit_amount)


func _add_material_rewards(parent: VBoxContainer, gained_materials: Array[int]) -> void:
	if gained_materials.is_empty():
		return
	var sorted_materials := gained_materials.duplicate()
	sorted_materials.sort_custom(func(a: int, b: int) -> bool:
		return MATERIAL_CREDIT_VALUES[a] > MATERIAL_CREDIT_VALUES[b])
	var reward_row := HFlowContainer.new()
	reward_row.custom_minimum_size.y = 22
	reward_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward_row.add_theme_constant_override("h_separation", 2)
	reward_row.add_theme_constant_override("v_separation", 2)
	parent.add_child(reward_row)
	var available_width := maxf(size.x, get_viewport_rect().size.x - 80.0)
	var icons_per_row := maxi(floori(available_width / 20.0), 1)
	var use_grouped_counts := sorted_materials.size() > icons_per_row * 2
	if use_grouped_counts:
		var counts: Array[int] = [0, 0, 0, 0]
		for category in sorted_materials:
			if category >= 0 and category < counts.size():
				counts[category] += 1
		var categories: Array[int] = [0, 1, 2, 3]
		categories.sort_custom(func(a: int, b: int) -> bool:
			return MATERIAL_CREDIT_VALUES[a] > MATERIAL_CREDIT_VALUES[b])
		for category in categories:
			if counts[category] > 0:
				_add_grouped_reward(reward_row, category, counts[category])
	else:
		for category in sorted_materials:
			if category < 0 or category >= MATERIAL_ICONS.size():
				continue
			var icon := _create_reward_icon(category)
			icon.modulate.a = 0.0
			reward_row.add_child(icon)
			_reward_items.append(icon)
	if not _reward_items.is_empty():
		_reward_reveal_interval = REWARD_REVEAL_DURATION / float(_reward_items.size())


func _create_reward_icon(category: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(18, 18)
	icon.texture = MATERIAL_ICONS[category]
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon


func _add_grouped_reward(parent: HFlowContainer, category: int, count: int) -> void:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 2)
	item.modulate.a = 0.0
	item.add_child(_create_reward_icon(category))
	var count_label := Label.new()
	count_label.text = "x%d" % count
	count_label.add_theme_font_size_override("font_size", 10)
	item.add_child(count_label)
	parent.add_child(item)
	_reward_items.append(item)


func _summarize_by_slot(entries: Array[Dictionary]) -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for slot_index in range(GameState.fleet_design_slots.size()):
		var design_name := GameState.fleet_design_slots[slot_index]
		if design_name.is_empty():
			continue
		var summary := {
			"slot": slot_index, "name": design_name, "ship": null,
			"damage": 0.0, "taken": 0.0, "repair_damage": 0.0,
			"deflected": 0.0, "destroyed": 0,
		}
		for entry in entries:
			var ship: FleetShip = entry.ship
			if _ship_type_name(ship.display_name) != design_name:
				continue
			if summary.ship == null:
				summary.ship = ship
			summary.damage += float(entry.damage)
			summary.taken += float(entry.taken)
			summary.repair_damage += float(entry.get("repair_damage", 0.0))
			summary.deflected += float(entry.get("deflected", 0.0))
			if entry.destroyed:
				summary.destroyed += 1
		if summary.ship != null:
			summaries.append(summary)
	return summaries


func _ship_type_name(display_name: String) -> String:
	var pieces := display_name.rsplit(" ", true, 1)
	return pieces[0] if pieces.size() == 2 and pieces[1].is_valid_int() else display_name
