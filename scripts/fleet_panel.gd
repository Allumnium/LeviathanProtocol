extends Control

signal selected_design_changed
signal selected_ship_changed

const SLOT_COUNT := 3
const PREVIEW = preload("res://scripts/ship_design_preview.gd")
const MATERIAL_ICONS: Array[Texture2D] = [
	preload("res://assets/ui/icons/red_square.png"),
	preload("res://assets/ui/icons/blue_square.png"),
	preload("res://assets/ui/icons/green_square.png"),
	preload("res://assets/core.png"),
]
const CREDIT_ICON: Texture2D = preload("res://assets/credits.png")
const PLUS_ICON: Texture2D = preload("res://assets/plus.png")
const MINUS_ICON: Texture2D = preload("res://assets/minus.png")
const SHIP_LIBRARY_DIALOG = preload("res://scenes/load_design_dialog.tscn")

var selected_design: Ship
var selected_title := ""
var choices: Array[Dictionary] = []
var slots: Array[Dictionary] = []
var slot_widgets: Array[Dictionary] = []
var active_slot := -1
var board := preload("res://scripts/formation_board.gd").new()
var picker: PopupPanel
var slot_host: VBoxContainer
var summary_host: VBoxContainer


func _ready() -> void:
	for index in range(_slot_count()):
		slots.append({"name": GameState.fleet_slot_name(index), "design": null})
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(board)
	board.selection_changed.connect(func() -> void: selected_ship_changed.emit())
	picker = SHIP_LIBRARY_DIALOG.instantiate()
	add_child(picker)
	picker.design_selected.connect(_on_picker_design_selected)
	GameState.design_library_changed.connect(_refresh_choices)
	GameState.fleet_changed.connect(_refresh_summary)
	GameState.fleet_changed.connect(_refresh_slots)
	GameState.credits_changed.connect(_refresh_slots)
	GameState.credits_changed.connect(_refresh_summary)
	GameState.tile_inventory_changed.connect(_refresh_slots)
	GameState.tile_inventory_changed.connect(_refresh_summary)
	GameState.build_area_changed.connect(_refresh_slots)
	_refresh_choices()


func bind_external_panels(left: VBoxContainer, right: VBoxContainer) -> void:
	slot_host = left
	summary_host = right
	_build_slot_controls()
	_refresh_slots()
	_refresh_summary()


func set_external_panels_visible(is_visible: bool) -> void:
	if slot_host != null:
		slot_host.visible = is_visible
	if summary_host != null:
		summary_host.visible = is_visible


