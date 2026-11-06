extends SceneTree

const Travel = preload("res://scripts/expedition_state.gd")
var checks := 0
var failures := 0
var state: Node
var credit_notifications := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for index in range(4):
		await process_frame

func capture_native(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://" + filename) == OK,
		"Save focused native travel research capture: " + filename)

func start(research_ids: Array = []) -> void:
	check(state.start_new_run(1, 847), "Start travel research fixture")
	for event: Dictionary in state.expedition_simulation.events:
		state.expedition_simulation.state.event_receipts[event.id] = true
	var data: Dictionary = state.hangar_snapshot()
	data.research.research_ids.append_array(research_ids)
	check(state._commit_hangar(data), "Persist travel research and isolate authored encounters")
	credit_notifications = 0

func advance_seconds(seconds: float, frame := 1.0 / 60.0) -> void:
	while seconds > 0.00000001:
		var delta := minf(frame, seconds)
		var result: Dictionary = state.advance_expedition(delta)
		if not result.ok:
			check(false, "Advance travel research: " + str(result.error))
			return
		seconds -= delta
	check(state.advance_expedition(0.0, true).ok, "Persist final travel tick")

func text_under(node: Node) -> String:
	var text := ""
	if node is ResourceText:
		text += node.source_text + "\n"
	elif node is Label:
		text += node.text + "\n"
	for child in node.get_children():
		text += text_under(child)
	return text

func registry_checks() -> void:
	var registry := GameDefinitions.snapshot()
	check(ResearchRules.validate_registry(registry).is_empty(), "Travel modifiers validate in the shared registry")
	for id: String in ["field_engineering", "civil_hospitality"]:
		var definition := ResearchViewModel.find(registry, "research", id)
		for value: Variant in [0, -1, NAN, INF, "1", null, 101]:
			var invalid := registry.duplicate(true)
			var node := ResearchViewModel.find(invalid, "research", id)
			node.grants.modifiers[0].value = value
			check(not ResearchRules.validate_registry(invalid).is_empty(), "Reject malformed travel modifier: " + str(value))
		check(definition.cost_rp == 20 and definition.prerequisite_ids == ["foundation"]
			and definition.family_id.is_empty(), "Travel upgrades retain costs and do not force branches")
	for value: Variant in [0, 1, -1, NAN, INF, "1.25", null, 2.01]:
		var invalid := registry.duplicate(true)
		var node := ResearchViewModel.find(invalid, "research", "field_engineering")
		node.grants.modifiers[1].value = value
		check(not ResearchRules.validate_registry(invalid).is_empty(), "Reject malformed cruise multiplier: " + str(value))
	check(ResearchViewModel.description(HangarResearch.view_registry(), "field_engineering") == "Cruise faster using less fuel."
		and ResearchViewModel.description(HangarResearch.view_registry(), "civil_hospitality") == "Travel earns credits for the expedition.",
		"Travel descriptions remain short gameplay sentences")

func rates_and_speeds() -> void:
	start()
	var credits: int = state.credits
	check(state.depart_expedition("refuel_station_1"), "Start unresearched cruise")
	advance_seconds(10)
	check(is_equal_approx(state.expedition_simulation.state.traveled_days, 1)
		and is_equal_approx(state.expedition_simulation.state.fuel, 96)
		and state.credits == credits and state.run_score.credits_earned == 0,
		"Without research one day costs four fuel and earns no passive credits")
	for speed: int in Travel.SPEEDS:
		for frame: float in [1.0 / 60, 0.2]:
			start(["civil_hospitality", "field_engineering"])
			state.credits = -10
			check(state.depart_expedition("refuel_station_1")
				and state.expedition_simulation.set_speed(speed), "Start researched cruise at speed " + str(speed))
			advance_seconds(8.0 / speed, frame)
			var simulation = state.expedition_simulation
			check(is_equal_approx(simulation.state.traveled_distance_nu, 40)
				and is_equal_approx(simulation.state.traveled_days, 1),
				"Faster cruise covers one day in eight simulation seconds at every speed/frame size")
			check(is_equal_approx(simulation.state.simulation_seconds, 8),
				"Research changes cruise distance, not the simulation clock")
			check(is_equal_approx(simulation.state.fuel, 97),
				"Field Engineering reduces actual fuel consumption by exactly 25 percent")
			check(state.credits == -6 and state.run_score.credits_earned == 4,
				"Civil Hospitality earns exactly four credits per travel day, including in debt")
			check(is_equal_approx(state.research_points, ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet()))),
				"Fuel and income research do not change distance-based lab production")
			check(credit_notifications > 0, "Passive income refreshes the existing wallet")
	start(["civil_hospitality"])
	var simulation = state.expedition_simulation
	var before: Dictionary = simulation.state.snapshot()
	for multiplier: float in [0.0, -0.5, 1.5, INF, NAN]:
		check(not simulation.advance(1.0, multiplier) and not simulation.last_error.is_empty()
			and SaveValidation.same(before, simulation.state.snapshot()),
			"Invalid fuel multipliers fail explicitly before mutation")
	for multiplier: float in [0.0, -0.5, 0.99, 2.01, INF, NAN]:
		check(not simulation.advance(1.0, 1.0, multiplier) and not simulation.last_error.is_empty()
			and SaveValidation.same(before, simulation.state.snapshot()),
			"Invalid cruise multipliers fail explicitly before mutation")

