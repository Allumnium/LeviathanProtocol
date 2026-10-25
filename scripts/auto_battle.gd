extends Control

const MAP_SCENE_PATH := "res://scenes/game_map.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const SHOOT_SOUND: AudioStream = preload("res://assets/audio/sfx/shoot-weapon.wav")
const SHIELD_HIT_SOUND: AudioStream = preload("res://assets/audio/sfx/shieldHit.wav")
const ALIEN_EXPLOSION_SOUND: AudioStream = preload("res://assets/audio/sfx/alien_explode.wav")
const SHIP_EXPLOSION_SOUND: AudioStream = preload("res://assets/audio/sfx/ship_explosion.mp3")
const AUTO_CAMERA_RETURN_DELAY := 5.0
const AUTO_CAMERA_MARGIN := Vector2(72.0, 64.0)
const AUTO_CAMERA_SMOOTHING := 4.0
const COMBAT_BLASTER_VOLUME_DB := -30.0
const COMBAT_IMPACT_VOLUME_DB := -10.0
const ALIEN_EXPLOSION_VOLUME_DB := -30.0
const FINISHING_SHOT_TIME_SCALE := 0.1
const FINISHING_SHOT_WINDOW_SECONDS := 0.25
const FINISHING_SHOT_CAMERA_ZOOM := 2.5
const FINISHING_SHOT_CAMERA_TRANSITION_SECONDS := 0.4
const RESULT_DELAY_SECONDS := 1.0

@onready var visuals: BattleVisuals = $BattleVisuals
@onready var battle_speed_controls: HBoxContainer = $BattleSpeedControls
@onready var pause_button: Button = $BattleSpeedControls/PauseButton
@onready var fast_forward_button: Button = $BattleSpeedControls/FastForwardButton
@onready var defeat_dialog: Control = $DefeatDialog
@onready var defeat_accept_button: Button = $DefeatDialog/CenterContainer/Panel/Contents/ButtonCenter/AcceptButton
@onready var defeat_close_button: TextureButton = $DefeatDialog/CenterContainer/Panel/CloseX

var simulation := BattleSimulation.new()
var _dragging := false
var _auto_camera_active := true
var _camera_inactive_seconds := 0.0
var _finished := false
var _credited_drops := 0
var withdraw_button: Button
var _run_lost := false
var _report_open := false
var _battle_credit_reward := 0
var _cinematic_projectile: BattleSimulation.Projectile
var _cinematic_camera_start := Vector2.ZERO
var _cinematic_zoom_start := 1.0
var _cinematic_transition_elapsed := 0.0
var _result_delay_remaining := -1.0
var _pending_result_won := false


func _ready() -> void:
	AudioManager.play_battle_music()
	if not GameState.battle_pending or not simulation.setup_owned(
		GameState.fleet, GameState.battle_aliens,
		GameState.allied_salvage_chance(), GameState.laser_upgrade_level
	):
		push_error("Cannot open battle without a valid deployment.")
		GameState.cancel_battle()
		set_physics_process(false)
		call_deferred("_return_to_map")
		return
	simulation.weapon_fired.connect(
		AudioManager.play_sfx.bind(SHOOT_SOUND, 1.0, COMBAT_BLASTER_VOLUME_DB, 35)
	)
	simulation.shield_hit.connect(
		AudioManager.play_sfx.bind(SHIELD_HIT_SOUND, 1.0, COMBAT_IMPACT_VOLUME_DB)
	)
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
	pause_button.toggled.connect(_on_pause_toggled)
	fast_forward_button.toggled.connect(_on_fast_forward_toggled)
	defeat_accept_button.pressed.connect(_return_to_main_menu)
	defeat_close_button.pressed.connect(_return_to_main_menu)


