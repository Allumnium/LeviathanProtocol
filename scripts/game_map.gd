extends Control

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const AUTO_BATTLE_SCENE_PATH := "res://scenes/auto_battle.tscn"
const ARCHIVE_TAB_INDEX := 2

@onready var deploy_button: Button = $Layout/UpperArea/DetailsPanel/DetailsContents/DeployButton
@onready var how_to_play_button: Button = $Layout/TopBar/BarContents/HowToPlayButton
@onready var settings_button: Button = $Layout/TopBar/BarContents/SettingsButton
@onready var panel_tabs: TabContainer = $Layout/UpperArea/LeftPanel/PanelContents/Tabs
@onready var panel_tab_buttons: Array[Button] = [
	$Layout/UpperArea/LeftPanel/PanelContents/TabButtons/BuildTabButton,
	$Layout/UpperArea/LeftPanel/PanelContents/TabButtons/UpgradesTabButton,
	$Layout/UpperArea/LeftPanel/PanelContents/TabButtons/ArchiveTabButton,
]
@onready var archive_unread_badge: Label = (
	$Layout/UpperArea/LeftPanel/PanelContents/TabButtons/ArchiveTabButton/UnreadCount
)
@onready var graph_modal: Control = $GraphModal
@onready var graph_backdrop: ColorRect = $GraphModal/Backdrop
@onready var graph_view: GraphView = $GraphModal/CenterContainer/GraphPanel/GraphView
@onready var settings_dialog: PopupPanel = $SettingsDialog
@onready var how_to_play_dialog: PopupPanel = $HowToPlayDialog
@onready var victory_dialog: Control = $VictoryDialog
@onready var victory_accept_button: Button = $VictoryDialog/CenterContainer/Panel/Contents/ButtonCenter/AcceptButton


func _ready() -> void:
	GameState.unviewed_discoveries_changed.connect(_refresh_archive_unread_badge)
	GameState.part_transformations_changed.connect(_refresh_deploy_button)
	_refresh_archive_unread_badge()
	_refresh_deploy_button()
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
		_style_panel_tab_button(button)

	panel_tabs.tab_changed.connect(_on_panel_tab_changed)
	_on_panel_tab_changed(panel_tabs.current_tab)


func _style_panel_tab_button(button: Button) -> void:
	button.add_theme_stylebox_override(
		"normal",
		panel_tabs.get_theme_stylebox("tab_unselected", "TabContainer")
	)
	button.add_theme_stylebox_override(
		"hover",
		panel_tabs.get_theme_stylebox("tab_hovered", "TabContainer")
	)
	button.add_theme_stylebox_override(
		"pressed",
		panel_tabs.get_theme_stylebox("tab_selected", "TabContainer")
	)
	button.add_theme_stylebox_override(
		"disabled",
		panel_tabs.get_theme_stylebox("tab_disabled", "TabContainer")
	)
	button.add_theme_font_override("font", panel_tabs.get_theme_font("font", "TabContainer"))
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override(
		"font_color",
		panel_tabs.get_theme_color("font_unselected_color", "TabContainer")
	)
	button.add_theme_color_override(
		"font_hover_color",
		panel_tabs.get_theme_color("font_hovered_color", "TabContainer")
	)
	button.add_theme_color_override(
		"font_pressed_color",
		panel_tabs.get_theme_color("font_selected_color", "TabContainer")
	)
	button.add_theme_color_override(
		"font_disabled_color",
		panel_tabs.get_theme_color("font_disabled_color", "TabContainer")
	)


func _on_panel_tab_button_pressed(tab_index: int) -> void:
	panel_tabs.current_tab = tab_index


func _on_panel_tab_changed(tab_index: int) -> void:
	for index in range(panel_tab_buttons.size()):
		panel_tab_buttons[index].button_pressed = index == tab_index
	if tab_index == ARCHIVE_TAB_INDEX:
		GameState.mark_discoveries_viewed()


func _refresh_archive_unread_badge() -> void:
	var unread_count := GameState.get_unviewed_discovery_count()
	archive_unread_badge.visible = unread_count > 0
	archive_unread_badge.text = str(unread_count)


func _refresh_deploy_button() -> void:
	deploy_button.disabled = GameState.active_part_transformations > 0


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
	if GameState.active_part_transformations > 0:
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
