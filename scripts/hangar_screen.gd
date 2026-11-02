extends Control

const EquipmentFilters = preload("res://scripts/hangar_equipment_filters.gd")
const StatBars = preload("res://scripts/ship_stat_bars.gd")
const CREDITS_ICON: Texture2D = preload("res://assets/credits.png")
const SCIENCE_ICON: Texture2D = preload("res://assets/science.png")
const BUY_ICON: Texture2D = preload("res://assets/ui/Btn_BuyCoins_n.png")
const ExpeditionStateData = preload("res://scripts/expedition_state.gd")
const EXPEDITION_SAVE_INTERVAL := 5.0

var selected_ship_id := -1
var selected_slot := ""
var roster: VBoxContainer
var details: VBoxContainer
var center: Control
var header: Label
var research_status: Label
var research_rate: Label
var research_progress_row: HBoxContainer
var research_progress: ProgressBar
var research_button: Button
var research_pulse: ShaderMaterial
var research_pulse_time := 0.0
var header_wallet: HBoxContainer
var feedback: Label
var canvas: Control
var shop: Control
var buy_open := false
var buy_mode := "EQUIPMENT"
var shop_rows: VBoxContainer
var shop_scroll: ScrollContainer
var active_tab := "FLEET"
var formation_view: Control
var formation_camera := Vector2.ZERO
var formation_zoom := 1.0
var formation_selection: Array[int] = []
var fitting_views: Dictionary = {}
var research_view: Dictionary = {}
var research_panel: Control
var traveling := false
var graph: Control
var map_camera: Dictionary = {}
var map_details: VBoxContainer
var flagship_icon: Texture2D
var refresh_queued := false
var stock: Control
var stock_preferences: Dictionary = {}
var shop_filters: EquipmentFilters
var only_researched := true
var researched_filter: CheckBox
var stats_grid: GridContainer
var slot_info: ResourceText
var roster_panel: PanelContainer
var details_panel: PanelContainer
var settings_dialog: PopupPanel
var tabs: HBoxContainer
var inspection: ScrollContainer
var inspected_item: Dictionary = {}
var travel_controls: PanelContainer
var speed_buttons: Dictionary = {}
var travel_pause_button: Button
var travel_refuel_button: Button
var travel_retry_button: Button
var travel_fuel: Label
var departure_button: Button
var departure_modal: Control
var departure_error: Label
var departure_retry: Button
var encounter_modal: Control
var encounter_error: Label
var encounter_retry: Button
var encounter_event_id := ""
var expedition_save_elapsed := 0.0
var expedition_status_override := ""
var shipyard_access_available := false

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
	tabs = HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_vertical = SIZE_SHRINK_BEGIN
	top.add_child(tabs)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(spacer)
	research_button = _button_with_sound("", func() -> void:
		if traveling:
			return
		active_tab = "RESEARCH"
		buy_open = false
		_refresh(), &"accept")
	research_button.name = "ResearchTab"
	research_button.theme_type_variation = &"NavigationTab"
	research_button.toggle_mode = true
	research_button.custom_minimum_size = Vector2(120, 30)
	research_button.size_flags_vertical = SIZE_SHRINK_CENTER
	research_pulse = ShaderMaterial.new()
	research_pulse.shader = preload("res://shaders/ui_research_pulse.gdshader")
	research_button.material = research_pulse
	top.add_child(research_button)
	var research_column := VBoxContainer.new()
	research_column.name = "HeaderResearch"
	research_column.size_flags_horizontal = SIZE_FILL
	research_column.size_flags_vertical = SIZE_SHRINK_CENTER
	research_column.alignment = BoxContainer.ALIGNMENT_CENTER
	research_column.add_theme_constant_override("separation", 2)
	research_column.mouse_filter = MOUSE_FILTER_IGNORE
	research_button.add_child(research_column)
	research_column.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	research_column.offset_left = 10
	research_column.offset_right = -10
	research_column.offset_top = 3
	research_column.offset_bottom = -3
	var research_row := HBoxContainer.new()
	research_row.alignment = BoxContainer.ALIGNMENT_CENTER
	research_row.mouse_filter = MOUSE_FILTER_IGNORE
	research_column.add_child(research_row)
	header_wallet = HBoxContainer.new()
	header_wallet.alignment = BoxContainer.ALIGNMENT_END
	header_wallet.size_flags_vertical = SIZE_SHRINK_BEGIN
	top.add_child(header_wallet)
	var credit_icon := TextureRect.new()
	credit_icon.name = "CreditsIcon"
	credit_icon.texture = CREDITS_ICON
	credit_icon.custom_minimum_size = Vector2(20, 20)
	credit_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	credit_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	credit_icon.size_flags_vertical = SIZE_SHRINK_CENTER
	header_wallet.add_child(credit_icon)
	header = _label("")
	header.size_flags_horizontal = SIZE_SHRINK_BEGIN
	header.size_flags_vertical = SIZE_SHRINK_CENTER
	header.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_wallet.add_child(header)
	var science_icon := TextureRect.new()
	science_icon.name = "ScienceIcon"
	science_icon.texture = SCIENCE_ICON
	science_icon.custom_minimum_size = Vector2(12, 12)
	science_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	science_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	science_icon.size_flags_vertical = SIZE_SHRINK_CENTER
	science_icon.mouse_filter = MOUSE_FILTER_IGNORE
	research_row.add_child(science_icon)
	research_status = _label("")
	research_status.name = "ResearchStatus"
	research_status.theme_type_variation = &"HeaderResearch"
	research_status.size_flags_horizontal = SIZE_FILL
	research_status.size_flags_vertical = SIZE_SHRINK_CENTER
	research_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	research_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	research_status.mouse_filter = MOUSE_FILTER_IGNORE
	research_row.add_child(research_status)
	research_progress = ProgressBar.new()
	research_progress.name = "ResearchProgress"
	research_progress.theme_type_variation = &"ResearchProgress"
	research_progress.custom_minimum_size.y = 8
	research_progress.size_flags_horizontal = SIZE_SHRINK_BEGIN
	research_progress.size_flags_vertical = SIZE_SHRINK_CENTER
	research_progress.min_value = -1
	research_progress.show_percentage = false
	research_progress.mouse_filter = MOUSE_FILTER_IGNORE
	research_progress_row = HBoxContainer.new()
	research_progress_row.name = "ResearchProgressRow"
	research_progress_row.mouse_filter = MOUSE_FILTER_IGNORE
	research_progress_row.add_theme_constant_override("separation", 4)
	research_column.add_child(research_progress_row)
	research_progress_row.add_child(research_progress)
	research_rate = _label("")
	research_rate.name = "ResearchRate"
	research_rate.theme_type_variation = &"HeaderResearch"
	research_rate.autowrap_mode = TextServer.AUTOWRAP_OFF
	research_rate.size_flags_vertical = SIZE_SHRINK_CENTER
	research_rate.mouse_filter = MOUSE_FILTER_IGNORE
	research_progress_row.add_child(research_rate)
	research_column.resized.connect(_resize_research_label)
	flagship_icon = load("res://assets/flag.png")
	for title in ["FLEET", "SHIPS", "MAP"]:
		var tab := _button_with_sound(title, func() -> void:
			if traveling:
				return
			active_tab = title
			for tab_button: Button in tabs.get_children():
				tab_button.set_pressed_no_signal(tab_button.text == title)
			buy_open = false
			_refresh(), &"accept")
		tab.size_flags_horizontal = SIZE_EXPAND_FILL
		tab.theme_type_variation = &"NavigationTab"
		tab.custom_minimum_size = Vector2(80, 30)
		tab.toggle_mode = true
		tab.button_pressed = active_tab == title
		tabs.add_child(tab)
	settings_dialog = load("res://scenes/settings_dialog.tscn").instantiate()
	settings_dialog.hide()
	add_child(settings_dialog)
	var settings: TextureButton = load("res://scenes/circular_icon_button.tscn").instantiate()
	settings.name = "SettingsButton"
	settings.custom_minimum_size = Vector2(30, 30)
	settings.size_flags_vertical = SIZE_SHRINK_CENTER
	AudioManager.connect_ui_button(settings, &"detail")
	settings.pressed.connect(func() -> void: settings_dialog.popup_centered())
	header_wallet.add_child(settings)
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
	var footer := HBoxContainer.new()
	column.add_child(footer)
	feedback = _label("")
	feedback.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(feedback)
	_build_travel_controls(top, footer)
	GameState.fleet_changed.connect(_queue_refresh)
	GameState.research_changed.connect(_queue_refresh)
	GameState.credits_changed.connect(_queue_refresh)
	_refresh()
	if GameState.expedition_simulation != null:
		if not GameState.expedition_simulation.state.pending_event_id.is_empty():
			_show_encounter()
		elif GameState.expedition_simulation.state.departure_choice_pending:
			_show_departure_choices()