func cruise_timing() -> void:
	var snapshots: Array[Dictionary] = []
	for researched: bool in [false, true]:
		start(["field_engineering", "civil_hospitality"] if researched else ["civil_hospitality"])
		state.fleet[0].hull_hp -= 100
		var hull_before: float = state.fleet[0].hull_hp
		var repair_rate: float = state.self_repair_rate(state.fleet[0])
		check(state.depart_expedition("refuel_station_1"), "Start equal-time cruise comparison")
		advance_seconds(2)
		var simulation = state.expedition_simulation
		snapshots.append(simulation.state.snapshot())
		check(is_equal_approx(state.fleet[0].hull_hp - hull_before, repair_rate * 2),
			"Faster cruise does not accelerate simulation-time hull repair")
		check(is_equal_approx(state.expedition_cruise_rate(), 5 if researched else 4),
			"Shared effective cruise rate derives from earned research")
	check(is_equal_approx(snapshots[1].traveled_distance_nu, snapshots[0].traveled_distance_nu * 1.25)
		and is_equal_approx(snapshots[1].simulation_seconds, snapshots[0].simulation_seconds),
		"Field Engineering moves exactly 25 percent farther in equal simulation time")
	var boundaries: Array[Dictionary] = []
	for researched: bool in [false, true]:
		start(["field_engineering"] if researched else [])
		var simulation = state.expedition_simulation
		simulation.state.event_receipts.erase("patrol_inspection")
		check(state.depart_expedition("refuel_station_1") and simulation.set_speed(20),
			"Start fast-forward zone admission fixture")
		check(state.advance_expedition(10, true).ok and simulation.state.pending_event_id == "patrol_inspection",
			"Faster cruise still admits authored zone encounters")
		boundaries.append(simulation.state.snapshot())
	check(Vector2(boundaries[0].position_nu[0], boundaries[0].position_nu[1]).is_equal_approx(
			Vector2(boundaries[1].position_nu[0], boundaries[1].position_nu[1]))
		and is_equal_approx(boundaries[0].traveled_distance_nu, boundaries[1].traveled_distance_nu)
		and boundaries[1].simulation_seconds < boundaries[0].simulation_seconds,
		"Authored zone boundary is unchanged and reached sooner with cruise research")

