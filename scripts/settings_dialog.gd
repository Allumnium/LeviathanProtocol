extends PopupPanel

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
var settings_status: Label

@onready var music_slider: HSlider = $Contents/ContentArea/MusicRow/MusicSlider
@onready var ambience_slider: HSlider = $Contents/ContentArea/AmbienceRow/AmbienceSlider
@onready var effects_slider: HSlider = $Contents/ContentArea/EffectsRow/EffectsSlider
@onready var battle_auto_pan_button: TextureButton = $Contents/ContentArea/BattleAutoPanRow/BattleAutoPanButton
@onready var battle_auto_zoom_button: TextureButton = $Contents/ContentArea/BattleAutoZoomRow/BattleAutoZoomButton
@onready var tutorials_button: TextureButton = $Contents/ContentArea/TutorialsRow/TutorialsButton
@onready var quit_to_menu_button: Button = $Contents/ContentArea/QuitToMenuButton
@onready var quit_confirmation_overlay: Control = $QuitConfirmOverlay
@onready var quit_confirmation_button: Button = (
	$QuitConfirmOverlay/CenterContainer/ConfirmationPanel/Contents/ConfirmationButtons/QuitButton
)
@onready var cancel_quit_button: TextureButton = (
	$QuitConfirmOverlay/CenterContainer/ConfirmationPanel/CloseX
)


func _ready() -> void:
	for button: TextureButton in [battle_auto_pan_button, battle_auto_zoom_button, tutorials_button]:
		button.texture_normal = button.get_theme_icon("off", "SettingsSwitch")
		button.texture_pressed = button.get_theme_icon("on", "SettingsSwitch")
	tutorials_button.set_pressed_no_signal(GameState.tutorials_enabled)
	about_to_popup.connect(_refresh_context)
	music_slider.value = AudioManager.get_bus_volume_percent(AudioManager.MUSIC_BUS)
	ambience_slider.value = AudioManager.get_bus_volume_percent(AudioManager.AMBIENCE_BUS)
	effects_slider.value = AudioManager.get_bus_volume_percent(AudioManager.SFX_BUS)
	_update_camera_buttons()
	for button: BaseButton in [
		battle_auto_pan_button,
		battle_auto_zoom_button,
		tutorials_button,
		quit_to_menu_button,
		quit_confirmation_button,
		cancel_quit_button,
	]:
		AudioManager.connect_ui_button(button, &"detail" if button in [battle_auto_pan_button, battle_auto_zoom_button, tutorials_button] else &"accept")
	settings_status = Label.new()
	settings_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_status.add_theme_color_override("font_color", Color("ffd28a"))
	$Contents.add_child(settings_status)
	settings_status.hide()
	var current_scene := get_tree().current_scene
	quit_to_menu_button.visible = (
		current_scene != null
		and current_scene.scene_file_path != MAIN_MENU_SCENE_PATH
	)

	music_slider.value_changed.connect(_on_music_volume_changed)
	ambience_slider.value_changed.connect(_on_ambience_volume_changed)
	effects_slider.value_changed.connect(_on_effects_volume_changed)
	battle_auto_pan_button.toggled.connect(_on_battle_auto_pan_toggled)
	battle_auto_zoom_button.toggled.connect(_on_battle_auto_zoom_toggled)
	tutorials_button.toggled.connect(_on_tutorials_toggled)
	quit_to_menu_button.pressed.connect(_on_quit_to_menu_pressed)
	quit_confirmation_button.pressed.connect(_on_quit_confirmed)
	cancel_quit_button.pressed.connect(_on_quit_cancelled)


func _on_music_volume_changed(volume_percent: float) -> void:
	AudioManager.set_bus_volume_percent(AudioManager.MUSIC_BUS, volume_percent)
	_save_preferences()


func _on_ambience_volume_changed(volume_percent: float) -> void:
	AudioManager.set_bus_volume_percent(AudioManager.AMBIENCE_BUS, volume_percent)
	_save_preferences()


func _on_effects_volume_changed(volume_percent: float) -> void:
	AudioManager.set_bus_volume_percent(AudioManager.SFX_BUS, volume_percent)
	_save_preferences()


func _on_battle_auto_pan_toggled(enabled: bool) -> void:
	GameState.battle_auto_pan = enabled
	_save_preferences()
	_update_camera_buttons()

func _on_battle_auto_zoom_toggled(enabled: bool) -> void:
	GameState.battle_auto_zoom = enabled
	_save_preferences()
	_update_camera_buttons()

func _update_camera_buttons() -> void:
	battle_auto_pan_button.set_pressed_no_signal(GameState.battle_auto_pan)
	battle_auto_zoom_button.set_pressed_no_signal(GameState.battle_auto_zoom)

func _on_tutorials_toggled(enabled: bool) -> void:
	GameState.tutorials_enabled = enabled
	_save_preferences()


func _on_quit_to_menu_pressed() -> void:
	var warning: Label = $QuitConfirmOverlay/CenterContainer/ConfirmationPanel/Contents/WarningLabel
	warning.text = "Return to the main menu?\nThe last checkpoint is kept. Unsaved edits and combat ticks are lost."
	quit_confirmation_overlay.show()


func _refresh_context() -> void:
	_update_camera_buttons()
	tutorials_button.set_pressed_no_signal(GameState.tutorials_enabled)
	var scene := get_tree().current_scene
	quit_to_menu_button.visible = scene != null and scene.scene_file_path != MAIN_MENU_SCENE_PATH
	quit_confirmation_overlay.hide()
	content_scale_factor = 1.0
	content_scale_size = Vector2i.ZERO
	min_size = Vector2i(304, 278 if quit_to_menu_button.visible else 246)
	size = min_size


func _save_preferences() -> void:
	settings_status.visible = not AudioManager.save_settings()
	settings_status.text = "Settings could not be saved. Current session changes still apply."


func _on_quit_confirmed() -> void:
	var error := get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	if error != OK:
		push_error("Could not return to the main menu. Error code: %s" % error)


func _on_quit_cancelled() -> void:
	quit_confirmation_overlay.hide()
