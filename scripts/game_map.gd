extends Control

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const AUTO_BATTLE_SCENE_PATH := "res://scenes/auto_battle.tscn"

@onready var deploy_button: Button = $Layout/UpperArea/DetailsPanel/DetailsContents/DeployButton
@onready var how_to_play_button: Button = $Layout/TopBar/BarContents/HowToPlayButton
@onready var settings_button: Button = $Layout/TopBar/BarContents/SettingsButton
@onready var graph_modal: Control = $GraphModal
@onready var graph_backdrop: ColorRect = $GraphModal/Backdrop
@onready var graph_view: GraphView = $GraphModal/CenterContainer/GraphPanel/GraphView
@onready var settings_dialog: PopupPanel = $SettingsDialog
@onready var how_to_play_dialog: PopupPanel = $HowToPlayDialog
@onready var victory_dialog: Control = $VictoryDialog
@onready var victory_accept_button: Button = $VictoryDialog/CenterContainer/Panel/Contents/ButtonCenter/AcceptButton


func _ready() -> void:
	deploy_button.pressed.connect(_on_deploy_pressed)
	how_to_play_button.pressed.connect(_on_how_to_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	graph_view.destination_selected.connect(_on_destination_selected)
	graph_backdrop.gui_input.connect(_on_graph_modal_backdrop_input)
	victory_accept_button.pressed.connect(_on_victory_accepted)

	if GameState.current_node_id == GameState.FINAL_NODE_ID:
		victory_dialog.show()


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