func _resize_panels() -> void:
	if header_wallet != null:
		_resize_research_label()
	if roster_panel != null:
		roster_panel.custom_minimum_size.x = clampf(size.x * 0.16, 116, 220)
	if details_panel != null:
		details_panel.custom_minimum_size.x = clampf(size.x * 0.24, 180, 300)
	if stats_grid != null and is_instance_valid(stats_grid):
		stats_grid.columns = 2 if size.x < 1000 else 4

func _resize_research_label() -> void:
	var text_width := research_status.get_theme_font("font").get_string_size(
		research_status.text, HORIZONTAL_ALIGNMENT_LEFT, -1, research_status.get_theme_font_size("font_size")).x
	var top := tabs.get_parent() as HBoxContainer
	var available := size.x - 16 - tabs.get_combined_minimum_size().x - header_wallet.get_combined_minimum_size().x
	if is_instance_valid(travel_controls):
		available -= travel_controls.get_combined_minimum_size().x + top.get_theme_constant("separation")
	available -= top.get_theme_constant("separation") * 3 + 36
	research_status.custom_minimum_size.x = minf(text_width, maxf(1, available))
	research_button.custom_minimum_size.x = maxf(120, research_status.custom_minimum_size.x + 36)
	var text_height := research_status.get_theme_font("font").get_multiline_string_size(
		research_status.text, HORIZONTAL_ALIGNMENT_CENTER, research_status.custom_minimum_size.x,
		research_status.get_theme_font_size("font_size")).y
	var progress_height := maxf(8, research_rate.get_combined_minimum_size().y) if research_progress.visible else 0.0
	research_button.custom_minimum_size.y = maxf(30, maxf(12, ceilf(text_height)) + progress_height + (8 if research_progress.visible else 6))
	var rate_width := research_rate.get_theme_font("font").get_string_size(
		research_rate.text, HORIZONTAL_ALIGNMENT_LEFT, -1, research_rate.get_theme_font_size("font_size")).x
	research_progress.custom_minimum_size.x = maxf(8, minf(
		floorf((research_status.custom_minimum_size.x + 16) * 0.5),
		research_status.custom_minimum_size.x + 16 - rate_width - 4))

func _process(delta: float) -> void:
	if research_pulse != null:
		if GameState.research_focus.is_empty():
			research_pulse_time = fmod(research_pulse_time + delta, 1.0)
			research_pulse.set_shader_parameter("white_mix", 0.08 * (1.0 - cos(TAU * research_pulse_time)) * 0.5)
		else:
			research_pulse_time = 0.0
			research_pulse.set_shader_parameter("white_mix", 0.0)
	_advance_expedition(delta)
	_sync_station_services()

func _sync_station_services() -> void:
	var available: bool = GameState.can_use_shipyard()
	if available == shipyard_access_available:
		return
	shipyard_access_available = available
	if not available:
		if get_viewport().gui_is_dragging():
			get_viewport().gui_cancel_drag()
		buy_open = false
		if is_instance_valid(shop):
			shop.queue_free()
			shop = null
	for button: Button in find_children("*", "Button", true, false):
		if button.has_meta("shipyard_eligible"):
			button.disabled = not available or not button.get_meta("shipyard_eligible")
			if button.name in ["BuyChassis", "BuyEquipment"] and not available:
				button.set_pressed_no_signal(false)
	var reason := roster.find_child("StationServiceReason", true, false) as Label
	if reason != null:
		reason.text = GameState.station_service_error("shipyard")
		reason.visible = not available
	if is_instance_valid(stock):
		stock.refresh_service_access()

func _shipyard_action(button: Button, eligible := true) -> Button:
	button.set_meta("shipyard_eligible", eligible)
	button.disabled = not GameState.can_use_shipyard() or not eligible
	return button

func _advance_expedition(delta: float) -> void:
	var simulation = GameState.expedition_simulation
	if simulation == null or simulation.state == null or is_instance_valid(departure_modal):
		return
	var previous: Dictionary = simulation.state.snapshot()
	var previous_boundary_sequence: int = simulation.boundary_sequence
	if not simulation.advance(delta):
		expedition_status_override = "Navigation error: " + simulation.last_error
		_restore_expedition(previous)
		_refresh_expedition_controls()
		return
	if is_instance_valid(formation_view):
		formation_view.travel_distance_nu = simulation.state.traveled_distance_nu
	expedition_save_elapsed += delta
	var boundary_reached: bool = simulation.boundary_sequence != previous_boundary_sequence
	_update_expedition_readouts()
	if boundary_reached or expedition_save_elapsed >= EXPEDITION_SAVE_INTERVAL:
		if not GameState.save_expedition_checkpoint():
			_restore_expedition(previous)
			simulation.set_pause(ExpeditionStateData.PauseReason.SAVE_ERROR, true)
			expedition_status_override = "Save failed: " + GameState.last_save_error
			expedition_save_elapsed = 0.0
		else:
			expedition_save_elapsed = 0.0
			if boundary_reached:
				expedition_status_override = ""
				if not simulation.state.pending_event_id.is_empty():
					_show_encounter()
				elif simulation.state.departure_choice_pending:
					_show_departure_choices()
		_refresh_expedition_controls()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not inspected_item.is_empty():
		var hovered := get_viewport().gui_get_hovered_control()
		while hovered != null:
			if hovered == inspection or hovered.has_meta("inspect_equipment") or hovered.has_meta("inspect_chassis"):
				return
			hovered = hovered.get_parent_control()
		_clear_inspection.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN and not inspected_item.is_empty():
		_clear_inspection()

