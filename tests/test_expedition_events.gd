extends SceneTree

const Travel = preload("res://scripts/expedition_state.gd")
const Simulation = preload("res://scripts/expedition_simulation.gd")
const Events = preload("res://scripts/expedition_events.gd")
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

func simulation() -> Simulation:
	var sim := Simulation.new()
	check(sim.configure(351), "Configure event fixture")
	# These checks exercise the distance-signal mechanics in isolation.
	for authored: Dictionary in sim.events:
		if authored.id != "derelict_signal":
			sim.state.event_receipts[authored.id] = true
	return sim

func open_screen(tab := "FLEET") -> void:
	screen = load("res://scenes/game_map.tscn").instantiate()
	screen.active_tab = tab
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	await settle()

func click_choice(text: String) -> void:
	await settle()
	for action: Button in screen.encounter_modal.find_children("*", "Button", true, false):
		if action.text != text:
			continue
		var motion := InputEventMouseMotion.new()
		motion.position = action.get_global_rect().get_center()
		root.push_input(motion, true)
		var click := InputEventMouseButton.new()
		click.position = motion.position
		click.global_position = motion.position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(click, true)
		await process_frame
		click = click.duplicate()
		click.pressed = false
		click.button_mask = 0
		root.push_input(click, true)
		await settle()
		return
	check(false, "Missing encounter action: " + text)

