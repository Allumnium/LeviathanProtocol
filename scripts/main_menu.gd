extends Control

const MAP_SCENE_PATH := "res://scenes/game_map.tscn"
const AUDIO_SETTINGS_DIALOG_SCRIPT := preload("res://scripts/audio_settings_dialog.gd")

var settings_dialog: PopupPanel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color.BLACK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center_container := CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center_container)

	var menu_buttons := VBoxContainer.new()
	menu_buttons.add_theme_constant_override("separation", 12)
	center_container.add_child(menu_buttons)

	var play_button := Button.new()
	play_button.text = "Play"
	play_button.custom_minimum_size = Vector2(180, 48)
	play_button.pressed.connect(_on_play_pressed)
	menu_buttons.add_child(play_button)

	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.custom_minimum_size = Vector2(180, 48)
	settings_button.pressed.connect(_on_settings_pressed)
	menu_buttons.add_child(settings_button)

	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.custom_minimum_size = Vector2(180, 48)
	quit_button.pressed.connect(_on_quit_pressed)
	menu_buttons.add_child(quit_button)

	settings_dialog = AUDIO_SETTINGS_DIALOG_SCRIPT.create_dialog()
	add_child(settings_dialog)


func _on_play_pressed() -> void:
	GameState.start_new_run()
	var error := get_tree().change_scene_to_file(MAP_SCENE_PATH)
	if error != OK:
		push_error("Could not open the game map scene. Error code: %s" % error)


func _on_settings_pressed() -> void:
	settings_dialog.popup_centered()


func _on_quit_pressed() -> void:
	get_tree().quit()
