extends Control

const StatBars = preload("res://scripts/ship_stat_bars.gd")
const CREDITS_ICON: Texture2D = preload("res://assets/credits.png")
const SCIENCE_ICON: Texture2D = preload("res://assets/science.png")
const BUY_ICON: Texture2D = preload("res://assets/ui/Btn_BuyCoins_n.png")
const ExpeditionStateData = preload("res://scripts/expedition_state.gd")
const SceneFadeScript = preload("res://scripts/scene_fade.gd")
const PlaceholderAssets = preload("res://scripts/placeholders.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const ShipLoadouts = preload("res://scripts/ship_loadouts.gd")
const CommandHeader = preload("res://scripts/command_header.gd")
const UiArtFrame = preload("res://scripts/ui_art_frame.gd")
const PanelSlide = preload("res://scripts/panel_slide.gd")
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
var delivery_readout: ResourceText
var delivery_seconds := 0.0
var delivery_income := 0
var instrument_seconds := {"fuel": 0.0, "hull": 0.0, "transport": 0.0}
var command_header: Container
var feedback: Label
var canvas: Control
var shop: Control
var buy_open := false
var buy_mode := "SHIPS"
var shop_rows: GridContainer
var active_tab := "MAP"
var formation_view: Control
var formation_camera := Vector2.ZERO
var formation_zoom := 1.0
var formation_station_angle := 0.0
var formation_selection: Array[int] = []
var selected_squadron_id := 0
var squadron_buy_count := 1
var fitting_views: Dictionary = {}
var research_dialog: Control
var dismissed_research_offer := ""
var traveling := false
var graph: Control
var map_camera: Dictionary = {}
var map_selected_id := ""
var map_details: VBoxContainer
var voyage_summary: Label
var map_course_used := false
var flagship_icon: Texture2D
var refresh_queued := false
var refit_panel: VBoxContainer
var stats_grid: GridContainer
var slot_info: ResourceText
var roster_panel: PanelContainer
var details_panel: PanelContainer
var settings_dialog: PopupPanel
var tabs: HBoxContainer
var inspection: ScrollContainer
var inspected_item: Dictionary = {}
var travel_controls: PanelContainer
var travel_play_button: Button
var travel_pause_button: Button
var travel_refuel_button: Button
var travel_retry_button: Button
var travel_fuel: Label
var missile_readout: Label
var missile_buy_button: Button
var departure_button: Button
var course_readout: Label
var station_actions: VBoxContainer
var station_action_signature: Array = []
var encounter_modal: Control
var encounter_error: Label
var encounter_retry: Button
var encounter_event_id := ""
var expedition_save_elapsed := 0.0
var expedition_status_override := ""
var shipyard_access_available := false
var entering_battle := false
var ship_editor: Control
var ship_editor_open := false
var editor_feedback: Label

func _ready() -> void:
	if GameState.run_id.is_empty():
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	var expedition = GameState.expedition_simulation
	if expedition != null and expedition.state != null and expedition.state.pending_event_id.is_empty() \
			and expedition.state.travel_state not in [ExpeditionStateData.TravelState.ENGAGED,
				ExpeditionStateData.TravelState.SETTLING, ExpeditionStateData.TravelState.REGROUPING]:
		expedition.set_speed(ExpeditionStateData.MAP_SPEED)
	var margin := MarginContainer.new()
	var background := ColorRect.new()
	background.color = get_theme_color("background_color", "SlotCanvas")
	background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	# A transient first-frame minimum size (wrapping text at zero width) can grow
	# the margin's offsets permanently; snap it back to the screen afterwards.
	var snap_margin := func() -> void:
		var fits := margin.get_combined_minimum_size().y <= size.y and margin.get_combined_minimum_size().x <= size.x
		if fits and (margin.size.y > size.y + 0.5 or margin.size.x > size.x + 0.5):
			margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.resized.connect(snap_margin, CONNECT_DEFERRED)
	margin.minimum_size_changed.connect(snap_margin, CONNECT_DEFERRED)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)
	var top := CommandHeader.new()
	command_header = top
	PanelSlide.wrap(column, top, Vector2.UP)
	tabs = HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_vertical = SIZE_SHRINK_BEGIN
	top.left.add_child(tabs)
	research_button = _button_with_sound("", func() -> void:
		_show_research_choices(), &"accept")
	research_button.name = "ResearchChoicesButton"
	research_button.theme_type_variation = &"NavigationTab"
	research_button.custom_minimum_size = Vector2(140, 27)
	research_button.size_flags_vertical = SIZE_SHRINK_BEGIN
	research_pulse = ShaderMaterial.new()
	research_pulse.shader = preload("res://shaders/ui_research_pulse.gdshader")
	research_button.material = research_pulse
	top.right.add_child(research_button)
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
	header_wallet.size_flags_vertical = SIZE_SHRINK_CENTER
	top.right.add_child(header_wallet)
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
	for title in ["MAP", "FLEET"]:
		var tab := _button_with_sound(title, func() -> void:
			if traveling:
				return
			active_tab = title
			ship_editor_open = false
			for tab_button: Button in tabs.get_children():
				tab_button.set_pressed_no_signal(tab_button.text == title)
			buy_open = false
			_refresh(), &"accept")
		tab.size_flags_horizontal = SIZE_EXPAND_FILL
		tab.theme_type_variation = &"NavigationTab"
		tab.custom_minimum_size = Vector2(72, 27)
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
	delivery_readout = ResourceText.create("")
	delivery_readout.name = "DeliveryIncome"
	delivery_readout.theme_type_variation = &"InstrumentFeedback"
	delivery_readout.z_index = UiKit.TOAST_Z
	delivery_readout.hide()
	add_child(delivery_readout)
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(body)
	roster = _panel(body, 132, &"CommandLeftPanel")
	roster_panel = roster.get_parent().get_parent()
	center = Control.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	center.size_flags_vertical = SIZE_EXPAND_FILL
	center.clip_contents = true
	body.add_child(center)
	details = _panel(body, 156, &"CommandRightPanel")
	details_panel = details.get_parent().get_parent()
	body.resized.connect(_resize_panels, CONNECT_DEFERRED)
	resized.connect(_resize_panels)
	_resize_panels()
	var footer := HBoxContainer.new()
	var footer_panel := UiArtFrame.new()
	footer_panel.horizontal = true
	footer_panel.name = "CommandFooter"
	footer_panel.theme_type_variation = &"CommandFooter"
	footer_panel.texture_filter = TEXTURE_FILTER_NEAREST
	PanelSlide.wrap(column, footer_panel, Vector2.DOWN)
	footer_panel.add_child(footer)
	feedback = _label("")
	feedback.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(feedback)
	_build_travel_controls(top, footer)
	GameState.fleet_changed.connect(_queue_refresh)
	GameState.research_changed.connect(_queue_refresh)
	GameState.credits_changed.connect(_on_credits_changed)
	_refresh()
	_sync_music()
	SceneFadeScript.reveal(self)
	if GameState.battle_pending and GameState.pending_encounter.has("expedition_event_id"):
		_enter_battle.call_deferred()
	elif GameState.expedition_simulation != null:
		if not GameState.expedition_simulation.state.pending_event_id.is_empty():
			_show_encounter()
		elif not GameState.arrival_notice.is_empty():
			_show_arrival(GameState.arrival_notice)
			GameState.arrival_notice = ""
		elif GameState.stranded():
			_show_rescue()
		elif GameState.pending_intro:
			var briefing: Dictionary = GameState.expedition_simulation.Events.start_event(GameState.expedition_simulation.events)
			if briefing.is_empty():
				GameState.pending_intro = false
			else:
				_show_encounter(briefing)
func _resize_panels() -> void:
	if header_wallet != null:
		_resize_research_label()
	if roster_panel != null:
		var footer_art := get_theme_icon("frame", "CommandFooter")
		var footer_height := ceilf(size.x * footer_art.get_height() / footer_art.get_width())
		var body_height := maxf(1, size.y - ceilf(command_header.get_combined_minimum_size().y) - footer_height)
		roster_panel.custom_minimum_size.x = body_height * roster_panel.art.get_width() / roster_panel.art.get_height()
	if details_panel != null:
		details_panel.custom_minimum_size.x = roster_panel.custom_minimum_size.x \
			* roster_panel.art.get_height() / roster_panel.art.get_width() \
			* details_panel.art.get_width() / details_panel.art.get_height()
	if is_instance_valid(roster):
		var ship_rows := roster.get_node_or_null("ShipTiles")
		if ship_rows != null:
			for tile: Button in ship_rows.get_children():
				tile.custom_minimum_size = Vector2.ONE * _ship_tile_size()
	if stats_grid != null and is_instance_valid(stats_grid):
		stats_grid.columns = 2 if size.x < 1000 else 4

func _resize_research_label() -> void:
	var text_width := research_status.get_theme_font("font").get_string_size(
		research_status.text, HORIZONTAL_ALIGNMENT_LEFT, -1, research_status.get_theme_font_size("font_size")).x
	var center_width := 0.0
	if is_instance_valid(travel_controls):
		center_width = travel_controls.get_combined_minimum_size().x
	center_width = maxf(center_width, minf(244, size.x - 16 - 2 * tabs.get_combined_minimum_size().x))
	var available := floorf((size.x - center_width) * 0.5) - 8 \
			- header_wallet.get_combined_minimum_size().x - 4 - 36
	research_status.custom_minimum_size.x = minf(text_width, maxf(1, available))
	research_button.custom_minimum_size.x = maxf(140, research_status.custom_minimum_size.x + 36)
	var text_height := research_status.get_theme_font("font").get_multiline_string_size(
		research_status.text, HORIZONTAL_ALIGNMENT_CENTER, research_status.custom_minimum_size.x,
		research_status.get_theme_font_size("font_size")).y
	var progress_height := maxf(8, research_rate.get_combined_minimum_size().y) if research_progress.visible else 0.0
	research_button.custom_minimum_size.y = maxf(27, maxf(12, ceilf(text_height)) + progress_height + (8 if research_progress.visible else 6))
	var rate_width := research_rate.get_theme_font("font").get_string_size(
		research_rate.text, HORIZONTAL_ALIGNMENT_LEFT, -1, research_rate.get_theme_font_size("font_size")).x
	var row_width := research_button.custom_minimum_size.x - 20
	research_progress.custom_minimum_size.x = maxf(8, minf(
		floorf(row_width * 0.5), row_width - rate_width - 4))

