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
var ship_actions: PanelContainer
var action_review: Control
var _refresh_queued := false
var reserve_modal: Control
var reserve_button: Button
var _reserve_page := 0
var _reserve_content: VBoxContainer


func _ready() -> void:
	for index in range(_slot_count()):
		slots.append({"name": GameState.fleet_slot_name(index), "design": null})
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(board)
	board.selection_changed.connect(_on_formation_selection_changed)
	ship_actions = PanelContainer.new()
	ship_actions.name = "SelectedShipActions"
	ship_actions.z_index = 5
	ship_actions.theme_type_variation = &"ContextPanel"
	board.add_child(ship_actions)
	board.selection_actions = ship_actions
	_refresh_selected_actions()
	picker = SHIP_LIBRARY_DIALOG.instantiate()
	add_child(picker)
	picker.design_selected.connect(_on_picker_design_selected)
	GameState.design_library_changed.connect(_refresh_choices)
	GameState.fleet_changed.connect(_queue_refresh)
	GameState.credits_changed.connect(_queue_refresh)
	GameState.tile_inventory_changed.connect(_queue_refresh)
	GameState.build_area_changed.connect(_queue_refresh)
	GameState.travel_plan_changed.connect(_queue_refresh)
	_refresh_choices()

func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_flush_refresh.call_deferred()