func stopped_and_boundaries() -> void:
	start(["civil_hospitality", "field_engineering"])
	var before: Dictionary = state.hangar_snapshot()
	advance_seconds(3)
	check(state.credits == before.credits and state.run_score == before.score
		and state.expedition_simulation.state.fuel == before.expedition.fuel,
		"Docked waiting earns no credits and spends no fuel")
	check(state.depart_expedition("refuel_station_1") and state.expedition_simulation.stop(),
		"Stop cruise before moving")
	advance_seconds(3)
	check(state.credits == before.credits and state.expedition_simulation.state.traveled_days == 0,
		"Stopped waiting cannot farm income")
	check(state.expedition_simulation.resume()
		and state.expedition_simulation.set_pause(Travel.PauseReason.USER, true), "Pause active cruise")
	advance_seconds(3)
	check(state.credits == before.credits and state.expedition_simulation.state.traveled_days == 0,
		"Paused waiting cannot farm income")
	check(state.expedition_simulation.set_pause(Travel.PauseReason.USER, false), "Resume after pause")
	state.expedition_simulation.state.travel_state = Travel.TravelState.ENGAGED
	advance_seconds(3)
	check(state.credits == before.credits and state.expedition_simulation.state.traveled_days == 0,
		"Engagement time earns no travel credits")
	state.battle_pending = true
	check(state.advance_expedition(30).income == 0 and state.credits == before.credits,
		"Transitioned battles cannot generate passive income")
	state.battle_pending = false

	start(["civil_hospitality", "field_engineering"])
	state.expedition_simulation.state.fuel = 0.9
	check(state.depart_expedition("refuel_station_1") and state.expedition_simulation.set_speed(20),
		"Start fuel-limited researched cruise")
	before = state.hangar_snapshot()
	var result: Dictionary = state.advance_expedition(10, true)
	check(result.ok and result.boundary and result.saved
		and is_equal_approx(state.expedition_simulation.state.traveled_distance_nu, 12)
		and state.expedition_simulation.state.fuel == 0
		and Travel.PauseReason.FUEL in state.expedition_simulation.state.pause_reasons,
		"Reduced fuel rate clips travel at the exact exhaustion boundary even at fast-forward")
	check(result.income == 1 and state.credits == before.credits + 1
		and state.run_score.credits_earned == before.score.credits_earned + 1,
		"Fuel exhaustion pays for traveled distance only")
	check(state.advance_expedition(30, true).income == 0 and state.credits == before.credits + 1,
		"Stranded waiting does not repeat the last distance payout")

	start(["civil_hospitality", "field_engineering"])
	state.expedition_simulation.state.event_receipts.erase("derelict_signal")
	check(state.depart_expedition("refuel_station_1") and state.expedition_simulation.set_speed(20),
		"Start event-limited researched cruise")
	before = state.hangar_snapshot()
	result = state.advance_expedition(10, true)
	check(result.ok and result.boundary and state.expedition_simulation.state.pending_event_id == "derelict_signal"
		and is_equal_approx(state.expedition_simulation.state.traveled_distance_nu, 80)
		and is_equal_approx(state.expedition_simulation.state.fuel, 94)
		and result.income == 8 and state.credits == before.credits + 8,
		"Event admission keeps its exact distance, with researched fuel and income")
	check(state.advance_expedition(30).income == 0 and state.credits == before.credits + 8,
		"Unresolved events do not generate income")

