extends Node

const MUSIC_BUS: StringName = &"Music"
const AMBIENCE_BUS: StringName = &"Ambience"
const SFX_BUS: StringName = &"SFX"
const MENU_MUSIC: AudioStreamMP3 = preload("res://assets/audio/music/Orbital Cartridge.mp3")
const BUILD_MUSIC: AudioStreamMP3 = preload("res://assets/audio/music/Star Cartridge.mp3")
const BATTLE_MUSIC: AudioStreamMP3 = preload("res://assets/audio/music/Phalanx Signal.mp3")
const MENU_THRUSTER_LOW: AudioStreamMP3 = preload(
	"res://assets/audio/sfx/thruster_low_loop.mp3"
)
const MENU_THRUSTER_LARGE: AudioStreamMP3 = preload(
	"res://assets/audio/sfx/thrust-large-loop.mp3"
)
const DEFAULT_VOLUME_PERCENT := 50.0
const OUTPUT_GAIN_DB := -6.0
const MAX_SFX_PLAYERS := 32
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_VERSION := 1

var _music_player: AudioStreamPlayer
var _current_music_track: StringName = &""
var _menu_thruster_player: AudioStreamPlayer
var _menu_thruster_mode: StringName = &""
var _sfx_players: Array[AudioStreamPlayer] = []
var _last_sfx_time_by_stream: Dictionary = {}


func _ready() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Master"), OUTPUT_GAIN_DB)
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(AMBIENCE_BUS)
	_ensure_bus(SFX_BUS)
	load_settings()


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


func load_settings(file_path: String = SETTINGS_PATH) -> void:
	var config := ConfigFile.new()
	var load_error := config.load(file_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		push_error("Could not load settings: %s" % error_string(load_error))
	var music := _validated_volume(config.get_value(
		"audio", "music", DEFAULT_VOLUME_PERCENT
	))
	var ambience := _validated_volume(config.get_value(
		"audio", "ambience", DEFAULT_VOLUME_PERCENT
	))
	var effects := _validated_volume(config.get_value(
		"audio", "effects", DEFAULT_VOLUME_PERCENT
	))
	set_bus_volume_percent(MUSIC_BUS, music)
	set_bus_volume_percent(AMBIENCE_BUS, ambience)
	set_bus_volume_percent(SFX_BUS, effects)
	GameState.battle_auto_camera = _validated_bool(
		config.get_value("battle", "auto_camera", true), true
	)
	GameState.battle_fast_forward = _validated_bool(
		config.get_value("battle", "fast_forward", false), false
	)


func save_settings(file_path: String = SETTINGS_PATH) -> bool:
	var config := ConfigFile.new()
	config.set_value("settings", "version", SETTINGS_VERSION)
	config.set_value("audio", "music", get_bus_volume_percent(MUSIC_BUS))
	config.set_value("audio", "ambience", get_bus_volume_percent(AMBIENCE_BUS))
	config.set_value("audio", "effects", get_bus_volume_percent(SFX_BUS))
	config.set_value("battle", "auto_camera", GameState.battle_auto_camera)
	config.set_value("battle", "fast_forward", GameState.battle_fast_forward)
	var save_error := config.save(file_path)
	if save_error != OK:
		push_error("Could not save settings: %s" % error_string(save_error))
		return false
	return true


func _validated_volume(value: Variant) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return DEFAULT_VOLUME_PERCENT
	return clampf(float(value), 0.0, 100.0)


func _validated_bool(value: Variant, fallback: bool) -> bool:
	return value if typeof(value) == TYPE_BOOL else fallback


func play_sfx(
	stream: AudioStream,
	pitch_scale: float = 1.0,
	volume_db: float = 0.0,
	minimum_interval_ms: int = 0
) -> void:
	if stream == null:
		push_error("Cannot play a sound effect without an audio stream.")
		return
	if pitch_scale <= 0.0:
		push_error("Cannot play a sound effect with a non-positive pitch scale.")
		return
	var now := Time.get_ticks_msec()
	var stream_key := stream.resource_path if not stream.resource_path.is_empty() else str(stream.get_instance_id())
	if (
		minimum_interval_ms > 0
		and now - int(_last_sfx_time_by_stream.get(stream_key, -minimum_interval_ms))
			< minimum_interval_ms
	):
		return
	_last_sfx_time_by_stream[stream_key] = now

	var player: AudioStreamPlayer
	for candidate in _sfx_players:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		if _sfx_players.size() >= MAX_SFX_PLAYERS:
			return
		player = AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % (_sfx_players.size() + 1)
		_sfx_players.append(player)
		add_child(player)
	player.bus = SFX_BUS
	player.stream = stream
	player.pitch_scale = pitch_scale
	player.volume_db = volume_db
	player.play()


func play_menu_music() -> void:
	_play_music(MENU_MUSIC, &"menu")


func play_build_music() -> void:
	_play_music(BUILD_MUSIC, &"build")


func play_battle_music() -> void:
	_play_music(BATTLE_MUSIC, &"battle")


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