func _flush_refresh() -> void:
	_refresh_queued = false
	_refresh_slots()
	_refresh_summary()
	_refresh_selected_actions()
	if is_instance_valid(reserve_modal) and not reserve_modal.is_queued_for_deletion():
		_refresh_reserve_modal()


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
	header.text = "SHIP SLOTS (3)" if GameState.campaign_active else "SHIP TYPES"
	slot_host.add_child(header)
	if GameState.campaign_active:
		_build_compact_slot_controls()
		return
	var rows := slot_host
	for index in range(_slot_count()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		rows.add_child(row)
		var select := Button.new()
		select.custom_minimum_size = Vector2(100, 76)
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		compact_button(select)
		row.add_child(select)
		var preview := PREVIEW.new()
		preview.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		preview.offset_left = 5
		preview.offset_top = 5
		preview.offset_right = 37
		preview.offset_bottom = 37
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		select.add_child(preview)
		var details := VBoxContainer.new()
		details.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		details.offset_left = 41
		details.offset_top = 4
		details.offset_right = -4
		details.offset_bottom = -4
		details.mouse_filter = Control.MOUSE_FILTER_IGNORE
		select.add_child(details)
		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(name_label)
		var cost_rows := VBoxContainer.new()
		cost_rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cost_rows.offset_left = 5
		cost_rows.offset_top = 40
		cost_rows.offset_right = -5
		cost_rows.offset_bottom = -4
		cost_rows.add_theme_constant_override("separation", 0)
		cost_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		select.add_child(cost_rows)
		var construct_host := CenterContainer.new()
		construct_host.custom_minimum_size = Vector2(20, 55)
		row.add_child(construct_host)
		var construct := TextureButton.new()
		construct.texture_normal = PLUS_ICON
		_style_slot_action(construct)
		construct_host.add_child(construct)
		select.pressed.connect(_open_picker.bind(index))
		construct.pressed.connect(_construct_slot.bind(index))
		slot_widgets.append({
			"button": select,
			"preview": preview,
			"label": name_label,
			"cost": cost_rows,
			"construct": construct,
			"construct_host": construct_host,
		})


func _build_compact_slot_controls() -> void:
	slot_host.add_theme_constant_override("separation", 2)
	for index in range(_slot_count()):
		var row := HBoxContainer.new()
		row.name = "ShipSlot%d" % index
		row.custom_minimum_size.y = 24
		row.add_theme_constant_override("separation", 2)
		slot_host.add_child(row)
		var select := Button.new()
		select.custom_minimum_size = Vector2(104, 24)
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		style_slot_button(select)
		row.add_child(select)
		var preview := PREVIEW.new()
		preview.position = Vector2(3, 2)
		preview.size = Vector2(20, 20)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		select.add_child(preview)
		var label := Label.new()
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.offset_left = 27
		label.offset_right = -3
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		select.add_child(label)
		# Detailed quotes belong in the library and clicked review, leaving all
		# five slots visible instead of repeating miniature cost dashboards.
		var cost := VBoxContainer.new()
		cost.hide()
		select.add_child(cost)
		var construct := TextureButton.new()
		construct.texture_normal = PLUS_ICON
		_style_slot_action(construct)
		construct.custom_minimum_size = Vector2(24, 24)
		var construct_host := CenterContainer.new()
		construct_host.custom_minimum_size = Vector2(24, 24)
		row.add_child(construct_host)
		construct_host.add_child(construct)
		select.pressed.connect(_open_picker.bind(index))
		construct.pressed.connect(_construct_slot.bind(index))
		slot_widgets.append({"button": select, "preview": preview, "label": label,
			"cost": cost,
			"construct": construct, "construct_host": construct_host})


static func style_slot_button(button: Button) -> void:
	button.theme_type_variation = &"CompactButton"


func _open_picker(slot_index: int) -> void:
	_activate_slot(slot_index)
	if GameState.campaign_active:
		picker.fleet_slot_role = _slot_role(slot_index)
		picker.open_library("SELECT", func(design: Ship) -> String:
			for owned in GameState.fleet_slot_members(slot_index):
				if PassengerRules.occupied(GameState.economy_state, owned.id) > 0 and FleetRules.fingerprint(owned.design) != FleetRules.fingerprint(design):
					return "Disembark passengers in Fleet before changing this slot."
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
		_open_construction_order(slot_index)


func _open_construction_order(slot_index: int) -> void:
	if is_instance_valid(action_review):
		return
	var slot: Dictionary = slots[slot_index]
	var design: Ship = slot.design
	var overlay := Control.new()
	action_review = overlay
	overlay.name = "FleetActionReview"
	overlay.add_to_group("modal_ui")
	overlay.z_index = 40
	get_tree().current_scene.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.75)
	overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "ConstructionModal"
	panel.theme_type_variation = &"CompactPanel"
	panel.custom_minimum_size = Vector2(500, 290)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	var heading := Label.new()
	heading.text = "CONSTRUCT SHIPS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.custom_minimum_size.y = 24
	content.add_child(heading)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 210
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 3)
	columns.add_child(left)
	var name_label := Label.new()
	name_label.text = slot.name
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	left.add_child(name_label)
	var preview := PREVIEW.new()
	preview.name = "ConstructionPreview"
	preview.custom_minimum_size = Vector2(160, 70)
	left.add_child(preview)
	preview.set_ship(design)
	var base_label := Label.new()
	base_label.text = "BASE COST / SHIP"
	left.add_child(base_label)
	var materials := HBoxContainer.new()
	materials.add_theme_constant_override("separation", 5)
	left.add_child(materials)
	var required := GameState.get_design_material_costs(design)
	var base_credits := 0
	for category in range(4):
		_add_cost_item(materials, MATERIAL_ICONS[category], required[category])
		base_credits += required[category] * GameState.MATERIAL_PRICES[category]
	var base_price := HBoxContainer.new()
	left.add_child(base_price)
	_add_cost_item(base_price, CREDIT_ICON, base_credits)
	var equipment := Label.new()
	equipment.name = "EquipmentSummary"
	var counts := [0, 0, 0, 0]
	for part in design.parts:
		if not part.stats.weapons.is_empty():
			counts[0] += 1
		elif part.type in [ShipPart.Type.THRUSTER, ShipPart.Type.LARGE_THRUSTER]:
			counts[2] += 1
		elif part.type in [ShipPart.Type.SHIELD, ShipPart.Type.ARMOR_BLOCK, ShipPart.Type.SINGLE_PLATE]:
			counts[1] += 1
		else:
			counts[3] += 1
	equipment.text = "EQUIPMENT\nWeapons %d | Defense %d\nEngines %d | Support %d" % counts
	left.add_child(equipment)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 220
	columns.add_child(right)
	var quantity_row := HBoxContainer.new()
	right.add_child(quantity_row)
	var quantity_label := Label.new()
	quantity_label.text = "QUANTITY"
	quantity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quantity_row.add_child(quantity_label)
	var quantity := SpinBox.new()
	quantity.name = "OrderQuantity"
	quantity.min_value = 1
	quantity.max_value = 2147483647
	quantity.step = 1
	quantity.value = 1
	quantity.update_on_text_changed = true
	quantity.custom_minimum_size.x = 100
	quantity_row.add_child(quantity)
	var breakdown := VBoxContainer.new()
	breakdown.name = "OrderBreakdown"
	right.add_child(breakdown)
	var status := Label.new()
	status.name = "ActionStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status)
	var bottom := CenterContainer.new()
	content.add_child(bottom)
	var confirm := Button.new()
	confirm.name = "ConfirmAction"
	confirm.text = "CONSTRUCT"
	style_slot_button(confirm)
	confirm.custom_minimum_size = Vector2(150, 28)
	bottom.add_child(confirm)
	var close := preload("res://scenes/close_x_button.tscn").instantiate()
	panel.add_child(close)
	close.pressed.connect(overlay.queue_free)
	var submitting := {"active": false}
	var refresh := func(_value := 0.0) -> void:
		for child in breakdown.get_children():
			breakdown.remove_child(child)
			child.queue_free()
		var quote := GameState.construction_order_quote(design, int(quantity.value))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 8)
		breakdown.add_child(grid)
		for text in ["", "NEEDED", "STOCK", "CREDITS"]:
			var label := Label.new()
			label.text = text
			grid.add_child(label)
		for category in range(4):
			var icon := TextureRect.new()
			icon.texture = MATERIAL_ICONS[category]
			icon.custom_minimum_size = Vector2(13, 13)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			grid.add_child(icon)
			for amount in [quote.required[category], quote.stock[category]]:
				var label := Label.new()
				label.text = str(amount)
				grid.add_child(label)
			var price := HBoxContainer.new()
			grid.add_child(price)
			_add_cost_item(price, CREDIT_ICON, int(quote.shortages[category]) * GameState.MATERIAL_PRICES[category])
		var total := HBoxContainer.new()
		breakdown.add_child(total)
		var total_label := Label.new()
		total_label.text = "TOTAL"
		total.add_child(total_label)
		_add_cost_item(total, CREDIT_ICON, int(quote.credits))
		status.text = GameState.construction_order_error(design, _slot_role(slot_index), int(quantity.value))
		status.visible = not status.text.is_empty()
		confirm.disabled = status.visible or submitting.active
	quantity.value_changed.connect(refresh)
	GameState.credits_changed.connect(refresh)
	GameState.tile_inventory_changed.connect(refresh)
	overlay.tree_exiting.connect(func() -> void:
		GameState.credits_changed.disconnect(refresh)
		GameState.tile_inventory_changed.disconnect(refresh))
	refresh.call()
	confirm.pressed.connect(func() -> void:
		if submitting.active:
			return
		quantity.apply()
		if not GameState.construction_order_error(design, _slot_role(slot_index), int(quantity.value)).is_empty():
			refresh.call()
			return
		submitting.active = true
		confirm.disabled = true
		if GameState.purchase_ships(design, slot.name, _slot_role(slot_index), int(quantity.value)):
			overlay.queue_free()
		else:
			submitting.active = false
			refresh.call()
			status.text = "Construction failed. " + GameState.last_save_error
			status.show())


