extends PopupPanel

@onready var music_slider: HSlider = $Contents/ContentArea/MusicRow/MusicSlider
@onready var ambience_slider: HSlider = $Contents/ContentArea/AmbienceRow/AmbienceSlider
@onready var effects_slider: HSlider = $Contents/ContentArea/EffectsRow/EffectsSlider


func _ready() -> void:
	music_slider.value = AudioManager.get_bus_volume_percent(AudioManager.MUSIC_BUS)
	ambience_slider.value = AudioManager.get_bus_volume_percent(AudioManager.AMBIENCE_BUS)
	effects_slider.value = AudioManager.get_bus_volume_percent(AudioManager.SFX_BUS)

	music_slider.value_changed.connect(_on_music_volume_changed)
	ambience_slider.value_changed.connect(_on_ambience_volume_changed)
	effects_slider.value_changed.connect(_on_effects_volume_changed)


func _on_music_volume_changed(volume_percent: float) -> void:
	AudioManager.set_bus_volume_percent(AudioManager.MUSIC_BUS, volume_percent)


func _on_ambience_volume_changed(volume_percent: float) -> void:
	AudioManager.set_bus_volume_percent(AudioManager.AMBIENCE_BUS, volume_percent)


func _on_effects_volume_changed(volume_percent: float) -> void:
	AudioManager.set_bus_volume_percent(AudioManager.SFX_BUS, volume_percent)