func _process(delta: float) -> void:
	if research_pulse != null:
		if GameState.research_choice_ready():
			research_pulse_time = fmod(research_pulse_time + delta, 1.0)
			research_pulse.set_shader_parameter("white_mix", 0.08 * (1.0 - cos(TAU * research_pulse_time)) * 0.5)
		else:
			research_pulse_time = 0.0
			research_pulse.set_shader_parameter("white_mix", 0.0)
	_maybe_show_research_choices()
	_advance_expedition(delta)
	_sync_station_services()
	_sync_station_actions()
	_update_instrument_feedback(delta)

func _update_instrument_feedback(delta: float) -> void:
	delivery_seconds = maxf(0, delivery_seconds - delta)
	if delivery_seconds == 0:
		delivery_income = 0
	delivery_readout.visible = delivery_seconds > 0
	if delivery_readout.visible:
		var font := delivery_readout.get_theme_font("normal_font")
		var font_size := delivery_readout.get_theme_font_size("normal_font_size")
		var width := font.get_string_size("+%d " % delivery_income,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + font_size
		delivery_readout.custom_minimum_size.x = ceilf(width)
		var extent := delivery_readout.get_combined_minimum_size()
		delivery_readout.size = extent
		var wallet := header.get_global_rect()
		delivery_readout.global_position = Vector2(
			clampf(wallet.end.x - extent.x, global_position.x, global_position.x + size.x - extent.x),
			wallet.end.y + 2).round()
		delivery_readout.self_modulate.a = minf(1, delivery_seconds / 0.3)
	for key: String in instrument_seconds:
		if float(instrument_seconds[key]) <= 0:
			continue
		instrument_seconds[key] = maxf(0, float(instrument_seconds[key]) - delta)
		var strength := sin(PI * float(instrument_seconds[key]) / 0.8)
		var tint := Color.WHITE.lerp(get_theme_color("pulse_color", "InstrumentFeedback"), maxf(0, strength))
		if key == "fuel":
			travel_fuel.self_modulate = tint
		else:
			for node: Node in get_tree().get_nodes_in_group(key + "_readout"):
				if is_ancestor_of(node) and node is CanvasItem:
					node.self_modulate = tint

func _show_delivery_income(amount: int) -> void:
	delivery_income += amount
	delivery_seconds = 1.6
	delivery_readout.set_content("+%d cr" % delivery_income)
	instrument_seconds.transport = 0.8
	AudioManager.play_ui_sfx(&"purchase")
	_update_instrument_feedback(0)

func _repair_selected_ship() -> void:
	_finish_repair(GameState.repair_ship(GameState.owned_ship(selected_ship_id)))

func _repair_fleet() -> void:
	_finish_repair(GameState.repair_all_ships())

func _finish_repair(ok: bool) -> void:
	if ok:
		instrument_seconds.hull = 0.8
		AudioManager.play_ui_sfx(&"repair")
	_result(ok)

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
			if button.name == "BuyShips" and not available:
				button.set_pressed_no_signal(false)
	var reason := roster.find_child("StationServiceReason", true, false) as Label
	if reason != null:
		reason.text = GameState.station_service_error("shipyard")
		reason.visible = not available
	_render_refit_panel()

func _shipyard_action(button: Button, eligible := true) -> Button:
	button.set_meta("shipyard_eligible", eligible)
	button.disabled = not GameState.can_use_shipyard() or not eligible
	return button

func _advance_expedition(delta: float) -> void:
	var simulation = GameState.expedition_simulation
	if simulation == null or simulation.state == null \
			or active_tab != "MAP" or not is_visible_in_tree() \
			or is_instance_valid(encounter_modal) or is_instance_valid(research_dialog) or entering_battle or GameState.completed or GameState.run_ended:
		return
	if simulation.state.requested_speed != ExpeditionStateData.MAP_SPEED and not simulation.set_speed(ExpeditionStateData.MAP_SPEED):
		return
	expedition_save_elapsed += delta
	var periodic: bool = expedition_save_elapsed >= EXPEDITION_SAVE_INTERVAL
	var result: Dictionary = GameState.advance_expedition(delta, periodic)
	if is_instance_valid(formation_view):
		formation_view.travel_distance_nu = simulation.state.traveled_distance_nu
	if not result.ok:
		simulation.set_pause(ExpeditionStateData.PauseReason.SAVE_ERROR, true)
		expedition_status_override = result.error
		expedition_save_elapsed = 0.0
		_refresh_expedition_controls()
		return
	if result.saved:
		expedition_save_elapsed = 0.0
	if int(result.delivered) > 0:
		_show_delivery_income(int(result.delivered))
	if result.repaired:
		instrument_seconds.hull = 0.8
		AudioManager.play_ui_sfx(&"repair")
		if active_tab == "FLEET":
			_show_details()
	_update_expedition_readouts()
	if result.boundary:
		expedition_status_override = ""
		var arrived := _arrived_location()
		if not simulation.state.docked_location_id.is_empty():
			AudioManager.play_ui_sfx(&"dock")
		_sync_music()
		if not simulation.state.pending_event_id.is_empty():
			_show_encounter()
		elif not arrived.is_empty():
			_show_arrival(arrived)
		elif GameState.stranded():
			_show_rescue()
		_refresh_expedition_controls()
		if is_instance_valid(graph):
			graph.queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not inspected_item.is_empty():
		if is_instance_valid(inspection) and inspection.get_global_rect().has_point(event.position):
			return
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
	for child: Node in details.get_children():
		if child.has_meta("hidden_by_inspection"):
			child.remove_meta("hidden_by_inspection")
			child.show()

func _inspect_chassis(id: String) -> void:
	AudioManager.play_ui_sfx(&"detail")
	inspected_item = {"kind": "chassis", "id": id}
	_render_inspection()

func _render_inspection() -> void:
	if is_instance_valid(inspection):
		details.remove_child(inspection)
		inspection.queue_free()
	# Inspection temporarily replaces the right panel's contents.
	for child: Node in details.get_children():
		if child is Control and child.visible:
			child.set_meta("hidden_by_inspection", true)
			child.hide()
	inspection = ScrollContainer.new()
	inspection.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
		ship.initialize_chassis(chassis.id, 0, chassis.flagship)
		body.add_child(_resource_label(chassis.name))
		var bars := StatBars.new()
		body.add_child(bars)
		bars.set_ship(ship)
		var price := int(chassis.price) if chassis.flagship else ShipLoadouts.ship_price(chassis.id, ShipLoadouts.purchase_for(chassis.id, GameState.current_research_ids))
		body.add_child(_resource_label("Fitted price %d cr" %
			price))
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
		if not ShipLoadouts.equipment_available(item, GameState.current_research_ids):
			body.add_child(_label("Research required"))
		if HangarTrade.has_load(instance):
			body.add_child(_label("%s: %d\nDeliver before removing" % [str(instance.load.kind).capitalize(), instance.load.quantity]))

func _panel(parent: Node, width: float, variation: StringName) -> VBoxContainer:
	var panel := UiArtFrame.new()
	panel.theme_type_variation = variation
	panel.custom_minimum_size.x = width
	PanelSlide.wrap(parent, panel, Vector2.LEFT if variation == &"CommandLeftPanel" else Vector2.RIGHT)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box

func _button(title: String, action: Callable) -> Button:
	return _button_with_sound(title, action, &"accept")

func _button_with_sound(title: String, action: Callable, sound: StringName) -> Button:
	return UiKit.button(title, action, sound)

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
	return UiKit.label(title)

func _resource_label(title: String) -> ResourceText:
	return ResourceText.create(title)

func _clear(host: Node) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()

func _on_credits_changed() -> void:
	header.text = str(GameState.credits)
	_resize_research_label.call_deferred()
	var simulation = GameState.expedition_simulation
	if simulation != null and simulation.state != null \
			and simulation.state.travel_state == ExpeditionStateData.TravelState.CRUISING:
		return
	_queue_refresh()

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
	for tab: Button in tabs.get_children():
		tab.set_pressed_no_signal(tab.text == active_tab)
	if is_instance_valid(canvas) and not canvas.auto_fit:
		fitting_views[canvas.owned_id] = {"camera": canvas.camera, "zoom": canvas.zoom}
	if is_instance_valid(formation_view):
		formation_camera = formation_view.camera
		formation_zoom = formation_view.zoom
		formation_station_angle = formation_view.station_angle
	if is_instance_valid(ship_editor):
		remove_child(ship_editor)
		ship_editor.queue_free()
	ship_editor = null
	editor_feedback = null
	if is_instance_valid(graph) and graph.is_inside_tree() and graph.get("user_moved") != false:
		map_camera = {"position": graph.camera_position, "zoom": graph.camera_zoom}
	graph = null
	formation_view = null
	header.text = str(GameState.credits)
	_update_research_header(true)
	_clear(roster)
	_clear(details)
	station_actions = null
	station_action_signature = []
	if is_instance_valid(shop) and shop.get_parent() == center:
		shop = null
	_clear(center)
	canvas = null
	refit_panel = null
	stats_grid = null
	slot_info = null
	if selected_ship_id > 0 and GameState.owned_ship(selected_ship_id) == null:
		selected_ship_id = 0
	if selected_ship_id == -1 and not GameState.fleet.is_empty():
		selected_ship_id = GameState.fleet[0].id
	if selected_ship_id <= 0:
		ship_editor_open = false
	if selected_squadron_id > 0:
		var selected_group := HangarSquadrons.find(GameState.squadrons, selected_squadron_id)
		if selected_group.is_empty():
			selected_squadron_id = 0
		else:
			selected_ship_id = int(selected_group.members[0])
			formation_selection.assign(selected_group.members)
	formation_selection = formation_selection.filter(func(id: int) -> bool: return GameState.owned_ship(id) != null)
	if GameState.completed or GameState.run_ended:
		_show_run_end()
		return
	if active_tab == "MAP":
		_show_map()
		_build_station_actions()
		_refresh_expedition_controls()
		return
	if active_tab == "FLEET":
		for group: Dictionary in GameState.squadrons:
			var choose := _button("%s #%d x%d" % [group.name, group.id, group.members.size()],
				_select_squadron.bind(int(group.id)))
			choose.name = "Squadron_%d" % group.id
			choose.icon = SurfaceArt.diffuse(GameState.owned_ship(int(group.members[0])).art_texture)
			choose.expand_icon = true
			choose.add_theme_constant_override("icon_max_width", 24)
			choose.toggle_mode = true
			choose.button_pressed = selected_squadron_id == int(group.id)
			roster.add_child(choose)
	var buy := _button_with_sound("Buy Ships", _open_shop.bind("SHIPS"), &"animate_ui")
	buy.name = "BuyShips"
	buy.toggle_mode = true
	buy.button_pressed = buy_open
	_shipyard_action(buy)
	roster.add_child(buy)
	var service_reason := _label(GameState.station_service_error("shipyard"))
	service_reason.name = "StationServiceReason"
	service_reason.visible = not shipyard_access_available
	roster.add_child(service_reason)
	if active_tab == "FLEET":
		_build_station_actions()
	if active_tab == "FLEET":
		var board: Control = load("res://scripts/hangar_formation.gd").new()
		board.selected_id = selected_ship_id
		board.selected_ids.assign(formation_selection)
		board.selected_squadron_id = selected_squadron_id
		board.camera = formation_camera
		board.zoom = formation_zoom
		board.station_angle = formation_station_angle
		if GameState.expedition_simulation != null and GameState.expedition_simulation.state != null:
			board.travel_distance_nu = GameState.expedition_simulation.state.traveled_distance_nu
		formation_view = board
		center.add_child(board)
		board.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		board.ship_selected.connect(_select_ship.bind(false))
		board.squadron_selected.connect(_select_squadron.bind(false))
		board.action_failed.connect(func(message: String) -> void: feedback.text = message)
	var reopen_editor := ship_editor_open
	ship_editor_open = false
	_show_details()
	if buy_open:
		_show_buy_panel()
	_refresh_expedition_controls()
	ship_editor_open = reopen_editor
	if ship_editor_open:
		_build_ship_editor()


func _update_research_header(update_rate := false) -> void:
	var progress := GameState.run_progress_snapshot()
	var required := HangarResearch.threshold(progress)
	var ready := GameState.research_choice_ready()
	var text := "Choose Upgrade" if ready else "%d / %d RP" % [floori(GameState.research_points), required]
	if GameState.research_offer.is_empty() and GameState.research_points >= required:
		text = "Research Banked"
	research_button.disabled = not ready
	if research_status.text != text:
		research_status.text = text
		_resize_research_label.call_deferred()
	research_progress.max_value = required
	research_progress.value = minf(GameState.research_points, required)
	research_progress.show()
	research_progress_row.show()
	if update_rate:
		research_rate.text = "+%s/day" % ScienceRules.format_rp(ScienceRules.production_rate(ScienceRules.snapshot(GameState.get_deployed_fleet())))

func _research_signature() -> String:
	return ",".join(GameState.research_offer) + "/" + str(GameState.current_research_ids.size())

func _maybe_show_research_choices() -> void:
	if not GameState.research_choice_ready() or dismissed_research_offer == _research_signature():
		return
	_show_research_choices()

func _show_research_choices() -> void:
	if is_instance_valid(research_dialog) or not GameState.research_choice_ready() or entering_battle \
			or GameState.battle_pending or GameState.run_ended or GameState.completed or UiNavigation.settings_open():
		return
	for modal: Node in get_tree().get_nodes_in_group("modal_ui"):
		if modal is CanvasItem and modal.is_visible_in_tree() and not modal.is_queued_for_deletion():
			return
	research_dialog = preload("res://scripts/research_choices.gd").new()
	research_dialog.closed.connect(func() -> void:
		dismissed_research_offer = _research_signature()
		research_dialog = null)
	research_dialog.chosen.connect(func() -> void:
		research_dialog = null
		dismissed_research_offer = ""
		_update_research_header())
	add_child(research_dialog)
	research_dialog.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

func _show_run_end() -> void:
	if is_instance_valid(get_node_or_null("RunEnd")):
		return
	for blocker: Control in [encounter_modal]:
		if is_instance_valid(blocker):
			blocker.queue_free()
	encounter_modal = null
	_sync_music()
	if GameState.completed:
		AudioManager.play_ui_sfx(&"demo_complete")
	var story := "The Bastion Gate is open. The Leviathan waits beyond it.\nThanks for playing this slice of Leviathan Protocol." \
			if GameState.completed else "The convoy is scattered without its flagship."
	var dialog := UiKit.dialog(self, "RunEnd", "", story,
			load("res://assets/ui/Victory_Badge.png") if GameState.completed else null, Callable(), UiKit.TOP_Z, 440.0)
	var title := UiKit.label("DEMO COMPLETE" if GameState.completed else "FLAGSHIP LOST")
	title.add_theme_font_size_override("font_size", 28)
	dialog.column.add_child(title)
	dialog.column.move_child(title, 0)
	var points := RunScore.breakdown(GameState.hangar_snapshot())
	if not points.is_empty():
		var lines: PackedStringArray = [
			"Research  %d" % int(points.research),
			"Swarm damage  %d" % int(points.damage),
			"Credits earned  %d" % int(points.credits)]
		if int(points.leviathan) > 0:
			lines.append("Bastion Gate cleared  %d" % int(points.leviathan))
		lines.append("SCORE  %d" % int(points.total))
		var score := UiKit.label("\n".join(lines))
		score.name = "RunEndScore"
		dialog.column.add_child(score)
		dialog.column.move_child(score, dialog.column.get_child_count() - 2)
	var menu := UiKit.button("MAIN MENU", func() -> void:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	menu.name = "RunEndMainMenu"
	dialog.actions.add_child(menu)

func _refresh_expedition_controls() -> void:
	_sync_station_services()
	_sync_station_actions()
	_update_voyage_summary()
	if not is_instance_valid(travel_controls) or GameState.expedition_simulation == null \
			or GameState.expedition_simulation.state == null:
		return
	var simulation = GameState.expedition_simulation
	var state = simulation.state
	travel_play_button.set_pressed_no_signal(state.pause_reasons.is_empty())
	travel_play_button.disabled = state.travel_state in [
		ExpeditionStateData.TravelState.ENGAGED,
		ExpeditionStateData.TravelState.SETTLING,
		ExpeditionStateData.TravelState.REGROUPING
	] or not state.pending_event_id.is_empty()
	travel_pause_button.set_pressed_no_signal(
			ExpeditionStateData.PauseReason.USER in state.pause_reasons)
	travel_fuel.text = "FUEL %d / %d" % [roundi(state.fuel), roundi(state.fuel_capacity)]
	missile_readout.text = "MISSILES %d" % GameState.missiles
	var ammunition_error: String = GameState.station_service_error("ammunition")
	missile_buy_button.visible = ammunition_error.is_empty()
	missile_buy_button.disabled = GameState.credits < GameState.MISSILE_PACK_PRICE
	var docked: Dictionary = simulation.locations.get(state.docked_location_id, {})
	travel_refuel_button.visible = not docked.is_empty() \
			and "refuel" in docked.get("services", []) and state.fuel < state.fuel_capacity \
			and not is_instance_valid(station_actions)
	var refuel_cost := int(ceil((state.fuel_capacity - state.fuel) * 2.0))
	travel_refuel_button.text = "REFUEL %d" % refuel_cost
	travel_refuel_button.disabled = not GameState.station_service_error("refuel").is_empty() or GameState.credits < refuel_cost
	travel_retry_button.visible = ExpeditionStateData.PauseReason.SAVE_ERROR in state.pause_reasons
	_update_course_control()
	_update_expedition_readouts()

func _show_encounter(intro: Dictionary = {}) -> void:
	if is_instance_valid(encounter_modal) or GameState.completed:
		return
	var simulation = GameState.expedition_simulation
	if simulation == null or (intro.is_empty() and simulation.state.pending_event_id.is_empty()):
		return
	var event: Dictionary = intro if not intro.is_empty() \
			else simulation.Events.find(simulation.events, simulation.state.pending_event_id)
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
	AudioManager.play_ui_sfx(&"question")
	var dialog := UiKit.dialog(self, "ExpeditionEncounter", str(event.title), str(event.text),
			str(event.get("art", "")), Callable(), UiKit.DIALOG_Z, 520.0)
	encounter_modal = dialog.root
	dialog.panel.name = "EncounterPanel"
	for option: Dictionary in simulation.Events.options(event):
		var action := _dismiss_intro if not intro.is_empty() else _choose_encounter.bind(event.id, str(option.id))
		var choice := UiKit.button(str(option.label), action)
		choice.name = "Choice_" + str(option.id)
		choice.disabled = GameState.credits < int(option.get("effects", {}).get("requires_credits", 0))
		if option.get("effects", {}).has("combat"):
			choice.add_theme_color_override("font_color", Color("ffb0a0"))
		dialog.actions.add_child(choice)
	encounter_error = UiKit.label("")
	dialog.column.add_child(encounter_error)
	encounter_retry = UiKit.button("RETRY SAVE", func() -> void:
		_on_expedition_retry_pressed()
		encounter_error.text = expedition_status_override
		encounter_retry.visible = ExpeditionStateData.PauseReason.SAVE_ERROR in simulation.state.pause_reasons)
	encounter_retry.visible = ExpeditionStateData.PauseReason.SAVE_ERROR in simulation.state.pause_reasons
	dialog.column.add_child(encounter_retry)

func _show_rescue() -> void:
	if is_instance_valid(encounter_modal) or not GameState.stranded():
		return
	var quote: Dictionary = GameState.rescue_quote()
	if quote.is_empty():
		return
	AudioManager.play_ui_sfx(&"alarm")
	var debt: int = int(quote.fee) - GameState.credits
	var text := "The convoy is adrift. A salvage tug can tow you %d NU to %s and fill the tanks for %d credits." % [
		roundi(quote.distance), quote.name, int(quote.fee)]
	if debt > 0:
		text += "\nThis leaves the convoy %d credits in debt." % debt
	var dialog := UiKit.dialog(self, "FuelRescue", "Out of fuel", text)
	encounter_modal = dialog.root
	encounter_error = UiKit.label("")
	var tow := UiKit.button("CALL A TUG %d cr" % int(quote.fee), func() -> void:
		if not GameState.accept_rescue():
			encounter_error.text = GameState.last_save_error
			return
		encounter_modal.queue_free()
		encounter_modal = null
		AudioManager.play_ui_sfx(&"refuel")
		_sync_music()
		_refresh_expedition_controls()
		_queue_refresh()
		_show_arrival(GameState.expedition_simulation.state.docked_location_id))
	tow.name = "AcceptRescue"
	dialog.actions.add_child(tow)
	dialog.column.add_child(encounter_error)

func _dismiss_intro() -> void:
	GameState.pending_intro = false
	if is_instance_valid(encounter_modal):
		encounter_modal.queue_free()
	encounter_modal = null
	encounter_error = null
	encounter_retry = null

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
	var simulation = GameState.expedition_simulation
	var event: Dictionary = simulation.Events.find(simulation.events, event_id)
	var here: String = event.get("location_id", "") if simulation.Events.trigger(event) == "arrival" \
			and simulation.state.destination_location_id.is_empty() else ""
	if GameState.battle_pending:
		GameState.arrival_notice = here
		_enter_battle()
		return
	if not GameState.last_event_result.is_empty():
		_toast(GameState.last_event_result, &"loot" if "Found" in GameState.last_event_result else &"notification")
	_refresh_expedition_controls()
	if not here.is_empty():
		_show_arrival(here)

# The location the fleet reached in the latest boundary batch, if any.
func _arrived_location() -> String:
	var simulation = GameState.expedition_simulation
	for index in range(simulation.emitted_boundaries.size() - 1, -1, -1):
		var boundary: Dictionary = simulation.emitted_boundaries[index]
		if int(boundary.kind) in [ExpeditionStateData.BoundaryKind.DOCK, ExpeditionStateData.BoundaryKind.ARRIVAL]:
			var id := str(boundary.details.location_id)
			var location: Dictionary = simulation.locations.get(id, {})
			var point := Vector2(location.position[0], location.position[1]) if not location.is_empty() else Vector2.INF
			return id if simulation.state.destination_location_id.is_empty() \
					and simulation.state.position_nu.distance_to(point) < 0.001 else ""
		return ""
	return ""

func _enter_battle() -> void:
	if entering_battle:
		return
	entering_battle = true
	if get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()
	AudioManager.play_ui_sfx(&"warp")
	var boss: bool = GameState.pending_encounter.get("template_id", "") == "bastion_warden"
	AudioManager.play_battle_music(boss)
	SceneFadeScript.cover_and_change(self, "res://scenes/auto_battle.tscn", "THE WARDEN" if boss else "ENGAGING")

func _toast(text: String, sound: StringName) -> void:
	UiKit.toast(self, text, sound)

func _sync_music() -> void:
	if entering_battle:
		return
	var simulation = GameState.expedition_simulation
	if GameState.completed:
		AudioManager.play_context_music(&"finale")
	elif simulation == null or simulation.state == null:
		AudioManager.play_menu_music()
	elif not simulation.state.docked_location_id.is_empty():
		AudioManager.play_context_music(&"docked")
	else:
		AudioManager.play_context_music(&"expedition")


func _update_expedition_readouts() -> void:
	if not is_instance_valid(travel_controls) or GameState.expedition_simulation == null:
		return
	var simulation = GameState.expedition_simulation
	_update_research_header()
	var state = simulation.state
	_update_course_control()
	travel_fuel.text = "FUEL %d / %d" % [roundi(state.fuel), roundi(state.fuel_capacity)]
	if not expedition_status_override.is_empty():
		feedback.text = expedition_status_override
	elif not state.destination_location_id.is_empty():
		var destination: Dictionary = simulation.locations.get(state.destination_location_id, {})
		var point := Vector2(destination.position[0], destination.position[1])
		var distance: float = state.position_nu.distance_to(point)
		var eta: float = distance / (GameState.expedition_cruise_rate() * ExpeditionStateData.MAP_SPEED)
		var paused: bool = active_tab != "MAP" or not is_visible_in_tree() or not state.pause_reasons.is_empty()
		feedback.text = "TO %s · %d NU · %s" % [
			str(destination.get("name", "UNKNOWN")).to_upper(), roundi(distance),
			"PAUSED" if paused else "ETA %ds" % ceili(eta)]
	else:
		feedback.text = _expedition_status_text()


func _build_travel_controls(top: Container, footer: HBoxContainer) -> void:
	if GameState.expedition_simulation == null or GameState.expedition_simulation.state == null:
		return
	travel_controls = PanelContainer.new()
	travel_controls.name = "ExpeditionTravelControls"
	travel_controls.theme_type_variation = &"TimeControlsPanel"
	travel_controls.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	travel_controls.size_flags_vertical = SIZE_SHRINK_CENTER
	travel_controls.mouse_filter = Control.MOUSE_FILTER_PASS
	top.middle.add_child(travel_controls)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	travel_controls.add_child(row)
	travel_pause_button = _time_button("pause", func() -> void:
		_apply_expedition_action(func() -> bool:
			return GameState.expedition_simulation.set_pause(ExpeditionStateData.PauseReason.USER, true)))
	travel_pause_button.name = "ExpeditionPause"
	row.add_child(travel_pause_button)
	travel_play_button = _time_button("play", _on_expedition_play_pressed)
	travel_play_button.name = "ExpeditionPlay"
	row.add_child(travel_play_button)
	travel_fuel = _label("")
	travel_fuel.name = "ExpeditionFuel"
	travel_fuel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	travel_fuel.autowrap_mode = TextServer.AUTOWRAP_OFF
	travel_fuel.size_flags_horizontal = Control.SIZE_SHRINK_END
	travel_fuel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(travel_fuel)
	missile_readout = _label("")
	missile_readout.name = "ExpeditionMissiles"
	missile_readout.autowrap_mode = TextServer.AUTOWRAP_OFF
	missile_readout.mouse_filter = MOUSE_FILTER_IGNORE
	missile_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(missile_readout)
	missile_buy_button = _button_with_sound("+%d MISSILES / %d cr" % [GameState.MISSILE_PACK, GameState.MISSILE_PACK_PRICE],
		_on_buy_missiles_pressed, &"")
	missile_buy_button.name = "BuyMissiles"
	footer.add_child(missile_buy_button)
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
	departure_button = _button("ENGAGE", _engage_course)
	departure_button.name = "ExpeditionDepart"
	departure_button.custom_minimum_size = Vector2(100, 24)
	departure_button.size_flags_vertical = SIZE_SHRINK_CENTER
	top.course.add_child(departure_button)
	course_readout = _label("")
	course_readout.name = "CourseReadout"
	course_readout.theme_type_variation = &"HeaderResearch"
	course_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	course_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	course_readout.size_flags_horizontal = SIZE_EXPAND_FILL
	course_readout.size_flags_vertical = SIZE_SHRINK_CENTER
	top.course.add_child(course_readout)
	_refresh_expedition_controls()

func _show_arrival(location_id: String) -> void:
	var simulation = GameState.expedition_simulation
	var location: Dictionary = {} if simulation == null else simulation.locations.get(location_id, {})
	if location.is_empty() or GameState.completed or is_instance_valid(encounter_modal):
		return
	if active_tab == "MAP" and map_selected_id.is_empty():
		map_selected_id = location_id
		graph.selected_id = location_id
		_render_map_details()
	_refresh_expedition_controls()

func _build_station_actions() -> void:
	station_actions = VBoxContainer.new()
	station_actions.name = "StationActions"
	roster.add_child(station_actions)
	_sync_station_actions()

func _sync_station_actions() -> void:
	if not is_instance_valid(station_actions):
		return
	var simulation = GameState.expedition_simulation
	if simulation == null:
		return
	var here: String = simulation.location_here()
	var location: Dictionary = simulation.locations.get(here, {})
	var docked: bool = not here.is_empty() and simulation.state.docked_location_id == here
	var repair_cost: int = GameState.fleet_repair_cost()
	var state = simulation.state
	var refuel_cost := ceili((state.fuel_capacity - state.fuel) * 2.0)
	var retry: Dictionary = simulation.retry_event_here()
	var blocked: bool = not state.pending_event_id.is_empty() or GameState.battle_pending \
			or GameState.completed or GameState.run_ended
	var signature: Array = [here, docked, repair_cost, refuel_cost, GameState.credits,
		retry.get("id", ""), blocked, GameState.station_service_error("shipyard"),
		GameState.station_service_error("refuel")]
	if signature == station_action_signature:
		return
	station_action_signature = signature
	_clear(station_actions)
	if location.is_empty() or blocked:
		return
	var actions := station_actions
	if docked:
		actions.add_child(_label(str(location.name)))
	if docked and "shipyard" in location.services and (repair_cost > 0 or active_tab == "FLEET"):
		var repair := UiKit.button("REPAIR ALL %d cr" % repair_cost, func() -> void:
			var can_repair: bool = GameState.can_use_shipyard() \
				and GameState.credits >= GameState.fleet_repair_cost()
			if GameState.repair_all_ships():
				expedition_status_override = ""
				instrument_seconds.hull = 0.8
				AudioManager.play_ui_sfx(&"repair")
			else:
				expedition_status_override = GameState.last_save_error
				if can_repair:
					simulation.set_pause(ExpeditionStateData.PauseReason.SAVE_ERROR, true)
			_refresh_expedition_controls(), &"")
		repair.name = "StationRepairAll" if active_tab == "MAP" else "FleetRepairAll"
		repair.disabled = repair_cost <= 0 or not GameState.can_use_shipyard() or GameState.credits < repair_cost
		actions.add_child(repair)
	if docked and "refuel" in location.services and state.fuel < state.fuel_capacity - 0.000001:
		var refuel := UiKit.button("REFUEL %d cr" % refuel_cost, _on_expedition_refuel_pressed, &"")
		refuel.name = "StationRefuel"
		refuel.disabled = not GameState.station_service_error("refuel").is_empty() or GameState.credits < refuel_cost
		actions.add_child(refuel)
	if active_tab == "MAP" and docked and "shipyard" in location.services:
		var yard := UiKit.button("SHIPYARD", func() -> void:
			active_tab = "FLEET"
			_refresh(), &"animate_ui")
		yard.name = "StationShipyard"
		yard.disabled = not GameState.can_use_shipyard()
		actions.add_child(yard)
	if not retry.is_empty():
		var face := UiKit.button("FACE " + str(retry.title).to_upper(), func() -> void:
			_apply_expedition_action(simulation.readmit_arrival_event)
			if not simulation.state.pending_event_id.is_empty():
				_show_encounter(), &"")
		face.name = "StationRetryEvent"
		face.disabled = ExpeditionStateData.PauseReason.SAVE_ERROR in state.pause_reasons
		face.add_theme_color_override("font_color", Color("ffb0a0"))
		actions.add_child(face)

func _open_map() -> void:
	active_tab = "MAP"
	buy_open = false
	_refresh()

# The one course command: departing a dock, rerouting mid-flight or leaving a POI.
func _set_course(location_id: String, engage := false) -> bool:
	var simulation = GameState.expedition_simulation
	if simulation == null:
		return false
	if ExpeditionStateData.PauseReason.SAVE_ERROR in simulation.state.pause_reasons:
		expedition_status_override = "Retry the failed save before setting a course."
		_refresh_expedition_controls()
		return false
	if not GameState.depart_expedition(location_id, engage):
		expedition_status_override = GameState.last_save_error
		_refresh_expedition_controls()
		return false
	expedition_status_override = ""
	expedition_save_elapsed = 0.0
	AudioManager.play_ui_sfx(&"depart")
	map_course_used = true
	if engage:
		map_selected_id = ""
		if is_instance_valid(graph):
			graph.selected_id = ""
	if not GameState.last_event_result.is_empty():
		_toast(GameState.last_event_result, &"")
	_sync_music()
	_refresh_expedition_controls()
	if is_instance_valid(graph):
		graph.queue_redraw()
		_render_map_details()
	return true

func _time_button(kind: String, action: Callable) -> Button:
	var button := _button_with_sound("", action, &"")
	preload("res://scripts/time_control.gd").decorate(button, kind)
	return button

func _engage_course() -> void:
	var simulation = GameState.expedition_simulation
	if _selected_course_available():
		_set_course(map_selected_id, true)
	elif not simulation.state.destination_location_id.is_empty() \
			and (not simulation.state.pause_reasons.is_empty() or simulation.state.travel_state == ExpeditionStateData.TravelState.STOPPED):
		_on_expedition_play_pressed()
	else:
		_open_map()

func _selected_course_available() -> bool:
	var simulation = GameState.expedition_simulation
	var location: Dictionary = simulation.locations.get(map_selected_id, {})
	return not location.is_empty() and simulation.location_accessible(location) \
		and map_selected_id in simulation.state.discovered_location_ids \
		and simulation.state.position_nu.distance_to(Vector2(location.position[0], location.position[1])) > 0.001 \
		and simulation.state.destination_location_id != map_selected_id \
		and not GameState.battle_pending and not GameState.completed and not GameState.run_ended \
		and simulation.state.pending_event_id.is_empty()

func _update_course_control() -> void:
	if not is_instance_valid(departure_button):
		return
	var simulation = GameState.expedition_simulation
	var state = simulation.state
	var selected := _selected_course_available()
	var cruising: bool = not state.destination_location_id.is_empty() and state.pause_reasons.is_empty() \
		and state.travel_state == ExpeditionStateData.TravelState.CRUISING
	var show_arrival: bool = cruising and not selected
	departure_button.visible = not show_arrival
	course_readout.visible = show_arrival
	departure_button.text = "CHANGE COURSE" if cruising and selected else "ENGAGE"
	if show_arrival:
		var destination: Dictionary = simulation.locations[state.destination_location_id]
		var remaining: float = state.position_nu.distance_to(Vector2(destination.position[0], destination.position[1]))
		course_readout.text = "%s\n%d NU" % [destination.name, ceili(remaining)]
	departure_button.disabled = not state.pending_event_id.is_empty() \
		or ExpeditionStateData.PauseReason.SAVE_ERROR in state.pause_reasons

func _on_expedition_play_pressed() -> void:
	_apply_expedition_action(func() -> bool:
		var simulation = GameState.expedition_simulation
		if not simulation.set_speed(ExpeditionStateData.MAP_SPEED):
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
	_set_course(location_id)


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
	var state = GameState.expedition_simulation.state
	var can_refuel: bool = GameState.station_service_error("refuel").is_empty() \
		and state.fuel_capacity - state.fuel > 0.000001 \
		and GameState.credits >= ceili((state.fuel_capacity - state.fuel) * 2.0)
	if not GameState.refuel_expedition():
		expedition_status_override = GameState.last_save_error
		if can_refuel:
			GameState.expedition_simulation.set_pause(ExpeditionStateData.PauseReason.SAVE_ERROR, true)
	else:
		expedition_status_override = ""
		instrument_seconds.fuel = 0.8
		AudioManager.play_ui_sfx(&"refuel")
	_refresh_expedition_controls()

func _on_buy_missiles_pressed() -> void:
	var eligible: bool = GameState.station_service_error("ammunition").is_empty() \
		and GameState.credits >= GameState.MISSILE_PACK_PRICE
	if GameState.buy_missiles():
		expedition_status_override = ""
		AudioManager.play_ui_sfx(&"loot")
	else:
		expedition_status_override = GameState.last_save_error
		if eligible:
			GameState.expedition_simulation.set_pause(ExpeditionStateData.PauseReason.SAVE_ERROR, true)
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


func _show_refit_panel() -> void:
	_clear(details)
	refit_panel = VBoxContainer.new()
	refit_panel.name = "RefitPanel"
	refit_panel.size_flags_vertical = SIZE_EXPAND_FILL
	details.add_child(refit_panel)
	_render_refit_panel()

# Player refits always apply a complete authored loadout. Mount clicks show
# equipment information without exposing custom fitting or part removal.
func _render_refit_panel() -> void:
	if not is_instance_valid(refit_panel):
		return
	_clear(refit_panel)
	var owned: HangarShip = GameState.owned_ship(selected_ship_id)
	if owned == null:
		return
	var access: bool = GameState.can_use_shipyard()
	var current: String = GameState.ship_loadout_id(owned.id)
	var heading := UiKit.label("LOADOUT", &"HeaderResearch")
	heading.name = "LoadoutHeading"
	refit_panel.add_child(heading)
	for loadout: Dictionary in ShipLoadouts.available_for(owned.chassis_id, GameState.current_research_ids):
		var fitted: bool = loadout.id == current
		var option := UiKit.button(str(loadout.name) + ("  FITTED" if fitted else ""),
			_refit_to.bind(loadout.id), &"")
		option.name = "Loadout_" + str(loadout.id)
		option.clip_text = true
		option.disabled = fitted or not access
		refit_panel.add_child(option)
	_render_squadron_assignment(owned)
	if not access:
		var reason := UiKit.label(GameState.station_service_error("shipyard"))
		reason.name = "RefitServiceReason"
		refit_panel.add_child(reason)

func _refit_to(loadout_id: String) -> void:
	var ok: bool = GameState.refit_ship(selected_ship_id, loadout_id)
	if ok:
		AudioManager.play_ui_sfx(&"place")
	_result(ok)

func _show_details() -> void:
	if (not inspected_item.is_empty() and not ship_editor_open) or (buy_open and active_tab == "FLEET"):
		return
	var owned: HangarShip = GameState.owned_ship(selected_ship_id)
	if selected_squadron_id > 0 and active_tab == "FLEET" and not ship_editor_open:
		_show_squadron_details(HangarSquadrons.find(GameState.squadrons, selected_squadron_id))
		return
	if owned == null:
		_clear(details)
		var cost: int = GameState.fleet_repair_cost()
		var repair := _button("REPAIR ALL %d cr" % cost, _repair_fleet)
		repair.name = "FleetRepairAll"
		_shipyard_action(repair, cost > 0 and GameState.credits >= cost)
		if is_instance_valid(station_actions) and station_actions.has_node("FleetRepairAll"):
			repair.queue_free()
		else:
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
		var loads := HangarTrade.summary(GameState.hangar_snapshot())
		if totals.cargo > 0:
			lines.append("Cargo %d / %d" % [loads.cargo, totals.cargo])
		if totals.passengers > 0:
			lines.append("Passengers %d / %d" % [loads.passengers, totals.passengers])
		var fleet_stats := _resource_label("\n".join(lines))
		fleet_stats.name = "FleetTotals"
		fleet_stats.add_to_group("hull_readout")
		fleet_stats.add_to_group("transport_readout")
		details.add_child(fleet_stats)
		return
	if ship_editor_open:
		if stats_grid == null:
			return
		var slot: Dictionary = {}
		for candidate: Dictionary in owned.chassis.slots:
			if candidate.id == selected_slot and owned.mounts.has(selected_slot):
				slot = candidate
		# Keep existing mounts available for read-only equipment inspection.
		if ShipLoadouts.slot_by_id(owned.chassis, selected_slot).is_empty():
			selected_slot = ""
			canvas.selected_slot = ""
		stats_grid.visible = slot.is_empty()
		slot_info.visible = not slot.is_empty()
		slot_info.set_content("")
		if not slot.is_empty():
			var instance: Dictionary = owned.mounts.get(selected_slot, {})
			var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
			slot_info.set_content("%s\n%s %s\n%s" % [item.name, item.size, item.type.capitalize(), _part_effect(item)])
			if HangarTrade.has_load(instance):
				slot_info.set_content(slot_info.source_text + "\n%s %d / %d" % [str(instance.load.kind).capitalize(),
					instance.load.quantity, HangarTrade.CARGO_CAPACITY if instance.load.kind == "cargo" else HangarTrade.PASSENGER_CAPACITY])
			return
		stats_grid.set_ship(owned, false)
		return
	_clear(details)
	details.add_child(_label(owned.display_name))
	var bars := StatBars.new()
	bars.name = "ShipStatBars"
	bars.size_flags_vertical = SIZE_SHRINK_BEGIN
	details.add_child(bars)
	bars.set_ship(owned, false)
	var repair_rate: float = GameState.self_repair_rate(owned)
	if repair_rate > 0:
		var regen := _label("Self-repair %.2f hull/s" % repair_rate)
		regen.name = "SelfRepairRate"
		details.add_child(regen)
	if not selected_slot.is_empty():
		for slot: Dictionary in owned.chassis.slots:
			if slot.id == selected_slot:
				details.add_child(_label(SlotCatalog.slot_label(slot)))
		var instance: Dictionary = owned.mounts.get(selected_slot, {})
		if not instance.is_empty():
			var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
			details.add_child(_resource_label("%s\n%s %s\n%s" % [item.name, item.size, item.type.capitalize(), _part_effect(item)]))
			if item.id in HangarResearch.DEFERRED_PURCHASES:
				details.add_child(_label("Deferred"))
			if HangarTrade.has_load(instance):
				var contents: Dictionary = instance.load
				details.add_child(_label("%s %d" % [str(contents.kind).capitalize(), contents.quantity]))
	details.add_child(_button("REPAIR %d cr" % owned.repair_cost(), _repair_selected_ship))
	var repair := details.get_child(details.get_child_count() - 1) as Button
	_shipyard_action(repair, owned.needs_repair() and GameState.credits >= owned.repair_cost())
	if not owned.flagship:
		var salvage := _button("SALVAGE", func() -> void: _confirm_salvage(selected_ship_id))
		_shipyard_action(salvage)
		details.add_child(salvage)
	refit_panel = VBoxContainer.new()
	details.add_child(refit_panel)
	_render_refit_panel()
	for mount: Dictionary in owned.mounts.values():
		var item := SlotCatalog.find_equipment(mount.equipment_id, int(mount.rank))
		details.add_child(_resource_label("%s\n%s" % [item.name, _part_effect(item)]))
		if HangarTrade.has_load(mount):
			details.add_child(_label("%s %d" % [str(mount.load.kind).capitalize(), mount.load.quantity]))

func _select_ship(id: int, refresh_board := true) -> void:
	selected_squadron_id = 0
	selected_ship_id = id
	formation_selection.clear()
	if id > 0:
		formation_selection.append(id)
	selected_slot = ""
	ship_editor_open = false
	buy_open = false
	if refresh_board:
		_queue_refresh()
	else:
		_refresh_selection_panel()

func _select_squadron(id: int, refresh_board := true) -> void:
	var group := HangarSquadrons.find(GameState.squadrons, id)
	if group.is_empty():
		return
	selected_squadron_id = id
	buy_open = false
	selected_ship_id = int(group.members[0])
	formation_selection.assign(group.members)
	selected_slot = ""
	ship_editor_open = false
	if refresh_board:
		_queue_refresh()
	else:
		_refresh_selection_panel()

func _refresh_selection_panel() -> void:
	for option in roster.get_children():
		if option is Button and str(option.name).begins_with("Squadron_"):
			option.set_pressed_no_signal(str(option.name) == "Squadron_%d" % selected_squadron_id)
	_show_details()

func _show_squadron_details(group: Dictionary) -> void:
	_clear(details)
	if group.is_empty():
		return
	details.add_child(_label("%s #%d x%d" % [group.name, group.id, group.members.size()]))
	var members: Array[HangarShip] = []
	for id: int in group.members:
		members.append(GameState.owned_ship(id))
	var bars := StatBars.new()
	bars.name = "SquadronStatBars"
	details.add_child(bars)
	bars.set_squadron(members)
	for stance: String in HangarSquadrons.STANCES:
		var option := _button(HangarSquadrons.LABELS[stance],
			func() -> void: _result(GameState.set_squadron_stance(int(group.id), stance)))
		option.name = "Stance_" + stance
		option.toggle_mode = true
		option.button_pressed = group.stance == stance
		option.disabled = not GameState._can_refit()
		details.add_child(option)
	var loadout := ShipLoadouts.find(group.chassis, group.loadout)
	details.add_child(_label("Default loadout"))
	for choice: Dictionary in ShipLoadouts.available_for(group.chassis, GameState.current_research_ids):
		var option := _button(choice.name, func() -> void:
			_result(GameState.refit_squadron(int(group.id), choice.id)))
		option.name = "SquadronLoadout_" + str(choice.id)
		option.toggle_mode = true
		option.button_pressed = choice.id == group.loadout
		_shipyard_action(option, choice.id != group.loadout)
		details.add_child(option)
	if not group.overrides.is_empty():
		var reset := _button("Reset %d overrides" % group.overrides.size(),
			func() -> void: _result(GameState.refit_squadron(int(group.id), group.loadout, true)))
		reset.name = "ResetOverrides"
		_shipyard_action(reset, ShipLoadouts.available(loadout, GameState.current_research_ids))
		details.add_child(reset)
	var cost: int = GameState.squadron_repair_cost(int(group.id))
	var repair := _button("Repair %d cr" % cost,
		func() -> void: _result(GameState.repair_squadron(int(group.id))))
	repair.name = "SquadronRepair"
	_shipyard_action(repair, cost > 0 and GameState.credits >= cost)
	details.add_child(repair)
	var chassis := SlotCatalog.find_chassis(group.chassis)
	if not chassis.flagship:
		var quantity := HBoxContainer.new()
		quantity.name = "SquadronQuantity"
		details.add_child(quantity)
		var lower := _button("-", func() -> void:
			squadron_buy_count = maxi(1, squadron_buy_count - 1)
			_show_squadron_details(group))
		lower.name = "BuyFewer"
		lower.disabled = squadron_buy_count <= 1
		quantity.add_child(lower)
		var number := _label(str(squadron_buy_count))
		number.name = "BuyCount"
		number.size_flags_horizontal = SIZE_EXPAND_FILL
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		quantity.add_child(number)
		var upper := _button("+", func() -> void:
			squadron_buy_count += 1
			_show_squadron_details(group))
		upper.name = "BuyMore"
		upper.disabled = squadron_buy_count >= maxi(1, GameState.credits / maxi(1, ShipLoadouts.ship_price(group.chassis, loadout)))
		quantity.add_child(upper)
		var price := ShipLoadouts.ship_price(group.chassis, loadout) * squadron_buy_count
		var buy := _button("Buy %d / %d cr" % [squadron_buy_count, price],
			func() -> void: _result(GameState.buy_ships(group.chassis, squadron_buy_count, int(group.id))))
		buy.name = "SquadronBuy"
		_shipyard_action(buy, ShipLoadouts.available(loadout, GameState.current_research_ids) and GameState.credits >= price)
		details.add_child(buy)
	for id: int in group.members:
		var inspect := _button(GameState.owned_ship(id).display_name, _select_ship.bind(id))
		inspect.name = "SelectShip_%d" % id
		details.add_child(inspect)

func _render_squadron_assignment(owned: HangarShip) -> void:
	var current := HangarSquadrons.for_ship(GameState.squadrons, owned.id)
	refit_panel.add_child(_label("Squadron #%d%s" % [current.id,
		" / override" if owned.id in current.overrides else ""]))
	for group: Dictionary in GameState.squadrons:
		if group.id == current.id or group.chassis != owned.chassis_id:
			continue
		var move := _button("Join #%d" % group.id, func() -> void:
			_result(GameState.assign_squadron(owned.id, int(group.id))))
		move.name = "JoinSquadron_%d" % group.id
		move.disabled = not GameState._can_refit()
		refit_panel.add_child(move)
	if current.members.size() > 1:
		var split := _button("New squadron", func() -> void: _result(GameState.assign_squadron(owned.id)))
		split.name = "SplitSquadron"
		split.disabled = not GameState._can_refit()
		refit_panel.add_child(split)

func _part_effect(item: Dictionary) -> String:
	var modifiers: Dictionary = GameState.research_grants().modifiers
	match item.id:
		"research_lab": return "%s RP/day" % ScienceRules.format_rp(float(item.rank) * ResearchUpgrades.value(modifiers, "research_output_multiplier"))
		"cargo_hold": return "%d cargo" % HangarTrade.CARGO_CAPACITY
		"passenger_cabin": return "%d passengers" % HangarTrade.PASSENGER_CAPACITY
		"ammunition_magazine": return "+20% weapon cycling"
		"tactical_computer": return "Cooldown reset / %ss per computer\nWaits for unshielded target" % ScienceRules.format_rp(12.0 / ResearchUpgrades.value(modifiers, "synchronization_multiplier"))
		"command_uplink": return "Mark: +%d%% per uplink\n5s / 20s" % roundi((ResearchUpgrades.value(modifiers, "mark_damage_multiplier", 1.2) - 1) * 100)
		"repair_station": return "Repair %.0f hull/s\n%.0f hull reserve per encounter" % [SharedSupport.REPAIR_RATE, SharedSupport.REPAIR_RESERVE]
		"repair_drone_bay": return "%s hull/s shared per hangar\nSelf + allies | Range 220" % ScienceRules.format_rp(2.0 * ResearchUpgrades.value(modifiers, "repair_aura_multiplier"))
		"shield_relay": return "%s shields | %s/s after 4s\nTransfer: 2/s each | Range 180" % [ScienceRules.format_rp(float(item.stats.shields)), ScienceRules.format_rp(float(item.stats.shields) * 0.04)]
		"ion_emitter":
			var weapon: Dictionary = item.stats.weapons[0]
			var base_dps: float = float(weapon.damage) * float(weapon.count) / float(weapon.interval)
			return "Shield DPS %s | Hull DPS %s\nRange %s" % [ScienceRules.format_rp(base_dps * 2),
				ScienceRules.format_rp(base_dps * 0.5), ScienceRules.format_rp(float(weapon.range))]
		"nanoforge": return "Deferred"
	if item.id in HangarCarriers.CAPACITIES:
		return "%d craft / 2 active" % int(HangarCarriers.CAPACITIES[item.id])
	var values: Dictionary = item.stats
	var effects: PackedStringArray = []
	if "prismatic" in item.get("research_capabilities", []) and modifiers.has("prismatic_lasers"):
		effects.append("Continuous / 1x to 2x DPS over 4s")
	if "splitting_missile" in item.get("research_capabilities", []) and modifiers.has("splinter_missiles"):
		effects.append("Splits: 3 x half damage")
	if float(values.shields) > 0 and modifiers.has("pulse_shields"):
		effects.append("Pulse: 25% shields / 8s")
	if not values.weapons.is_empty():
		var dps := 0.0
		var reach := 0.0
		for weapon: ShipWeaponStats in SlotCatalog.stats_for(item.id, int(item.rank)).weapons:
			ResearchUpgrades.apply_weapon(weapon, modifiers)
			dps += weapon.get_dps()
			reach = maxf(reach, weapon.range_units)
		effects.append("DPS %.1f | Range %.0f" % [dps, reach])
		var missile_cost := 0
		var charge := 0.0
		for weapon: Dictionary in values.weapons:
			missile_cost += int(weapon.get("missiles", 0)) * int(weapon.count)
			charge = maxf(charge, float(weapon.get("charge", 0)))
		if missile_cost > 0:
			effects.append("%d missiles / salvo" % missile_cost)
		if charge > 0:
			effects.append("%ss charge" % ScienceRules.format_rp(charge))
	if values.shields > 0:
		effects.append("Shields %.0f | %.1f recharge/s after 4s" % [values.shields, values.shields * 0.04])
	if values.thrust > 0:
		effects.append("Thrust %.0f" % values.thrust)
	if values.integrity > 0:
		effects.append("Integrity +%.0f" % values.integrity)
	return " | ".join(effects)

func _result(ok: bool) -> void:
	feedback.text = "" if ok else (GameState.last_save_error if not GameState.last_save_error.is_empty() else "Unavailable")
	if is_instance_valid(editor_feedback):
		editor_feedback.text = feedback.text
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
	shop.z_index = UiKit.DIALOG_Z + 1 if ship_editor_open else 30
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

func _open_shop(mode := "SHIPS") -> void:
	if not GameState.can_use_shipyard():
		feedback.text = GameState.station_service_error("shipyard")
		return
	buy_open = not buy_open or buy_mode != mode
	buy_mode = mode
	_refresh()

func _show_buy_panel(_scroll_position := 0) -> void:
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
	var simulation = GameState.expedition_simulation
	var station: Dictionary = {} if simulation == null else simulation.locations.get(simulation.state.docked_location_id, {})
	var heading := _label("%s · Ships" % str(station.get("name", "Shipyard")))
	heading.name = "ShopHeading"
	heading.custom_minimum_size.y = 22
	column.add_child(heading)
	var close: TextureButton = load("res://scenes/close_x_button.tscn").instantiate()
	card.add_child(close)
	close.set_anchors_preset(PRESET_TOP_RIGHT)
	close.size_flags_horizontal = SIZE_SHRINK_END
	close.size_flags_vertical = SIZE_SHRINK_BEGIN
	AudioManager.connect_ui_button(close)
	close.pressed.connect(func() -> void:
		buy_open = false
		_refresh())
	shop_rows = GridContainer.new()
	shop_rows.name = "ShopItems"
	shop_rows.add_theme_constant_override("h_separation", 6)
	shop_rows.add_theme_constant_override("v_separation", 4)
	shop_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	column.add_child(shop_rows)
	_shop_ships()

# Each shipyard sells a fixed, seeded selection of its own stock; only as many
# cards as fit the panel are offered, so the shop never needs to scroll.
func _shop_capacity(card_height: float) -> Vector2i:
	var area := center.size - Vector2(shop.get_theme_stylebox("panel").get_minimum_size().x,
			shop.get_combined_minimum_size().y)
	var columns := clampi(floori(area.x / 220.0), 1, 3)
	var rows := maxi(1, floori((area.y + 4) / (card_height + 4)))
	return Vector2i(columns, rows)

func _station_stock(key: String, all_ids: Array) -> Array:
	var simulation = GameState.expedition_simulation
	var station: Dictionary = {} if simulation == null else simulation.locations.get(simulation.state.docked_location_id, {})
	var ids: Array = station.get(key, all_ids).duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d/shop/%s/%s" % [GameState.run_seed, str(station.get("id", "")), key])
	for index in range(ids.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held: Variant = ids[index]
		ids[index] = ids[swap]
		ids[swap] = held
	var featured: Array = station.get("featured", [])
	for index in range(featured.size() - 1, -1, -1):
		if featured[index] in ids:
			ids.erase(featured[index])
			ids.push_front(featured[index])
	return ids

func _shop_thumbnail(texture: Texture2D, lit: bool) -> TextureRect:
	var image := TextureRect.new()
	image.name = "ItemArt"
	image.texture = texture
	if lit:
		SurfaceArt.apply(image)
	image.custom_minimum_size = Vector2(34, 38)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return image

func _shop_ships() -> void:
	buy_mode = "SHIPS"
	_clear(shop_rows)
	var all_ids: Array = []
	for chassis in SlotCatalog.chassis():
		if not chassis.flagship:
			all_ids.append(chassis.id)
	var capacity := _shop_capacity(48)
	shop_rows.columns = capacity.x
	var shown := 0
	for id: Variant in _station_stock("chassis_stock", all_ids):
		if shown >= capacity.x * capacity.y:
			break
		var chassis := SlotCatalog.find_chassis(str(id))
		if chassis.is_empty() or chassis.flagship:
			continue
		var row := HBoxContainer.new()
		row.size_flags_horizontal = SIZE_EXPAND_FILL
		shop_rows.add_child(row)
		var image := _shop_thumbnail(SurfaceArt.texture(chassis.art), true)
		image.custom_minimum_size = Vector2(40, 48)
		row.add_child(image)
		var loadout := ShipLoadouts.purchase_for(chassis.id, GameState.current_research_ids)
		var price := ShipLoadouts.ship_price(chassis.id, loadout)
		if not ShipLoadouts.available(loadout, GameState.current_research_ids):
			row.queue_free()
			continue
		var available_to_buy := GameState.credits >= price
		var button := _shop_button(
			"%s (%s)" % [chassis.name, loadout.get("name", "")], "", price, true, available_to_buy,
			func() -> void:
				var ok := GameState.buy_ship(chassis.id, loadout.id)
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
		shown += 1
	if shown == 0:
		shop_rows.add_child(_label("No ships for sale"))

func _ship_tile_size() -> float:
	var scale: float = roster_panel.custom_minimum_size.x / roster_panel.art.get_width()
	var insets: Vector4 = roster_panel.source_padding
	var available := roster_panel.custom_minimum_size.x - ceilf(insets.x * scale) - ceilf(insets.z * scale) - 4
	return clampf(floorf(available * 0.5), 40, 72)

func _ship_tile(owned: HangarShip, tile_size: float) -> Button:
	var button := _button_with_sound("", func() -> void:
		selected_squadron_id = 0
		selected_ship_id = owned.id
		formation_selection.assign([owned.id])
		selected_slot = ""
		_refresh(), &"select_tab")
	button.name = "Ship%d" % owned.id
	button.toggle_mode = true
	button.button_pressed = owned.id == selected_ship_id
	button.custom_minimum_size = Vector2(tile_size, tile_size)
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.set_meta("ship_id", owned.id)
	var texture := SurfaceArt.diffuse(owned.art_texture)
	button.draw.connect(func() -> void:
		var inner := Rect2(Vector2(5, 4), button.size - Vector2(10, 14))
		var art_size := texture.get_size()
		var fit := minf(inner.size.x / art_size.x, inner.size.y / art_size.y)
		var drawn := art_size * fit
		button.draw_texture_rect(texture, Rect2(inner.position + (inner.size - drawn) * 0.5, drawn), false)
		if owned.flagship and flagship_icon != null:
			button.draw_texture_rect(flagship_icon, Rect2(Vector2(4, 3), Vector2(9, 9)), false)
		var bar := Rect2(Vector2(6, button.size.y - 8), Vector2(button.size.x - 12, 5))
		var ratio := clampf(owned.hull_hp / maxf(1.0, owned.hull_max), 0.0, 1.0)
		preload("res://scripts/integrity_bars.gd").draw_hull(button, bar, ratio))
	return button

func _open_ship_editor(id: int) -> void:
	if GameState.owned_ship(id) == null:
		return
	selected_squadron_id = 0
	selected_ship_id = id
	formation_selection.assign([id])
	selected_slot = ""
	active_tab = "FLEET"
	ship_editor_open = true
	buy_open = false
	_queue_refresh()

func _close_ship_editor() -> void:
	ship_editor_open = false
	selected_slot = ""
	_queue_refresh()

func _build_ship_editor() -> void:
	var owned: HangarShip = GameState.owned_ship(selected_ship_id)
	if owned == null:
		ship_editor_open = false
		return
	ship_editor = Control.new()
	ship_editor.name = "FleetShipEditor"
	ship_editor.add_to_group("modal_ui")
	ship_editor.z_index = UiKit.DIALOG_Z
	add_child(ship_editor)
	ship_editor.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	ship_editor.add_child(shade)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "ShipEditorPanel"
	panel.theme_type_variation = &"CompactPanel"
	ship_editor.add_child(panel)
	panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	panel.offset_left = 12
	panel.offset_top = 12
	panel.offset_right = -12
	panel.offset_bottom = -12
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := _label(owned.display_name)
	title.name = "ShipEditorTitle"
	column.add_child(title)
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(body)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(stack)
	canvas = load("res://scripts/hangar_canvas.gd").new()
	var view: Dictionary = fitting_views.get(owned.id, {})
	canvas.camera = view.get("camera", Vector2.ZERO)
	canvas.zoom = view.get("zoom", 1.0)
	canvas.auto_fit = view.is_empty()
	canvas.size_flags_vertical = SIZE_EXPAND_FILL
	stack.add_child(canvas)
	canvas.selected_slot = selected_slot
	canvas.set_owned(owned)
	var bottom := Control.new()
	bottom.name = "ShipOrPartDetails"
	bottom.custom_minimum_size.y = 96
	stack.add_child(bottom)
	slot_info = _resource_label("")
	bottom.add_child(slot_info)
	slot_info.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	stats_grid = StatBars.new()
	stats_grid.columns = 2 if size.x < 1000 else 4
	bottom.add_child(stats_grid)
	stats_grid.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.name = "ShipActions"
	scroll.custom_minimum_size.x = 180 if size.x < 1000 else 240
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var actions := VBoxContainer.new()
	actions.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(actions)
	refit_panel = VBoxContainer.new()
	refit_panel.name = "RefitPanel"
	actions.add_child(refit_panel)
	_render_refit_panel()
	var repair := _button("REPAIR %d cr" % owned.repair_cost(), _repair_selected_ship)
	repair.name = "ShipRepair"
	_shipyard_action(repair, owned.needs_repair() and GameState.credits >= owned.repair_cost())
	actions.add_child(repair)
	var repair_rate: float = GameState.self_repair_rate(owned)
	if repair_rate > 0:
		var regen := _label("Travel repair %.2f hull/s" % repair_rate)
		regen.name = "SelfRepairRate"
		actions.add_child(regen)
	if not owned.flagship:
		var salvage := _button("SALVAGE", func() -> void: _confirm_salvage(selected_ship_id))
		salvage.name = "ShipSalvage"
		_shipyard_action(salvage)
		actions.add_child(salvage)
	editor_feedback = _label("")
	editor_feedback.name = "ShipEditorFeedback"
	column.add_child(editor_feedback)
	panel.add_child(UiKit.close_button(_close_ship_editor))
	canvas.slot_selected.connect(func(key: String) -> void:
		_clear_inspection()
		selected_slot = key
		_show_details()
		_render_refit_panel())
	_show_details()

func _show_map() -> void:
	if GameState.expedition_simulation != null:
		_show_expedition_map()
		return
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
	for id: int in GameState.get_reachable_nodes(GameState.current_node_id):
		var preview: Dictionary = GameState.node_preview(id)
		roster.add_child(_button(preview.title, _select_destination.bind(id)))
	var problem: String = GameState.deployment_error()
	if not problem.is_empty():
		map_details.add_child(_label(problem))
	_map_event_details()
	map_details.add_child(_label(NodeEnvironment.description(GameState.node_environment(GameState.current_node_id))))

func _show_expedition_map() -> void:
	map_details = VBoxContainer.new()
	map_details.name = "MapDetails"
	map_details.size_flags_vertical = SIZE_EXPAND_FILL
	details.add_child(map_details)
	graph = load("res://scripts/expedition_map.gd").new()
	graph.name = "ExpeditionMap"
	center.add_child(graph)
	graph.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	if not map_camera.is_empty():
		graph.camera_position = map_camera.position
		graph.camera_zoom = map_camera.zoom
		graph.user_moved = true
	graph.selected_id = map_selected_id
	graph.location_selected.connect(func(id: String) -> void:
		map_selected_id = id
		_update_course_control()
		_render_map_details())
	graph.go_requested.connect(func(id: String) -> void: _set_course(id, true))
	_render_map_details()
	_render_voyage_summary()

func _render_voyage_summary() -> void:
	voyage_summary = _label("")
	voyage_summary.name = "VoyageSummary"
	voyage_summary.add_to_group("transport_readout")
	roster.add_child(voyage_summary)
	_update_voyage_summary()

func _update_voyage_summary() -> void:
	if not is_instance_valid(voyage_summary) or active_tab != "MAP":
		return
	var simulation = GameState.expedition_simulation
	var state = simulation.state
	var loads := HangarTrade.summary(GameState.hangar_snapshot())
	var lines: PackedStringArray = [
		"Cargo\n%d / %d" % [loads.cargo, loads.cargo_capacity],
		"Passengers\n%d / %d" % [loads.passengers, loads.passenger_capacity]]
	if state.flags.get("leviathan_protocol", false) and not GameState.completed:
		lines.append("")
		lines.append("Orders: clear the Bastion Gate")
	voyage_summary.text = "\n".join(lines)

func _render_map_details() -> void:
	if not is_instance_valid(map_details):
		return
	_clear(map_details)
	var simulation = GameState.expedition_simulation
	var location: Dictionary = simulation.locations.get(map_selected_id, {})
	if location.is_empty():
		if GameState.tutorials_enabled and not map_course_used \
				and simulation.state.traveled_distance_nu == 0 and simulation.state.destination_location_id.is_empty():
			map_details.add_child(_label("Select a destination, then GO TO."))
		return
	var state = simulation.state
	var title := _label(str(location.name).to_upper())
	title.theme_type_variation = &"HeaderResearch"
	map_details.add_child(title)
	if not str(location.get("description", "")).is_empty():
		map_details.add_child(_label(location.description))
	var distance: float = state.position_nu.distance_to(Vector2(location.position[0], location.position[1]))
	var cruise: float = GameState.expedition_cruise_rate()
	var lines: PackedStringArray = []
	if distance > 0.01:
		var fuel_needed: float = distance * GameState.expedition_fuel_rate()
		lines.append("%d NU away" % roundi(distance))
		lines.append("%d fuel%s" % [ceili(fuel_needed), " (out of range)" if fuel_needed > state.fuel else ""])
		lines.append("ETA %ds at 1x · %ds at 10x" % [ceili(distance / cruise), ceili(distance / cruise / 10.0)])
	var services: PackedStringArray = []
	for service: String in location.services:
		services.append(service.capitalize())
	if not services.is_empty() and distance > 0.01:
		lines.append(", ".join(services))
	if not simulation.location_accessible(location):
		lines.append("Locked")
	if not lines.is_empty():
		map_details.add_child(_label("\n".join(lines)))

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
		feedback.text = "Select a destination on the Map."
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
	map_details.add_child(_resource_label("%s RP on arrival" % ScienceRules.format_points(ScienceRules.journey_rp(ScienceRules.snapshot(GameState.get_deployed_fleet()), days))))
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
		feedback.text = "Select a destination on the Map."
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
	var error := _label("")
	error.name = "SalvageError"
	column.add_child(error)
	column.add_child(_button("SALVAGE", func() -> void:
		if GameState.salvage_hangar_ship(id):
			selected_ship_id = 0
			formation_selection.clear()
			_result(true)
		else:
			_result(false)
			error.text = GameState.last_save_error))
