extends Control

const GAME_MAP_SCENE_PATH := "res://scenes/game_map.tscn"
const PLAY_TRANSITION_DURATION := 4.0
const GAME_TITLE_TEXT := "Leviathan Protocol"
const WARP_SFX: AudioStreamMP3 = preload("res://assets/audio/sfx/warp.mp3")

@onready var menu_ui: Control = $CenterContainer
@onready var play_button: Button = $CenterContainer/MenuButtons/PlayButton
@onready var settings_button: TextureButton = $SettingsButton
@onready var quit_button: Button = $CenterContainer/MenuButtons/QuitButton
@onready var settings_dialog: PopupPanel = $SettingsDialog
@onready var game_title: Label = $GameTitle
@onready var starfield: Control = $Starfield
@onready var white_fade: ColorRect = $WhiteFade
@onready var game_setup = $GameSetup

var _is_starting_run := false
var continue_button: Button
var status_label: Label


func _ready() -> void:
	play_button.text = "NEW RUN"
	continue_button = Button.new()
	continue_button.name = "ContinueButton"
	continue_button.text = "CONTINUE"
	continue_button.custom_minimum_size = Vector2(180, 40)
	play_button.get_parent().add_child(continue_button)
	play_button.get_parent().move_child(continue_button, 0)
	continue_button.pressed.connect(_on_continue_pressed)
	status_label = Label.new()
	status_label.name = "CheckpointStatus"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.custom_minimum_size.x = 260
	status_label.add_theme_color_override("font_color", Color("ffd28a"))
	play_button.get_parent().add_child(status_label)
	status_label.hide()
	var summary := GameState.checkpoint_summary()
	continue_button.visible = not summary.is_empty()
	if summary.is_empty() and ["", ".next", ".bak"].any(func(suffix: String) -> bool: return FileAccess.file_exists(GameState.run_save_path + suffix)):
		status_label.text = "No recoverable checkpoint was found. Older saves are kept separately."
		status_label.show()
	continue_button.disabled = summary.get("ended", false)
	if continue_button.disabled:
		status_label.text = "This run has ended. Start a new run."
		status_label.show()
	AudioManager.play_menu_music()
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	game_setup.back_requested.connect(_on_setup_back_requested)
	game_setup.start_requested.connect(_on_start_run_requested)
	resized.connect(_fit_title)
	_fit_title()


func _on_continue_pressed() -> void:
	if _is_starting_run:
		return
	_is_starting_run = true
	continue_button.disabled = true
	if not GameState.load_run_checkpoint() or not GameState.prepare_checkpoint_resume():
		status_label.text = "Could not resume: " + GameState.last_save_error
		status_label.show()
		continue_button.disabled = false
		_is_starting_run = false
		return
	if GameState.run_ended:
		status_label.text = "All ships were lost. Start a new run."
		status_label.show()
		_is_starting_run = false
		return
	var path := "res://scenes/auto_battle.tscn" if GameState.battle_pending else GAME_MAP_SCENE_PATH
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		status_label.text = "Could not open the saved run. Please try again."
		status_label.show()
		continue_button.disabled = false
		_is_starting_run = false


func _on_play_pressed() -> void:
	if _is_starting_run:
		return
	menu_ui.hide()
	settings_button.hide()
	settings_dialog.hide()
	game_setup.show()
	var warning: Label = game_setup.get_node("CenterContainer/SetupModal/Contents/CheckpointWarning")
	warning.visible = continue_button.visible


func _on_setup_back_requested() -> void:
	game_setup.hide()
	menu_ui.show()
	settings_button.show()


func _on_start_run_requested(difficulty: int) -> void:
	if _is_starting_run or not GameState.start_new_run(difficulty):
		return

	_is_starting_run = true
	game_setup.hide()
	if GameState.reduced_motion:
		get_tree().change_scene_to_file(GAME_MAP_SCENE_PATH)
		return
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

	var error := get_tree().change_scene_to_file(GAME_MAP_SCENE_PATH)
	if error != OK:
		push_error("Could not open the game map scene. Error code: %s" % error)
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
	var font_size := theme.get_font_size("font_size", &"GameTitle")
	while font_size > 16 and font.get_string_size(GAME_TITLE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x * 0.78:
		font_size -= 1
	game_title.add_theme_font_size_override("font_size", font_size)


func _on_settings_pressed() -> void:
	settings_dialog.popup_centered()


func _on_quit_pressed() -> void:
	get_tree().quit()
