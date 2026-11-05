extends "res://tests/test_research_travel.gd"

func frozen_wait(title: String) -> void:
	var before: Dictionary = state.hangar_snapshot()
	var accumulator: float = state.expedition_simulation.accumulator
	var result: Dictionary = state.advance_expedition(30, true)
	check(result.ok and result.saved and not result.repaired and result.income == 0,
		title + ": idle frame saves without healing or income")
	check(SaveValidation.same(before, state.hangar_snapshot())
		and state.expedition_simulation.accumulator == accumulator,
		title + ": hull, expedition clock, travel yields and loads stay unchanged")

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://stationary-repair.json"
	start(["civil_hospitality", "field_engineering"])
	var researched: Dictionary = state.hangar_snapshot()
	researched.research.research_ids.append("renewal_i")
	researched.research.branch_choices.survival = "renewal"
	check(state._commit_hangar(researched), "Persist earned Renewal with its branch commitment")
	state.fleet[0].hull_hp -= 100
	check(state.save_expedition_checkpoint(), "Persist damaged docked fleet")
	check(state.can_use_shipyard(), "Idle regression starts at a real shipyard")
	frozen_wait("Docked shipyard")
	check(state.expedition_simulation.set_speed(20), "Choose fast-forward while docked")
	frozen_wait("Docked fast-forward")
	check(state.load_run_checkpoint(), "Continue damaged docked save")
	frozen_wait("Docked Continue")
	var sim = state.expedition_simulation
	check(state.depart_expedition("refuel_station_1") and sim.set_speed(1), "Begin moving repair check")
	var hull: float = state.fleet[0].hull_hp
	var seconds: float = sim.state.simulation_seconds
	var rate: float = state.self_repair_rate(state.fleet[0])
	check(state.advance_expedition(2, true).ok
		and is_equal_approx(sim.state.simulation_seconds - seconds, 2)
		and is_equal_approx(state.fleet[0].hull_hp - hull, rate * 2),
		"Moving fleet repairs at the existing Renewal-modified per-second rate")
	check(sim.stop(), "Stop mid-route")
	frozen_wait("Stopped mid-route")
	check(state.load_run_checkpoint(), "Continue stopped route")
	sim = state.expedition_simulation
	frozen_wait("Stopped Continue")
	check(sim.resume() and sim.set_pause(Travel.PauseReason.USER, true), "Pause resumed route")
	frozen_wait("Paused cruise")
	check(sim.set_pause(Travel.PauseReason.USER, false), "Unpause resumed route")
	hull = state.fleet[0].hull_hp
	check(state.advance_expedition(1, true).ok and state.fleet[0].hull_hp > hull,
		"Resuming map movement resumes passive repair")
	var before: Dictionary = state.hangar_snapshot()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/blocked-moving-repair.json"
	var failed: Dictionary = state.advance_expedition(1, true)
	check(not failed.ok and not failed.error.is_empty()
		and SaveValidation.same(before, state.hangar_snapshot()),
		"Moving repair and clock roll back together on save failure")
	state.run_save_path = path
	check(sim.set_speed(20) and state.advance_expedition(100, true).ok
		and sim.state.travel_state == Travel.TravelState.DOCKED,
		"Fast-forward clips at shipyard arrival")
	state.fleet[0].hull_hp -= 20
	frozen_wait("New shipyard arrival")
	check(state.depart_expedition("derelict_1") and sim.set_speed(20)
		and state.advance_expedition(100, true).ok and sim.state.travel_state == Travel.TravelState.STOPPED,
		"Travel to a non-shipyard POI")
	state.fleet[0].hull_hp -= 20
	frozen_wait("Non-shipyard POI")
	check(state.depart_expedition("refuel_station_1"), "Depart POI")
	sim.state.fuel = 0
	hull = state.fleet[0].hull_hp
	seconds = sim.state.simulation_seconds
	check(state.advance_expedition(1, true).ok and sim.state.travel_state == Travel.TravelState.STOPPED,
		"Empty fuel stops movement")
	check(state.fleet[0].hull_hp == hull and sim.state.simulation_seconds == seconds,
		"A cruise tick with no movement grants no clock time or repair")
	frozen_wait("Fuel-empty stop")
	sim.state.pause_reasons.clear()
	sim.state.travel_state = Travel.TravelState.ENGAGED
	frozen_wait("Encounter-blocked map")
	state.battle_pending = true
	before = state.hangar_snapshot()
	check(state.advance_expedition(30).ok and SaveValidation.same(before, state.hangar_snapshot()),
		"Battle-pending map does not heal or advance expedition time")
	print("STATIONARY REPAIR: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