func _clear_inspection() -> void:
	inspected_item.clear()
	if is_instance_valid(inspection):
		details.remove_child(inspection)
		inspection.queue_free()
	inspection = null
	if is_instance_valid(stock):
		stock.show()

func _inspect_equipment(id: String, rank: int, uid := "") -> void:
	AudioManager.play_ui_sfx(&"detail")
	inspected_item = {"kind": "equipment", "id": id, "rank": rank, "uid": uid}
	_render_inspection()

func _inspect_chassis(id: String) -> void:
	AudioManager.play_ui_sfx(&"detail")
	inspected_item = {"kind": "chassis", "id": id}
	_render_inspection()

func _render_inspection() -> void:
	if stock == null:
		_show_stock()
	if is_instance_valid(inspection):
		details.remove_child(inspection)
		inspection.queue_free()
	stock.hide()
	inspection = ScrollContainer.new()
	inspection.name = "ItemDetails"
	inspection.size_flags_vertical = SIZE_EXPAND_FILL
	inspection.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details.add_child(inspection)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	inspection.add_child(body)
	if inspected_item.kind == "chassis":
		var chassis := SlotCatalog.find_chassis(inspected_item.id)
		var ship := HangarShip.new()
		ship.initialize_chassis(chassis.id, 0, int(chassis.command) > 0)
		body.add_child(_resource_label(chassis.name))
		var bars := StatBars.new()
		body.add_child(bars)
		bars.set_ship(ship)
		body.add_child(_resource_label("Command %d\nPrice %d cr" %
			[chassis.command if chassis.command > 0 else chassis.command_cost, chassis.price]))
		body.add_child(_resource_label(SlotCatalog.chassis_bonuses(chassis)))
	else:
		var item := SlotCatalog.find_equipment(inspected_item.id, int(inspected_item.rank))
		var instance: Dictionary = GameState.equipment_inventory.get(inspected_item.uid, {})
		body.add_child(_resource_label(item.name))
		body.add_child(_resource_label("%s %s\nMass %.0f\nPrice %d cr\n%s" %
			[item.size, item.type.capitalize(), item.stats.weight, item.price, _part_effect(item)]))
		for weapon: ShipWeaponStats in SlotCatalog.stats_for(item.id, int(item.rank)).weapons:
			body.add_child(_label("%s\n%.1f damage x %d | %.1fs cycle\nRange %.0f | Charge %.1fs" %
				[weapon.weapon_name, weapon.damage_per_shot, weapon.projectiles_per_activation, weapon.fire_interval_seconds, weapon.range_units, weapon.charge_seconds]))
		if not SlotCatalog.unlocked(item, GameState.research_grants()):
			body.add_child(_label("Research required"))
		if HangarTrade.has_load(instance):
			body.add_child(_label("%s: %d\nDeliver before removing" % [str(instance.load.kind).capitalize(), instance.load.quantity]))

