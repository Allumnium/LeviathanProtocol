extends "res://tests/test_act1_content.gd"

func travel_to(location: String) -> void:
	check(state.depart_expedition(location, true), "Optional course " + location)
	state.expedition_simulation.set_speed(8)
	for tick in range(2000):
		if state.expedition_simulation.state.destination_location_id.is_empty():
			break
		var id := pending()
		if id == "derelict_signal":
			choose(id, "continue")
		elif id == "corporate_convoy":
			choose(id, "decline")
		elif id == "patrol_inspection":
			choose(id, "records")
		elif id == "free_trader":
			choose(id, "pass")
		elif not id.is_empty():
			check(false, "Unexpected early event " + id)
			break
		if not state.advance_expedition(0.1).ok or state.stranded():
			check(false, "Optional route interrupted")
			break
	check(state.expedition_simulation.location_here() == location, "Arrive optional location")

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://act1-edges.json"
	check(state.start_new_run(1, 8302), "Start edge fixture")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Events.DATA_PATH))
	var sim = state.expedition_simulation
	var bad := catalog.duplicate(true)
	bad.events[0].requires_flags = ["misspelled_story_flag"]
	check(not Events.valid(bad, sim.locations), "Reject unknown causal flag")
	bad = catalog.duplicate(true)
	bad.events[0].requires_flags = "not_an_array"
	check(not Events.valid(bad, sim.locations), "Reject malformed conditions")
	bad = catalog.duplicate(true)
	bad.events[0].text_variants = [{"text": "invalid", "chassis": "missing"}]
	check(not Events.valid(bad, sim.locations), "Reject unknown company variant")
	travel_to("anomaly_1")
	check(pending().is_empty() and not state.battle_pending, "Pre-incident nebula has no alien study")
	travel_to("derelict_1")
	choose("derelict_salvage", "careful")
	travel_to("settlement_1")
	choose("settlement_shortage", "decline")
	check(state.refuel_expedition(), "Refuel at ordinary settlement during long detour")
	travel_to("start_station")
	check(state.expedition_simulation.state.traveled_distance_nu > 700, "Detour exceeds old broadcast threshold")
	check(not state.expedition_simulation.state.flags.get("leviathan_protocol", false) and not state.battle_pending, "Distance alone cannot trigger Protocol or alien combat")
	check(state.refuel_expedition(), "Refuel after bounded civilian detour")
	check(state.depart_expedition("refuel_station_1", true), "Reach Meridian after detour")
	reach("meridian_welcome")
	choose("meridian_welcome", "dock")
	check(state.depart_expedition("settlement_1", true), "Save departure course")
	var before: Dictionary = state.hangar_snapshot()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-departure.json"
	check(not state.advance_expedition(0.1).ok and state.hangar_snapshot() == before, "Departure-boundary save failure rolls back movement, fuel, RP and pending event")
	state.run_save_path = path
	check(state.advance_expedition(0.1).ok and pending() == "meridian_departure", "Retry admits same departure once")
	choose("meridian_departure", "leave")
	protocol("meridian_left_report")
	# Isolate the zero-fuel boundary without another full route.
	check(state.start_new_run(1, 2), "Start fuel-boundary fixture")
	var fixture: Dictionary = state.hangar_snapshot()
	fixture.expedition.position_nu = [240, -35]
	fixture.expedition.docked_location_id = "refuel_station_1"
	fixture.expedition.visited_location_ids.append("refuel_station_1")
	fixture.expedition.flags.meridian_visited = true
	fixture.expedition.event_receipts.meridian_welcome = true
	fixture.expedition.fuel = 0
	check(state._commit_hangar(fixture), "Commit empty-tank port fixture")
	check(state.expedition_simulation.restore(fixture.expedition), "Apply empty-tank travel fixture")
	check(state.depart_expedition("settlement_1", true), "Set empty-tank course")
	state.advance_expedition(0.1)
	check(pending().is_empty() and state.stranded(), "No departure incident without movement; fuel recovery remains available")
	check(not state.rescue_quote().is_empty(), "Empty tank retains actionable recovery")
	# Actual side-event transactions, disabled funding and variant text.
	check(state.start_new_run(1, 3), "Start side-event fixture")
	state.expedition_simulation.state.pending_event_id = "corporate_convoy"
	state.expedition_simulation.state.pause_reasons.append(Travel.PauseReason.ENCOUNTER)
	state.expedition_simulation.state.fuel = 9
	before = state.hangar_snapshot()
	check(not state.resolve_expedition_event("corporate_convoy", "transfer") and state.hangar_snapshot() == before, "Fuel transfer cannot underpay")
	state.expedition_simulation.state.fuel = 10
	choose("corporate_convoy", "transfer")
	check(state.credits == 725 and state.expedition_simulation.state.fuel == 0, "Transfer debits ten fuel for twenty-five credits")
	check(not state.resolve_expedition_event("corporate_convoy", "transfer"), "Transfer receipt prevents repeat payout")
	var nebula := Events.find(state.expedition_simulation.events, "nebula_study")
	check(state.expedition_event_text(nebula).begins_with("Your labs"), "Living lab supplies science observation")
	for ship: HangarShip in state.fleet:
		ship.hull_hp = -1
	check(state.expedition_event_text(nebula) == nebula.text, "Destroyed labs never supply observation")
	opening()
	choose("meridian_departure", "return")
	reach("first_contact")
	choose("first_contact", "fight")
	var battle := BattleSimulation.new()
	check(battle.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, state.battle_simulation_seed(), state.battle_support_context()), "Set up terminal outcome")
	battle.battle_id = state.battle_identity()
	battle.phase = BattleSimulation.Phase.DEFEAT
	for ship: HangarShip in state.fleet:
		if ship.flagship:
			ship.hull_hp = -1
	check(state.settle_battle(battle) and state.run_ended and not state.expedition_simulation.state.flags.get("meridian_saved", false), "Flagship loss ends run without rescue outcome")
	check(not state.resolve_expedition_event("protocol_broadcast", "acknowledge"), "Terminal loss cannot progress story")
	print("ACT I EDGES: %d checks, %d failures; COMPLETE" % [checks, failures])
	quit(0 if failures == 0 else 1)