func _refresh_slots() -> void:
	if slot_widgets.is_empty():
		return
	for index in range(_slot_count()):
		var slot: Dictionary = slots[index]
		var widget: Dictionary = slot_widgets[index]
		var design: Ship = slot.design
		widget.preview.set_ship(design)
		if GameState.campaign_active:
			widget.preview.visible = design != null
		widget.label.text = slot.name if design != null else "SELECT SHIP"
		if index >= 3:
			widget.label.text = _slot_role(index).to_upper() + ((": " + slot.name) if design != null else "") if GameState.campaign_active else _slot_role(index).to_upper() + "\n" + (slot.name if design != null else "SELECT")
		if GameState.campaign_active:
			widget.cost.hide()
		else:
			_populate_cost_row(widget.cost, design)
		widget.button.disabled = design != null and _fleet_has_type(slot.name)
		if GameState.campaign_active:
			widget.button.disabled = not GameState.is_shipyard_node(GameState.current_node_id) and not GameState.emergency_roster_available()
		widget.construct.visible = design != null
		if design != null and not GameState.campaign_active:
			var error := GameState.construction_error(design, _slot_role(index))
			widget.construct.disabled = not error.is_empty()
		if GameState.campaign_active:
			# Click opens a priced review, including any current restriction.
			widget.construct.disabled = design == null


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
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)


