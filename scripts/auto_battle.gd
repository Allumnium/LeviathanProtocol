extends Control

const MAP_SCENE_PATH := "res://scenes/game_map.tscn"

@onready var visuals: BattleVisuals = $BattleVisuals
@onready var status_label: Label = $Status

var simulation := BattleSimulation.new()
var _dragging := false
var _follow_player := false
var _finished := false
var _credited_drops := 0


func _ready() -> void:
	AudioManager.play_battle_ambience()
	if not GameState.battle_pending or not simulation.setup(
		GameState.ship.get_stats(), GameState.battle_aliens
	):
		push_error("Cannot open battle without a valid deployment.")
		GameState.cancel_battle()
		set_physics_process(false)
		call_deferred("_return_to_map")
		return
	visuals.simulation = simulation
	visuals.camera_zoom = clampf(minf(visuals.size.x / 850.0, visuals.size.y / 600.0), 0.25, 2.5)


func _exit_tree() -> void:
	AudioManager.stop_battle_ambience()


func _physics_process(delta: float) -> void:
	if _finished:
		return
	simulation.advance(delta)
	while _credited_drops < simulation.collected_categories.size():
		GameState.refund_tile(simulation.collected_categories[_credited_drops])
		_credited_drops += 1
	match simulation.phase:
		BattleSimulation.Phase.COMBAT:
			status_label.text = "AUTO BATTLE - %d aliens remaining" % simulation.living_alien_count()
		BattleSimulation.Phase.SALVAGE:
			status_label.text = "COLLECTING SALVAGE - %d squares recovered" % _credited_drops
		BattleSimulation.Phase.VICTORY:
			status_label.text = "VICTORY - %d squares recovered" % _credited_drops
			_finish_battle(true)
		BattleSimulation.Phase.DEFEAT:
			status_label.text = "SHIP LOST - Returning to rebuild"
			_finish_battle(false)
	visuals.queue_redraw()


func _process(delta: float) -> void:
	if _follow_player and simulation.player != null:
		visuals.camera_position = visuals.camera_position.lerp(simulation.player.position, minf(delta * 5.0, 1.0))
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


func _finish_battle(won: bool) -> void:
	_finished = true
	if won:
		if not GameState.complete_battle():
			push_error("Could not record battle victory.")
			return
	else:
		GameState.cancel_battle()
	await get_tree().create_timer(2.0).timeout
	_return_to_map()


func _return_to_map() -> void:
	var error := get_tree().change_scene_to_file(MAP_SCENE_PATH)
	if error != OK:
		push_error("Could not return to the game map. Error code: %s" % error)