func run() -> void:
	root.size = Vector2i(1280, 720)
	state = root.get_node("GameState")
	state.run_save_path = "user://expedition-events-test.json"
	for speed: int in Travel.SPEEDS:
		var sim := simulation()
		check(sim.request_destination("refuel_station_1") and sim.set_speed(speed)
				and sim.advance(100), "Admit signal at %dx without tunneling" % speed)
		check(sim.state.pending_event_id == "derelict_signal"
				and is_equal_approx(sim.state.traveled_distance_nu, 80)
				and is_equal_approx(sim.state.fuel, 92)
				and sim.state.requested_speed == 1 and sim.accumulator == 0,
				"Signal clips at exactly 80 NU with speed-independent fuel and no stale budget")
		check(sim.state.destination_location_id == "refuel_station_1"
				and sim.state.travel_state == Travel.TravelState.CRUISING
				and Travel.PauseReason.ENCOUNTER in sim.state.pause_reasons,
				"Signal retains route and owns its decision pause")
		var tick := sim.state.simulation_tick
		check(sim.advance(100) and sim.state.simulation_tick == tick
				and not sim.set_speed(10) and not sim.set_pause(Travel.PauseReason.ENCOUNTER, false)
				and not sim.request_destination("settlement_1") and not sim.cancel_destination(),
				"Time and route controls cannot bypass the pending decision")
		check(sim.set_pause(Travel.PauseReason.USER, true)
				and sim.set_pause(Travel.PauseReason.EVENT, true), "Add independent pauses")
		check(sim.resolve_event("derelict_signal", "continue")
				and sim.state.destination_location_id == "refuel_station_1"
				and sim.state.pause_reasons.has(Travel.PauseReason.USER)
				and sim.state.pause_reasons.has(Travel.PauseReason.EVENT)
				and not sim.state.pause_reasons.has(Travel.PauseReason.ENCOUNTER),
				"Continue preserves course and clears only this encounter's pause")
		check(not sim.resolve_event("derelict_signal", "investigate"),
				"Duplicate or stale choice cannot change the route twice")
		sim.set_pause(Travel.PauseReason.USER, false)
		sim.set_pause(Travel.PauseReason.EVENT, false)
		check(sim.set_speed(10) and sim.advance(100) and sim.state.departure_choice_pending,
				"Resolved event does not recur during the remainder of the journey")

	for frame: float in [0.007, 0.25, 1.0]:
		var framed := simulation()
		framed.request_destination("refuel_station_1")
		framed.set_speed(10)
		for index in range(400):
			if not framed.state.pending_event_id.is_empty():
				break
			framed.advance(frame)
		check(framed.state.pending_event_id == "derelict_signal"
				and is_equal_approx(framed.state.traveled_distance_nu, 80)
				and is_equal_approx(framed.state.fuel, 92),
				"Frame-size independence at %s seconds" % frame)
	var clipped := simulation()
	clipped.events[0].distance_nu = 80.05
	check(clipped.request_destination("refuel_station_1") and clipped.set_speed(10)
			and clipped.advance(100) and is_equal_approx(clipped.state.traveled_distance_nu, 80.05),
			"Signal clips a fractional distance inside a fixed tick")
	var fuel := simulation()
	fuel.state.fuel = 8
	check(fuel.request_destination("refuel_station_1") and fuel.set_speed(10) and fuel.advance(100)
			and fuel.state.pending_event_id.is_empty() and Travel.PauseReason.FUEL in fuel.state.pause_reasons,
			"Coincident fuel exhaustion takes priority without consuming the signal")
	fuel.state.fuel = 10
	fuel.set_pause(Travel.PauseReason.FUEL, false)
	check(fuel.resume() and fuel.advance(1)
			and fuel.state.pending_event_id == "derelict_signal",
			"Deferred coincident signal is not lost after fuel recovery")
	var engaged := simulation()
	engaged.request_destination("refuel_station_1")
	engaged.state.travel_state = Travel.TravelState.ENGAGED
	check(engaged.advance(100) and engaged.state.pending_event_id.is_empty(),
			"Travel signals are not admitted during combat")
	var bad_catalog := {"version": 1, "events": clipped.events.duplicate(true)}
	bad_catalog.events[0].destination_id = "missing"
	check(not Events.valid(bad_catalog, clipped.locations), "Reject an event with an unknown detour")
	bad_catalog.events[0] = clipped.events[0].duplicate(true)
	bad_catalog.events.append(clipped.events[0].duplicate(true))
	check(not Events.valid(bad_catalog, clipped.locations), "Reject duplicate event identities/triggers")
	bad_catalog.events = [clipped.events[0].duplicate(true)]
	bad_catalog.events[0].distance_nu = -0.5
	check(not Events.valid(bad_catalog, clipped.locations), "Reject negative trigger distances")

	check(state.start_new_run(1, 351), "Start integrated signal run")
	for authored: Dictionary in state.expedition_simulation.events:
		if authored.id != "derelict_signal":
			state.expedition_simulation.state.event_receipts[authored.id] = true
	await open_screen("RESEARCH")
	screen._on_expedition_destination_selected("refuel_station_1")
	screen.speed_buttons[10].pressed.emit()
	var saved_before_signal: Dictionary = state.hangar_snapshot()
	var generation: int = state.hangar_generation
	var save_path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-save.json"
	screen._process(100)
	check(screen.encounter_modal == null and state.expedition_simulation.state.pending_event_id.is_empty()
			and state.expedition_simulation.state.position_nu == Vector2.ZERO
			and state.hangar_generation == generation
			and Travel.PauseReason.SAVE_ERROR in state.expedition_simulation.state.pause_reasons,
			"Failed admission checkpoint rolls back before showing a signal")
	state.run_save_path = save_path
	screen._on_expedition_retry_pressed()
	screen._process(100)
	check(is_instance_valid(screen.encounter_modal) and screen.active_tab == "RESEARCH"
			and state.expedition_simulation.state.pending_event_id == "derelict_signal",
			"Committed signal surfaces above management without changing the existing tab")
	for viewport: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport
		await settle()
		var panel: Control = screen.encounter_modal.find_child("EncounterPanel", true, false)
		check(screen.get_global_rect().encloses(panel.get_global_rect()), "Signal fits at %s" % viewport)
		for action: Button in panel.find_children("*", "Button", true, false):
			if action.is_visible_in_tree():
				check(panel.get_global_rect().encloses(action.get_global_rect()), "Signal action fits the panel")
	var pending: Dictionary = state.hangar_snapshot()
	check(pending.expedition.pending_event_id == "derelict_signal"
			and HangarCheckpoint.valid(pending), "Pending encounter is valid physical checkpoint state")
	var invalid := pending.duplicate(true)
	invalid.expedition.pending_event_id = "missing"
	check(not HangarCheckpoint.valid(invalid), "Reject unknown pending event before applying a checkpoint")
	invalid = pending.duplicate(true)
	invalid.expedition.pause_reasons.erase(Travel.PauseReason.ENCOUNTER)
	check(not HangarCheckpoint.valid(invalid), "Reject pending encounter without its pause")
	invalid = pending.duplicate(true)
	invalid.expedition.return_destination_id = "missing"
	check(not HangarCheckpoint.valid(invalid), "Reject unknown saved return destination")

	screen.queue_free()
	await settle()
	check(state.load_run_checkpoint() and state.prepare_checkpoint_resume(), "Continue pending signal")
	await open_screen()
	check(is_instance_valid(screen.encounter_modal), "Continue reopens the durable signal decision")
	var flagship = state.fleet[0]
	generation = state.hangar_generation
	var position: Vector2 = state.expedition_simulation.state.position_nu
	state.run_save_path = "res://project.godot/no-save.json"
	screen._choose_encounter("derelict_signal", "investigate")
	root.size = Vector2i(640, 360)
	await settle()
	check(is_instance_valid(screen.encounter_modal) and not screen.encounter_error.text.is_empty()
			and state.hangar_generation == generation
			and not state.expedition_simulation.state.event_receipts.get("derelict_signal", false)
			and state.expedition_simulation.state.destination_location_id == "refuel_station_1"
			and state.expedition_simulation.state.return_destination_id.is_empty()
			and state.fleet[0] == flagship,
			"Failed choice checkpoint does not consume signal, reroute or change return target")
	check(screen.get_global_rect().encloses(screen.encounter_modal.find_child(
			"EncounterPanel", true, false).get_global_rect()),
			"Save-error decision panel fits at minimum viewport")
	state.run_save_path = save_path
	screen.encounter_retry.pressed.emit()
	await click_choice("INVESTIGATE")
	check(screen.encounter_modal == null
			and state.expedition_simulation.state.destination_location_id == "derelict_1"
			and state.expedition_simulation.state.return_destination_id == "refuel_station_1"
			and state.expedition_simulation.state.position_nu == position
			and Travel.PauseReason.USER in state.expedition_simulation.state.pause_reasons
			and state.credits == saved_before_signal.credits and state.fleet[0] == flagship,
			"Investigate atomically reroutes from current position, retains original route and user pause, with no free reward")
	check(not state.resolve_expedition_event("derelict_signal", "continue"),
			"Backend rejects double submission after committed investigation")
	check(state.fleet[0] == flagship, "Repeated decisions preserve live ship identity")
	screen.speed_buttons[10].pressed.emit()
	screen._process(100)
	check(is_instance_valid(screen.departure_modal)
			and state.expedition_simulation.state.return_destination_id == "refuel_station_1",
			"Detour arrival preserves a manual return choice")
	var resume_button: Button
	for action: Button in screen.departure_modal.find_children("*", "Button", true, false):
		if action.get_meta("expedition_destination", "") == "refuel_station_1":
			resume_button = action
	check(resume_button != null and resume_button.text.begins_with("RESUME:"),
			"Arrival options clearly identify the original route without auto-departing")
	screen.queue_free()
	await settle()
	check(state.load_run_checkpoint(), "Reload investigated POI arrival")
	await open_screen()
	check(state.expedition_simulation.state.return_destination_id == "refuel_station_1",
			"Return destination survives POI Continue")
	screen._choose_departure("refuel_station_1")
	check(state.expedition_simulation.state.return_destination_id.is_empty(),
			"Explicit onward choice clears the detour return target")
	screen.speed_buttons[10].pressed.emit()
	screen._process(100)
	check(state.expedition_simulation.state.docked_location_id == "refuel_station_1"
			and state.expedition_simulation.state.pending_event_id.is_empty()
			and state.expedition_simulation.state.event_receipts.get("derelict_signal", false),
			"Return reaches the original destination without replaying the signal")
	print("EXPEDITION_EVENTS_CHECKS=%d failures=%d" % [checks, failures])
	screen.queue_free()
	await settle()
	quit(1 if failures else 0)