func _refresh_summary() -> void:
	if summary_host == null:
		return
	for child in summary_host.get_children():
		summary_host.remove_child(child)
		child.queue_free()
	var header := Label.new()
	header.text = "FLEET SUMMARY"
	summary_host.add_child(header)
	if GameState.campaign_active:
		_refresh_roster_summary()
		return
	if GameState.fleet.is_empty():
		var empty := Label.new()
		empty.text = "No ships constructed"
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
	return SLOT_COUNT


func _slot_role(index: int) -> String:
	return "regular"


func _refresh_roster_summary() -> void:
	var totals := Label.new()
	totals.name = "FleetTotals"
	totals.text = "Deployed: %d / %d" % [GameState.get_deployed_fleet().size(), GameState.fleet.size()]
	var health := 0.0
	var maximum := 0.0
	var damaged := 0
	for owned in GameState.get_deployed_fleet():
		damaged += 1 if owned.needs_repair() else 0
		for unit in owned.units:
			health += unit.hp
			maximum += unit.max_hp
	totals.text += "\nHull: %d%%\nDamaged: %d" % [roundi(100 * health / maximum) if maximum > 0 else 0, damaged]
	if GameState.campaign_active:
		totals.text += "\nCapacity %d / %d" % [GameState.used_deployment_capacity(), GameState.deployment_capacity()]
		var economy := GameState.fleet_economy_summary()
		if economy.has_cabins:
			totals.text += "\nPassengers %d/%d" % [economy.passengers, economy.places]
		if economy.has_holds:
			totals.text += "\nCargo %d/%d" % [economy.cargo, economy.cargo_capacity]
		if GameState.emergency_roster_available() and not GameState.is_shipyard_node(GameState.current_node_id):
			totals.text += "\nEmergency: select an owned revision, then deploy reserves."
		if GameState.used_deployment_capacity() > GameState.deployment_capacity():
			totals.modulate = Color(1.0, 0.45, 0.35)
	totals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	totals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_host.add_child(totals)
	var economy := GameState.fleet_economy_summary()
	if economy.has_cabins or economy.has_holds:
		_add_income_row(summary_host, economy)
	reserve_button = Button.new()
	reserve_button.name = "OpenReserve"
	reserve_button.text = "RESERVE (%d)" % (GameState.fleet.size() - GameState.get_deployed_fleet().size())
	style_slot_button(reserve_button)
	reserve_button.custom_minimum_size.y = 26
	reserve_button.pressed.connect(_open_reserve)
	summary_host.add_child(reserve_button)
	var readiness := GameState.deployment_error()
	if not readiness.is_empty():
		var warning := Label.new()
		warning.name = "DepartureStatus"
		warning.text = readiness
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warning.add_theme_color_override("font_color", Color("ffd28a"))
		summary_host.add_child(warning)
	var revision := Button.new()
	revision.text = "REGISTER REVISION"
	revision.disabled = active_slot < 0 or active_slot >= 3 or not GameState.is_shipyard_node(GameState.current_node_id)
	revision.visible = active_slot >= 0 and active_slot < 3
	revision.pressed.connect(func() -> void:
		_review_action("REGISTER REVISION", "Select the current editor blueprint as this family's active revision. Older physical copies become reserves and keep their own damage. Construct new copies at normal cost.", "", "REGISTER", func() -> bool: return GameState.assign_fleet_design(active_slot, slots[active_slot].name, GameState.ship, true)))
	summary_host.add_child(revision)


func _select_owned_revision(owned: FleetShip) -> bool:
	var index: int = GameState.roster_state.active.find(owned.family_id)
	if index < 0:
		index = active_slot if active_slot >= 0 and active_slot < 3 else 0
	if GameState.assign_fleet_design(index, _ship_type_name(owned.display_name), owned.design):
		_refresh_choices()
		return true
	return false


func _open_reserve() -> void:
	if is_instance_valid(reserve_modal):
		return
	_reserve_page = 0
	reserve_modal = Control.new()
	reserve_modal.name = "ReserveModal"
	reserve_modal.add_to_group("modal_ui")
	reserve_modal.z_index = 40
	get_tree().current_scene.add_child(reserve_modal)
	reserve_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.75)
	reserve_modal.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reserve_modal.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(panel)
	_reserve_content = VBoxContainer.new()
	_reserve_content.add_theme_constant_override("separation", 6)
	panel.add_child(_reserve_content)
	_refresh_reserve_modal()

