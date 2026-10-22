extends Control

const GAME_SETUP_SCENE_PATH := "res://scenes/game_setup.tscn"
const PLAY_TRANSITION_DURATION := 4.0
const GAME_TITLE_TEXT := "LEVIATHAN PROTOCOL"
const WARP_SFX: AudioStreamMP3 = preload("res://assets/audio/sfx/warp.mp3")

@onready var menu_ui: Control = $CenterContainer
@onready var play_button: Button = $CenterContainer/MenuButtons/PlayButton
@onready var settings_button: TextureButton = $SettingsButton
@onready var quit_button: Button = $CenterContainer/MenuButtons/QuitButton
@onready var settings_dialog: PopupPanel = $SettingsDialog
@onready var game_title: Label = $GameTitle
@onready var starfield: Control = $Starfield
@onready var white_fade: ColorRect = $WhiteFade

var _is_starting_run := false


func _ready() -> void:
	AudioManager.play_menu_music()
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	resized.connect(_fit_title)
	_fit_title()


func _on_play_pressed() -> void:
	if _is_starting_run:
		return

	_is_starting_run = true
	play_button.disabled = true
	settings_button.disabled = true
	quit_button.disabled = true
	menu_ui.hide()
	settings_button.hide()
	settings_dialog.hide()
	game_title.text = ""
	game_title.hide()
	white_fade.color = Color(1.0, 1.0, 1.0, 0.0)
	white_fade.show()
	AudioManager.play_sfx(WARP_SFX, WARP_SFX.get_length() / PLAY_TRANSITION_DURATION)

	var transition_tween := create_tween()
	transition_tween.set_parallel()
	transition_tween.tween_property(
		white_fade,
		"color",
		Color.WHITE,
		PLAY_TRANSITION_DURATION / 3.0
	).set_delay(PLAY_TRANSITION_DURATION * 2.0 / 3.0)
	transition_tween.tween_method(
		Callable(starfield, "set_warp_progress"),
		0.0,
		1.0,
		PLAY_TRANSITION_DURATION
	)
	await transition_tween.finished

	var error := get_tree().change_scene_to_file(GAME_SETUP_SCENE_PATH)
	if error != OK:
		push_error("Could not open the game setup scene. Error code: %s" % error)
		await _restore_menu_after_failed_transition()
		return


func _restore_menu_after_failed_transition() -> void:
	var restore_tween := create_tween()
	restore_tween.set_parallel()
	restore_tween.tween_property(
		white_fade,
		"color",
		Color(1.0, 1.0, 1.0, 0.0),
		0.5
	)
	restore_tween.tween_method(
		Callable(starfield, "set_warp_progress"),
		1.0,
		0.0,
		0.5
	)
	await restore_tween.finished

	white_fade.hide()
	menu_ui.show()
	settings_button.show()
	game_title.text = GAME_TITLE_TEXT
	game_title.show()
	play_button.disabled = false
	settings_button.disabled = false
	quit_button.disabled = false
	_is_starting_run = false


func _fit_title() -> void:
	var font := game_title.get_theme_font("font")
	var font_size := 28
	while font_size > 16 and font.get_string_size(GAME_TITLE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x * 0.78:
		font_size -= 1
	game_title.add_theme_font_size_override("font_size", font_size)


func _on_settings_pressed() -> void:
	settings_dialog.popup_centered()


func _on_quit_pressed() -> void:
	get_tree().quit()
