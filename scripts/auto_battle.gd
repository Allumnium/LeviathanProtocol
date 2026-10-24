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

@onready var visuals: BattleVisuals = $BattleVisuals
@onready var status_label: Label = $Status
@onready var defeat_dialog: Control = $DefeatDialog
@onready var defeat_accept_button: Button = $DefeatDialog/CenterContainer/Panel/Contents/ButtonCenter/AcceptButton

var simulation := BattleSimulation.new()
var _dragging := false
var _auto_camera_active := true
var _camera_inactive_seconds := 0.0
var _finished := false
var _credited_drops := 0
var withdraw_button: Button
var _run_lost := false


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
	defeat_accept_button.pressed.connect(_return_to_main_menu)


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
	var ships: Array[BattleSimulation.Combatant] = []
	for member in simulation.players:
		if member.is_alive():
			ships.append(member)
	for member in simulation.aliens:
		if member.is_alive():
			ships.append(member)
	if ships.is_empty() or visuals.size.x <= 0.0 or visuals.size.y <= 0.0:
		return
	var center := Vector2.ZERO
	for member in ships:
		center += member.position
	center /= float(ships.size())
	var extent := Vector2.ONE
	for member in ships:
		var distance := (member.position - center).abs() + Vector2.ONE * member.radius
		extent.x = maxf(extent.x, distance.x)
		extent.y = maxf(extent.y, distance.y)
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
	if _run_lost:
		defeat_dialog.show()
		defeat_accept_button.grab_focus()
	else:
		_return_to_map()


func _show_report(won: bool) -> void:
	var report := preload("res://scripts/battle_report.gd").new()
	add_child(report)
	report.show_report(GameState.last_battle_report, "Victory" if won else ("Withdrawn" if simulation.phase == BattleSimulation.Phase.WITHDRAWN else "Defeat"), _credited_drops)
	report.closed.connect(_on_report_closed)