func _reserve_problem(owned: FleetShip) -> String:
	if GameState.battle_pending or GameState.run_ended:
		return "Unavailable during deployment or after the run ends."
	if not GameState.is_shipyard_node(GameState.current_node_id) and not GameState.emergency_roster_available():
		return "Deploy reserves at a secured port."
	if PassengerRules.occupied(GameState.economy_state, owned.id) > 0:
		return "Disembark passengers first."
	var problem := GameState.design_research_error(owned.design)
	if not problem.is_empty():
		return problem
	problem = FleetRules.operational_error(owned)
	if not problem.is_empty():
		return problem
	if owned.slot_role != "regular" and int(GameState.roster_state.support_ids[owned.slot_role]) not in [0, owned.id]:
		return "Reserve the active %s ship first." % owned.slot_role
	return ""

func _refresh_reserve_modal() -> void:
	for child in _reserve_content.get_children():
		_reserve_content.remove_child(child)
		child.queue_free()
	var reserves: Array[FleetShip] = []
	reserves.assign(GameState.fleet.filter(func(owned: FleetShip) -> bool: return not GameState.is_ship_deployed(owned)))
	var pages := maxi(1, ceili(reserves.size() / 3.0))
	_reserve_page = clampi(_reserve_page, 0, pages - 1)
	var title := Label.new()
	title.text = "RESERVE (%d)" % reserves.size()
	_reserve_content.add_child(title)
	if reserves.is_empty():
		var empty := Label.new()
		empty.text = "No ships in reserve."
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_reserve_content.add_child(empty)
	for owned in reserves.slice(_reserve_page * 3, mini(reserves.size(), (_reserve_page + 1) * 3)):
		var row := HBoxContainer.new()
		row.name = "ReserveShip%d" % owned.id
		_reserve_content.add_child(row)
		var preview := preload("res://scripts/fleet_ship_preview.gd").new()
		preview.owned = owned
		preview.custom_minimum_size = Vector2(36, 30)
		row.add_child(preview)
		var name_label := Label.new()
		name_label.text = owned.display_name
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var historical: bool = owned.slot_role == "regular" and not GameState._is_active_revision(owned)
		var problem := _reserve_problem(owned)
		var deploy := Button.new()
		deploy.name = "DeployReserve"
		deploy.text = "USE REVISION" if historical else "DEPLOY"
		style_slot_button(deploy)
		deploy.custom_minimum_size.y = 26
		deploy.disabled = not problem.is_empty()
		row.add_child(deploy)
		var status := Label.new()
		status.text = problem
		status.visible = not problem.is_empty()
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_reserve_content.add_child(status)
		deploy.pressed.connect(func() -> void:
			deploy.disabled = true
			var ok := _select_owned_revision(owned) if historical else GameState.set_ship_reserve(owned, false)
			if not ok:
				status.text = "Change failed. " + GameState.last_save_error
				status.show()
				deploy.disabled = false)
	if pages > 1:
		var pager := HBoxContainer.new()
		_reserve_content.add_child(pager)
		for direction in [-1, 1]:
			var page_button := Button.new()
			page_button.text = "PREVIOUS" if direction == -1 else "NEXT"
			style_slot_button(page_button)
			page_button.disabled = _reserve_page + direction < 0 or _reserve_page + direction >= pages
			page_button.pressed.connect(func() -> void:
				_reserve_page += direction
				_refresh_reserve_modal())
			pager.add_child(page_button)
	var close := Button.new()
	close.text = "CLOSE"
	style_slot_button(close)
	close.custom_minimum_size.y = 26
	close.pressed.connect(reserve_modal.queue_free)
	_reserve_content.add_child(close)


func _on_formation_selection_changed() -> void:
	_refresh_selected_actions()
	selected_ship_changed.emit()


