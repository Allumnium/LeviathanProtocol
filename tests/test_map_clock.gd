extends "res://tests/test_fleet_redesign.gd"

var clock_completed := false

func map_clock() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://map-clock.json"
	check(state.start_new_run(1, 8404), "Start isolated map clock fixture")
	state.pending_intro = false
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	await settle()
	var sim = state.expedition_simulation
	check(sim.state.requested_speed == 8 and screen.travel_controls.get_child(0).get_child_count() == 2,
		"Map defaults to 8x with only Pause and Play controls")
	check(screen.find_child("ExpeditionSpeed*", true, false) == null, "Selectable map speeds are absent")
	check(screen._set_course("refuel_station_1", true), "Engage normal opening route")
	var seconds: float = sim.state.simulation_seconds
	var distance: float = sim.state.traveled_distance_nu
	screen._process(0.25)
	check(is_equal_approx(sim.state.simulation_seconds - seconds, 2)
		and is_equal_approx(sim.state.traveled_distance_nu - distance, state.expedition_cruise_rate() * 2), "Quarter-second map frame advances two travel seconds at fixed 8x")
	var map_tab: Button = screen.tabs.get_child(0)
	var fleet_tab: Button = screen.tabs.get_child(1)
	await click(fleet_tab)
	check(screen.active_tab == "FLEET", "Pointer switches to Fleet")
	var before: Dictionary = state.hangar_snapshot()
	screen._process(2)
	check(SaveValidation.same(before, state.hangar_snapshot()), "Fleet page freezes position, time, RP, income, fuel, hull and pause reasons")
	await click(map_tab)
	seconds = sim.state.simulation_seconds
	screen._process(0.25)
	check(is_equal_approx(sim.state.simulation_seconds - seconds, 2), "Unpaused travel resumes at 8x on return to Map")
	await click(screen.travel_pause_button)
	check(ExpeditionState.PauseReason.USER in sim.state.pause_reasons, "Manual pause remains available")
	await click(fleet_tab)
	before = state.hangar_snapshot()
	screen._process(2)
	await click(map_tab)
	screen._process(0.25)
	check(SaveValidation.same(before, state.hangar_snapshot()), "Returning to Map preserves manual pause and all travel state")
	await click(screen.travel_play_button)
	seconds = sim.state.simulation_seconds
	screen._process(0.25)
	check(is_equal_approx(sim.state.simulation_seconds - seconds, 2), "Play resumes at fixed 8x")
	check(sim.set_pause(ExpeditionState.PauseReason.EVENT, true), "Add mandatory interruption")
	await click(fleet_tab)
	await click(map_tab)
	await click(screen.travel_play_button)
	before = state.hangar_snapshot()
	screen._process(1)
	check(ExpeditionState.PauseReason.EVENT in sim.state.pause_reasons and SaveValidation.same(before, state.hangar_snapshot()), "Page return and Play never clear mandatory interruptions")
	sim.set_pause(ExpeditionState.PauseReason.EVENT, false)
	screen.hide()
	before = state.hangar_snapshot()
	screen._process(1)
	check(SaveValidation.same(before, state.hangar_snapshot()), "Hidden Map suspends travel without changing pause intent")
	screen.show()
	check(state.save_expedition_checkpoint() and state.load_run_checkpoint() and state.prepare_checkpoint_resume(), "Save and Continue active route")
	sim = state.expedition_simulation
	await click(fleet_tab)
	await click(map_tab)
	seconds = sim.state.simulation_seconds
	screen._process(0.25)
	check(sim.state.requested_speed == 8 and sim.state.simulation_seconds == seconds
		and ExpeditionState.PauseReason.USER in sim.state.pause_reasons, "Continue remains manually paused through page switches")
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		check(screen.command_header.get_global_rect().encloses(screen.travel_controls.get_global_rect()), "Pause/Play remain inside the shared header")
		await capture("map-fixed-speed-%d" % resolution.x)
	screen.queue_free()
	await settle()
	clock_completed = true

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	await map_clock()
	check(clock_completed, "Native clock/interaction section completed")
	print("MAP CLOCK: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
