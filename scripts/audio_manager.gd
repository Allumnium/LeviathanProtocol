extends Node

const MUSIC_BUS: StringName = &"Music"
const AMBIENCE_BUS: StringName = &"Ambience"
const SFX_BUS: StringName = &"SFX"
const BUILD_MUSIC: AudioStreamMP3 = preload("res://assets/audio/music/build1.mp3")
const DEFAULT_VOLUME_PERCENT := 50.0

var _music_player: AudioStreamPlayer


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(AMBIENCE_BUS)
	_ensure_bus(SFX_BUS)
	set_bus_volume_percent(MUSIC_BUS, DEFAULT_VOLUME_PERCENT)
	set_bus_volume_percent(AMBIENCE_BUS, DEFAULT_VOLUME_PERCENT)
	set_bus_volume_percent(SFX_BUS, DEFAULT_VOLUME_PERCENT)
	_start_build_music()


func get_bus_volume_percent(bus_name: StringName) -> float:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		push_error("Audio bus '%s' does not exist." % bus_name)
		return 0.0
	if AudioServer.is_bus_mute(bus_index):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(bus_index)) * 100.0, 0.0, 100.0)


func set_bus_volume_percent(bus_name: StringName, volume_percent: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		push_error("Audio bus '%s' does not exist." % bus_name)
		return

	var linear_volume := clampf(volume_percent, 0.0, 100.0) / 100.0
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(linear_volume, 0.0001)))
	AudioServer.set_bus_mute(bus_index, is_zero_approx(linear_volume))


func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return

	AudioServer.add_bus()
	var bus_index := AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(bus_index, bus_name)
	AudioServer.set_bus_send(bus_index, &"Master")


func _start_build_music() -> void:
	var music_stream := BUILD_MUSIC.duplicate() as AudioStreamMP3
	if music_stream == null:
		push_error("Could not load the build music stream.")
		return

	music_stream.loop = true
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = MUSIC_BUS
	_music_player.stream = music_stream
	add_child(_music_player)
	_music_player.play()