func _refresh_selected_actions() -> void:
	if ship_actions == null:
		return
	for child in ship_actions.get_children():
		ship_actions.remove_child(child)
		child.queue_free()
	if not GameState.campaign_active or board.selected_ships.size() != 1:
		ship_actions.hide()
		return
	var owned: FleetShip = board.selected_ships[0]
	if not GameState.fleet.has(owned):
		ship_actions.hide()
		return
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	ship_actions.add_child(content)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	content.add_child(row)
	var historical := owned.slot_role == "regular" and not GameState._is_active_revision(owned)
	var deployed := GameState.is_ship_deployed(owned)
	var problem := ""
	if GameState.battle_pending:
		problem = "Unavailable during deployment."
	elif not GameState.is_shipyard_node(GameState.current_node_id) and not GameState.emergency_roster_available():
		problem = "Requires a secured port."
	elif PassengerRules.occupied(GameState.economy_state, owned.id) > 0 or CargoRules.quantity(GameState.economy_state, owned.id) > 0:
		problem = "Unload first."
	elif not deployed and not historical:
		problem = GameState.design_research_error(owned.design)
		if problem.is_empty():
			problem = FleetRules.operational_error(owned)
		if problem.is_empty() and owned.slot_role != "regular" and int(GameState.roster_state.support_ids[owned.slot_role]) not in [0, owned.id]:
			problem = "Reserve the active %s ship first." % owned.slot_role
	var toggle := Button.new()
	toggle.name = "ReserveAction"
	toggle.text = "USE REVISION" if historical else ("RESERVE" if deployed else "DEPLOY")
	style_slot_button(toggle)
	toggle.custom_minimum_size.y = 24
	toggle.disabled = not problem.is_empty()
	row.add_child(toggle)
	var feedback := Label.new()
	feedback.name = "ActionStatus"
	feedback.text = problem
	feedback.visible = not problem.is_empty()
	feedback.custom_minimum_size.x = 110 if feedback.visible else 0
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_color_override("font_color", Color("ffd28a"))
	content.add_child(feedback)
	var salvage := Button.new()
	salvage.name = "SalvageAction"
	salvage.text = "SALVAGE"
	style_slot_button(salvage)
	salvage.custom_minimum_size.y = 24
	salvage.disabled = GameState.battle_pending or not GameState.is_shipyard_node(GameState.current_node_id) \
		or PassengerRules.occupied(GameState.economy_state, owned.id) > 0 or CargoRules.quantity(GameState.economy_state, owned.id) > 0
	row.add_child(salvage)
	salvage.pressed.connect(func() -> void:
		salvage.disabled = true
		if not GameState.dismantle_ship(owned):
			feedback.text = "Salvage failed. " + GameState.last_save_error
			feedback.custom_minimum_size.x = 110
			feedback.show()
			salvage.disabled = false)
	toggle.pressed.connect(func() -> void:
		var ok := _select_owned_revision(owned) if historical else GameState.set_ship_reserve(owned, deployed)
		if not ok:
			feedback.text = "Change failed. " + GameState.last_save_error
			feedback.custom_minimum_size.x = 110
			feedback.show()
			board.position_selection_actions())
	if owned.needs_repair():
		var repair := Button.new()
		repair.name = "RepairAction"
		repair.text = "REPAIR"
		style_slot_button(repair)
		repair.custom_minimum_size.y = 24
		row.add_child(repair)
		repair.pressed.connect(func() -> void:
			var quote := GameState.repair_quote(owned)
			var blocked := ""
			if GameState.battle_pending or not GameState.is_shipyard_node(GameState.current_node_id):
				blocked = "Repair requires a secured port."
			elif not owned.is_alive():
				blocked = "A destroyed hull cannot be repaired."
			elif int(quote.credits) > 0 and int(quote.credits) > GameState.credits:
				blocked = "Insufficient credits."
			var material: Array = quote.reconstruction
			_review_action("REPAIR " + owned.display_name, "Repair/reconstruction price: %d cr.\nRebuild: Offense %d / Defense %d / Tech %d / Civic %d.\nStored materials are used first; the price includes shortages. Rebuilt accommodation starts empty." % [quote.credits, material[0], material[1], material[2], material[3]], blocked, "REPAIR", func() -> bool: return GameState.repair_ship(owned)))
	_add_selected_economy(content, owned)
	board.position_selection_actions()
	board.position_selection_actions.call_deferred()