func _physics_process(delta: float) -> void:
	if _finished:
		return
	if _result_delay_remaining >= 0.0:
		# Keep the wreckage moving while the battlefield remains visible during
		# the short beat before the result panel appears.
		simulation.advance(delta)
		_result_delay_remaining -= delta
		visuals.queue_redraw()
		if _result_delay_remaining <= 0.0:
			_finish_battle(_pending_result_won)
		return
	if pause_button.button_pressed:
		return
	if _cinematic_projectile == null:
		_try_begin_finishing_shot()
	var speed_multiplier := (
		FINISHING_SHOT_TIME_SCALE * (2.0 if fast_forward_button.button_pressed else 1.0)
		if _cinematic_projectile != null
		else (2.0 if fast_forward_button.button_pressed else 1.0)
	)
	simulation.advance(delta * speed_multiplier)
	if _cinematic_projectile == null:
		_try_begin_finishing_shot()
	while _credited_drops < simulation.collected_categories.size():
		GameState.refund_tile(simulation.collected_categories[_credited_drops])
		_credited_drops += 1
	match simulation.phase:
		BattleSimulation.Phase.COMBAT:
			pass
		BattleSimulation.Phase.VICTORY:
			_begin_result_delay(true)
		BattleSimulation.Phase.DEFEAT:
			_begin_result_delay(false)
		BattleSimulation.Phase.WITHDRAWN:
			_finish_battle(false)
	if simulation.withdrawing and not _finished:
		withdraw_button.text = "RETREAT %d" % ceili(simulation.retreat_remaining)
	visuals.queue_redraw()


func _on_pause_toggled(is_paused: bool) -> void:
	if is_paused:
		fast_forward_button.set_pressed_no_signal(false)


func _on_fast_forward_toggled(is_fast: bool) -> void:
	if is_fast:
		pause_button.set_pressed_no_signal(false)


func _process(delta: float) -> void:
	if _report_open or _result_delay_remaining >= 0.0:
		return
	if _cinematic_projectile != null and simulation.projectiles.has(_cinematic_projectile):
		_cinematic_transition_elapsed += delta
		var transition_weight := smoothstep(
			0.0,
			1.0,
			clampf(
				_cinematic_transition_elapsed / FINISHING_SHOT_CAMERA_TRANSITION_SECONDS,
				0.0,
				1.0
			)
		)
		visuals.camera_position = _cinematic_camera_start.lerp(
			_cinematic_projectile.position,
			transition_weight
		)
		visuals.camera_zoom = lerpf(
			_cinematic_zoom_start,
			FINISHING_SHOT_CAMERA_ZOOM,
			transition_weight
		)
		visuals.queue_redraw()
		return
	_cinematic_projectile = null
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if not direction.is_zero_approx():
		_mark_manual_camera_input()
		visuals.camera_position += direction.normalized() * 400.0 * delta / visuals.camera_zoom
	elif GameState.battle_auto_camera and not _auto_camera_active:
		_camera_inactive_seconds += delta
		if _camera_inactive_seconds >= AUTO_CAMERA_RETURN_DELAY:
			_auto_camera_active = true
	if GameState.battle_auto_camera and _auto_camera_active:
		_update_auto_camera(delta)
	visuals.queue_redraw()


func _input(event: InputEvent) -> void:
	if _report_open or _result_delay_remaining >= 0.0 or _cinematic_projectile != null:
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var world_under_cursor: Vector2 = visuals.world_transform().affine_inverse() * event.position
			var zoom_factor := 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			visuals.camera_zoom = clampf(visuals.camera_zoom * zoom_factor, 0.2, 3.0)
			visuals.camera_position = world_under_cursor - (event.position - visuals.size * 0.5) / visuals.camera_zoom
			_mark_manual_camera_input()
	elif event is InputEventMouseMotion and _dragging:
		visuals.camera_position -= event.relative / visuals.camera_zoom
		_mark_manual_camera_input()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if GameState.battle_auto_camera:
			_auto_camera_active = true
			_camera_inactive_seconds = AUTO_CAMERA_RETURN_DELAY


func _mark_manual_camera_input() -> void:
	_auto_camera_active = false
	_camera_inactive_seconds = 0.0


