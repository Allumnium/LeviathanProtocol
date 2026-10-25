extends PopupPanel

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"

@onready var music_slider: HSlider = $Contents/ContentArea/MusicRow/MusicSlider
@onready var ambience_slider: HSlider = $Contents/ContentArea/AmbienceRow/AmbienceSlider
@onready var effects_slider: HSlider = $Contents/ContentArea/EffectsRow/EffectsSlider
@onready var battle_auto_camera_button: Button = $Contents/ContentArea/BattleAutoCameraRow/BattleAutoCameraButton
@onready var quit_to_menu_button: Button = $Contents/ContentArea/QuitToMenuButton
@onready var quit_confirmation_overlay: Control = $QuitConfirmOverlay
@onready var quit_confirmation_button: Button = (
	$QuitConfirmOverlay/CenterContainer/ConfirmationPanel/Contents/ConfirmationButtons/QuitButton
)
@onready var cancel_quit_button: TextureButton = (
	$QuitConfirmOverlay/CenterContainer/ConfirmationPanel/CloseX
)


func _ready() -> void:
	music_slider.value = AudioManager.get_bus_volume_percent(AudioManager.MUSIC_BUS)
	ambience_slider.value = AudioManager.get_bus_volume_percent(AudioManager.AMBIENCE_BUS)
	effects_slider.value = AudioManager.get_bus_volume_percent(AudioManager.SFX_BUS)
	_update_battle_auto_camera_button()
	var current_scene := get_tree().current_scene
	quit_to_menu_button.visible = (
		current_scene != null
		and current_scene.scene_file_path != MAIN_MENU_SCENE_PATH
	)

	music_slider.value_changed.connect(_on_music_volume_changed)
	ambience_slider.value_changed.connect(_on_ambience_volume_changed)
	effects_slider.value_changed.connect(_on_effects_volume_changed)
	battle_auto_camera_button.pressed.connect(_on_battle_auto_camera_pressed)
	quit_to_menu_button.pressed.connect(_on_quit_to_menu_pressed)
	quit_confirmation_button.pressed.connect(_on_quit_confirmed)
	cancel_quit_button.pressed.connect(_on_quit_cancelled)


func _on_music_volume_changed(volume_percent: float) -> void:
	AudioManager.set_bus_volume_percent(AudioManager.MUSIC_BUS, volume_percent)


func _on_ambience_volume_changed(volume_percent: float) -> void:
	AudioManager.set_bus_volume_percent(AudioManager.AMBIENCE_BUS, volume_percent)


func _on_effects_volume_changed(volume_percent: float) -> void:
	AudioManager.set_bus_volume_percent(AudioManager.SFX_BUS, volume_percent)


func _on_battle_auto_camera_pressed() -> void:
	GameState.battle_auto_camera = not GameState.battle_auto_camera
	_update_battle_auto_camera_button()


func _update_battle_auto_camera_button() -> void:
	battle_auto_camera_button.text = "ON" if GameState.battle_auto_camera else "OFF"


func _on_quit_to_menu_pressed() -> void:
	quit_confirmation_overlay.show()
	cancel_quit_button.grab_focus()


func _on_quit_confirmed() -> void:
	var error := get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	if error != OK:
		push_error("Could not return to the main menu. Error code: %s" % error)


func _on_quit_cancelled() -> void:
	quit_confirmation_overlay.hide()
	quit_to_menu_button.grab_focus()