func _build_slot_controls() -> void:
	var header := Label.new()
	header.text = "SHIP TYPES"
	header.add_theme_font_size_override("font_size", 14)
	if GameState.campaign_active:
		header.add_theme_font_override("font", ThemeDB.fallback_font)
		header.add_theme_font_size_override("font_size", 12)
	slot_host.add_child(header)
	var rows := slot_host
	if GameState.campaign_active:
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.custom_minimum_size.y = 80
		slot_host.add_child(scroll)
		rows = VBoxContainer.new()
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(rows)
	for index in range(_slot_count()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		rows.add_child(row)
		var salvage_host := CenterContainer.new()
		salvage_host.custom_minimum_size = Vector2(20, 55)
		row.add_child(salvage_host)
		var salvage := TextureButton.new()
		salvage.texture_normal = MINUS_ICON
		_style_slot_action(salvage)
		salvage_host.add_child(salvage)
		var select := Button.new()
		select.custom_minimum_size = Vector2(114, 55)
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		compact_button(select)
		row.add_child(select)
		var preview := PREVIEW.new()
		preview.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		preview.offset_left = 5
		preview.offset_top = 5
		preview.offset_right = 55
		preview.offset_bottom = -4
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		select.add_child(preview)
		var details := VBoxContainer.new()
		details.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		details.offset_left = 59
		details.offset_top = 4
		details.offset_right = -4
		details.offset_bottom = -4
		details.mouse_filter = Control.MOUSE_FILTER_IGNORE
		select.add_child(details)
		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.add_theme_font_size_override("font_size", 9)
		if GameState.campaign_active:
			name_label.add_theme_font_override("font", ThemeDB.fallback_font)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		details.add_child(name_label)
		var cost_rows := VBoxContainer.new()
		cost_rows.add_theme_constant_override("separation", 0)
		cost_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		details.add_child(cost_rows)
		var construct_host := CenterContainer.new()
		construct_host.custom_minimum_size = Vector2(20, 55)
		row.add_child(construct_host)
		var construct := TextureButton.new()
		construct.texture_normal = PLUS_ICON
		_style_slot_action(construct)
		construct_host.add_child(construct)
		select.pressed.connect(_open_picker.bind(index))
		salvage.pressed.connect(_salvage_slot.bind(index))
		construct.pressed.connect(_construct_slot.bind(index))
		slot_widgets.append({
			"button": select,
			"preview": preview,
			"label": name_label,
			"cost": cost_rows,
			"salvage": salvage,
			"salvage_host": salvage_host,
			"construct": construct,
			"construct_host": construct_host,
		})


func _open_picker(slot_index: int) -> void:
	_activate_slot(slot_index)
	if GameState.campaign_active:
		picker.fleet_slot_role = _slot_role(slot_index)
		picker.open_library("SELECT", func(design: Ship) -> String:
			var problem := GameState.design_research_error(design)
			return problem if not problem.is_empty() else FleetRules.design_error(design, _slot_role(slot_index)))
	else:
		picker.open_library("SELECT")


func _on_picker_design_selected(design_name: String, design: Ship) -> void:
	_assign_slot(active_slot, {"name": design_name, "design": design})


func _activate_slot(slot_index: int) -> void:
	active_slot = slot_index
	selected_title = slots[slot_index].name
	selected_design = slots[slot_index].design
	selected_design_changed.emit()
	if GameState.campaign_active:
		_refresh_summary()


func _assign_slot(slot_index: int, choice: Dictionary) -> void:
	if slot_index < 0 or slot_index >= _slot_count():
		return
	if GameState.campaign_active:
		if not GameState.assign_fleet_design(slot_index, choice.name, choice.design):
			return
		slots[slot_index] = {"name": choice.name, "design": choice.design}
		_activate_slot(slot_index)
		_refresh_slots()
		return
	for index in range(SLOT_COUNT):
		if index != slot_index and slots[index].name == choice.name:
			return
	if not slots[slot_index].name.is_empty() and slots[slot_index].name != choice.name and _fleet_has_type(slots[slot_index].name):
		return
	slots[slot_index] = {"name": choice.name, "design": choice.design}
	GameState.fleet_design_slots[slot_index] = choice.name
	_activate_slot(slot_index)
	_refresh_slots()


func _construct_slot(slot_index: int) -> void:
	var slot: Dictionary = slots[slot_index]
	if slot.design != null:
		if GameState.campaign_active:
			GameState.purchase_ship(slot.design, slot.name, _slot_role(slot_index))
		else:
			GameState.purchase_saved_ship(slot.name, _slot_role(slot_index))


func _salvage_slot(slot_index: int) -> void:
	var slot: Dictionary = slots[slot_index]
	if slot.design != null:
		if GameState.campaign_active:
			GameState.salvage_fleet_slot(slot_index)
		else:
			GameState.salvage_ship_type(slot.name)


func _refresh_slots() -> void:
	if slot_widgets.is_empty():
		return
	for index in range(_slot_count()):
		var slot: Dictionary = slots[index]
		var widget: Dictionary = slot_widgets[index]
		var design: Ship = slot.design
		widget.preview.set_ship(design)
		widget.label.text = slot.name if design != null else "SELECT SHIP"
		if index >= 3:
			widget.label.text = _slot_role(index).to_upper() + "\n" + (slot.name if design != null else "SELECT")
			widget.button.tooltip_text = "Science requires one operational lab; Civic requires cargo or berths. Dedicated ships forbid mining, strike craft and offensive capstones; maximum six Offense tiles."
		_populate_cost_row(widget.cost, design)
		widget.button.disabled = design != null and _fleet_has_type(slot.name)
		if GameState.campaign_active:
			widget.button.disabled = not GameState.is_shipyard_node(GameState.current_node_id) and not GameState.emergency_roster_available()
		widget.construct.visible = design != null
		widget.salvage.visible = design != null
		widget.salvage.disabled = design == null or not _fleet_has_type(slot.name) or GameState.battle_pending
		if GameState.campaign_active:
			widget.salvage.disabled = GameState.fleet_slot_members(index).is_empty() or not GameState.is_shipyard_node(GameState.current_node_id)
		if design != null:
			var error := GameState.construction_error(design, _slot_role(index))
			widget.construct.disabled = not error.is_empty()
			widget.construct.tooltip_text = error
			if GameState.campaign_active:
				widget.construct.tooltip_text += ("\n" if not error.is_empty() else "") + "Deployment capacity: %d per intact copy. Excess capacity blocks departure; reserve ships at a port." % FleetRules.design_capacity(design)


func _populate_cost_row(container: VBoxContainer, design: Ship) -> void:
	for child in container.get_children():
		child.queue_free()
	container.visible = design != null
	if design == null:
		return
	var material_row := HBoxContainer.new()
	material_row.add_theme_constant_override("separation", 1)
	container.add_child(material_row)
	var counts := GameState.get_construction_material_costs(design)
	for category in range(counts.size()):
		if counts[category] > 0:
			_add_cost_item(material_row, MATERIAL_ICONS[category], counts[category])
	material_row.visible = material_row.get_child_count() > 0
	var credit_row := HBoxContainer.new()
	credit_row.add_theme_constant_override("separation", 1)
	container.add_child(credit_row)
	var credit_cost := GameState.get_construction_credit_cost(design)
	if credit_cost > 0:
		_add_cost_item(credit_row, CREDIT_ICON, credit_cost)
	credit_row.visible = credit_cost > 0


func _add_cost_item(row: HBoxContainer, icon: Texture2D, amount: int) -> void:
	var texture := TextureRect.new()
	texture.custom_minimum_size = Vector2(7, 7)
	texture.texture = icon
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texture)
	var label := Label.new()
	label.text = str(amount)
	label.add_theme_font_size_override("font_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)


func _refresh_summary() -> void:
	if summary_host == null:
		return
	for child in summary_host.get_children():
		child.queue_free()
	var header := Label.new()
	header.text = "FLEET SUMMARY"
	header.add_theme_font_size_override("font_size", 14)
	if GameState.campaign_active:
		header.add_theme_font_override("font", ThemeDB.fallback_font)
		header.add_theme_font_size_override("font_size", 12)
	summary_host.add_child(header)
	if GameState.campaign_active:
		_refresh_roster_summary()
		return
	if GameState.fleet.is_empty():
		var empty := Label.new()
		empty.text = "No ships constructed"
		empty.add_theme_font_size_override("font_size", 10)
		summary_host.add_child(empty)
		return
	var groups: Dictionary = {}
	for owned in GameState.fleet:
		var type_name := _ship_type_name(owned.display_name)
		if not groups.has(type_name):
			groups[type_name] = {"count": 0, "damaged": 0}
		groups[type_name].count += 1
		if owned.needs_repair():
			groups[type_name].damaged += 1
	for type_name in groups:
		var group: Dictionary = groups[type_name]
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 10)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s  ×%d" % [type_name, group.count]
		if group.damaged > 0:
			label.text += "\n%d NEED REPAIR" % group.damaged
			label.add_theme_color_override("font_color", Color("edb272"))
		summary_host.add_child(label)


