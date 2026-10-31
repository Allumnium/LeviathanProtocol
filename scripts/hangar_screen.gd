extends Control

const EquipmentFilters = preload("res://scripts/hangar_equipment_filters.gd")

var selected_ship_id := -1
var selected_slot := ""
var roster: VBoxContainer
var details: VBoxContainer
var center: Control
var header: Label
var feedback: Label
var canvas: Control
var shop: Control
var buy_open := false
var buy_mode := "EQUIPMENT"
var shop_rows: VBoxContainer
var active_tab := "FLEET"
var formation_view: Control
var formation_camera := Vector2.ZERO
var formation_zoom := 1.0
var formation_selection: Array[int] = []
var fitting_views: Dictionary = {}
var traveling := false
var graph: Control
var flagship_icon: Texture2D
var refresh_queued := false
var stock: Control
var stock_preferences: Dictionary = {}
var shop_filters: EquipmentFilters
var stats_grid: GridContainer
var slot_info: Label
var roster_panel: PanelContainer
var details_panel: PanelContainer

func _ready() -> void:
	if GameState.run_id.is_empty():
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	AudioManager.play_menu_music()
	var margin := MarginContainer.new()
	var background := ColorRect.new()
	background.color = get_theme_color("background_color", "SlotCanvas")
	background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 8)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var credit_icon := TextureRect.new()
	credit_icon.texture = load("res://assets/credits.png")
	credit_icon.custom_minimum_size = Vector2(20, 20)
	credit_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	credit_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	credit_icon.size_flags_vertical = SIZE_SHRINK_CENTER
	top.add_child(credit_icon)
	header = _label("")
	header.size_flags_horizontal = SIZE_EXPAND_FILL
	header.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(header)
	flagship_icon = load("res://assets/flag.png")
	top.add_child(_button("MENU", func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	for title in ["FLEET", "SHIPS", "RESEARCH", "MAP"]:
		var tab := _button(title, func() -> void:
			if traveling:
				return
			active_tab = title
			buy_open = false
			_refresh())
		tab.size_flags_horizontal = SIZE_EXPAND_FILL
		tabs.add_child(tab)
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(body)
	roster = _panel(body, 132)
	roster_panel = roster.get_parent()
	center = Control.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	center.size_flags_vertical = SIZE_EXPAND_FILL
	center.clip_contents = true
	body.add_child(center)
	details = _panel(body, 156)
	details_panel = details.get_parent()
	resized.connect(_resize_panels)
	_resize_panels()
	feedback = _label("")
	column.add_child(feedback)
	GameState.fleet_changed.connect(_queue_refresh)
	GameState.research_changed.connect(_queue_refresh)
	GameState.credits_changed.connect(_queue_refresh)
	_refresh()

func _resize_panels() -> void:
	if roster_panel != null:
		roster_panel.custom_minimum_size.x = clampf(size.x * 0.16, 116, 220)
	if details_panel != null:
		details_panel.custom_minimum_size.x = clampf(size.x * 0.24, 180, 300)
	if stats_grid != null and is_instance_valid(stats_grid):
		stats_grid.columns = 3 if size.x < 1000 else 5

func _panel(parent: Node, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CompactPanel"
	panel.custom_minimum_size.x = width
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	return box

func _button(title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.theme_type_variation = &"CompactButton"
	button.focus_mode = FOCUS_NONE
	button.custom_minimum_size.y = 26
	button.pressed.connect(action)
	return button

func _label(title: String) -> Label:
	var label := Label.new()
	label.text = title
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _clear(host: Node) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()

func _queue_refresh() -> void:
	if not refresh_queued:
		refresh_queued = true
		_refresh.call_deferred()

func _refresh() -> void:
	refresh_queued = false
	if traveling:
		return
	if is_instance_valid(canvas):
		fitting_views[canvas.owned_id] = {"camera": canvas.camera, "zoom": canvas.zoom}
	if is_instance_valid(formation_view):
		formation_camera = formation_view.camera
		formation_zoom = formation_view.zoom
		if formation_view.selected_id == selected_ship_id:
			formation_selection.assign(formation_view.selected_ids)
	formation_view = null
	header.text = str(GameState.credits)
	_clear(roster)
	_clear(details)
	if is_instance_valid(shop) and shop.get_parent() == center:
		shop = null
	_clear(center)
	canvas = null
	stock = null
	stats_grid = null
	slot_info = null
	if selected_ship_id > 0 and GameState.owned_ship(selected_ship_id) == null:
		selected_ship_id = 0
	if active_tab == "SHIPS" and selected_ship_id <= 0:
		for owned: HangarShip in GameState.fleet:
			if owned.flagship:
				selected_ship_id = owned.id
				formation_selection.assign([owned.id])
				selected_slot = ""
				break
	elif selected_ship_id == -1 and not GameState.fleet.is_empty():
		selected_ship_id = GameState.fleet[0].id
	formation_selection = formation_selection.filter(func(id: int) -> bool: return GameState.owned_ship(id) != null)
	if GameState.completed or GameState.run_ended:
		center.add_child(_label("RUN COMPLETE" if GameState.completed else "FLAGSHIP LOST"))
		return
	if active_tab == "RESEARCH":
		var research: Control = load("res://scripts/research_panel.gd").new()
		research.registry = HangarResearch.view_registry()
		center.add_child(research)
		research.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		research.bind_external_panels(roster, details)
		research.focus_requested.connect(func(key: String) -> void: _result(GameState.set_research_focus(key)))
		return
	if active_tab == "MAP":
		_show_map()
		return
	roster.add_child(_label("SHIPS"))
	var ship_scroll := ScrollContainer.new()
	ship_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	ship_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster.add_child(ship_scroll)
	var ship_rows := VBoxContainer.new()
	ship_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	ship_scroll.add_child(ship_rows)
	for owned: HangarShip in GameState.fleet:
		var button := _button(owned.display_name, func() -> void:
			selected_ship_id = owned.id
			formation_selection.assign([owned.id])
			selected_slot = ""
			_refresh())
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = flagship_icon if owned.flagship else null
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.name = "Ship%d" % owned.id
		button.toggle_mode = true
		button.button_pressed = owned.id == selected_ship_id
		ship_rows.add_child(button)
	roster.add_child(_label("Command %d / %d" % [GameState.used_command(), GameState.command_limit()]))
	var buy := _button("BUY", _open_shop)
	buy.name = "BuyToggle"
	buy.toggle_mode = true
	buy.button_pressed = buy_open
	roster.add_child(buy)
	(roster.get_child(roster.get_child_count() - 1) as Button).disabled = not GameState.is_shipyard_node(GameState.current_node_id)
	if not GameState.is_shipyard_node(GameState.current_node_id):
		roster.add_child(_label("Buy at shipyard"))
	if active_tab == "FLEET":
		var board: Control = load("res://scripts/hangar_formation.gd").new()
		board.selected_id = selected_ship_id
		board.selected_ids.assign(formation_selection)
		board.camera = formation_camera
		board.zoom = formation_zoom
		formation_view = board
		center.add_child(board)
		board.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		board.ship_selected.connect(func(id: int) -> void:
			selected_ship_id = id
			_queue_refresh())
		board.salvage_requested.connect(_confirm_salvage)
		board.equipment_requested.connect(func(id: int) -> void:
			selected_ship_id = id
			active_tab = "SHIPS"
			_refresh())
	else:
		var owned: HangarShip = GameState.owned_ship(selected_ship_id)
		if owned != null:
			var stack := VBoxContainer.new()
			center.add_child(stack)
			stack.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
			canvas = load("res://scripts/hangar_canvas.gd").new()
			var view: Dictionary = fitting_views.get(owned.id, {})
			canvas.camera = view.get("camera", Vector2.ZERO)
			canvas.zoom = view.get("zoom", 1.0)
			canvas.size_flags_vertical = SIZE_EXPAND_FILL
			stack.add_child(canvas)
			canvas.selected_slot = selected_slot
			canvas.set_owned(owned)
			var bottom := Control.new()
			bottom.name = "ShipOrPartDetails"
			bottom.custom_minimum_size.y = 64
			stack.add_child(bottom)
			slot_info = _label("")
			bottom.add_child(slot_info)
			slot_info.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
			stats_grid = GridContainer.new()
			stats_grid.columns = 3 if size.x < 1000 else 5
			bottom.add_child(stats_grid)
			stats_grid.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
			stock = load("res://scripts/hangar_stock.gd").new()
			stock.preferences = stock_preferences.duplicate()
			stock.size_flags_vertical = SIZE_EXPAND_FILL
			details.add_child(stock)
			stock.changed_preferences.connect(func(value: Dictionary) -> void:
				stock_preferences = value
				if buy_open and is_instance_valid(shop_filters):
					shop_filters.set_preferences(value)
					if buy_mode == "EQUIPMENT":
						_shop_equipment())
			stock.equipment_stored.connect(_result)
			stock.equipment_sold.connect(_result)
			var repair := _button("REPAIR %d cr" % owned.repair_cost(), func() -> void: _result(GameState.repair_ship(GameState.owned_ship(selected_ship_id))))
			repair.disabled = not owned.needs_repair() or GameState.credits < owned.repair_cost()
			roster.add_child(repair)
			if not owned.flagship:
				roster.add_child(_button("SALVAGE", func() -> void: _confirm_salvage(selected_ship_id)))
			canvas.slot_selected.connect(func(key: String) -> void:
				selected_slot = key
				_show_details())
			canvas.instance_selected.connect(func(key: String, uid: String) -> void:
				selected_slot = key
				_result(GameState.fit_equipment(selected_ship_id, key, uid)))
	_show_details()
	if buy_open:
		_show_buy_panel()

func _show_details() -> void:
	var owned: HangarShip = GameState.owned_ship(selected_ship_id)
	if owned == null:
		_clear(details)
		details.add_child(_label("FLEET"))
		var cost: int = GameState.fleet_repair_cost()
		var repair := _button("REPAIR ALL %d cr" % cost, func() -> void: _result(GameState.repair_all_ships()))
		repair.disabled = cost <= 0 or GameState.credits < cost
		details.add_child(repair)
		return
	if active_tab == "SHIPS":
		if stats_grid == null:
			return
		var slot: Dictionary = {}
		for candidate: Dictionary in owned.chassis.slots:
			if candidate.id == selected_slot and owned.mounts.has(selected_slot):
				slot = candidate
		if slot.is_empty():
			selected_slot = ""
			canvas.selected_slot = ""
		stats_grid.visible = slot.is_empty()
		slot_info.visible = not slot.is_empty()
		slot_info.text = ""
		if not slot.is_empty():
			var instance: Dictionary = owned.mounts.get(selected_slot, {})
			var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
			slot_info.text = "%s\nHP %.0f / %.0f | %s\n%s" % [item.name, instance.hp, item.hit_points, SlotCatalog.slot_label(slot), _part_effect(item)]
			return
		_clear(stats_grid)
		var summary := owned.hangar_summary()
		for value in ["Integrity\n%.0f / %.0f" % [summary.integrity, summary.integrity_max],
			"Shields\n%.0f" % summary.shields, "DPS\n%.1f" % summary.dps,
			"Cargo\n%d" % summary.cargo, "Passengers\n%d" % summary.passengers]:
			var label := _label(value)
			label.size_flags_horizontal = SIZE_EXPAND_FILL
			stats_grid.add_child(label)
		return
	_clear(details)
	details.add_child(_label(owned.display_name))
	details.add_child(_label("Hull %.0f / %.0f" % [owned.hull_hp, owned.hull_max]))
	var stats := owned.get_stats()
	details.add_child(_label("Shield %.0f\nDPS %.1f" % [stats.shields, stats.dps]))
	if not selected_slot.is_empty():
		for slot: Dictionary in owned.chassis.slots:
			if slot.id == selected_slot:
				details.add_child(_label(SlotCatalog.slot_label(slot)))
		var instance: Dictionary = owned.mounts.get(selected_slot, {})
		if not instance.is_empty():
			var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
			details.add_child(_label(item.name + " #%s\nHP %.0f / %.0f" % [instance.uid, instance.hp, item.hit_points]))
			if item.id == "research_lab":
				details.add_child(_label("%d RP/day" % int(item.rank)))
			if item.id in HangarCarriers.CAPACITIES:
				details.add_child(_label("%d craft / 2 active" % int(HangarCarriers.CAPACITIES[item.id])))
			if item.id == "ammunition_magazine":
				details.add_child(_label("+20% weapon cycling"))
			if item.id == "tactical_computer":
				details.add_child(_label("Salvo / 12s per computer"))
			if item.id == "command_uplink":
				details.add_child(_label("Auto mark: +20% / 5s"))
			if item.id in HangarResearch.DEFERRED_PURCHASES:
				details.add_child(_label("Deferred"))
			if HangarTrade.has_load(instance):
				var contents: Dictionary = instance.load
				details.add_child(_label("%s %d" % [str(contents.kind).capitalize(), contents.quantity]))
	details.add_child(_button("REPAIR %d cr" % owned.repair_cost(), func() -> void: _result(GameState.repair_ship(GameState.owned_ship(selected_ship_id)))))
	var repair := details.get_child(details.get_child_count() - 1) as Button
	repair.disabled = not owned.needs_repair() or GameState.credits < owned.repair_cost()
	if not owned.flagship and active_tab != "FLEET":
		details.add_child(_button("SALVAGE", func() -> void: _confirm_salvage(selected_ship_id)))
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	details.add_child(spacer)

func _part_effect(item: Dictionary) -> String:
	match item.id:
		"research_lab": return "%d RP/day" % int(item.rank)
		"cargo_hold": return "%d cargo" % HangarTrade.CARGO_CAPACITY
		"passenger_cabin": return "%d passengers" % HangarTrade.PASSENGER_CAPACITY
		"ammunition_magazine": return "+20% weapon cycling"
		"tactical_computer": return "Salvo / 12s per computer"
		"command_uplink": return "Auto mark: +20% / 5s"
	if item.id in HangarCarriers.CAPACITIES:
		return "%d craft / 2 active" % int(HangarCarriers.CAPACITIES[item.id])
	var values: Dictionary = item.stats
	var effects: PackedStringArray = []
	if not values.weapons.is_empty():
		var dps := 0.0
		var reach := 0.0
		for weapon: ShipWeaponStats in SlotCatalog.stats_for(item.id, int(item.rank)).weapons:
			dps += weapon.get_dps()
			reach = maxf(reach, weapon.range_units)
		effects.append("DPS %.1f | Range %.0f" % [dps, reach])
	if values.shields > 0:
		effects.append("Shields %.0f" % values.shields)
	if values.thrust > 0:
		effects.append("Thrust %.0f" % values.thrust)
	if values.integrity > 0:
		effects.append("Integrity +%.0f" % values.integrity)
	return " | ".join(effects)

func _result(ok: bool) -> void:
	feedback.text = "" if ok else (GameState.last_save_error if not GameState.last_save_error.is_empty() else "Unavailable")
	if ok:
		_queue_refresh()
		if shop != null and not buy_open:
			shop.queue_free()
			shop = null

func _modal(title: String) -> VBoxContainer:
	buy_open = false
	if shop != null:
		shop.queue_free()
	shop = Control.new()
	shop.name = "HangarShopModal"
	shop.add_to_group("modal_ui")
	shop.z_index = 30
	add_child(shop)
	shop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.65)
	shop.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var card := PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = &"CompactPanel"
	shop.add_child(card)
	card.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	card.offset_left = 32
	card.offset_top = 24
	card.offset_right = -32
	card.offset_bottom = -24
	var column := VBoxContainer.new()
	card.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var heading := _label(title)
	heading.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(heading)
	var close: TextureButton = load("res://scenes/close_x_button.tscn").instantiate()
	card.add_child(close)
	close.set_anchors_preset(PRESET_TOP_RIGHT)
	close.pressed.connect(func() -> void:
		shop.queue_free()
		shop = null)
	return column

func _open_shop() -> void:
	if not GameState.is_shipyard_node(GameState.current_node_id):
		return
	buy_open = not buy_open
	_refresh()

func _show_buy_panel() -> void:
	var card := PanelContainer.new()
	card.name = "BuyPanel"
	card.set_meta("close_target", true)
	card.theme_type_variation = &"CompactPanel"
	card.z_index = 10
	shop = card
	center.add_child(card)
	card.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	card.add_child(column)
	column.add_child(_label("BUY"))
	var close: TextureButton = load("res://scenes/close_x_button.tscn").instantiate()
	card.add_child(close)
	close.set_anchors_preset(PRESET_TOP_RIGHT)
	close.pressed.connect(func() -> void:
		buy_open = false
		_refresh())
	var modes := HBoxContainer.new()
	column.add_child(modes)
	modes.add_child(_button("EQUIPMENT", func() -> void: _shop_equipment()))
	modes.add_child(_button("SHIPS", func() -> void: _shop_ships()))
	shop_filters = EquipmentFilters.new()
	shop_filters.name = "ShopFilters"
	shop_filters.set_preferences(stock_preferences)
	column.add_child(shop_filters)
	shop_filters.changed.connect(_shop_equipment_filters_changed)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	shop_rows = VBoxContainer.new()
	shop_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(shop_rows)
	if buy_mode == "SHIPS":
		_shop_ships()
	else:
		_shop_equipment()

func _shop_equipment() -> void:
	buy_mode = "EQUIPMENT"
	shop_filters.show()
	_clear(shop_rows)
	var grants: Dictionary = GameState.research_grants()
	var candidates: Array[Dictionary] = []
	for item in SlotCatalog.equipment():
		if item.id in HangarResearch.DEFERRED_EQUIPMENT or item.id in HangarResearch.DEFERRED_PURCHASES:
			continue
		if not shop_filters.matches(item):
			continue
		candidates.append(item)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.price) == int(b.price):
			var a_name := str(a.name).to_lower()
			var b_name := str(b.name).to_lower()
			if a_name == b_name:
				return str(a.id) < str(b.id) if a.id != b.id else int(a.rank) < int(b.rank)
			return a_name < b_name
		return int(a.price) < int(b.price))
	for item: Dictionary in candidates:
		var button := _button("%s\n%s %s | %d cr%s" % [item.name, item.type.capitalize(), item.size, item.price, "" if SlotCatalog.unlocked(item, grants) else " | Research"], func() -> void: _result(GameState.buy_equipment(item.id, int(item.rank))))
		button.disabled = not SlotCatalog.unlocked(item, grants) or GameState.credits < int(item.price)
		shop_rows.add_child(button)
	if candidates.is_empty():
		shop_rows.add_child(_label("No matches"))

func _shop_equipment_filters_changed(value: Dictionary) -> void:
	stock_preferences = value
	if is_instance_valid(stock):
		stock.preferences = value.duplicate(true)
		stock.filters.set_preferences(value)
		stock._render()
	if buy_mode == "EQUIPMENT":
		_shop_equipment()

func _shop_ships() -> void:
	buy_mode = "SHIPS"
	shop_filters.hide()
	_clear(shop_rows)
	var available := SlotCatalog.chassis()
	available.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.price) == int(b.price):
			return str(a.name) < str(b.name)
		return int(a.price) < int(b.price))
	for chassis in available:
		if int(chassis.command) > 0:
			continue
		var row := HBoxContainer.new()
		shop_rows.add_child(row)
		var image := TextureRect.new()
		image.texture = SurfaceArt.texture(chassis.art)
		SurfaceArt.apply(image)
		image.custom_minimum_size = Vector2(40, 48)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(image)
		var button := _button("%s\n%d command | %d cr" % [chassis.name, chassis.command_cost, chassis.price], func() -> void: _result(GameState.buy_chassis(chassis.id)))
		button.disabled = GameState.credits < int(chassis.price) or GameState.used_command() + int(chassis.command_cost) > GameState.command_limit()
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(button)

