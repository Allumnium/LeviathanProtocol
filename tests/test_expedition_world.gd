extends SceneTree

const State = preload("res://scripts/expedition_state.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func settle() -> void:
	await process_frame
	await process_frame


func run() -> void:
	root.size = Vector2i(1280, 720)
	var state = root.get_node("GameState")
	check(state.run_save_path == "user://expedition_run.json",
			"New runs default to the isolated expedition save namespace")
	state.run_save_path = "user://expedition-world-test.json"
	if not state.start_new_run(1, 151):
		check(false, "Fresh expedition run starts and checkpoints: " + state.last_save_error)
		quit(1)
		return
	check(true, "Fresh expedition run starts and checkpoints")
	check(state.checkpoint_summary().get("expedition", false),
			"Continue summary recognizes the expedition checkpoint")
	for authored: Dictionary in state.expedition_simulation.events:
		state.expedition_simulation.state.event_receipts[authored.id] = true
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	screen.active_tab = "FLEET"
	root.add_child(screen)
	current_scene = screen
	await settle()
	if screen.get("travel_controls") == null:
		check(false, "Existing hangar screen mounts its travel controls on the Fleet page")
		quit(1)
		return
	var expedition = state.expedition_simulation
	check(screen.name == "Hangar" and screen.travel_controls != null
			and screen.formation_view != null,
			"Existing Fleet page remains the continuous expedition view")
	check(state.fleet.size() > 1 and state.fleet[0].flagship,
			"Starting flagship remains the active ship in the world")
	check(screen.find_children("*", "OptionButton", true, false).is_empty(),
			"Travel header has no destination dropdown")
	check(screen.travel_controls.get_parent() == screen.command_header.middle
			and screen.tabs.get_parent() == screen.command_header.left
			and screen.travel_controls.get_child(0).get_child_count() == 4
			and screen.find_child("ExpeditionClearRoute", true, false) == null,
			"Header groups only Pause, Play and 10x icons with the multiplier label")
	screen.travel_pause_button.pressed.emit()
	check(State.PauseReason.USER in expedition.state.pause_reasons, "Pause icon pauses simulation")
	screen.speed_buttons[10].pressed.emit()
	check(expedition.state.requested_speed == 10 and expedition.state.pause_reasons.is_empty(),
			"Fast-forward icon unpauses at exactly 10x")
	expedition.set_pause(State.PauseReason.EVENT, true)
	screen.speed_buttons[1].pressed.emit()
	check(expedition.state.requested_speed == 1
			and State.PauseReason.EVENT in expedition.state.pause_reasons,
			"Play selects 1x without clearing a mandatory interruption")
	expedition.set_pause(State.PauseReason.EVENT, false)
	var starting_position: Vector2 = expedition.state.position_nu
	var formation: Control = screen.formation_view
	var starfield: Control = screen.formation_view.starfield
	var star_position: Vector2 = starfield._get_star_position(starfield._stars[0])
	check(screen.departure_button.visible and screen.departure_button.text == "SET COURSE"
			and not is_instance_valid(screen.get_node_or_null("DepartureChoices")),
			"Docked fleets get a Set Course shortcut instead of a forced destination modal")
	screen._on_expedition_speed_pressed(20)
	_select_destination(screen, "refuel_station_1")
	check(expedition.state.travel_state == State.TravelState.CRUISING
			and expedition.state.destination_location_id == "refuel_station_1",
			"Selecting a destination starts automatic travel")
	screen._process(0.25)
	var first_position: Vector2 = expedition.state.position_nu
	var distance_moved := first_position.distance_to(starting_position)
	check(distance_moved > 0.0 and distance_moved < 240.0,
			"Fleet moves continuously without teleporting to the destination")
	await settle()
	check(is_instance_valid(formation) and screen.formation_view == formation,
			"Undocking updates station actions without rebuilding the Fleet view")
	check(not starfield._get_star_position(starfield._stars[0]).is_equal_approx(star_position),
			"Existing Fleet background scrolls with travel distance")
	check(screen.feedback.text.contains("NU"),
			"Existing Fleet page shows remaining course distance")
	check(current_scene == screen, "Travel does not replace the expedition scene")

	screen._on_expedition_stop_pressed()
	var stopped_position: Vector2 = expedition.state.position_nu
	screen._process(0.5)
	check(expedition.state.travel_state == State.TravelState.STOPPED
			and expedition.state.position_nu.is_equal_approx(stopped_position),
			"Stop halts fleet movement while retaining its course")
	screen._on_expedition_stop_pressed()
	screen._on_expedition_pause_pressed()
	var paused_position: Vector2 = expedition.state.position_nu
	screen._process(0.5)
	check(State.PauseReason.USER in expedition.state.pause_reasons
			and expedition.state.position_nu.is_equal_approx(paused_position),
			"Pause halts the simulation independently of route stop")
	screen._on_expedition_pause_pressed()
	screen._process(0.25)
	check(expedition.state.position_nu.distance_to(paused_position) > 0.0,
			"Unpausing resumes continuous travel")
	var before_reroute: Vector2 = expedition.state.position_nu
	_select_destination(screen, "derelict_1")
	check(expedition.state.destination_location_id == "derelict_1"
			and expedition.state.position_nu.is_equal_approx(before_reroute),
			"Mid-flight rerouting preserves the fleet's current position")
	screen._process(5.0)
	check(expedition.state.travel_state == State.TravelState.STOPPED
			and expedition.state.destination_location_id.is_empty(),
			"POI arrival ends the active leg without swapping scenes")
	check(is_instance_valid(screen.arrival_modal) and screen.arrival_location_id == "derelict_1"
			and screen.arrival_modal.find_child("ArrivalSetCourse", true, false) != null
			and screen.arrival_modal.find_child("ArrivalRepairAll", true, false) == null,
			"POI arrival describes the location and offers only applicable actions")
	var arrival_clock: float = expedition.state.simulation_seconds
	var arrival_point: Vector2 = expedition.state.position_nu
	screen._process(2.0)
	check(expedition.state.simulation_seconds > arrival_clock
			and expedition.state.position_nu.is_equal_approx(arrival_point),
			"Arrival never holds the simulation for a destination choice")
	screen._on_expedition_speed_pressed(20)
	_select_destination(screen, "refuel_station_1")
	screen._process(4.5)
	check(expedition.state.travel_state == State.TravelState.DOCKED
			and expedition.state.docked_location_id == "refuel_station_1",
			"Station arrival docks the fleet and opens its refueling service")
	check(is_instance_valid(screen.arrival_modal) and screen.arrival_location_id == "refuel_station_1"
			and screen.arrival_modal.find_child("ArrivalRefuel", true, false) != null
			and screen.arrival_modal.find_child("ArrivalShipyard", true, false) != null,
			"Docking describes the station with Refuel and Shipyard actions")
	var credits_before_refuel: int = state.credits
	screen._on_expedition_refuel_pressed()
	check(is_equal_approx(expedition.state.fuel, expedition.state.fuel_capacity)
			and state.credits < credits_before_refuel
			and screen.travel_fuel.text.contains("%d / %d" % [
				roundi(expedition.state.fuel), roundi(expedition.state.fuel_capacity)]),
			"Refueling atomically restores fuel and charges credits")
	check(state.save_expedition_checkpoint(), "Expedition position checkpoints atomically")
	var saved_position: Vector2 = expedition.state.position_nu
	for viewport_size: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport_size
		screen._refresh_expedition_controls()
		await settle()
		check(screen.travel_controls.is_visible_in_tree() and screen.travel_fuel.is_visible_in_tree(),
				"Fleet travel controls remain available at %s" % viewport_size)
		check(screen.travel_controls.size.y <= 32
				and screen.travel_controls.get_global_rect().position.y >= screen.tabs.global_position.y
				and screen.travel_controls.get_global_rect().end.x <= screen.research_button.global_position.x
				and screen.header_wallet.get_global_rect().end.x <= screen.size.x,
				"Time panel fits beside existing header items at %s" % viewport_size)
		var arrival_panel: Control = screen.arrival_modal.find_child("ArrivalDialogPanel", true, false)
		check(screen.get_global_rect().encloses(arrival_panel.get_global_rect()),
				"Arrival dialog stays within the viewport at %s" % viewport_size)
	check(state.load_run_checkpoint(), "Saved expedition can continue from its committed state")
	check(state.expedition_simulation.state.position_nu.is_equal_approx(saved_position),
			"Continue restores the saved continuous position")
	check(current_scene == screen, "Restoring the checkpoint does not change scenes")
	screen._refresh()
	await settle()
	var valid_save_path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-save.json"
	_select_destination(screen, "derelict_1")
	check(State.PauseReason.SAVE_ERROR in state.expedition_simulation.state.pause_reasons
			and state.expedition_simulation.state.destination_location_id.is_empty(),
			"Failed route checkpoint rolls back and pauses on a save error")
	screen._refresh_expedition_controls()
	check(not screen.feedback.text.is_empty() and screen.travel_retry_button.visible,
			"Failed course change reports the error with a retry action")
	state.run_save_path = valid_save_path
	screen._on_expedition_retry_pressed()
	check(State.PauseReason.SAVE_ERROR not in state.expedition_simulation.state.pause_reasons,
			"Retry commits the paused state before allowing travel again")
	print("EXPEDITION_WORLD_CHECKS=%d failures=%d" % [checks, failures])
	screen.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)


func _select_destination(screen: Control, location_id: String) -> void:
	screen._set_course(location_id)