func _panel(parent: Node, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CompactPanel"
	panel.custom_minimum_size.x = width
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	return box

func _button(title: String, action: Callable) -> Button:
	return _button_with_sound(title, action, &"accept")

func _button_with_sound(title: String, action: Callable, sound: StringName) -> Button:
	var button := Button.new()
	button.text = "" if ResourceText.has_icons(title) else title
	button.theme_type_variation = &"TacticalButton"
	button.focus_mode = FOCUS_NONE
	button.custom_minimum_size.y = 30
	if not sound.is_empty():
		AudioManager.connect_ui_button(button, sound)
	button.pressed.connect(action)
	if ResourceText.has_icons(title):
		ResourceText.button_content(button, title)
	return button

func _add_buy_icon(button: Button) -> void:
	var icon := TextureRect.new()
	icon.name = "BuyIcon"
	icon.texture = BUY_ICON
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	icon.anchor_left = 1.0
	icon.anchor_right = 1.0
	icon.anchor_top = 0.5
	icon.anchor_bottom = 0.5
	icon.offset_left = -22.0
	icon.offset_right = -6.0
	icon.offset_top = -8.0
	icon.offset_bottom = 8.0
	button.add_child(icon)

func _shop_button(title: String, summary: String, price: int, unlocked: bool, available: bool, action: Callable, icon_only := false) -> Button:
	var button := Button.new() if icon_only else _button_with_sound("", action, &"")
	if icon_only:
		button.theme_type_variation = &"TacticalButton"
		button.focus_mode = FOCUS_NONE
		button.mouse_filter = MOUSE_FILTER_STOP
	button.disabled = not available
	var minimum_height := 38 if icon_only else 52
	button.custom_minimum_size.y = minimum_height
	button.set_meta("price", price)
	var column := VBoxContainer.new()
	if icon_only:
		column.add_theme_constant_override("separation", 0)
	column.mouse_filter = MOUSE_FILTER_IGNORE
	button.add_child(column)
	column.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	column.offset_left = 12
	column.offset_top = 2 if icon_only else 5
	column.offset_right = -44 if icon_only else -30
	column.offset_bottom = -2 if icon_only else -5
	var name_label := _resource_label(title)
	name_label.name = "ItemName"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(name_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(row)
	var summary_label := _label(summary)
	summary_label.name = "ItemSummary"
	summary_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	summary_label.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(summary_label)
	var credit_icon := _shop_icon(CREDITS_ICON, "PriceIcon")
	row.add_child(credit_icon)
	var price_label := _label(str(price))
	price_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	price_label.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(price_label)
	if not unlocked:
		row.add_child(_shop_icon(SCIENCE_ICON, "ResearchRequiredIcon"))
	if button.disabled:
		column.modulate = get_theme_color("font_disabled_color", "Button")
	if available:
		if icon_only:
			var buy := TextureButton.new()
			buy.name = "BuyIcon"
			buy.texture_normal = BUY_ICON
			buy.ignore_texture_size = true
			buy.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			buy.focus_mode = FOCUS_NONE
			buy.mouse_default_cursor_shape = CURSOR_POINTING_HAND
			button.add_child(buy)
			buy.set_anchors_preset(PRESET_CENTER_RIGHT)
			buy.offset_left = -38
			buy.offset_right = -6
			buy.offset_top = -16
			buy.offset_bottom = 16
			buy.mouse_entered.connect(func() -> void: buy.self_modulate = Color(1.25, 1.25, 1.25))
			buy.mouse_exited.connect(func() -> void: buy.self_modulate = Color.WHITE)
			buy.button_down.connect(func() -> void: buy.self_modulate = Color(0.75, 0.75, 0.75))
			buy.button_up.connect(func() -> void: buy.self_modulate = Color(1.25, 1.25, 1.25) if buy.is_hovered() else Color.WHITE)
			buy.pressed.connect(action)
		else:
			_add_buy_icon(button)
	column.minimum_size_changed.connect(func() -> void:
		button.custom_minimum_size.y = maxf(minimum_height, column.get_combined_minimum_size().y + (4 if icon_only else 10)))
	return button

func _shop_icon(texture: Texture2D, node_name: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = node_name
	icon.texture = texture
	icon.custom_minimum_size = Vector2(14, 14)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = SIZE_SHRINK_CENTER
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	return icon

func _label(title: String) -> Label:
	var label := Label.new()
	label.text = title
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _resource_label(title: String) -> ResourceText:
	return ResourceText.create(title)

func _clear(host: Node) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()

func _queue_refresh() -> void:
	if not refresh_queued:
		refresh_queued = true
		_refresh.call_deferred()

func _refresh() -> void:
	inspected_item.clear()
	inspection = null
	refresh_queued = false
	if traveling:
		return
	shipyard_access_available = GameState.can_use_shipyard()
	if not shipyard_access_available:
		buy_open = false
	var buy_scroll_position := 0
	if buy_open and is_instance_valid(shop) and shop.get_parent() == center \
			and shop.get_meta("buy_mode", "") == buy_mode and is_instance_valid(shop_scroll):
		buy_scroll_position = shop_scroll.scroll_vertical
	shop_scroll = null
	for tab: Button in tabs.get_children():
		tab.set_pressed_no_signal(tab.text == active_tab)
	research_button.set_pressed_no_signal(active_tab == "RESEARCH")
	if is_instance_valid(canvas):
		fitting_views[canvas.owned_id] = {"camera": canvas.camera, "zoom": canvas.zoom}
	if is_instance_valid(formation_view):
		formation_camera = formation_view.camera
		formation_zoom = formation_view.zoom
		if formation_view.selected_id == selected_ship_id:
			formation_selection.assign(formation_view.selected_ids)
	if is_instance_valid(research_panel):
		research_view = {"selected_id": research_panel.selected_id,
			"camera_position": research_panel.tree_canvas.camera_position,
			"camera_zoom": research_panel.tree_canvas.camera_zoom}
	if is_instance_valid(graph) and graph.is_inside_tree():
		map_camera = {"position": graph.camera_position, "zoom": graph.camera_zoom}
	graph = null
	research_panel = null
	formation_view = null
	header.text = str(GameState.credits)
	var focus: String = GameState.research_focus
	if focus.is_empty():
		research_status.text = "Choose Research"
		research_progress.value = 0
		research_progress.hide()
		research_progress_row.hide()
	else:
		var technology := GameDefinitions.find("research", focus)
		var required := ResearchFocusRules.cost(focus, GameState.run_progress_snapshot())
		research_status.text = technology.display_name
		research_progress.max_value = required
		research_progress.value = float(GameState.research_progress.get(focus, 0))
		research_progress.show()
		research_rate.text = "+%s/day" % ScienceRules.format_rp(ScienceRules.production_rate(ScienceRules.snapshot(GameState.get_deployed_fleet())))
		research_progress_row.show()
	if not focus.is_empty():
		research_pulse_time = 0.0
		research_pulse.set_shader_parameter("white_mix", 0.0)
	_resize_research_label.call_deferred()
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
		research.view_state = research_view
		research_panel = research
		research.registry = HangarResearch.view_registry()
		center.add_child(research)
		research.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		research.bind_external_panels(roster, details)
		research.focus_requested.connect(func(key: String) -> void: _result(GameState.set_research_focus(key)))
		return
	if active_tab == "MAP":
		_show_map()
		_refresh_expedition_controls()
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
		var button := _button_with_sound(owned.display_name, func() -> void:
			selected_ship_id = owned.id
			formation_selection.assign([owned.id])
			selected_slot = ""
			_refresh(), &"select_tab")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = flagship_icon if owned.flagship else null
		if owned.flagship:
			button.add_theme_constant_override("icon_max_width", 9)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.name = "Ship%d" % owned.id
		button.clip_text = true
		button.resized.connect(_fit_roster_name.bind(button))
		button.toggle_mode = true
		button.button_pressed = owned.id == selected_ship_id
		if active_tab == "FLEET":
			button.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
					selected_ship_id = owned.id
					formation_selection.assign([owned.id])
					selected_slot = ""
					active_tab = "SHIPS"
					_queue_refresh()
					button.accept_event())
		ship_rows.add_child(button)
	roster.add_child(_label("Command %d / %d" % [GameState.used_command(), GameState.command_limit()]))
	var mode := "SHIPS" if active_tab == "FLEET" else "EQUIPMENT"
	var buy := _button_with_sound("Buy Chassis" if mode == "SHIPS" else "Buy Equipment", _open_shop.bind(mode), &"animate_ui")
	buy.name = "BuyChassis" if mode == "SHIPS" else "BuyEquipment"
	buy.toggle_mode = true
	buy.button_pressed = buy_open and buy_mode == mode
	_shipyard_action(buy)
	roster.add_child(buy)
	var service_reason := _label(GameState.station_service_error("shipyard"))
	service_reason.name = "StationServiceReason"
	service_reason.visible = not shipyard_access_available
	roster.add_child(service_reason)
	if active_tab == "FLEET":
		var board: Control = load("res://scripts/hangar_formation.gd").new()
		board.selected_id = selected_ship_id
		board.selected_ids.assign(formation_selection)
		board.camera = formation_camera
		board.zoom = formation_zoom
		if GameState.expedition_simulation != null and GameState.expedition_simulation.state != null:
			board.travel_distance_nu = GameState.expedition_simulation.state.traveled_distance_nu
		formation_view = board
		center.add_child(board)
		board.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		board.ship_selected.connect(func(id: int) -> void:
			selected_ship_id = id
			_queue_refresh())
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
			bottom.custom_minimum_size.y = 128
			stack.add_child(bottom)
			slot_info = _resource_label("")
			bottom.add_child(slot_info)
			slot_info.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
			stats_grid = StatBars.new()
			stats_grid.columns = 2 if size.x < 1000 else 4
			bottom.add_child(stats_grid)
			stats_grid.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
			_show_stock()
			var repair := _button("REPAIR %d cr" % owned.repair_cost(), func() -> void: _result(GameState.repair_ship(GameState.owned_ship(selected_ship_id))))
			_shipyard_action(repair, owned.needs_repair() and GameState.credits >= owned.repair_cost())
			roster.add_child(repair)
			if not owned.flagship:
				var salvage := _button("SALVAGE", func() -> void: _confirm_salvage(selected_ship_id))
				_shipyard_action(salvage)
				roster.add_child(salvage)
			canvas.slot_selected.connect(func(key: String) -> void:
				selected_slot = key
				_show_details())
			canvas.instance_selected.connect(func(key: String, uid: String) -> void:
				selected_slot = key
				var ok := GameState.fit_equipment(selected_ship_id, key, uid)
				if ok:
					AudioManager.play_ui_sfx(&"place")
				_result(ok))
	_show_details()
	if buy_open:
		if stock == null:
			_show_stock()
		_show_buy_panel(buy_scroll_position)
	_refresh_expedition_controls()


func _refresh_expedition_controls() -> void:
	_sync_station_services()
	if not is_instance_valid(travel_controls) or GameState.expedition_simulation == null \
			or GameState.expedition_simulation.state == null:
		return
	var simulation = GameState.expedition_simulation
	var state = simulation.state
	for speed: int in speed_buttons:
		var speed_button: Button = speed_buttons[speed]
		speed_button.set_pressed_no_signal(state.pause_reasons.is_empty() and state.requested_speed == speed)
		speed_button.disabled = state.travel_state in [
			ExpeditionStateData.TravelState.ENGAGED,
			ExpeditionStateData.TravelState.SETTLING,
			ExpeditionStateData.TravelState.REGROUPING
		] and speed != 1
	travel_pause_button.set_pressed_no_signal(
			ExpeditionStateData.PauseReason.USER in state.pause_reasons)
	travel_fuel.text = "FUEL %d / %d" % [roundi(state.fuel), roundi(state.fuel_capacity)]
	var docked: Dictionary = simulation.locations.get(state.docked_location_id, {})
	travel_refuel_button.visible = not docked.is_empty() \
			and "refuel" in docked.get("services", []) and state.fuel < state.fuel_capacity
	var refuel_cost := int(ceil((state.fuel_capacity - state.fuel) * 2.0))
	travel_refuel_button.text = "REFUEL %d" % refuel_cost
	travel_refuel_button.disabled = not GameState.station_service_error("refuel").is_empty() or GameState.credits < refuel_cost
	travel_retry_button.visible = ExpeditionStateData.PauseReason.SAVE_ERROR in state.pause_reasons
	departure_button.visible = state.destination_location_id.is_empty() \
			and state.travel_state in [ExpeditionStateData.TravelState.DOCKED, ExpeditionStateData.TravelState.STOPPED]
	_update_expedition_readouts()

func _show_encounter() -> void:
	if is_instance_valid(encounter_modal):
		return
	var simulation = GameState.expedition_simulation
	if simulation == null or simulation.state.pending_event_id.is_empty():
		return
	var event: Dictionary = simulation.Events.find(simulation.events, simulation.state.pending_event_id)
	if event.is_empty():
		push_error("Cannot show an encounter without its validated event data.")
		return
	if get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()
	if is_instance_valid(shop):
		shop.queue_free()
		shop = null
	buy_open = false
	encounter_event_id = event.id
	encounter_modal = Control.new()
	encounter_modal.name = "ExpeditionEncounter"
	encounter_modal.add_to_group("modal_ui")
	encounter_modal.z_index = 40
	add_child(encounter_modal)
	encounter_modal.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	encounter_modal.add_child(shade)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	encounter_modal.add_child(margin)
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	var panel := PanelContainer.new()
	panel.name = "EncounterPanel"
	panel.theme_type_variation = &"CompactPanel"
	panel.custom_minimum_size.x = minf(440, size.x - 48)
	panel.size_flags_horizontal = SIZE_SHRINK_CENTER
	panel.size_flags_vertical = SIZE_SHRINK_CENTER
	margin.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	column.add_child(_label(str(event.title).to_upper()))
	var text := _label(event.text)
	text.custom_minimum_size.x = minf(360, size.x - 96)
	column.add_child(text)
	column.add_child(_button("INVESTIGATE", _choose_encounter.bind(event.id, "investigate")))
	column.add_child(_button("CONTINUE COURSE", _choose_encounter.bind(event.id, "continue")))
	encounter_error = _label("")
	column.add_child(encounter_error)
	encounter_retry = _button("RETRY SAVE", func() -> void:
		_on_expedition_retry_pressed()
		encounter_error.text = expedition_status_override
		encounter_retry.visible = ExpeditionStateData.PauseReason.SAVE_ERROR in simulation.state.pause_reasons)
	encounter_retry.visible = ExpeditionStateData.PauseReason.SAVE_ERROR in simulation.state.pause_reasons
	column.add_child(encounter_retry)

func _choose_encounter(event_id: String, choice: String) -> void:
	if not is_instance_valid(encounter_modal) or encounter_event_id != event_id:
		return
	if not GameState.resolve_expedition_event(event_id, choice):
		encounter_error.text = GameState.last_save_error
		encounter_retry.show()
		return
	encounter_modal.queue_free()
	encounter_modal = null
	encounter_error = null
	encounter_retry = null
	encounter_event_id = ""
	expedition_status_override = ""
	expedition_save_elapsed = 0.0
	_refresh_expedition_controls()


func _update_expedition_readouts() -> void:
	if not is_instance_valid(travel_controls) or GameState.expedition_simulation == null:
		return
	var simulation = GameState.expedition_simulation
	var state = simulation.state
	travel_fuel.text = "FUEL %d / %d" % [roundi(state.fuel), roundi(state.fuel_capacity)]
	if not expedition_status_override.is_empty():
		feedback.text = expedition_status_override
	elif not state.destination_location_id.is_empty():
		var destination: Dictionary = simulation.locations.get(state.destination_location_id, {})
		var point := Vector2(destination.position[0], destination.position[1])
		var distance: float = state.position_nu.distance_to(point)
		var effective_speed: int = 1 if state.travel_state in [
			ExpeditionStateData.TravelState.ENGAGED,
			ExpeditionStateData.TravelState.SETTLING,
			ExpeditionStateData.TravelState.REGROUPING
		] else state.requested_speed
		var eta: float = distance / (float(simulation.tuning.cruise_units_per_sim_second) * effective_speed)
		var paused: bool = not state.pause_reasons.is_empty()
		feedback.text = "TO %s · %d NU · %s" % [
			str(destination.get("name", "UNKNOWN")).to_upper(), roundi(distance),
			"PAUSED" if paused else "ETA %ds" % ceili(eta)]
	else:
		feedback.text = _expedition_status_text()


func _build_travel_controls(top: HBoxContainer, footer: HBoxContainer) -> void:
	if GameState.expedition_simulation == null or GameState.expedition_simulation.state == null:
		return
	travel_controls = PanelContainer.new()
	travel_controls.name = "ExpeditionTravelControls"
	travel_controls.theme_type_variation = &"TimeControlsPanel"
	travel_controls.size_flags_vertical = SIZE_SHRINK_CENTER
	travel_controls.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(travel_controls)
	top.move_child(travel_controls, 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	travel_controls.add_child(row)
	travel_pause_button = _time_button("pause", func() -> void:
		_apply_expedition_action(func() -> bool:
			return GameState.expedition_simulation.set_pause(ExpeditionStateData.PauseReason.USER, true)))
	travel_pause_button.name = "ExpeditionPause"
	row.add_child(travel_pause_button)
	for speed: int in [1, 10]:
		var speed_button := _time_button("play" if speed == 1 else "fast",
				_on_expedition_play_pressed.bind(speed))
		speed_button.name = "ExpeditionSpeed%d" % speed
		speed_buttons[speed] = speed_button
		row.add_child(speed_button)
	var multiplier := _label("10x")
	multiplier.autowrap_mode = TextServer.AUTOWRAP_OFF
	multiplier.size_flags_vertical = SIZE_SHRINK_CENTER
	multiplier.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(multiplier)
	travel_fuel = _label("")
	travel_fuel.name = "ExpeditionFuel"
	travel_fuel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	travel_fuel.autowrap_mode = TextServer.AUTOWRAP_OFF
	travel_fuel.size_flags_horizontal = Control.SIZE_SHRINK_END
	travel_fuel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(travel_fuel)
	travel_refuel_button = _button_with_sound("REFUEL",
			Callable(self, "_on_expedition_refuel_pressed"), &"")
	travel_refuel_button.name = "ExpeditionRefuel"
	travel_refuel_button.custom_minimum_size = Vector2(74, 26)
	footer.add_child(travel_refuel_button)
	travel_retry_button = _button_with_sound("RETRY SAVE",
			Callable(self, "_on_expedition_retry_pressed"), &"")
	travel_retry_button.name = "ExpeditionRetrySave"
	travel_retry_button.custom_minimum_size = Vector2(90, 26)
	footer.add_child(travel_retry_button)
	departure_button = _button("DEPART", _show_departure_choices)
	departure_button.name = "ExpeditionDepart"
	footer.add_child(departure_button)
	_refresh_expedition_controls()

func _show_departure_choices() -> void:
	if is_instance_valid(departure_modal):
		return
	var simulation = GameState.expedition_simulation
	if simulation == null or not simulation.state.destination_location_id.is_empty():
		return
	if not simulation.state.departure_choice_pending:
		_apply_expedition_action(simulation.begin_departure_choice)
		if not simulation.state.departure_choice_pending:
			return
	departure_modal = Control.new()
	departure_modal.name = "DepartureChoices"
	departure_modal.add_to_group("modal_ui")
	departure_modal.z_index = 40
	add_child(departure_modal)
	departure_modal.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	departure_modal.add_child(shade)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	departure_modal.add_child(margin)
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	var panel := PanelContainer.new()
	panel.name = "DeparturePanel"
	panel.theme_type_variation = &"CompactPanel"
	panel.size_flags_horizontal = SIZE_SHRINK_CENTER
	panel.custom_minimum_size.x = minf(440, size.x - 48)
	margin.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	column.add_child(_label("NEXT DESTINATION"))
	column.add_child(_label("Choose where to go next."))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(choices)
	for id: String in simulation.state.discovered_location_ids:
		var location: Dictionary = simulation.locations.get(id, {})
		if location.is_empty() or not location.accessible:
			continue
		var distance: float = simulation.state.position_nu.distance_to(Vector2(location.position[0], location.position[1]))
		if distance <= 0.000001:
			continue
		var option := VBoxContainer.new()
		choices.add_child(option)
		var choose := _button(location.name, _choose_departure.bind(id))
		if id == simulation.state.return_destination_id:
			choose.text = "RESUME: " + location.name
		choose.set_meta("expedition_destination", id)
		option.add_child(choose)
		var description := "Explore a derelict field. No station services." if location.kind == "poi" \
				else "Dock at this station."
		var services: PackedStringArray = []
		for service: String in location.services:
			services.append(service.capitalize())
		if not services.is_empty():
			description += " " + ", ".join(services) + "."
		option.add_child(_label("%s\n%d NU away" % [description, roundi(distance)]))
	departure_error = _label("")
	column.add_child(departure_error)
	departure_retry = _button("RETRY SAVE", func() -> void:
		_on_expedition_retry_pressed()
		departure_error.text = expedition_status_override
		departure_retry.visible = ExpeditionStateData.PauseReason.SAVE_ERROR in simulation.state.pause_reasons)
	departure_retry.visible = ExpeditionStateData.PauseReason.SAVE_ERROR in simulation.state.pause_reasons
	column.add_child(departure_retry)

func _choose_departure(location_id: String) -> void:
	var simulation = GameState.expedition_simulation
	if ExpeditionStateData.PauseReason.SAVE_ERROR in simulation.state.pause_reasons:
		departure_error.text = "Retry the failed save before choosing a destination."
		return
	_on_expedition_destination_selected(location_id)
	if simulation.state.destination_location_id != location_id:
		departure_error.text = expedition_status_override
		departure_retry.visible = ExpeditionStateData.PauseReason.SAVE_ERROR in simulation.state.pause_reasons
		return
	departure_modal.queue_free()
	departure_modal = null
	departure_error = null
	departure_retry = null

func _time_button(kind: String, action: Callable) -> Button:
	var button := _button_with_sound("", action, &"")
	button.custom_minimum_size = Vector2(24, 24)
	button.toggle_mode = true
	button.draw.connect(func() -> void:
		var origin := (button.size - Vector2(12, 12)) * 0.5
		var color := button.get_theme_color("font_disabled_color" if button.disabled else "font_color")
		if kind == "pause":
			for x: float in [0.0, 8.0]:
				button.draw_rect(Rect2(origin + Vector2(x, 0), Vector2(4, 12)), color)
		else:
			var width := 6.0 if kind == "fast" else 10.0
			for x: float in ([0.0, 6.0] if kind == "fast" else [1.0]):
				button.draw_colored_polygon(PackedVector2Array([
					origin + Vector2(x, 0), origin + Vector2(x + width, 6),
					origin + Vector2(x, 12)]), color))
	return button

func _on_expedition_play_pressed(speed: int) -> void:
	_apply_expedition_action(func() -> bool:
		var simulation = GameState.expedition_simulation
		if not simulation.set_speed(speed):
			return false
		if not simulation.set_pause(ExpeditionStateData.PauseReason.USER, false):
			return false
		if simulation.state.travel_state == ExpeditionStateData.TravelState.STOPPED \
				and not simulation.state.destination_location_id.is_empty() \
				and simulation.state.pause_reasons.is_empty():
			return simulation.resume()
		return true)

func _expedition_status_text() -> String:
	var simulation = GameState.expedition_simulation
	var state = simulation.state
	if not state.destination_location_id.is_empty():
		var destination: Dictionary = simulation.locations.get(state.destination_location_id, {})
		return "TO %s" % str(destination.get("name", "UNKNOWN")).to_upper()
	if not state.docked_location_id.is_empty():
		var dock: Dictionary = simulation.locations.get(state.docked_location_id, {})
		return "DOCKED · %s" % str(dock.get("name", "STATION")).to_upper()
	if state.travel_state == ExpeditionStateData.TravelState.STOPPED:
		return "STOPPED · SELECT A COURSE"
	return "NO ACTIVE COURSE"


func _on_expedition_destination_selected(location_id: String) -> void:
	_apply_expedition_action(func() -> bool:
		return GameState.expedition_simulation.request_destination(location_id))


func _on_expedition_speed_pressed(speed: int) -> void:
	_apply_expedition_action(func() -> bool:
		return GameState.expedition_simulation.set_speed(speed))


func _on_expedition_pause_pressed() -> void:
	var simulation = GameState.expedition_simulation
	var pause: bool = ExpeditionStateData.PauseReason.USER not in simulation.state.pause_reasons
	_apply_expedition_action(func() -> bool:
		return simulation.set_pause(ExpeditionStateData.PauseReason.USER, pause))


func _on_expedition_stop_pressed() -> void:
	var simulation = GameState.expedition_simulation
	var resume: bool = simulation.state.travel_state == ExpeditionStateData.TravelState.STOPPED
	_apply_expedition_action(func() -> bool:
		return simulation.resume() if resume else simulation.stop())


func _on_expedition_clear_pressed() -> void:
	_apply_expedition_action(func() -> bool:
		return GameState.expedition_simulation.cancel_destination())


func _on_expedition_refuel_pressed() -> void:
	if not GameState.refuel_expedition():
		expedition_status_override = GameState.last_save_error
	else:
		expedition_status_override = "FUEL TANKS REFILLED"
	_refresh_expedition_controls()


func _on_expedition_retry_pressed() -> void:
	var simulation = GameState.expedition_simulation
	var previous: Dictionary = simulation.state.snapshot()
	simulation.set_pause(ExpeditionStateData.PauseReason.SAVE_ERROR, false)
	if not GameState.save_expedition_checkpoint():
		_restore_expedition(previous)
		simulation.set_pause(ExpeditionStateData.PauseReason.SAVE_ERROR, true)
		expedition_status_override = "Save failed: " + GameState.last_save_error
	else:
		expedition_status_override = ""
		expedition_save_elapsed = 0.0
	_refresh_expedition_controls()


func _apply_expedition_action(action: Callable) -> void:
	var simulation = GameState.expedition_simulation
	var previous: Dictionary = simulation.state.snapshot()
	if not bool(action.call()):
		expedition_status_override = simulation.last_error
		_refresh_expedition_controls()
		return
	if not GameState.save_expedition_checkpoint():
		_restore_expedition(previous)
		simulation.set_pause(ExpeditionStateData.PauseReason.SAVE_ERROR, true)
		expedition_status_override = "Save failed: " + GameState.last_save_error
	else:
		expedition_status_override = ""
		expedition_save_elapsed = 0.0
	_refresh_expedition_controls()


func _restore_expedition(snapshot: Dictionary) -> void:
	var simulation = GameState.expedition_simulation
	if not simulation.restore(snapshot):
		push_error("Could not roll back expedition state: " + simulation.last_error)


func _show_stock() -> void:
	_clear(details)
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
	stock.equipment_selected.connect(func(uid: String) -> void:
		var instance: Dictionary = GameState.equipment_inventory[uid]
		_inspect_equipment(instance.equipment_id, int(instance.rank), uid))

func _show_details() -> void:
	if (not inspected_item.is_empty() and active_tab != "SHIPS") or (buy_open and active_tab == "FLEET"):
		return
	var owned: HangarShip = GameState.owned_ship(selected_ship_id)
	if owned == null:
		_clear(details)
		details.add_child(_label("FLEET"))
		var cost: int = GameState.fleet_repair_cost()
		var repair := _button("REPAIR ALL %d cr" % cost, func() -> void: _result(GameState.repair_all_ships()))
		_shipyard_action(repair, cost > 0 and GameState.credits >= cost)
		details.add_child(repair)
		var totals := {"dps": 0.0, "shields": 0.0, "integrity": 0.0, "integrity_max": 0.0,
			"cargo": 0, "passengers": 0}
		for ship: HangarShip in GameState.fleet:
			if not ship.is_alive():
				continue
			var summary := ship.hangar_summary()
			for key: String in totals:
				totals[key] += summary[key]
		var lines: Array[String] = [
			"DPS %.1f" % totals.dps,
			"Shield %.0f" % totals.shields,
			"Hull %.0f / %.0f" % [totals.integrity, totals.integrity_max],
			"%s RP / day" % ScienceRules.format_rp(ScienceRules.production_rate(ScienceRules.snapshot(GameState.fleet)))]
		if totals.cargo > 0:
			lines.append("Cargo capacity %d" % totals.cargo)
		if totals.passengers > 0:
			lines.append("Passenger capacity %d" % totals.passengers)
		var fleet_stats := _resource_label("\n".join(lines))
		fleet_stats.name = "FleetTotals"
		details.add_child(fleet_stats)
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
		slot_info.set_content("")
		if not slot.is_empty():
			var instance: Dictionary = owned.mounts.get(selected_slot, {})
			var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
			slot_info.set_content("%s\n%s %s\n%s" % [item.name, item.size, item.type.capitalize(), _part_effect(item)])
			return
		stats_grid.set_ship(owned)
		return
	_clear(details)
	details.add_child(_label(owned.display_name))
	var stat_scroll := ScrollContainer.new()
	stat_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	stat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details.add_child(stat_scroll)
	var bars := StatBars.new()
	stat_scroll.add_child(bars)
	bars.set_ship(owned)
	if not selected_slot.is_empty():
		for slot: Dictionary in owned.chassis.slots:
			if slot.id == selected_slot:
				details.add_child(_label(SlotCatalog.slot_label(slot)))
		var instance: Dictionary = owned.mounts.get(selected_slot, {})
		if not instance.is_empty():
			var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
			details.add_child(_resource_label("%s\n%s %s\n%s" % [item.name, item.size, item.type.capitalize(), _part_effect(item)]))
			if item.id == "research_lab":
				details.add_child(_resource_label("%d RP/day" % int(item.rank)))
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
	_shipyard_action(repair, owned.needs_repair() and GameState.credits >= owned.repair_cost())
	if not owned.flagship and active_tab != "FLEET":
		var salvage := _button("SALVAGE", func() -> void: _confirm_salvage(selected_ship_id))
		_shipyard_action(salvage)
		details.add_child(salvage)
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
		"repair_station": return "Repair %.0f hull/s\n%.0f hull reserve per encounter" % [SharedSupport.REPAIR_RATE, SharedSupport.REPAIR_RESERVE]
		"repair_drone_bay": return "Repair drones: 4 hull / 2s\n20 hull reserve per encounter"
		"shield_relay": return "Share shields: 2/s\nRange 180"
		"nanoforge": return "Deferred"
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
		effects.append("Shields %.0f | %.1f recharge/s after 4s" % [values.shields, values.shields * 0.04])
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
	AudioManager.connect_ui_button(close)
	close.pressed.connect(func() -> void:
		shop.queue_free()
		shop = null)
	return column

func _open_shop(mode := "EQUIPMENT") -> void:
	if not GameState.can_use_shipyard():
		feedback.text = GameState.station_service_error("shipyard")
		return
	buy_open = not buy_open or buy_mode != mode
	buy_mode = mode
	_refresh()

func _show_buy_panel(scroll_position := 0) -> void:
	var card := PanelContainer.new()
	card.name = "BuyPanel"
	card.set_meta("buy_mode", buy_mode)
	card.set_meta("close_target", true)
	card.theme_type_variation = &"CompactPanel"
	card.z_index = 10
	shop = card
	center.add_child(card)
	card.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	card.add_child(column)
	var heading := _label("Buy Chassis" if buy_mode == "SHIPS" else "Buy Equipment")
	heading.name = "ShopHeading"
	heading.custom_minimum_size.y = 22
	column.add_child(heading)
	var close: TextureButton = load("res://scenes/close_x_button.tscn").instantiate()
	card.add_child(close)
	close.set_anchors_preset(PRESET_TOP_RIGHT)
	AudioManager.connect_ui_button(close)
	close.pressed.connect(func() -> void:
		buy_open = false
		_refresh())
	shop_filters = EquipmentFilters.new()
	shop_filters.name = "ShopFilters"
	shop_filters.set_preferences(stock_preferences)
	column.add_child(shop_filters)
	shop_filters.changed.connect(_shop_equipment_filters_changed)
	researched_filter = CheckBox.new()
	researched_filter.name = "OnlyResearched"
	researched_filter.text = "Only show researched"
	researched_filter.button_pressed = only_researched
	shop_filters.get_child(1).add_child(researched_filter)
	researched_filter.toggled.connect(func(enabled: bool) -> void:
		only_researched = enabled
		_shop_equipment())
	var scroll := ScrollContainer.new()
	shop_scroll = scroll
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
	scroll.set_deferred("scroll_vertical", scroll_position)

func _shop_equipment() -> void:
	buy_mode = "EQUIPMENT"
	shop_filters.show()
	researched_filter.show()
	_clear(shop_rows)
	var grants: Dictionary = GameState.research_grants()
	var candidates: Array[Dictionary] = []
	for item in SlotCatalog.equipment():
		if item.id in HangarResearch.DEFERRED_EQUIPMENT or item.id in HangarResearch.DEFERRED_PURCHASES:
			continue
		if not shop_filters.matches(item):
			continue
		if only_researched and not SlotCatalog.unlocked(item, grants):
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
		var unlocked := SlotCatalog.unlocked(item, grants)
		var button := _shop_button(
			item.name, "%s %s" % [item.type.capitalize(), item.size], int(item.price),
			unlocked, unlocked and GameState.credits >= int(item.price),
			func() -> void:
				var ok := GameState.buy_equipment(item.id, int(item.rank))
				if ok:
					AudioManager.play_ui_sfx(&"purchase")
				_result(ok),
			true)
		button.set_meta("equipment_id", item.id)
		button.set_meta("rank", int(item.rank))
		button.set_meta("inspect_equipment", item.id)
		button.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_inspect_equipment(item.id, int(item.rank)))
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
	researched_filter.hide()
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
		var available_to_buy := GameState.credits >= int(chassis.price) and GameState.used_command() + int(chassis.command_cost) <= GameState.command_limit()
		var button := _shop_button(
			chassis.name, "%d command" % chassis.command_cost, int(chassis.price), true, available_to_buy,
			func() -> void:
				var ok := GameState.buy_chassis(chassis.id)
				if ok:
					AudioManager.play_ui_sfx(&"purchase")
				_result(ok),
			true)
		button.set_meta("inspect_chassis", chassis.id)
		button.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_inspect_chassis(chassis.id))
		image.mouse_filter = MOUSE_FILTER_STOP
		image.set_meta("inspect_chassis", chassis.id)
		image.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_inspect_chassis(chassis.id))
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(button)

