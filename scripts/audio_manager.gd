extends Node

const MUSIC_BUS: StringName = &"Music"
const AMBIENCE_BUS: StringName = &"Ambience"
const SFX_BUS: StringName = &"SFX"
const MENU_MUSIC: AudioStreamMP3 = preload("res://assets/audio/music/Orbital Cartridge.mp3")
const BUILD_MUSIC: AudioStreamMP3 = preload("res://assets/audio/music/Star Cartridge.mp3")
const BATTLE_AMBIENCE: AudioStreamMP3 = preload("res://assets/audio/music/ambient_space.mp3")
const MENU_THRUSTER_LOW: AudioStreamMP3 = preload(
	"res://assets/audio/sfx/thruster_low_loop.mp3"
)
const MENU_THRUSTER_LARGE: AudioStreamMP3 = preload(
	"res://assets/audio/sfx/thrust-large-loop.mp3"
)
const DEFAULT_VOLUME_PERCENT := 50.0

var _music_player: AudioStreamPlayer
var _current_music_track: StringName = &""
var _battle_ambience_player: AudioStreamPlayer
var _menu_thruster_player: AudioStreamPlayer
var _menu_thruster_mode: StringName = &""


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


func play_sfx(stream: AudioStream, pitch_scale: float = 1.0) -> void:
	if stream == null:
		push_error("Cannot play a sound effect without an audio stream.")
		return
	if pitch_scale <= 0.0:
		push_error("Cannot play a sound effect with a non-positive pitch scale.")
		return

	var player := AudioStreamPlayer.new()
	player.bus = SFX_BUS
	player.stream = stream
	player.pitch_scale = pitch_scale
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func play_menu_music() -> void:
	_play_music(MENU_MUSIC, &"menu")


func play_build_music() -> void:
	_play_music(BUILD_MUSIC, &"build")


func play_battle_ambience() -> void:
	if is_instance_valid(_battle_ambience_player) and _battle_ambience_player.playing:
		return

	var ambience_stream := _create_looping_stream(BATTLE_AMBIENCE)
	if ambience_stream == null:
		return

	_battle_ambience_player = AudioStreamPlayer.new()
	_battle_ambience_player.name = "BattleAmbiencePlayer"
	_battle_ambience_player.bus = AMBIENCE_BUS
	_battle_ambience_player.stream = ambience_stream
	add_child(_battle_ambience_player)
	_battle_ambience_player.play()


func stop_battle_ambience() -> void:
	if not is_instance_valid(_battle_ambience_player):
		return

	_battle_ambience_player.stop()
	_battle_ambience_player.queue_free()
	_battle_ambience_player = null


func set_menu_thruster_mode(use_large_thruster: bool) -> void:
	var requested_mode: StringName = &"large" if use_large_thruster else &"low"
	if (
		requested_mode == _menu_thruster_mode
		and is_instance_valid(_menu_thruster_player)
		and _menu_thruster_player.playing
	):
		return

	var source_stream: AudioStreamMP3 = (
		MENU_THRUSTER_LARGE if use_large_thruster else MENU_THRUSTER_LOW
	)
	var looping_stream := _create_looping_stream(source_stream)
	if looping_stream == null:
		return

	if not is_instance_valid(_menu_thruster_player):
		_menu_thruster_player = AudioStreamPlayer.new()
		_menu_thruster_player.name = "MenuThrusterPlayer"
		_menu_thruster_player.bus = SFX_BUS
		add_child(_menu_thruster_player)
	else:
		_menu_thruster_player.stop()

	_menu_thruster_player.stream = looping_stream
	_menu_thruster_player.play()
	_menu_thruster_mode = requested_mode


func stop_menu_thrusters() -> void:
	if is_instance_valid(_menu_thruster_player):
		_menu_thruster_player.stop()
	_menu_thruster_mode = &""


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

	var music_stream := _create_looping_stream(stream)
	if music_stream == null:
		return

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


func _create_looping_stream(stream: AudioStreamMP3) -> AudioStreamMP3:
	if stream == null:
		push_error("Cannot loop a null audio stream.")
		return null

	var looping_stream := stream.duplicate() as AudioStreamMP3
	if looping_stream == null:
		push_error("Could not duplicate the audio stream for looping.")
		return null

	looping_stream.loop = true
	return looping_stream