func persistence_and_unlocks() -> void:
	start(["civil_hospitality", "field_engineering"])
	check(state.depart_expedition("refuel_station_1"), "Start fractional-income cruise")
	advance_seconds(0.8)
	var before: Dictionary = state.hangar_snapshot()
	check(state.load_run_checkpoint() and SaveValidation.same(before, state.hangar_snapshot()),
		"Continue preserves partial credit distance, fuel and progress without new save fields")
	check(state.advance_expedition(0, true).income == 0 and state.credits == before.credits,
		"Continue cannot repay past distance")
	advance_seconds(1.2)
	check(state.credits == before.credits + 1 and state.run_score.credits_earned == 1
		and is_equal_approx(state.expedition_simulation.state.fuel, 99.25),
		"Partial travel combines across Continue into exactly one credit")
	state.fleet[0].hull_hp -= 10
	check(state.save_run_checkpoint(), "Persist damaged hull before failed travel save")
	before = state.hangar_snapshot()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-travel-research.json"
	var failed: Dictionary = state.advance_expedition(2, true)
	check(not failed.ok and failed.income == 0 and not failed.error.is_empty()
		and SaveValidation.same(before, state.hangar_snapshot()),
		"Failed travel save rolls back credits, score, fuel, distance, labs and health together")
	state.run_save_path = path
	check(state.advance_expedition(2, true).income == 1 and state.credits == before.credits + 1,
		"Retry earns the rolled-back income exactly once")

	start()
	check(state.depart_expedition("refuel_station_1"), "Start cruise before earning upgrades")
	advance_seconds(5)
	before = state.hangar_snapshot()
	var proposal := before.duplicate(true)
	proposal.research.research_ids.append_array(["civil_hospitality", "field_engineering"])
	state.run_save_path = "res://project.godot/no-travel-research.json"
	check(not state._commit_hangar(proposal) and SaveValidation.same(before, state.hangar_snapshot())
		and is_equal_approx(state.expedition_fuel_rate(), 0.1)
		and is_equal_approx(state.expedition_cruise_rate(), 4),
		"Failed research transaction leaves future travel rates unchanged")
	state.run_save_path = path
	check(state._commit_hangar(proposal) and state.credits == before.credits
		and is_equal_approx(state.expedition_fuel_rate(), 0.075)
		and is_equal_approx(state.expedition_cruise_rate(), 5), "Earned upgrades affect future travel without retroactive payouts")
	check(state.load_run_checkpoint() and state.current_research_ids.has("civil_hospitality")
		and is_equal_approx(state.expedition_fuel_rate(), 0.075)
		and is_equal_approx(state.expedition_cruise_rate(), 5),
		"Already-earned upgrades derive their effects on Continue")
	advance_seconds(2)
	check(state.credits == before.credits + 1
		and is_equal_approx(state.expedition_simulation.state.fuel, float(before.expedition.fuel) - 0.75),
		"Only new distance receives researched income and fuel economy")

	start()
	proposal = state.hangar_snapshot()
	proposal.research.research_points = 19.6
	check(HangarCheckpoint.valid(proposal), "Nearly completed research fixture is valid: " + str(proposal.research))
	check(state._commit_hangar(proposal), "Persist nearly completed income research: " + state.last_save_error)
	check(state.depart_expedition("refuel_station_1"), "Depart with nearly completed income research: " + state.last_save_error)
	before = state.hangar_snapshot()
	var result: Dictionary = state.advance_expedition(1, true)
	check(result.ok and result.research_ready and result.income == 0
		and not state.current_research_ids.has("civil_hospitality") and state.credits == before.credits,
		"Completing research during travel does not pay for the preceding frame")
	# Isolate this offered upgrade from the seeded draw; eligibility is still validated.
	proposal = state.hangar_snapshot()
	proposal.research.research_offer = ["civil_hospitality"]
	check(state._commit_hangar(proposal) and state.choose_research("civil_hospitality"), "Choose earned income upgrade during cruise")
	advance_seconds(1.5)
	check(state.credits == before.credits + 1, "Chosen research starts paying on subsequent travel")
	start()
	proposal = state.hangar_snapshot()
	proposal.research.research_points = 19.6
	check(state._commit_hangar(proposal) and state.depart_expedition("refuel_station_1"),
		"Start cruise with nearly completed fuel research")
	result = state.advance_expedition(1, true)
	check(result.ok and result.research_ready
		and is_equal_approx(state.expedition_simulation.state.fuel, 99.6)
		and is_equal_approx(state.expedition_simulation.state.traveled_distance_nu, 4),
		"Travel research neither discounts nor accelerates the frame that completed it")
	proposal = state.hangar_snapshot()
	proposal.research.research_offer = ["field_engineering"]
	check(state._commit_hangar(proposal) and state.choose_research("field_engineering"), "Choose earned cruise upgrade")
	advance_seconds(2)
	check(is_equal_approx(state.expedition_simulation.state.fuel, 98.85),
		"Travel research starts increasing speed and reducing consumption on subsequent travel")