func _fit_roster_name(button: Button) -> void:
	var font := button.get_theme_font("font")
	var font_size := get_theme_font_size("font_size", "Button")
	var padding := button.get_theme_stylebox("normal").get_minimum_size().x
	var icon_width := 9 + button.get_theme_constant("h_separation") if button.icon != null else 0
	var available := maxf(1, button.size.x - padding - icon_width)
	while font_size > 1 and font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available:
		font_size -= 1
	button.add_theme_font_size_override("font_size", font_size)

func _show_map() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details.add_child(scroll)
	map_details = VBoxContainer.new()
	map_details.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(map_details)
	if not GameState.navigation.is_empty():
		var threat := _label("Swarm Intensity: %s" % ScienceRules.format_rp(GameState.navigation.intensity))
		threat.name = "SwarmIntensity"
		roster.add_child(threat)
	roster.add_child(_label("DESTINATION"))
	graph = load("res://scripts/graph_view.gd").new()
	center.add_child(graph)
	graph.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	graph.set_current_node(GameState.current_node_id)
	if not map_camera.is_empty():
		graph.camera_position = map_camera.position
		graph.camera_zoom = map_camera.zoom
	graph.destination_selected.connect(_select_destination)
	if GameState.expedition_simulation != null:
		map_details.add_child(_label("Choose your onward destination after arrival."))
		return
	for id: int in GameState.get_reachable_nodes(GameState.current_node_id):
		var preview: Dictionary = GameState.node_preview(id)
		roster.add_child(_button(preview.title, _select_destination.bind(id)))
	var problem: String = GameState.deployment_error()
	if not problem.is_empty():
		map_details.add_child(_label(problem))
	_map_event_details()
	map_details.add_child(_label(NodeEnvironment.description(GameState.node_environment(GameState.current_node_id))))

