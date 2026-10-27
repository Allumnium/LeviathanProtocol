extends Control

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const AUTO_BATTLE_SCENE_PATH := "res://scenes/auto_battle.tscn"
const BUILD_TAB_INDEX := 1
const RESEARCH_TAB_INDEX := 2
const ARCHIVE_TAB_INDEX := 3
var fleet_controls := VBoxContainer.new()

@onready var fleet_right_panel: VBoxContainer = $Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost/FleetRightMargin/FleetRightPanel
@onready var fleet_summary: VBoxContainer = $Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost/FleetRightMargin/FleetRightPanel/FleetSummary
@onready var deploy_button: Button = $Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost/FleetRightMargin/FleetRightPanel/DeployCenter/DeployButton
@onready var stat_rows: VBoxContainer = (
	$Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost/DetailsContents/StatsScroll/StatsContents/StatRows
)
@onready var weapon_rows: VBoxContainer = (
	$Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost/DetailsContents/StatsScroll/StatsContents/WeaponRows
)
@onready var no_weapons_label: Label = (
	$Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost/DetailsContents/StatsScroll/StatsContents/WeaponRows/NoWeaponsLabel
)
@onready var how_to_play_button: TextureButton = $Layout/TopBar/BarContents/HowToPlayButton
@onready var settings_button: TextureButton = $Layout/TopBar/BarContents/SettingsButton
@onready var panel_tabs: TabContainer = $Layout/UpperArea/WorkspaceContents/PanelsRow/CenterPanel/PanelContents/Tabs
@onready var panel_tab_buttons: Array[Button] = [
	$Layout/UpperArea/WorkspaceContents/TabButtons/FleetTabButton,
	$Layout/UpperArea/WorkspaceContents/TabButtons/BuildTabButton,
	$Layout/UpperArea/WorkspaceContents/TabButtons/UpgradesTabButton,
	$Layout/UpperArea/WorkspaceContents/TabButtons/ArchiveTabButton,
]
@onready var archive_unread_badge: Label = (
	$Layout/UpperArea/WorkspaceContents/TabButtons/ArchiveTabButton/UnreadCount
)
@onready var archive_tab: Control = $Layout/UpperArea/WorkspaceContents/PanelsRow/CenterPanel/PanelContents/Tabs/Archive
@onready var build_area: Control = $Layout/UpperArea/WorkspaceContents/PanelsRow/CenterPanel/PanelContents/Tabs/Build/BuildTilemapArea
@onready var build_controls: VBoxContainer = $Layout/UpperArea/WorkspaceContents/PanelsRow/LeftPanel/PanelContents/BuildControls
@onready var archive_progress: VBoxContainer = $Layout/UpperArea/WorkspaceContents/PanelsRow/LeftPanel/PanelContents/ArchiveProgress
@onready var archive_progress_label: Label = $Layout/UpperArea/WorkspaceContents/PanelsRow/LeftPanel/PanelContents/ArchiveProgress/DiscoveredLabel
@onready var archive_details: VBoxContainer = $Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost/ArchiveDetails
@onready var graph_modal: Control = $GraphModal
@onready var graph_backdrop: ColorRect = $GraphModal/Backdrop
@onready var graph_view: GraphView = $GraphModal/CenterContainer/GraphPanel/GraphView
@onready var graph_close_button: TextureButton = $GraphModal/CenterContainer/GraphPanel/CloseX
@onready var settings_dialog: PopupPanel = $SettingsDialog
@onready var how_to_play_dialog: PopupPanel = $HowToPlayDialog
@onready var victory_dialog: Control = $VictoryDialog
@onready var victory_accept_button: Button = $VictoryDialog/CenterContainer/Panel/Contents/ButtonCenter/AcceptButton
@onready var victory_close_button: TextureButton = $VictoryDialog/CenterContainer/Panel/CloseX
@onready var map_button: Button = $Layout/TopBar/BarContents/MapButton
@onready var sector_name_label: Label = $Layout/TopBar/BarContents/SectorName

var _graph_map_only := false
var _travel_in_progress := false
var route_preview: Label
var route_travel_button: Button
var campaign_overlay: PanelContainer
var port_button: Button
var story_button: Button
var research_groups: VBoxContainer
var research_details: VBoxContainer