func _add_income_row(host: Container, economy: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.name = "ArrivalIncome"
	host.add_child(row)
	var label := Label.new()
	label.text = "Arrival" if economy.planned else "Next port"
	row.add_child(label)
	_add_cost_item(row, CREDIT_ICON, int(economy.income))


func _add_selected_economy(content: VBoxContainer, owned: FleetShip) -> void:
	var economy := GameState.fleet_economy_summary(owned.id)
	if not economy.has_cabins and not economy.has_holds:
		return
	var info := Label.new()
	info.name = "ShipEconomy"
	var lines: Array[String] = []
	if economy.has_cabins:
		lines.append("Passengers %d/%d" % [economy.passengers, economy.places])
		var luxury := str(economy.luxury_min) if economy.luxury_min == economy.luxury_max else "%d-%d" % [economy.luxury_min, economy.luxury_max]
		lines.append("Luxury " + luxury)
	if economy.has_holds:
		lines.append("Cargo %d/%d" % [economy.cargo, economy.cargo_capacity])
	info.text = "\n".join(lines)
	content.add_child(info)
	_add_income_row(content, economy)
	var actions := HBoxContainer.new()
	content.add_child(actions)
	var at_port := not GameState.battle_pending and not GameState.port_services().is_empty()
	for kind in ["cargo", "passengers"]:
		if int(economy[kind]) == 0:
			continue
		var button := Button.new()
		button.name = "OffloadCargo" if kind == "cargo" else "DisembarkPassengers"
		button.text = "OFFLOAD" if kind == "cargo" else "DISEMBARK"
		style_slot_button(button)
		button.custom_minimum_size.y = 24
		button.disabled = not at_port
		actions.add_child(button)
		button.pressed.connect(func() -> void:
			var ok := GameState.offload_cargo(owned.id) if kind == "cargo" else GameState.disembark_passengers(owned.id)
			if not ok:
				var feedback: Label = ship_actions.find_child("ActionStatus", true, false)
				feedback.text = "Unload failed. " + GameState.last_save_error
				feedback.show())


func _review_action(title: String, body: String, problem: String, action_name: String, action: Callable) -> void:
	if is_instance_valid(action_review):
		return
	var overlay := Control.new()
	action_review = overlay
	overlay.name = "FleetActionReview"
	overlay.add_to_group("modal_ui")
	overlay.z_index = 40
	get_tree().current_scene.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.75)
	overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 180)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	var heading := Label.new()
	heading.text = title
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(heading)
	var description := Label.new()
	description.text = body
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(description)
	var status := Label.new()
	status.name = "ActionStatus"
	status.text = problem
	status.visible = not problem.is_empty()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color("ffd28a"))
	content.add_child(status)
	var row := HBoxContainer.new()
	content.add_child(row)
	var confirm := Button.new()
	confirm.name = "ConfirmAction"
	confirm.text = action_name
	confirm.disabled = not problem.is_empty()
	style_slot_button(confirm)
	confirm.custom_minimum_size.y = 28
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(confirm)
	var cancel := Button.new()
	cancel.text = "CANCEL"
	style_slot_button(cancel)
	cancel.custom_minimum_size.y = 28
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cancel)
	cancel.pressed.connect(overlay.queue_free)
	confirm.pressed.connect(func() -> void:
		confirm.disabled = true
		if action.call():
			overlay.queue_free()
		else:
			status.text = "Could not complete action. " + GameState.last_save_error
			status.show()
			confirm.disabled = false)


static func compact_button(button: Button) -> void:
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 30)
	button.theme_type_variation = &"FramedButton"


static func _style_slot_action(button: TextureButton) -> void:
	button.custom_minimum_size = Vector2(24, 30)
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


static func style_checkbox(_checkbox: CheckBox) -> void:
	pass # Icons and styles inherit from ui_theme.tres.


static func _arrow_icon(right: bool) -> Texture2D:
	var image := Image.new()
	var path := "M4 2 L9 7 L4 12" if right else "M9 2 L4 7 L9 12"
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14"><path d="%s" fill="none" stroke="#cfdee4" stroke-width="2"/></svg>' % path)
	return ImageTexture.create_from_image(image)


static func trash_icon() -> Texture2D:
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="16"><path d="M2 4h10M5 4V2h4v2M3 5l1 9h6l1-9M6 6v6M8 6v6" fill="none" stroke="#ed7272" stroke-width="1.5" stroke-linejoin="round"/></svg>')
	return ImageTexture.create_from_image(image)
