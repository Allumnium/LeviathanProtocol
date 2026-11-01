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

var _reward_items: Array[Control] = []
var _reward_reveal_elapsed := 0.0
var _next_reward_icon := 0
var _reward_reveal_interval := REWARD_REVEAL_DURATION


func show_report(
	entries: Array[Dictionary],
	outcome: String,
	gained_materials: Array[int],
	credits_gained: int = 0,
	equipment_loot: String = ""
) -> void:
	add_to_group("modal_ui")
	z_index = 40
	texture_filter = Control.TEXTURE_FILTER_NEAREST
	theme_type_variation = &"VictoryPanel" if outcome == "Victory" else &"CompactPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 16
	offset_top = 16
	offset_right = -16
	offset_bottom = -16
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	if outcome == "Victory":
		_add_victory_banner(column)
		_add_title(column, "", credits_gained)
	else:
		_add_title(column, outcome, credits_gained)
	if not equipment_loot.is_empty():
		var loot_label := ResourceText.create("Loot: " + equipment_loot)
		column.add_child(loot_label)
	var deaths := 0
	var fees := 0
	for entry in entries:
		deaths += int(entry.get("passenger_deaths", 0))
		fees += int(entry.get("passenger_fees", 0))
	if deaths > 0:
		var casualties := ResourceText.create("Passengers lost: %d | Fees: -%d cr | Balance: %d cr" % [deaths, fees, GameState.credits])
		casualties.name = "PassengerCasualties"
		casualties.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(casualties)
	_add_material_rewards(column, gained_materials)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	if GameState.completed:
		var score := ResourceText.create(RunScore.description(GameState.hangar_snapshot()))
		score.name = "RunScore"
		rows.add_child(score)
	var summaries := _summarize_by_slot(entries)
	summaries.append_array(_summarize_aliens(entries))
	for summary in summaries:
		var card := PanelContainer.new()
		card.theme_type_variation = &"ReportCard"
		rows.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		row.add_child(_create_summary_preview(summary))
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 2)
		row.add_child(details)
		var name_label := ResourceText.create(summary.name + (" · %d DESTROYED" % summary.destroyed if summary.destroyed > 0 else ""))
		name_label.name = "ShipName"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(name_label)
		if summary.destroyed > 0:
			name_label.add_theme_color_override("default_color", DAMAGE_DEALT_COLOR)
		var stats := GridContainer.new()
		stats.columns = 2
		stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats.add_theme_constant_override("h_separation", 12)
		details.add_child(stats)
		_add_stat(stats, "Damage dealt", summary.damage)
		if summary.deflected > 0.0:
			_add_stat(stats, "Damage deflected", summary.deflected)
		if summary.repair_damage > 0.0:
			_add_stat(stats, "Repair", summary.repair_damage)
	var button_center := CenterContainer.new()
	column.add_child(button_center)
	var accept_button := Button.new()
	accept_button.name = "AcceptButton"
	accept_button.text = "CONTINUE" if GameState.is_run_lost() else "BACK TO FLEET"
	accept_button.custom_minimum_size = Vector2(112, 34)
	accept_button.theme_type_variation = &"FramedButton"
	AudioManager.connect_ui_button(accept_button)
	accept_button.pressed.connect(func() -> void: closed.emit())
	button_center.add_child(accept_button)

func _add_stat(parent: GridContainer, title: String, value: float) -> void:
	var label := ResourceText.create(title)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.y = 20
	parent.add_child(label)
	var amount := Label.new()
	amount.text = str(roundi(value))
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(amount)

func _add_victory_banner(parent: VBoxContainer) -> void:
	var banner := Control.new()
	banner.name = "VictoryBanner"
	banner.custom_minimum_size.y = 88
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(banner)
	_banner_art(banner, preload("res://assets/ui/Victory_EmitLight.png"), Vector2(280, 88), 0, 0.18)
	_banner_art(banner, preload("res://assets/ui/Victory_Light Line.png"), Vector2(420, 88), 0, 0.4)
	_banner_art(banner, preload("res://assets/ui/Victory_Badge.png"), Vector2(216, 76), 0)
	_banner_art(banner, preload("res://assets/ui/Victory2_Title.png"), Vector2(216, 36), 52)

func _banner_art(parent: Control, texture: Texture2D, extent: Vector2, top: float, opacity := 1.0) -> void:
	var art := TextureRect.new()
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.anchor_left = 0.5
	art.anchor_right = 0.5
	art.offset_left = -extent.x * 0.5
	art.offset_right = extent.x * 0.5
	art.offset_top = top
	art.offset_bottom = top + extent.y
	art.modulate.a = opacity
	parent.add_child(art)

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
	if outcome.is_empty() and credits_gained <= 0:
		return
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 4)
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(title_row)
	var title := Label.new()
	title.text = outcome if not outcome.is_empty() else "Reward"
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
	item.add_child(count_label)
	parent.add_child(item)
	_reward_items.append(item)


func _summarize_by_slot(entries: Array[Dictionary]) -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	if entries.any(func(entry: Dictionary) -> bool: return entry.get("ship") is HangarShip):
		for entry: Dictionary in entries:
			if entry.get("ship") is HangarShip:
				var summary := entry.duplicate()
				summary["name"] = entry.ship.display_name
				summary["destroyed"] = 1 if entry.destroyed else 0
				summaries.append(summary)
		return summaries
	return summaries


func _summarize_aliens(entries: Array[Dictionary]) -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	var summary_by_name: Dictionary = {}
	for entry in entries:
		var alien := entry.get("alien") as AlienShip
		if alien == null:
			continue
		var summary: Dictionary = summary_by_name.get(alien.display_name, {})
		if summary.is_empty():
			summary = {
				"name": alien.display_name, "alien": alien, "is_alien": true,
				"damage": 0.0, "taken": 0.0, "repair_damage": 0.0,
				"deflected": 0.0, "destroyed": 0,
			}
			summary_by_name[alien.display_name] = summary
			summaries.append(summary)
		summary.damage += float(entry.get("damage", 0.0))
		summary.taken += float(entry.get("taken", 0.0))
		summary.deflected += float(entry.get("deflected", 0.0))
		if bool(entry.get("destroyed", false)):
			summary.destroyed += 1
	return summaries


func _create_summary_preview(summary: Dictionary) -> Control:
	if not bool(summary.get("is_alien", false)):
		var preview := preload("res://scripts/fleet_ship_preview.gd").new()
		preview.owned = summary.ship
		preview.custom_minimum_size = Vector2(53, 53)
		return preview
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(53, 53)
	var alien: AlienShip = summary.alien
	var texture := TextureRect.new()
	var texture_size := alien.texture.get_size()
	var preview_size := texture_size * (27.0 * alien.art_scale() / maxf(texture_size.x, texture_size.y))
	texture.custom_minimum_size = preview_size
	texture.texture = alien.texture
	SurfaceArt.apply(texture)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(texture)
	return center


func _ship_type_name(display_name: String) -> String:
	var pieces := display_name.rsplit(" ", true, 1)
	return pieces[0] if pieces.size() == 2 and pieces[1].is_valid_int() else display_name
