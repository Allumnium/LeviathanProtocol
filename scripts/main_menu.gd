extends Control

const MAP_SCENE_PATH := "res://scenes/game_map.tscn"

@onready var play_button: Button = $CenterContainer/MenuButtons/PlayButton
@onready var settings_button: Button = $CenterContainer/MenuButtons/SettingsButton
@onready var quit_button: Button = $CenterContainer/MenuButtons/QuitButton
@onready var settings_dialog: PopupPanel = $SettingsDialog


func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _on_play_pressed() -> void:
	GameState.start_new_run()
	var error := get_tree().change_scene_to_file(MAP_SCENE_PATH)
	if error != OK:
		push_error("Could not open the game map scene. Error code: %s" % error)


func _on_settings_pressed() -> void:
	settings_dialog.popup_centered()


func _on_quit_pressed() -> void:
	get_tree().quit()
