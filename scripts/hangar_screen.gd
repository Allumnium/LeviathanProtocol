extends Control

var selected_ship_id := 0
var selected_slot := ""
var roster: VBoxContainer
var details: VBoxContainer
var center: Control
var header: Label
var feedback: Label
var canvas: Control
var shop: Control
var shop_rows: VBoxContainer
var active_tab := "HANGAR"
var refresh_queued := false

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
	top.add_child(credit_icon)
	header = _label("")
	header.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(header)
	top.add_child(_button("MENU", func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	for title in ["HANGAR", "FORMATION", "RESEARCH", "MAP"]:
		var tab := _button(title, func() -> void:
			active_tab = title
			_refresh())
		tab.size_flags_horizontal = SIZE_EXPAND_FILL
		tabs.add_child(tab)
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(body)
	roster = _panel(body, 132)
	center = Control.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	center.size_flags_vertical = SIZE_EXPAND_FILL
	center.clip_contents = true
	body.add_child(center)
	details = _panel(body, 156)
	feedback = _label("")
	column.add_child(feedback)
	GameState.fleet_changed.connect(_queue_refresh)
	GameState.research_changed.connect(_queue_refresh)
	GameState.credits_changed.connect(_queue_refresh)
	_refresh()

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
	header.text = "%d     RP %s" % [GameState.credits, ScienceRules.format_rp(GameState.research_points)]
	_clear(roster)
	_clear(details)
	_clear(center)
	canvas = null
	if GameState.owned_ship(selected_ship_id) == null and not GameState.fleet.is_empty():
		selected_ship_id = GameState.fleet[0].id
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
		var button := _button(("* " if owned.flagship else "") + owned.display_name, func() -> void:
			selected_ship_id = owned.id
			selected_slot = ""
			_refresh())
		button.name = "Ship%d" % owned.id
		ship_rows.add_child(button)
	roster.add_child(_label("Command %d / %d" % [GameState.used_command(), GameState.command_limit()]))
	roster.add_child(_button("BUY", _open_shop))
	(roster.get_child(roster.get_child_count() - 1) as Button).disabled = not GameState.is_shipyard_node(GameState.current_node_id)
	if not GameState.is_shipyard_node(GameState.current_node_id):
		roster.add_child(_label("Buy at shipyard"))
	if active_tab == "FORMATION":
		var board: Control = load("res://scripts/hangar_formation.gd").new()
		board.selected_id = selected_ship_id
		center.add_child(board)
		board.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		board.ship_selected.connect(func(id: int) -> void:
			selected_ship_id = id
			_refresh())
		board.equipment_requested.connect(func(id: int) -> void:
			selected_ship_id = id
			active_tab = "HANGAR"
			_refresh())
	else:
		var owned: HangarShip = GameState.owned_ship(selected_ship_id)
		if owned != null:
			canvas = load("res://scripts/hangar_canvas.gd").new()
			center.add_child(canvas)
			canvas.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
			canvas.selected_slot = selected_slot
			canvas.set_owned(owned)
			canvas.slot_selected.connect(func(key: String) -> void:
				selected_slot = key
				_show_details())
			canvas.instance_selected.connect(func(key: String, uid: String) -> void:
				selected_slot = key
				_result(GameState.fit_equipment(selected_ship_id, key, uid)))
	_show_details()

func _show_details() -> void:
	_clear(details)
	var owned: HangarShip = GameState.owned_ship(selected_ship_id)
	if owned == null:
		return
	details.add_child(_label(owned.display_name))
	details.add_child(_label("Hull %.0f / %.0f" % [owned.hull_hp, owned.hull_max]))
	var stats := owned.get_stats()
	details.add_child(_label("Shield %.0f\nDPS %.1f" % [stats.shields, stats.dps]))
	if not selected_slot.is_empty():
		for slot: Dictionary in owned.chassis.slots:
			if slot.id == selected_slot:
				details.add_child(_label("%s | %s" % [slot.type.capitalize(), slot.size]))
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
	if not owned.flagship and active_tab != "FORMATION":
		details.add_child(_button("SALVAGE", func() -> void: _result(GameState.salvage_hangar_ship(selected_ship_id))))
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	details.add_child(spacer)
	details.add_child(_button("STOCK", _open_stock))

func _result(ok: bool) -> void:
	feedback.text = "" if ok else (GameState.last_save_error if not GameState.last_save_error.is_empty() else "Unavailable")
	if ok:
		_queue_refresh()
		if shop != null:
			shop.queue_free()
			shop = null

func _modal(title: String) -> VBoxContainer:
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
	var column := _modal("BUY")
	var modes := HBoxContainer.new()
	column.add_child(modes)
	modes.add_child(_button("EQUIPMENT", func() -> void: _shop_equipment()))
	modes.add_child(_button("SHIPS", func() -> void: _shop_ships()))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	shop_rows = VBoxContainer.new()
	shop_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(shop_rows)
	_shop_equipment()

func _shop_equipment() -> void:
	_clear(shop_rows)
	var grants: Dictionary = GameState.research_grants()
	for item in SlotCatalog.equipment():
		if item.id in HangarResearch.DEFERRED_EQUIPMENT or item.id in HangarResearch.DEFERRED_PURCHASES:
			continue
		var button := _button("%s | %s %s | %d cr%s" % [item.name, item.type.capitalize(), item.size, item.price, "" if SlotCatalog.unlocked(item, grants) else " | Research"], func() -> void: _result(GameState.buy_equipment(item.id, int(item.rank))))
		button.disabled = not SlotCatalog.unlocked(item, grants) or GameState.credits < int(item.price)
		shop_rows.add_child(button)

func _shop_ships() -> void:
	_clear(shop_rows)
	for chassis in SlotCatalog.chassis():
		if int(chassis.command) > 0:
			continue
		var row := HBoxContainer.new()
		shop_rows.add_child(row)
		var image := TextureRect.new()
		image.texture = load(chassis.art)
		image.custom_minimum_size = Vector2(64, 64)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(image)
		var button := _button("%s | %d command | %d cr" % [chassis.name, chassis.command_cost, chassis.price], func() -> void: _result(GameState.buy_chassis(chassis.id)))
		button.disabled = GameState.credits < int(chassis.price) or GameState.used_command() + int(chassis.command_cost) > GameState.command_limit()
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(button)

func _open_stock() -> void:
	var column := _modal("STOCK")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for instance: Dictionary in GameState.equipment_inventory.values():
		if not GameState.equipment_location(instance.uid).is_empty():
			continue
		var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
		var row := HBoxContainer.new()
		rows.add_child(row)
		var label := _label("%s #%s | %.0f%%" % [item.name, instance.uid, 100 * instance.hp / item.hit_points])
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(_button("SELL %d cr" % floori(float(item.price) * 0.5 * instance.hp / item.hit_points), func() -> void: _result(GameState.sell_equipment(instance.uid))))
		if instance.hp < item.hit_points:
			row.add_child(_button("REPAIR %d cr" % ceili(item.hit_points - instance.hp), func() -> void: _result(GameState.repair_equipment(instance.uid))))

func _show_map() -> void:
	roster.add_child(_label("DESTINATION"))
	var graph: Control = load("res://scripts/graph_view.gd").new()
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
	GameState.set_planned_destination(id)
	_clear(details)
	var preview: Dictionary = GameState.node_preview(id)
	details.add_child(_label(preview.title))
	details.add_child(_label(preview.text))
	var days: float = GameState.research_travel_time(GameState.current_node_id, id)
	details.add_child(_label("%s RP on arrival" % ScienceRules.format_rp(ScienceRules.journey_rp(ScienceRules.snapshot(GameState.get_deployed_fleet()), days))))
	details.add_child(_button("TRAVEL", func() -> void:
		if GameState.travel_to(id):
			if GameState.battle_pending:
				get_tree().change_scene_to_file("res://scenes/auto_battle.tscn")
			else:
				_refresh()
		else:
			_result(false)))
