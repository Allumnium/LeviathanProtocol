extends SceneTree

const Travel = preload("res://scripts/expedition_state.gd")
var checks := 0
var failures := 0
var state: Node
var screen: Control

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func settle() -> void:
	for index in range(4):
		await process_frame

func open_screen() -> void:
	screen = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	await settle()

func reopen_checkpoint() -> void:
	screen.queue_free()
	await settle()
	check(state.load_run_checkpoint(), "Reload committed expedition")
	await open_screen()

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://arrival-choice-test.json"
	check(state.start_new_run(1, 1501), "Start arrival fixture")
	await open_screen()
	check(screen.departure_modal == null, "Starting dock allows fleet preparation before Depart")
	screen.departure_button.pressed.emit()
	check(state.expedition_simulation.state.departure_choice_pending,
			"Initial Depart commits its required choice before opening")
	await reopen_checkpoint()
	check(is_instance_valid(screen.departure_modal), "Continue restores an unfinished initial choice")
	screen._choose_departure("refuel_station_1")
	check(screen.departure_modal == null and not state.expedition_simulation.state.departure_choice_pending,
			"Committed destination clears the required choice")
	screen.speed_buttons[10].pressed.emit()
	screen._process(0.5)
	check(state.save_expedition_checkpoint(), "Save an in-flight checkpoint")
	var position: Vector2 = state.expedition_simulation.state.position_nu
	check(state.load_run_checkpoint() and state.prepare_checkpoint_resume(), "Prepare Continue transaction")
	check(state.expedition_simulation.state.position_nu == position
			and state.expedition_simulation.state.requested_speed == 10
			and Travel.PauseReason.USER in state.expedition_simulation.state.pause_reasons,
			"Continue preserves exact position and requested speed but starts paused")
	var tick: int = state.expedition_simulation.state.simulation_tick
	check(state.expedition_simulation.advance(20)
			and state.expedition_simulation.state.simulation_tick == tick,
			"Continue cannot advance before Play")
	check(state.load_run_checkpoint() and Travel.PauseReason.USER in state.expedition_simulation.state.pause_reasons,
			"Continue pause is durable")
	var save_path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-save.json"
	var before: Dictionary = state.expedition_simulation.state.snapshot()
	check(not state.prepare_checkpoint_resume()
			and state.expedition_simulation.state.snapshot() == before,
			"Failed Continue checkpoint preserves navigation and reports failure")
	state.run_save_path = save_path
	screen.speed_buttons[10].pressed.emit()
	before = state.expedition_simulation.state.snapshot()
	state.run_save_path = "res://project.godot/no-save.json"
	screen._process(100)
	check(screen.departure_modal == null
			and not state.expedition_simulation.state.departure_choice_pending
			and state.expedition_simulation.state.position_nu == Vector2(before.position_nu[0], before.position_nu[1])
			and Travel.PauseReason.SAVE_ERROR in state.expedition_simulation.state.pause_reasons,
			"Failed arrival save rolls back before showing a successful arrival")
	state.run_save_path = save_path
	screen._on_expedition_retry_pressed()
	screen._process(100)
	check(is_instance_valid(screen.departure_modal)
			and state.expedition_simulation.state.departure_choice_pending,
			"Retried arrival commits its pending choice and opens the modal")
	tick = state.expedition_simulation.state.simulation_tick
	check(state.expedition_simulation.advance(100)
			and state.expedition_simulation.state.simulation_tick == tick,
			"Pending choice freezes the authoritative clock even without the screen coordinator")
	await reopen_checkpoint()
	check(is_instance_valid(screen.departure_modal), "Continue restores the committed station arrival choice")
	screen.speed_buttons[1].pressed.emit()
	tick = state.expedition_simulation.state.simulation_tick
	check(state.expedition_simulation.advance(100)
			and state.expedition_simulation.state.simulation_tick == tick,
			"Play cannot bypass a required destination choice")
	var before_route: Dictionary = state.hangar_snapshot()
	state.run_save_path = "res://project.godot/no-save.json"
	screen._choose_departure("derelict_1")
	check(is_instance_valid(screen.departure_modal) and not screen.departure_error.text.is_empty()
			and state.expedition_simulation.state.departure_choice_pending
			and state.expedition_simulation.state.destination_location_id.is_empty(),
			"Failed choice save retains the modal and pending choice")
	check(state.hangar_snapshot().ships == before_route.ships
			and state.credits == before_route.credits, "Failed choice preserves fleet and credits")
	state.run_save_path = save_path
	screen.departure_retry.pressed.emit()
	screen._choose_departure("derelict_1")
	check(screen.departure_modal == null and not state.expedition_simulation.state.departure_choice_pending,
			"Retry permits one committed onward route")
	screen.speed_buttons[10].pressed.emit()
	screen._process(100)
	check(state.expedition_simulation.state.travel_state == Travel.TravelState.STOPPED
			and state.expedition_simulation.state.departure_choice_pending,
			"POI arrival also commits a required choice")
	await reopen_checkpoint()
	check(is_instance_valid(screen.departure_modal), "Continue restores a POI arrival choice")
	screen._choose_departure("start_station")
	screen._on_expedition_stop_pressed()
	check(state.save_expedition_checkpoint(), "Persist manually stopped route")
	await reopen_checkpoint()
	check(screen.departure_modal == null
			and not state.expedition_simulation.state.departure_choice_pending,
			"Stopping a route is not mistaken for an arrival on Continue")
	print("EXPEDITION_ARRIVAL_CHECKS=%d failures=%d" % [checks, failures])
	screen.queue_free()
	await settle()
	quit(1 if failures else 0)
