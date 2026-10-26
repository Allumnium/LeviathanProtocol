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


func _ready() -> void:
	AudioManager.play_build_music()
	GameState.credits_changed.connect(_refresh_top_bar)
	GameState.tile_inventory_changed.connect(_refresh_top_bar)
	GameState.tile_inventory_changed.connect(_refresh_ship_stats)
	GameState.fleet_changed.connect(_refresh_top_bar)
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

	if GameState.current_node_id == GameState.FINAL_NODE_ID:
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


func _refresh_ship_stats() -> void:
	_refresh_deploy_button()
	var design := GameState.ship
	if panel_tabs.current_tab == 0:
		var selected: Ship = panel_tabs.get_node("Fleet").selected_design
		design = selected if selected != null else Ship.new()
	var stats := design.get_stats()

	for child in stat_rows.get_children():
		stat_rows.remove_child(child)
		child.queue_free()

	_add_stat_row("Shields", stats.shields, _format_stat_value(stats.shields))
	_add_stat_row("Integrity", stats.integrity, _format_stat_value(stats.integrity))
	_add_stat_row("Thrust", stats.thrust, _format_stat_value(stats.thrust))
	_add_stat_row("DPS", stats.dps, "%.2f" % stats.dps)



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


func _on_deploy_pressed() -> void:
	if deploy_button.disabled:
		return
	var destinations := GameState.get_reachable_nodes(GameState.current_node_id)
	var chosen_destination := GameState.planned_destination_node_id
	if destinations.size() == 1 or destinations.has(chosen_destination):
		if destinations.size() == 1:
			chosen_destination = destinations[0]
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
		if owned.repair_cost() > 0:
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
	$Layout/TopBar/BarContents/StatsSpace.text = "Level %d\n%s" % [GameState.campaign_level(), summary]
