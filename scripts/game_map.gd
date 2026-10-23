extends Control

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const AUTO_BATTLE_SCENE_PATH := "res://scenes/auto_battle.tscn"
const BUILD_TAB_INDEX := 1
const ARCHIVE_TAB_INDEX := 3
var shop := preload("res://scripts/fleet_shop.gd").new()

@onready var deploy_button: Button = $Layout/UpperArea/WorkspaceContents/PanelsRow/CenterPanel/PanelContents/DeployButton
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
@onready var settings_dialog: PopupPanel = $SettingsDialog
@onready var how_to_play_dialog: PopupPanel = $HowToPlayDialog
@onready var victory_dialog: Control = $VictoryDialog
@onready var victory_accept_button: Button = $VictoryDialog/CenterContainer/Panel/Contents/ButtonCenter/AcceptButton


func _ready() -> void:
	AudioManager.play_build_music()
	GameState.credits_changed.connect(_refresh_top_bar)
	GameState.fleet_changed.connect(_refresh_top_bar)
	_refresh_top_bar()
	GameState.unviewed_discoveries_changed.connect(_refresh_archive_unread_badge)
	GameState.part_transformations_changed.connect(_refresh_deploy_button)
	GameState.player_ship_count_changed.connect(_refresh_deploy_button)
	GameState.ship_stats_changed.connect(_refresh_ship_stats)
	_refresh_archive_unread_badge()
	_refresh_deploy_button()
	_refresh_ship_stats()
	$Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost.add_child(shop)
	shop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop.bind_fleet(panel_tabs.get_node("Fleet"))
	build_area.move_controls_to(build_controls)
	archive_tab.bind_external_panels(archive_progress_label, archive_details)
	_setup_panel_tabs()
	deploy_button.pressed.connect(_on_deploy_pressed)
	how_to_play_button.pressed.connect(_on_how_to_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	graph_view.destination_selected.connect(_on_destination_selected)
	graph_backdrop.gui_input.connect(_on_graph_modal_backdrop_input)
	victory_accept_button.pressed.connect(_on_victory_accepted)

	if GameState.current_node_id == GameState.FINAL_NODE_ID:
		victory_dialog.show()


func _setup_panel_tabs() -> void:
	var tab_button_group := ButtonGroup.new()
	tab_button_group.allow_unpress = false
	for index in range(panel_tab_buttons.size()):
		var button := panel_tab_buttons[index]
		button.button_group = tab_button_group
		button.pressed.connect(_on_panel_tab_button_pressed.bind(index))

	panel_tabs.tab_changed.connect(_on_panel_tab_changed)
	_on_panel_tab_changed(panel_tabs.current_tab)


func _on_panel_tab_button_pressed(tab_index: int) -> void:
	panel_tabs.current_tab = tab_index


func _on_panel_tab_changed(tab_index: int) -> void:
	deploy_button.visible = tab_index == 0
	shop.visible = tab_index == 0
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
	deploy_button.tooltip_text = "" if GameState.can_deploy() else "Construct an armed ship in Fleet."


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
	_add_stat_row("Weight", stats.weight, _format_stat_value(stats.weight))
	_add_stat_row("Cost", 0.0, "%d credits" % design.cost, false)
	_add_stat_row("Thrust", stats.thrust, _format_stat_value(stats.thrust))
	_add_stat_row("DPS", stats.dps, "%.2f" % stats.dps)

	for child in weapon_rows.get_children():
		if child == no_weapons_label:
			continue
		weapon_rows.remove_child(child)
		child.queue_free()

	no_weapons_label.visible = stats.weapons.is_empty()
	var grouped_weapons: Array[ShipWeaponStats] = []
	var weapon_counts: Array[int] = []
	for weapon in stats.weapons:
		var group_index := -1
		for index in range(grouped_weapons.size()):
			if grouped_weapons[index].weapon_name == weapon.weapon_name:
				group_index = index
				break
		if group_index < 0:
			grouped_weapons.append(weapon)
			weapon_counts.append(1)
		else:
			weapon_counts[group_index] = weapon_counts[group_index] + 1

	for group_index in range(grouped_weapons.size()):
		var weapon := grouped_weapons[group_index]
		var weapon_details: Array[String] = []
		var fire_rate := weapon.get_fire_rate_per_second()
		if not is_zero_approx(fire_rate):
			weapon_details.append("Fire rate: %.2f per sec" % fire_rate)
		if not is_zero_approx(weapon.damage_per_shot):
			weapon_details.append(
				"Damage per shot: %s" % _format_stat_value(weapon.damage_per_shot)
			)
		if weapon.projectiles_per_activation != 0:
			weapon_details.append(
				"Shots: %d" % weapon.projectiles_per_activation
			)
		var weapon_dps := weapon.get_dps()
		if not is_zero_approx(weapon_dps):
			var group_dps := weapon_dps * weapon_counts[group_index]
			weapon_details.append("DPS: %.2f (%.2f)" % [weapon_dps, group_dps])
		if weapon_details.is_empty():
			continue

		var weapon_label := Label.new()
		weapon_label.name = "WeaponGroup%d" % (group_index + 1)
		weapon_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		weapon_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		weapon_label.add_theme_font_size_override("font_size", 11)
		var weapon_display_name := weapon.weapon_name
		if weapon_counts[group_index] > 1:
			weapon_display_name += " (x%d)" % weapon_counts[group_index]
		weapon_label.text = "%s\n%s" % [
			weapon_display_name,
			"\n".join(weapon_details),
		]
		weapon_rows.add_child(weapon_label)


func _add_stat_row(
	stat_name: String,
	value: float,
	formatted_value: String,
	show_segments: bool = true
) -> void:
	if show_segments and is_zero_approx(value):
		return
	stat_rows.add_child(
		StatDisplayRow.new(stat_name, value, formatted_value, 12, show_segments)
	)


func _format_stat_value(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.2f" % value


func _on_destination_selected(node_id: int) -> void:
	if not GameState.set_destination(node_id):
		push_error("The selected destination is not reachable from the current room.")
		return
	graph_modal.hide()

	var error := get_tree().change_scene_to_file(AUTO_BATTLE_SCENE_PATH)
	if error != OK:
		GameState.cancel_battle()
		graph_modal.show()
		push_error("Could not open the auto-battle scene. Error code: %s" % error)


func _on_deploy_pressed() -> void:
	if deploy_button.disabled:
		return
	graph_view.set_current_node(GameState.current_node_id)
	graph_modal.show()


func _on_graph_modal_backdrop_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		graph_modal.hide()


func _unhandled_key_input(event: InputEvent) -> void:
	if not graph_modal.visible:
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
	$Layout/TopBar/BarContents/StatsSpace.text = "%d cr     Level %d\n%s" % [GameState.credits, GameState.campaign_level(), summary]