func _ship_type_name(display_name: String) -> String:
	var pieces := display_name.rsplit(" ", true, 1)
	return pieces[0] if pieces.size() == 2 and pieces[1].is_valid_int() else display_name


func _fleet_has_type(type_name: String) -> bool:
	return GameState.fleet.any(func(owned: FleetShip) -> bool:
		return _ship_type_name(owned.display_name) == type_name)


func _refresh_choices() -> void:
	choices.clear()
	for entry in GameState.get_visible_ship_designs():
		var blueprint := Ship.new()
		if blueprint.load_design_data(entry.ship):
			choices.append({"name": entry.name, "design": blueprint})
	if GameState.campaign_active:
		for index in range(_slot_count()):
			var name := GameState.fleet_slot_name(index)
			var design: Ship = GameState.slot_blueprint(index) if index < 3 else null
			for choice in choices:
				if choice.name == name and design == null:
					design = choice.design
					break
			slots[index] = {"name": name, "design": design}
		_refresh_slots()
		return
	_seed_slots_from_fleet()
	for index in range(SLOT_COUNT):
		var name: String = slots[index].name
		if name.is_empty():
			continue
		var choice_match: Dictionary = {}
		for choice in choices:
			if choice.name == name:
				choice_match = choice
				break
		slots[index] = {"name": choice_match.get("name", ""), "design": choice_match.get("design")}
		GameState.fleet_design_slots[index] = slots[index].name
	if active_slot >= 0:
		_activate_slot(active_slot)
	_refresh_slots()


