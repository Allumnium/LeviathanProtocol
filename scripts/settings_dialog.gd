extends PopupPanel

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
var settings_status: Label

@onready var music_slider: HSlider = $Contents/ContentArea/MusicRow/MusicSlider
@onready var ambience_slider: HSlider = $Contents/ContentArea/AmbienceRow/AmbienceSlider
@onready var effects_slider: HSlider = $Contents/ContentArea/EffectsRow/EffectsSlider
@onready var battle_auto_camera_button: CheckBox = $Contents/ContentArea/BattleAutoCameraRow/BattleAutoCameraButton
@onready var quit_to_menu_button: Button = $Contents/ContentArea/QuitToMenuButton
@onready var quit_confirmation_overlay: Control = $QuitConfirmOverlay
@onready var quit_confirmation_button: Button = (
	$QuitConfirmOverlay/CenterContainer/ConfirmationPanel/Contents/ConfirmationButtons/QuitButton
)
@onready var cancel_quit_button: TextureButton = (
	$QuitConfirmOverlay/CenterContainer/ConfirmationPanel/CloseX
)


func _ready() -> void:
	about_to_popup.connect(_refresh_context)
	music_slider.value = AudioManager.get_bus_volume_percent(AudioManager.MUSIC_BUS)
	ambience_slider.value = AudioManager.get_bus_volume_percent(AudioManager.AMBIENCE_BUS)
	effects_slider.value = AudioManager.get_bus_volume_percent(AudioManager.SFX_BUS)
	_update_battle_auto_camera_button()
	for button: BaseButton in [
		battle_auto_camera_button,
		quit_to_menu_button,
		quit_confirmation_button,
		cancel_quit_button,
	]:
		AudioManager.connect_ui_button(button, &"detail" if button == battle_auto_camera_button else &"accept")
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
	battle_auto_camera_button.toggled.connect(_on_battle_auto_camera_toggled)
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


func _on_battle_auto_camera_toggled(enabled: bool) -> void:
	GameState.battle_auto_camera = enabled
	_save_preferences()
	_update_battle_auto_camera_button()


func _update_battle_auto_camera_button() -> void:
	battle_auto_camera_button.set_pressed_no_signal(GameState.battle_auto_camera)


func _on_quit_to_menu_pressed() -> void:
	var warning: Label = $QuitConfirmOverlay/CenterContainer/ConfirmationPanel/Contents/WarningLabel
	warning.text = "Return to the main menu?\nThe last checkpoint is kept. Unsaved edits and combat ticks are lost."
	quit_confirmation_overlay.show()


func _refresh_context() -> void:
	_update_battle_auto_camera_button()
	var scene := get_tree().current_scene
	quit_to_menu_button.visible = scene != null and scene.scene_file_path != MAIN_MENU_SCENE_PATH
	quit_confirmation_overlay.hide()
	size.y = 280 if quit_to_menu_button.visible else 244


func _save_preferences() -> void:
	settings_status.visible = not AudioManager.save_settings()
	settings_status.text = "Settings could not be saved. Current session changes still apply."


func _on_quit_confirmed() -> void:
	var error := get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	if error != OK:
		push_error("Could not return to the main menu. Error code: %s" % error)


func _on_quit_cancelled() -> void:
	quit_confirmation_overlay.hide()
