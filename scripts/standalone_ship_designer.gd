extends Control

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const BUILD_TAB_INDEX := 0
const ARCHIVE_TAB_INDEX := 1

@onready var back_button: Button = $Layout/TopBar/BackButton
@onready var build_tab_button: Button = $Layout/Workspace/TabButtons/BuildTabButton
@onready var archive_tab_button: Button = $Layout/Workspace/TabButtons/ArchiveTabButton
@onready var archive_unread_badge: Label = $Layout/Workspace/TabButtons/ArchiveTabButton/UnreadCount
@onready var panel_tabs: TabContainer = $Layout/Workspace/Panels/CenterPanel/PanelContents/Tabs
@onready var build_controls: VBoxContainer = $Layout/Workspace/Panels/LeftPanel/PanelContents/BuildControls
@onready var archive_details: VBoxContainer = $Layout/Workspace/Panels/LeftPanel/PanelContents/ArchiveDetails
@onready var build_area: Control = $Layout/Workspace/Panels/CenterPanel/PanelContents/Tabs/Build/BuildTilemapArea
@onready var archive_tab: Control = $Layout/Workspace/Panels/CenterPanel/PanelContents/Tabs/Archive
@onready var stats_contents: VBoxContainer = $Layout/Workspace/Panels/RightPanel/ContentHost/StatsContents
@onready var stat_rows: VBoxContainer = $Layout/Workspace/Panels/RightPanel/ContentHost/StatsContents/StatRows
@onready var archive_progress: VBoxContainer = $Layout/Workspace/Panels/RightPanel/ContentHost/ArchiveProgress
@onready var archive_progress_label: Label = $Layout/Workspace/Panels/RightPanel/ContentHost/ArchiveProgress/DiscoveredLabel


func _ready() -> void:
	AudioManager.play_build_music()
	build_area.move_controls_to(build_controls)
	archive_tab.bind_external_panels(archive_progress_label, archive_details)
	var tab_group := ButtonGroup.new()
	tab_group.allow_unpress = false
	build_tab_button.button_group = tab_group
	archive_tab_button.button_group = tab_group
	build_tab_button.pressed.connect(_select_tab.bind(BUILD_TAB_INDEX))
	archive_tab_button.pressed.connect(_select_tab.bind(ARCHIVE_TAB_INDEX))
	panel_tabs.tab_changed.connect(_on_tab_changed)
	back_button.pressed.connect(_return_to_main_menu)
	GameState.ship_stats_changed.connect(_refresh_stats)
	GameState.part_transformations_changed.connect(_refresh_stats)
	GameState.unviewed_discoveries_changed.connect(_refresh_archive_unread_badge)
	_refresh_stats()
	_refresh_archive_unread_badge()
	_on_tab_changed(panel_tabs.current_tab)


func _select_tab(tab_index: int) -> void:
	panel_tabs.current_tab = tab_index


func _on_tab_changed(tab_index: int) -> void:
	var build_selected := tab_index == BUILD_TAB_INDEX
	build_controls.visible = build_selected
	stats_contents.visible = build_selected
	archive_details.visible = not build_selected
	archive_progress.visible = not build_selected
	build_tab_button.button_pressed = build_selected
	archive_tab_button.button_pressed = not build_selected
	if tab_index == ARCHIVE_TAB_INDEX:
		GameState.mark_discoveries_viewed()


func _refresh_archive_unread_badge() -> void:
	var unread_count := GameState.get_unviewed_discovery_count()
	archive_unread_badge.visible = unread_count > 0
	archive_unread_badge.text = str(unread_count)


func _refresh_stats() -> void:
	for child in stat_rows.get_children():
		child.queue_free()
	var stats := GameState.ship.get_stats()
	_add_stat("Shields", stats.shields)
	_add_stat("Integrity", stats.integrity)
	_add_stat("Thrust", stats.thrust)
	_add_stat("DPS", stats.dps, "%.2f" % stats.dps)
	_add_stat("Mass", stats.weight)
	_add_stat("Speed", stats.top_speed)


func _add_stat(name: String, value: float, formatted := "") -> void:
	if is_zero_approx(value):
		return
	var display_value: String = formatted
	if display_value.is_empty():
		display_value = str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.2f" % value
	stat_rows.add_child(StatDisplayRow.new(name, value, display_value, 11))


func _return_to_main_menu() -> void:
	var error := get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	if error != OK:
		push_error("Could not return to the main menu. Error code: %s" % error)