func arrival_and_ui() -> void:
	start(["civil_hospitality", "field_engineering"])
	check(state.depart_expedition("refuel_station_1") and state.expedition_simulation.set_speed(20),
		"Start trading arrival with research")
	var before: Dictionary = state.hangar_snapshot()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-travel-arrival.json"
	var failed: Dictionary = state.advance_expedition(10, true)
	check(not failed.ok and failed.income == 0 and failed.delivered == 0
		and credit_notifications == 0 and SaveValidation.same(before, state.hangar_snapshot()),
		"Failed arrival saves no fuel use, travel income, cargo payment or wallet success feedback")
	state.run_save_path = path
	var result: Dictionary = state.advance_expedition(10, true)
	var expected := floori(state.expedition_simulation.state.traveled_days * 4 + 0.00000001)
	check(result.ok and result.saved and result.boundary and result.income == expected
		and result.delivered == 30 and state.credits == before.credits + expected + 30
		and state.run_score.credits_earned == expected + 30,
		"Docking settles travel income and ordinary cargo income once in the same checkpoint: %s / credits %d / score %s" \
			% [str(result), state.credits, str(state.run_score)])
	var committed: Dictionary = state.hangar_snapshot()
	check(state.load_run_checkpoint() and SaveValidation.same(committed, state.hangar_snapshot())
		and state.advance_expedition(10, true).income == 0 and state.credits == committed.credits,
		"Docked Continue neither repeats passive income nor delivers cargo twice")

	start()
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	screen.active_tab = "MAP"
	screen._refresh()
	await settle()
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		for researched: bool in [false, true]:
			var proposal: Dictionary = state.hangar_snapshot()
			proposal.research.research_ids = ["foundation", "field_engineering"] if researched else ["foundation"]
			check(state._commit_hangar(proposal), "Update quote research fixture")
			state.expedition_simulation.state.fuel = 20
			screen.map_selected_id = "refuel_station_1"
			screen._render_map_details()
			await settle()
			var text := text_under(screen.map_details)
			var quote := "19 fuel" if researched else "25 fuel (out of range)"
			check(text.contains(quote) and (researched or text.contains("out of range"))
				and (not researched or not text.contains("out of range")),
				"Actual Map fuel quote and range use the researched consumption at " + str(resolution))
			var destination: Dictionary = state.expedition_simulation.locations["refuel_station_1"]
			var distance: float = state.expedition_simulation.state.position_nu.distance_to(Vector2(destination.position[0], destination.position[1]))
			var rate := 5.0 if researched else 4.0
			check(text.contains("ETA %ds at 1x · %ds at 10x" % [ceili(distance / rate), ceili(distance / rate / 10)]),
				"Selected-trip ETA uses the researched cruise rate at " + str(resolution))
			if resolution == Vector2i(1280, 720) and researched:
				await capture_native("cruise-map.png")
	var proposal: Dictionary = state.hangar_snapshot()
	proposal.research.research_ids = ["foundation", "civil_hospitality", "field_engineering"]
	check(state._commit_hangar(proposal) and state.depart_expedition("refuel_station_1"),
		"Start passive-income UI cruise")
	await settle()
	screen.active_tab = "MAP"
	screen._refresh()
	await settle()
	var map: Control = screen.graph
	map.camera_position = Vector2(17, 29)
	map.camera_zoom = 0.8
	map.user_moved = true
	check(state.advance_expedition(2, true).income == 1, "Earn one visible income tick on the Map")
	screen._update_expedition_readouts()
	var remaining: float = state.expedition_simulation.state.position_nu.distance_to(
		Vector2(state.expedition_simulation.locations["refuel_station_1"].position[0],
			state.expedition_simulation.locations["refuel_station_1"].position[1]))
	check(screen.feedback.text.contains("ETA %ds" % ceili(remaining / 5)),
		"Underway ETA shares the researched cruise rate")
	await settle()
	check(screen.graph == map and map.camera_position == Vector2(17, 29) and is_equal_approx(map.camera_zoom, 0.8)
		and screen.header.text == str(state.credits) and not screen.refresh_queued,
		"Income updates the wallet without rebuilding the Map or changing pan/zoom")
	check(state.advance_expedition(2, true).income == 1, "Further cruising earns the next income tick")
	await settle()
	check(screen.graph == map and map.camera_position == Vector2(17, 29) and is_equal_approx(map.camera_zoom, 0.8)
		and screen.header.text == str(state.credits) and not screen.delivery_readout.visible,
		"Income preserves the map view without a recurring delivery toast")
	await capture_native("cruise-research.png")
	screen.queue_free()
	await settle()

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://research-travel.json"
	state.credits_changed.connect(func() -> void: credit_notifications += 1)
	registry_checks()
	rates_and_speeds()
	cruise_timing()
	stopped_and_boundaries()
	persistence_and_unlocks()
	await arrival_and_ui()
	print("RESEARCH TRAVEL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