func _update_auto_camera(delta: float) -> void:
	var ship_count := 0
	var center := Vector2.ZERO
	for member in simulation.players:
		if member.is_alive():
			center += member.position
			ship_count += 1
	for member in simulation.aliens:
		if member.is_alive():
			center += member.position
			ship_count += 1
	if ship_count == 0 or visuals.size.x <= 0.0 or visuals.size.y <= 0.0:
		return
	center /= float(ship_count)
	var extent := Vector2.ONE
	for member in simulation.players:
		if not member.is_alive():
			continue
		var distance := (member.position - center).abs() + Vector2.ONE * member.radius
		extent.x = maxf(extent.x, distance.x)
		extent.y = maxf(extent.y, distance.y)
	for member in simulation.aliens:
		if not member.is_alive():
			continue
		var alien_distance := (member.position - center).abs() + Vector2.ONE * member.radius
		extent.x = maxf(extent.x, alien_distance.x)
		extent.y = maxf(extent.y, alien_distance.y)
	var raw_available_half := visuals.size * 0.5 - AUTO_CAMERA_MARGIN
	var available_half := Vector2(
		maxf(raw_available_half.x, 1.0),
		maxf(raw_available_half.y, 1.0)
	)
	var target_zoom := clampf(
		minf(available_half.x / extent.x, available_half.y / extent.y),
		0.2,
		3.0
	)
	var interpolation := minf(delta * AUTO_CAMERA_SMOOTHING, 1.0)
	visuals.camera_position = visuals.camera_position.lerp(center, interpolation)
	visuals.camera_zoom = lerpf(visuals.camera_zoom, target_zoom, interpolation)


func _on_ship_destroyed(is_player: bool) -> void:
	if is_player:
		AudioManager.play_sfx(SHIP_EXPLOSION_SOUND)
	else:
		AudioManager.play_sfx(ALIEN_EXPLOSION_SOUND, 1.0, ALIEN_EXPLOSION_VOLUME_DB)


func _try_begin_finishing_shot() -> void:
	var projectile := simulation.get_finishing_projectile(FINISHING_SHOT_WINDOW_SECONDS)
	if projectile == null:
		return
	_cinematic_projectile = projectile
	_cinematic_camera_start = visuals.camera_position
	_cinematic_zoom_start = visuals.camera_zoom
	_cinematic_transition_elapsed = 0.0


func _begin_result_delay(won: bool) -> void:
	_pending_result_won = won
	_result_delay_remaining = RESULT_DELAY_SECONDS
	_cinematic_projectile = null
	_dragging = false
	battle_speed_controls.hide()
	withdraw_button.hide()


func _finish_battle(won: bool) -> void:
	_finished = true
	withdraw_button.hide()
	battle_speed_controls.hide()
	GameState.record_battle(simulation)
	var credits_before := GameState.credits
	if won:
		if not GameState.complete_battle():
			push_error("Could not record battle victory.")
			return
	else:
		GameState.cancel_battle()
	_battle_credit_reward = maxi(GameState.credits - credits_before, 0)
	_run_lost = GameState.is_run_lost()
	_show_report(won)


func _return_to_map() -> void:
	var error := get_tree().change_scene_to_file(MAP_SCENE_PATH)
	if error != OK:
		push_error("Could not return to the game map. Error code: %s" % error)


func _return_to_main_menu() -> void:
	var error := get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	if error != OK:
		push_error("Could not return to the main menu. Error code: %s" % error)


func _on_report_closed() -> void:
	_report_open = false
	if _run_lost:
		defeat_dialog.show()
		defeat_accept_button.grab_focus()
	else:
		_return_to_map()


func _show_report(won: bool) -> void:
	_report_open = true
	var report := preload("res://scripts/battle_report.gd").new()
	add_child(report)
	report.show_report(
		GameState.last_battle_report,
		"Victory" if won else (
			"Withdrawn" if simulation.phase == BattleSimulation.Phase.WITHDRAWN else "Defeat"
		),
		simulation.collected_categories,
		_battle_credit_reward
	)
	report.closed.connect(_on_report_closed)