func _seed_slots_from_fleet() -> void:
	for owned in GameState.fleet:
		var type_name := _ship_type_name(owned.display_name)
		if slots.any(func(slot: Dictionary) -> bool: return slot.name == type_name):
			continue
		var empty_index := slots.find_custom(func(slot: Dictionary) -> bool: return slot.name.is_empty())
		if empty_index < 0:
			return
		for choice in choices:
			if choice.name == type_name:
				slots[empty_index] = {"name": choice.name, "design": choice.design}
				GameState.fleet_design_slots[empty_index] = choice.name
				break


func _slot_count() -> int:
	return 5 if GameState.campaign_active else SLOT_COUNT


func _slot_role(index: int) -> String:
	return "regular" if index < 3 else ("science" if index == 3 else "civic")


func _refresh_roster_summary() -> void:
	var totals := Label.new()
	totals.text = "%d deployed / %d owned" % [GameState.get_deployed_fleet().size(), GameState.fleet.size()]
	if GameState.campaign_active:
		totals.text += "\nCapacity %d / %d" % [GameState.used_deployment_capacity(), GameState.deployment_capacity()]
		totals.text += "\nVictory RP: %d" % int(ScienceRules.snapshot(GameState.get_deployed_fleet()).total_rp)
		if GameState.emergency_roster_available() and not GameState.is_shipyard_node(GameState.current_node_id):
			totals.text += "\nEmergency: select an owned revision, then deploy reserves."
		totals.tooltip_text = "Each deployed hull: 2 + ceil(occupied material cells / 12) + active lab levels. Reserves use no capacity."
		if GameState.used_deployment_capacity() > GameState.deployment_capacity():
			totals.modulate = Color(1.0, 0.45, 0.35)
	totals.add_theme_font_size_override("font_size", 10)
	totals.add_theme_font_override("font", ThemeDB.fallback_font)
	summary_host.add_child(totals)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 40
	summary_host.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for owned in GameState.fleet:
		var row := HBoxContainer.new()
		list.add_child(row)
		var label := Label.new()
		label.text = owned.display_name
		label.tooltip_text = "%s / %s" % [owned.slot_role.capitalize(), "Deployed" if GameState.is_ship_deployed(owned) else "Reserve"]
		label.tooltip_text += "\nDeployment capacity: %d%s" % [FleetRules.ship_capacity(owned), "" if GameState.is_ship_deployed(owned) else " (not charged while reserved)"]
		label.add_theme_font_size_override("font_size", 9)
		label.add_theme_font_override("font", ThemeDB.fallback_font)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var toggle := Button.new()
		toggle.text = "RESERVE" if GameState.is_ship_deployed(owned) else "DEPLOY"
		toggle.add_theme_font_size_override("font_size", 9)
		toggle.add_theme_font_override("font", ThemeDB.fallback_font)
		toggle.custom_minimum_size.y = 22
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.18, 0.26, 0.31) if state == "hover" else Color(0.10, 0.15, 0.19)
			style.content_margin_left = 4
			style.content_margin_right = 4
			style.content_margin_top = 2
			style.content_margin_bottom = 2
			toggle.add_theme_stylebox_override(state, style)
		toggle.disabled = not GameState.is_shipyard_node(GameState.current_node_id) and not GameState.emergency_roster_available()
		if owned.slot_role == "regular" and not GameState._is_active_revision(owned):
			toggle.text = "SELECT"
			toggle.tooltip_text = "Select this owned revision in its family's slot (or the selected regular slot, default 1). Older physical copies keep their design and damage."
			toggle.pressed.connect(func() -> void: _select_owned_revision(owned))
		else:
			toggle.pressed.connect(func() -> void: GameState.set_ship_reserve(owned, GameState.is_ship_deployed(owned)))
		row.add_child(toggle)
		if owned.needs_repair():
			var quote := GameState.repair_quote(owned)
			var service := Button.new()
			service.text = "REPAIR %d cr" % int(quote.credits)
			if quote.materials.any(func(amount: int) -> bool: return amount > 0):
				service.text = "FIX %d cr + mats" % int(quote.credits)
			service.tooltip_text = "Repairs: %d cr. Reconstruction O/D/T/C: %s. Uses stored materials first; credit total includes shortages." % [quote.repair_credits, str(quote.reconstruction)]
			service.add_theme_font_override("font", ThemeDB.fallback_font)
			service.add_theme_font_size_override("font_size", 9)
			service.custom_minimum_size.y = 20
			for style_state in ["normal", "hover", "pressed", "disabled"]:
				service.add_theme_stylebox_override(style_state, toggle.get_theme_stylebox(style_state))
			service.disabled = GameState.battle_pending or not owned.is_alive() or not GameState.is_shipyard_node(GameState.current_node_id) or (int(quote.credits) > 0 and int(quote.credits) > GameState.credits)
			service.pressed.connect(func() -> void: GameState.repair_ship(owned))
			list.add_child(service)
	var revision := Button.new()
	revision.text = "REGISTER REVISION"
	revision.add_theme_font_size_override("font_size", 9)
	revision.add_theme_font_override("font", ThemeDB.fallback_font)
	revision.tooltip_text = "Select the editor blueprint as this family's active revision. Older physical copies become reserves; construct new copies at normal cost."
	revision.disabled = active_slot < 0 or active_slot >= 3 or not GameState.is_shipyard_node(GameState.current_node_id)
	revision.pressed.connect(func() -> void:
		if GameState.assign_fleet_design(active_slot, slots[active_slot].name, GameState.ship, true):
			_refresh_choices())
	summary_host.add_child(revision)