func _map_event_details() -> void:
	if GameState.navigation.is_empty():
		return
	for source: String in GameState.navigation.quests:
		var quest := SwarmNavigation.event(GameState.campaign_dag, int(source))
		var target := GameState.campaign_node(quest.target)
		if GameState.navigation.quests[source] == "complete" and GameState.current_node_id != quest.target:
			continue
		map_details.add_child(_resource_label(("Relay complete: +%d cr, -%d intensity" % [quest.reward, quest.reduction] if GameState.navigation.quests[source] == "complete"
			else "Relay data -> " + target.name)))
	var event := SwarmNavigation.event(GameState.campaign_dag, GameState.current_node_id)
	if event.is_empty() or GameState.navigation.events.has(str(GameState.current_node_id)):
		return
	map_details.add_child(_label(event.title))
	map_details.add_child(_label(event.text))
	map_details.add_child(_resource_label("Relay: +%d cr\nSwarm -%d | Disrupt -%d" % [event.reward, event.reduction, event.disruption]))
	map_details.add_child(_button("Relay data", func() -> void: _result(GameState.resolve_map_event("relay"))))
	map_details.add_child(_button("Disrupt signal", func() -> void: _result(GameState.resolve_map_event("disrupt"))))

func _select_destination(id: int) -> void:
	if traveling:
		return
	if GameState.expedition_simulation != null:
		feedback.text = "Choose the next destination in the arrival dialog."
		return
	AudioManager.play_ui_sfx(&"detail")
	GameState.set_planned_destination(id)
	_clear(map_details)
	var preview: Dictionary = GameState.node_preview(id)
	map_details.add_child(_label(preview.title))
	map_details.add_child(_resource_label(preview.text))
	var days: float = GameState.research_travel_time(GameState.current_node_id, id)
	if not GameState.navigation.is_empty():
		var intensity: float = GameState.navigation.intensity + days
		var enemy_intensity: float = GameState.navigation.encounters.get(str(id), {}).get("swarm_intensity", intensity)
		map_details.add_child(_label("Swarm: %s -> %s\nHostile strength +%.0f%%" % [
			ScienceRules.format_rp(GameState.navigation.intensity), ScienceRules.format_rp(intensity), enemy_intensity * SwarmNavigation.STRENGTH_PER_POINT * 100]))
		if GameState.visited_nodes.has(id):
			map_details.add_child(_label("Visited: no encounter reward"))
	map_details.add_child(_resource_label("%s RP on arrival" % ScienceRules.format_rp(ScienceRules.journey_rp(ScienceRules.snapshot(GameState.get_deployed_fleet()), days))))
	map_details.add_child(_button_with_sound("TRAVEL", func() -> void:
		_begin_travel(id), &""))
	_map_event_details()
	var conditions := _label(NodeEnvironment.description(GameState.node_environment(id)))
	conditions.name = "NodeConditions"
	map_details.add_child(conditions)

func _begin_travel(id: int) -> void:
	if traveling:
		return
	if GameState.expedition_simulation != null:
		feedback.text = "Choose the next destination in the arrival dialog."
		return
	traveling = true
	# Commit departure before animation; prevent UI rebuilds until arrival.
	if not GameState.travel_to(id):
		traveling = false
		_result(false)
		return
	AudioManager.play_ui_sfx(&"animate_ui")
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
	if not GameState.can_use_shipyard():
		feedback.text = GameState.station_service_error("shipyard")
		return
	var owned: HangarShip = GameState.owned_ship(id)
	if owned == null or owned.flagship:
		return
	AudioManager.play_ui_sfx(&"question")
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
