extends Node

const MUSIC_BUS: StringName = &"Music"
const AMBIENCE_BUS: StringName = &"Ambience"
const SFX_BUS: StringName = &"SFX"
const MENU_MUSIC: AudioStreamMP3 = preload("res://assets/audio/music/Orbital Cartridge.mp3")
const BUILD_MUSIC: AudioStreamMP3 = preload("res://assets/audio/music/Star Cartridge.mp3")
const DEFAULT_VOLUME_PERCENT := 50.0

var _music_player: AudioStreamPlayer
var _current_music_track: StringName = &""


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(AMBIENCE_BUS)
	_ensure_bus(SFX_BUS)
	set_bus_volume_percent(MUSIC_BUS, DEFAULT_VOLUME_PERCENT)
	set_bus_volume_percent(AMBIENCE_BUS, DEFAULT_VOLUME_PERCENT)
	set_bus_volume_percent(SFX_BUS, DEFAULT_VOLUME_PERCENT)


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


func play_sfx(stream: AudioStream) -> void:
	if stream == null:
		push_error("Cannot play a sound effect without an audio stream.")
		return

	var player := AudioStreamPlayer.new()
	player.bus = SFX_BUS
	player.stream = stream
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func play_menu_music() -> void:
	_play_music(MENU_MUSIC, &"menu")


func play_build_music() -> void:
	_play_music(BUILD_MUSIC, &"build")


func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return

	AudioServer.add_bus()
	var bus_index := AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(bus_index, bus_name)
	AudioServer.set_bus_send(bus_index, &"Master")


func _play_music(stream: AudioStreamMP3, track_id: StringName) -> void:
	if (
		_current_music_track == track_id
		and is_instance_valid(_music_player)
		and _music_player.playing
	):
		return

	var music_stream := stream.duplicate() as AudioStreamMP3
	if music_stream == null:
		push_error("Could not duplicate the music stream.")
		return

	music_stream.loop = true
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.queue_free()

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = MUSIC_BUS
	_music_player.stream = music_stream
	add_child(_music_player)
	_music_player.play()
	_current_music_track = track_id