func _show_map() -> void:
	roster.add_child(_label("DESTINATION"))
	graph = load("res://scripts/graph_view.gd").new()
	center.add_child(graph)
	graph.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	graph.set_current_node(GameState.current_node_id)
	graph.destination_selected.connect(_select_destination)
	for id: int in GameState.get_reachable_nodes(GameState.current_node_id):
		var preview: Dictionary = GameState.node_preview(id)
		roster.add_child(_button(preview.title, _select_destination.bind(id)))
	var problem: String = GameState.deployment_error()
	if not problem.is_empty():
		details.add_child(_label(problem))

func _select_destination(id: int) -> void:
	if traveling:
		return
	GameState.set_planned_destination(id)
	_clear(details)
	var preview: Dictionary = GameState.node_preview(id)
	details.add_child(_label(preview.title))
	details.add_child(_label(preview.text))
	var days: float = GameState.research_travel_time(GameState.current_node_id, id)
	details.add_child(_label("%s RP on arrival" % ScienceRules.format_rp(ScienceRules.journey_rp(ScienceRules.snapshot(GameState.get_deployed_fleet()), days))))
	details.add_child(_button("TRAVEL", func() -> void:
		_begin_travel(id)))

func _begin_travel(id: int) -> void:
	if traveling:
		return
	traveling = true
	# Commit departure before animation; prevent UI rebuilds until arrival.
	if not GameState.travel_to(id):
		traveling = false
		_result(false)
		return
	for button in details.find_children("*", "Button", true, false):
		button.disabled = true
	graph.start_travel(id)
	await graph.travel_finished
	traveling = false
	if GameState.battle_pending:
		get_tree().change_scene_to_file("res://scenes/auto_battle.tscn")
	else:
		_refresh()

func _confirm_salvage(id: int) -> void:
	var owned: HangarShip = GameState.owned_ship(id)
	if owned == null or owned.flagship:
		return
	var column := _modal("SALVAGE " + owned.display_name + "?")
	var card: PanelContainer = column.get_parent()
	card.set_anchors_and_offsets_preset(PRESET_CENTER)
	card.offset_left = -140
	card.offset_right = 140
	card.offset_top = -45
	card.offset_bottom = 45
	column.add_child(_button("SALVAGE", func() -> void:
		if GameState.salvage_hangar_ship(id):
			selected_ship_id = 0
			formation_selection.clear()
			_result(true)
		else:
			_result(false)))
