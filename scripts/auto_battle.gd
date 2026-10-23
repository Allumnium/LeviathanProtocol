extends Control

const MAP_SCENE_PATH := "res://scenes/game_map.tscn"
const SHOOT_SOUND: AudioStream = preload("res://assets/audio/sfx/shoot-weapon.wav")
const SHIELD_HIT_SOUND: AudioStream = preload("res://assets/audio/sfx/shieldHit.wav")
const ALIEN_EXPLOSION_SOUND: AudioStream = preload("res://assets/audio/sfx/alien_explode.wav")
const SHIP_EXPLOSION_SOUND: AudioStream = preload("res://assets/audio/sfx/ship_explosion.mp3")

@onready var visuals: BattleVisuals = $BattleVisuals
@onready var status_label: Label = $Status

var simulation := BattleSimulation.new()
var _dragging := false
var _follow_player := false
var _finished := false
var _credited_drops := 0
var withdraw_button: Button


func _ready() -> void:
	if not GameState.battle_pending or not simulation.setup_owned(
		GameState.fleet, GameState.battle_aliens,
		GameState.allied_salvage_chance(), GameState.laser_upgrade_level
	):
		push_error("Cannot open battle without a valid deployment.")
		GameState.cancel_battle()
		set_physics_process(false)
		call_deferred("_return_to_map")
		return
	simulation.weapon_fired.connect(AudioManager.play_sfx.bind(SHOOT_SOUND))
	simulation.shield_hit.connect(AudioManager.play_sfx.bind(SHIELD_HIT_SOUND))
	simulation.ship_destroyed.connect(_on_ship_destroyed)
	withdraw_button = Button.new()
	withdraw_button.text = "RETREAT"
	withdraw_button.add_theme_font_size_override("font_size", 10)
	preload("res://scripts/fleet_panel.gd").compact_button(withdraw_button)
	withdraw_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	withdraw_button.offset_left = -100
	withdraw_button.offset_right = -8
	withdraw_button.offset_top = 8
	withdraw_button.offset_bottom = 32
	withdraw_button.pressed.connect(func() -> void:
		simulation.request_withdrawal()
		withdraw_button.disabled = true)
	add_child(withdraw_button)
	withdraw_button.offset_left = -110
	withdraw_button.offset_right = -8
	visuals.simulation = simulation
	visuals.camera_zoom = clampf(minf(visuals.size.x / 850.0, visuals.size.y / 600.0), 0.25, 2.5)


func _physics_process(delta: float) -> void:
	if _finished:
		return
	simulation.advance(delta)
	while _credited_drops < simulation.collected_categories.size():
		GameState.refund_tile(simulation.collected_categories[_credited_drops])
		_credited_drops += 1
	match simulation.phase:
		BattleSimulation.Phase.COMBAT:
			status_label.text = "Auto Battle - %d ships / %d aliens" % [
				simulation.living_player_count(),
				simulation.living_alien_count()
			]
		BattleSimulation.Phase.SALVAGE:
			status_label.text = "Collecting Salvage - %d squares recovered" % _credited_drops
		BattleSimulation.Phase.VICTORY:
			status_label.text = "Victory - %d squares recovered" % _credited_drops
			_finish_battle(true)
		BattleSimulation.Phase.DEFEAT:
			status_label.text = "Ship Lost - Returning to rebuild"
			_finish_battle(false)
		BattleSimulation.Phase.WITHDRAWN:
			_finish_battle(false)
	if simulation.withdrawing and not _finished:
		withdraw_button.text = "RETREAT %d" % ceili(simulation.retreat_remaining)
	visuals.queue_redraw()


func _process(delta: float) -> void:
	if _follow_player:
		var camera_target := simulation.get_living_player()
		if camera_target != null:
			visuals.camera_position = visuals.camera_position.lerp(
				camera_target.position,
				minf(delta * 5.0, 1.0)
			)
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if not direction.is_zero_approx():
		_follow_player = false
		visuals.camera_position += direction.normalized() * 400.0 * delta / visuals.camera_zoom
	visuals.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_dragging = event.pressed
			if _dragging:
				_follow_player = false
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var world_under_cursor: Vector2 = visuals.world_transform().affine_inverse() * event.position
			var zoom_factor := 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			visuals.camera_zoom = clampf(visuals.camera_zoom * zoom_factor, 0.2, 3.0)
			visuals.camera_position = world_under_cursor - (event.position - visuals.size * 0.5) / visuals.camera_zoom
			_follow_player = false
	elif event is InputEventMouseMotion and _dragging:
		visuals.camera_position -= event.relative / visuals.camera_zoom
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_follow_player = not _follow_player


func _on_ship_destroyed(is_player: bool) -> void:
	AudioManager.play_sfx(SHIP_EXPLOSION_SOUND if is_player else ALIEN_EXPLOSION_SOUND)


func _finish_battle(won: bool) -> void:
	_finished = true
	withdraw_button.hide()
	GameState.record_battle(simulation)
	if won:
		if not GameState.complete_battle():
			push_error("Could not record battle victory.")
			return
	else:
		GameState.cancel_battle()
	_show_report(won)


func _return_to_map() -> void:
	var error := get_tree().change_scene_to_file(MAP_SCENE_PATH)
	if error != OK:
		push_error("Could not return to the game map. Error code: %s" % error)


func _show_report(won: bool) -> void:
	var report := preload("res://scripts/battle_report.gd").new()
	add_child(report)
	report.show_report(GameState.last_battle_report, "Victory" if won else ("Withdrawn" if simulation.phase == BattleSimulation.Phase.WITHDRAWN else "Defeat"), _credited_drops)
	report.closed.connect(_return_to_map)