func _select_owned_revision(owned: FleetShip) -> void:
	var index: int = GameState.roster_state.active.find(owned.family_id)
	if index < 0:
		index = active_slot if active_slot >= 0 and active_slot < 3 else 0
	if GameState.assign_fleet_design(index, _ship_type_name(owned.display_name), owned.design):
		_refresh_choices()


static func compact_button(button: Button) -> void:
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 30)
	button.add_theme_font_override("font", preload("res://assets/fonts/starhull-fonts/Starhull/Starhull.fnt"))
	var theme := preload("res://themes/ui_theme.tres")
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style: StyleBox = theme.get_stylebox(state, "Button").duplicate()
		if button.text.is_empty() and button.icon != null and style is StyleBoxTexture:
			style.texture = preload("res://assets/ui/panels/simple_panel.png")
			style.texture_margin_left = 12
			style.texture_margin_right = 12
			style.texture_margin_top = 12
			style.texture_margin_bottom = 12
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		button.add_theme_stylebox_override(state, style)


static func _style_slot_action(button: TextureButton) -> void:
	button.custom_minimum_size = Vector2(18, 30)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			button.self_modulate = Color(1.25, 1.25, 1.25, 1.0))
	button.mouse_exited.connect(func() -> void:
		button.self_modulate = Color.WHITE)
	button.button_down.connect(func() -> void:
		if not button.disabled:
			button.self_modulate = Color(0.48, 0.52, 0.58, 1.0))
	button.button_up.connect(func() -> void:
		button.self_modulate = Color(1.25, 1.25, 1.25, 1.0) if button.is_hovered() else Color.WHITE)


static func style_checkbox(checkbox: CheckBox) -> void:
	for checked in [false, true]:
		var image := Image.new()
		var mark := '<path d="M3 7 L6 10 L11 3" fill="none" stroke="#cfdee4" stroke-width="2"/>' if checked else ""
		image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14"><rect x="1" y="1" width="12" height="12" rx="1" fill="#172128" stroke="#8ea5b2"/>%s</svg>' % mark)
		checkbox.add_theme_icon_override("checked" if checked else "unchecked", ImageTexture.create_from_image(image))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var style := StyleBoxEmpty.new()
		style.set_content_margin_all(2)
		checkbox.add_theme_stylebox_override(state, style)


static func _arrow_icon(right: bool) -> Texture2D:
	var image := Image.new()
	var path := "M4 2 L9 7 L4 12" if right else "M9 2 L4 7 L9 12"
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14"><path d="%s" fill="none" stroke="#cfdee4" stroke-width="2"/></svg>' % path)
	return ImageTexture.create_from_image(image)


static func trash_icon() -> Texture2D:
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="16"><path d="M2 4h10M5 4V2h4v2M3 5l1 9h6l1-9M6 6v6M8 6v6" fill="none" stroke="#ed7272" stroke-width="1.5" stroke-linejoin="round"/></svg>')
	return ImageTexture.create_from_image(image)