func _ready() -> void:
	AudioManager.play_build_music()
	GameState.credits_changed.connect(_refresh_top_bar)
	GameState.tile_inventory_changed.connect(_refresh_top_bar)
	GameState.tile_inventory_changed.connect(_refresh_ship_stats)
	GameState.fleet_changed.connect(_refresh_top_bar)
	GameState.fleet_changed.connect(_refresh_deploy_button)
	_refresh_top_bar()
	GameState.unviewed_discoveries_changed.connect(_refresh_archive_unread_badge)
	GameState.part_transformations_changed.connect(_refresh_deploy_button)
	GameState.player_ship_count_changed.connect(_refresh_deploy_button)
	GameState.ship_stats_changed.connect(_refresh_ship_stats)
	_refresh_archive_unread_badge()
	_refresh_deploy_button()
	_refresh_ship_stats()
	var fleet_panel: Control = panel_tabs.get_node("Fleet")
	fleet_controls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fleet_controls.add_theme_constant_override("separation", 5)
	$Layout/UpperArea/WorkspaceContents/PanelsRow/LeftPanel/PanelContents.add_child(fleet_controls)
	fleet_panel.bind_external_panels(fleet_controls, fleet_summary)
	if GameState.campaign_active:
		research_groups = VBoxContainer.new()
		research_details = VBoxContainer.new()
		research_groups.size_flags_vertical = Control.SIZE_EXPAND_FILL
		research_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
		$Layout/UpperArea/WorkspaceContents/PanelsRow/LeftPanel/PanelContents.add_child(research_groups)
		$Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost.add_child(research_details)
		research_details.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		research_details.offset_left = 6
		research_details.offset_top = 4
		research_details.offset_right = -6
		research_details.offset_bottom = -4
		panel_tabs.get_node("Upgrades").grouped_view.bind_external_panels(research_groups, research_details)
		panel_tabs.get_node("Upgrades").grouped_view.set_external_panels_visible(panel_tabs.current_tab == RESEARCH_TAB_INDEX)
	build_area.move_controls_to(build_controls)
	archive_details.reparent(
		$Layout/UpperArea/WorkspaceContents/PanelsRow/LeftPanel/PanelContents
	)
	archive_details.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	archive_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	archive_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	archive_progress.reparent(
		$Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost
	)
	archive_progress.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	archive_tab.bind_external_panels(archive_progress_label, archive_details)
	_setup_panel_tabs()
	deploy_button.pressed.connect(_on_deploy_pressed)
	how_to_play_button.pressed.connect(_on_how_to_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	map_button.pressed.connect(_on_map_pressed)
	graph_view.destination_selected.connect(_on_destination_selected)
	graph_backdrop.gui_input.connect(_on_graph_modal_backdrop_input)
	graph_close_button.pressed.connect(graph_modal.hide)
	victory_accept_button.pressed.connect(_on_victory_accepted)
	victory_close_button.pressed.connect(_on_victory_accepted)
	if GameState.campaign_active:
		_setup_campaign_controls()

	if GameState.current_node_id == GameState.FINAL_NODE_ID:
		if not GameState.campaign_active:
			victory_dialog.show()


func _setup_panel_tabs() -> void:
	var tab_button_group := ButtonGroup.new()
	tab_button_group.allow_unpress = false
	for index in range(panel_tab_buttons.size()):
		var button := panel_tab_buttons[index]
		button.button_group = tab_button_group
		button.pressed.connect(_on_panel_tab_button_pressed.bind(index))
	var shipyard_available := GameState.is_shipyard_node(GameState.current_node_id)
	panel_tab_buttons[BUILD_TAB_INDEX].disabled = not shipyard_available
	panel_tab_buttons[BUILD_TAB_INDEX].get_node("Lock").visible = not shipyard_available
	panel_tab_buttons[RESEARCH_TAB_INDEX].disabled = false

	panel_tabs.tab_changed.connect(_on_panel_tab_changed)
	_on_panel_tab_changed(panel_tabs.current_tab)


func _on_panel_tab_button_pressed(tab_index: int) -> void:
	panel_tabs.current_tab = tab_index


func _on_panel_tab_changed(tab_index: int) -> void:
	if GameState.campaign_active and research_groups != null:
		panel_tabs.get_node("Upgrades").grouped_view.set_external_panels_visible(tab_index == RESEARCH_TAB_INDEX)
	fleet_right_panel.visible = tab_index == 0
	panel_tabs.get_node("Fleet").set_external_panels_visible(tab_index == 0)
	build_controls.visible = tab_index == BUILD_TAB_INDEX
	archive_progress.visible = tab_index == ARCHIVE_TAB_INDEX
	archive_details.visible = tab_index == ARCHIVE_TAB_INDEX
	$Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost/DetailsContents.visible = tab_index == BUILD_TAB_INDEX
	_refresh_ship_stats()
	for index in range(panel_tab_buttons.size()):
		panel_tab_buttons[index].button_pressed = index == tab_index
	if tab_index == ARCHIVE_TAB_INDEX:
		GameState.mark_discoveries_viewed()


func _refresh_archive_unread_badge() -> void:
	var unread_count := GameState.get_unviewed_discovery_count()
	archive_unread_badge.visible = unread_count > 0
	archive_unread_badge.text = str(unread_count)


func _refresh_deploy_button() -> void:
	deploy_button.disabled = not GameState.can_deploy()
	deploy_button.tooltip_text = GameState.deployment_error()


func _refresh_ship_stats() -> void:
	_refresh_deploy_button()
	var design := GameState.ship
	if panel_tabs.current_tab == 0:
		var selected: Ship = panel_tabs.get_node("Fleet").selected_design
		design = selected if selected != null else Ship.new()
	var stats := design.get_stats(GameState.laser_upgrade_level, GameState.energy_efficiency())

	for child in stat_rows.get_children():
		stat_rows.remove_child(child)
		child.queue_free()

	_add_stat_row("Shields", stats.shields, _format_stat_value(stats.shields))
	_add_stat_row("Integrity", stats.integrity, _format_stat_value(stats.integrity))
	_add_stat_row("Thrust", stats.thrust, _format_stat_value(stats.thrust))
	_add_stat_row("DPS", stats.dps, "%.2f" % stats.dps)
	_add_stat_row("Mass", stats.weight, _format_stat_value(stats.weight))
	_add_stat_row("Speed", stats.top_speed, _format_stat_value(stats.top_speed))



func _add_stat_row(
	stat_name: String,
	value: float,
	formatted_value: String,
	show_segments: bool = true,
	value_icon: Texture2D = null
) -> void:
	if show_segments and is_zero_approx(value):
		return
	stat_rows.add_child(
		StatDisplayRow.new(stat_name, value, formatted_value, 12, show_segments, value_icon)
	)


func _format_stat_value(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.2f" % value


func _on_destination_selected(node_id: int) -> void:
	if _travel_in_progress:
		return
	if not GameState.set_planned_destination(node_id):
		push_error("The selected destination is not reachable from the current room.")
		return
	graph_view.selected_node_id = node_id
	graph_view.queue_redraw()
	if GameState.campaign_active:
		_show_route_preview(node_id)


func _on_deploy_pressed() -> void:
	if deploy_button.disabled:
		return
	var destinations := GameState.get_reachable_nodes(GameState.current_node_id)
	var chosen_destination := GameState.planned_destination_node_id
	if destinations.size() == 1 or destinations.has(chosen_destination):
		if destinations.size() == 1:
			chosen_destination = destinations[0]
		if GameState.campaign_active:
			_travel_campaign(chosen_destination)
			return
		if GameState.set_destination(chosen_destination):
			_open_pending_battle(false)
		else:
			push_error("The selected sector could not be deployed to.")
		return
	_graph_map_only = false
	graph_view.set_current_node(GameState.current_node_id)
	graph_modal.show()


func _on_map_pressed() -> void:
	_graph_map_only = false
	graph_view.set_current_node(GameState.current_node_id)
	graph_modal.show()


func _open_pending_battle(restore_map_on_failure: bool) -> void:
	var error := get_tree().change_scene_to_file(AUTO_BATTLE_SCENE_PATH)
	if error == OK:
		return
	GameState.cancel_battle()
	if restore_map_on_failure:
		graph_modal.show()
	push_error("Could not open the auto-battle scene. Error code: %s" % error)


func _on_graph_modal_backdrop_input(event: InputEvent) -> void:
	if _travel_in_progress:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		graph_modal.hide()


func _unhandled_key_input(event: InputEvent) -> void:
	if not graph_modal.visible or _travel_in_progress:
		return

	var key_event := event as InputEventKey
	if key_event == null:
		return
	if not key_event.pressed or key_event.echo or key_event.keycode != KEY_ESCAPE:
		return

	graph_modal.hide()
	get_viewport().set_input_as_handled()


func _on_settings_pressed() -> void:
	settings_dialog.popup_centered()


func _on_how_to_play_pressed() -> void:
	how_to_play_dialog.popup_centered()


func _on_victory_accepted() -> void:
	victory_dialog.hide()
	call_deferred("_return_to_main_menu")


func _return_to_main_menu() -> void:
	var error := get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	if error != OK:
		push_error("Could not return to the main menu. Error code: %s" % error)


func _refresh_top_bar() -> void:
	var health := 0.0
	var maximum := 0.0
	var damaged := 0
	for owned in GameState.fleet:
		if owned.needs_repair():
			damaged += 1
		for unit in owned.units:
			health += unit.hp
			maximum += unit.max_hp
	var summary := "%d %s" % [GameState.fleet.size(), "ship" if GameState.fleet.size() == 1 else "ships"]
	if maximum > 0.0:
		summary += " · %d%% hull · %d damaged" % [roundi(health / maximum * 100.0), damaged]
	$Layout/TopBar/BarContents/CreditAmount.text = str(GameState.credits)
	$Layout/TopBar/BarContents/OffenseAmount.text = str(GameState.red_tiles_available)
	$Layout/TopBar/BarContents/DefenseAmount.text = str(GameState.blue_tiles_available)
	$Layout/TopBar/BarContents/TechAmount.text = str(GameState.green_tiles_available)
	$Layout/TopBar/BarContents/CivicAmount.text = str(GameState.core_tiles_available)
	sector_name_label.text = "SECTOR %d" % (GameState.current_node_id + 1)
	if GameState.campaign_active:
		var node := GameState.campaign_node(GameState.current_node_id)
		var row := int(node.get("local_row", 0)) if int(node.get("act", 0)) == GameState.current_act() else 0
		sector_name_label.text = "ACT %d / ROW %d" % [GameState.current_act(), row]
	$Layout/TopBar/BarContents/StatsSpace.text = "Level %d\n%s" % [GameState.campaign_level(), summary]


func _setup_campaign_controls() -> void:
	port_button = Button.new()
	port_button.text = "PORT SERVICES"
	port_button.disabled = GameState.port_services().is_empty()
	port_button.add_theme_font_size_override("font_size", 10)
	port_button.add_theme_font_override("font", ThemeDB.fallback_font)
	port_button.pressed.connect(_show_port_services)
	fleet_controls.add_child(port_button)
	story_button = Button.new()
	story_button.text = "STORY ARCHIVE"
	story_button.add_theme_font_size_override("font_size", 10)
	story_button.add_theme_font_override("font", ThemeDB.fallback_font)
	story_button.pressed.connect(func() -> void: _show_story(false))
	fleet_controls.add_child(story_button)
	var panel := PanelContainer.new()
	panel.name = "RoutePreview"
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.07, 0.10, 0.14, 0.98)
	background.content_margin_left = 6
	background.content_margin_right = 6
	background.content_margin_top = 4
	background.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", background)
	graph_view.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -120
	panel.offset_left = 5
	panel.offset_right = -5
	panel.offset_bottom = -5
	var contents := VBoxContainer.new()
	panel.add_child(contents)
	var legend := Label.new()
	legend.text = "Circle: Patrol | Diamond: Elite/Boss | Square: Port\nTriangle: Salvage | + Signal | Dot: Survey | Green: cleared | Amber: charted"
	legend.add_theme_font_size_override("font_size", 8)
	legend.add_theme_font_override("font", ThemeDB.fallback_font)
	contents.add_child(legend)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 52
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(scroll)
	route_preview = Label.new()
	route_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	route_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	route_preview.add_theme_font_size_override("font_size", 10)
	route_preview.add_theme_font_override("font", ThemeDB.fallback_font)
	scroll.add_child(route_preview)
	route_travel_button = Button.new()
	route_travel_button.text = "SELECT A REACHABLE DESTINATION"
	route_travel_button.disabled = true
	route_travel_button.add_theme_font_size_override("font_size", 10)
	route_travel_button.add_theme_font_override("font", ThemeDB.fallback_font)
	preload("res://scripts/fleet_panel.gd").compact_button(route_travel_button)
	route_travel_button.add_theme_font_override("font", ThemeDB.fallback_font)
	route_travel_button.pressed.connect(_on_deploy_pressed)
	contents.add_child(route_travel_button)
	graph_view.node_inspected.connect(_show_route_preview)
	_show_route_preview(GameState.current_node_id)
	call_deferred("_show_unread_story")


func _show_route_preview(node_id: int) -> void:
	if route_preview == null:
		return
	var preview := GameState.node_preview(node_id)
	route_preview.text = preview.title + "\n" + preview.text
	var reachable := GameState.get_reachable_nodes(GameState.current_node_id).has(node_id)
	route_travel_button.disabled = not reachable or _travel_in_progress
	route_travel_button.text = "TRAVEL TO " + str(preview.title).to_upper() if reachable else "INSPECTING " + str(preview.title).to_upper()
	# Inspection alone cannot silently change the chosen destination.
	if reachable:
		GameState.set_planned_destination(node_id)
		graph_view.selected_node_id = node_id
		graph_view.queue_redraw()


func _travel_campaign(node_id: int) -> void:
	if _travel_in_progress:
		return
	_travel_in_progress = true
	route_travel_button.disabled = true
	graph_modal.show()
	graph_view.start_travel(node_id, 0.4)
	await graph_view.travel_finished
	if not GameState.travel_to(node_id):
		_travel_in_progress = false
		_show_route_preview(node_id)
		return
	if GameState.battle_pending:
		_open_pending_battle(true)
	else:
		get_tree().change_scene_to_file("res://scenes/game_map.tscn")


func _campaign_dialog(title: String, body: String, close_action: Callable = Callable()) -> void:
	if is_instance_valid(campaign_overlay):
		campaign_overlay.queue_free()
	campaign_overlay = PanelContainer.new()
	campaign_overlay.name = "CampaignDialog"
	campaign_overlay.add_to_group("modal_ui")
	campaign_overlay.z_index = 25
	add_child(campaign_overlay)
	campaign_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	campaign_overlay.offset_left = 28
	campaign_overlay.offset_top = 28
	campaign_overlay.offset_right = -28
	campaign_overlay.offset_bottom = -28
	var box := VBoxContainer.new()
	campaign_overlay.add_child(box)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_font_override("font", ThemeDB.fallback_font)
	box.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var text := Label.new()
	text.text = body
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("font_size", 12)
	text.add_theme_font_override("font", ThemeDB.fallback_font)
	scroll.add_child(text)
	var close := Button.new()
	close.name = "Close"
	close.text = "CLOSE / SKIP"
	close.add_theme_font_size_override("font_size", 12)
	close.add_theme_font_override("font", ThemeDB.fallback_font)
	box.add_child(close)
	var overlay := campaign_overlay
	close.pressed.connect(func() -> void:
		if close_action.is_valid():
			close_action.call()
		overlay.queue_free())


func _show_port_services() -> void:
	var port := GameState.port_services()
	if port.is_empty():
		return
	_campaign_dialog(port.name, "Repair damaged ships in Fleet. Refit and construct in Build; buy materials in Upgrades.\n\n%s goods: %d credits/unit at origin.\nNo operational passenger accommodation or cargo holds aboard.\n\nPort services can be reopened freely; opening this screen grants no arrival income." % [port.goods_grade, int(port.goods_unit_value)])


func _show_unread_story() -> void:
	_show_story(true)


func _show_story(unread_only: bool) -> void:
	var body := ""
	var ids: Array[String] = []
	for entry in GameState.story_archive():
		if unread_only and GameState.story_flags.get("seen/" + entry.id, false):
			continue
		body += entry.title + "\n" + entry.text + "\n\n"
		ids.append(entry.id)
	if body.is_empty():
		if unread_only and GameState.current_node_id == GameState.FINAL_NODE_ID:
			victory_dialog.show()
		return
	_campaign_dialog("STORY ARCHIVE", body, func() -> void:
		GameState.mark_story_seen(ids)
		if GameState.current_node_id == GameState.FINAL_NODE_ID:
			victory_dialog.show())
