extends SceneTree

const Events = preload("res://scripts/expedition_events.gd")
const Travel = preload("res://scripts/expedition_state.gd")
var state: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func pending() -> String:
	return state.expedition_simulation.state.pending_event_id

func choose(id: String, choice: String) -> void:
	check(pending() == id and state.resolve_expedition_event(id, choice), "Resolve " + id + "/" + choice)

func reach(id: String) -> void:
	for index in range(2000):
		if pending() == id:
			return
		if pending() == "derelict_signal":
			choose(pending(), "continue")
		elif pending() == "patrol_inspection":
			choose(pending(), "records")
		elif not pending().is_empty():
			break
		var result: Dictionary = state.advance_expedition(0.1)
		if not result.ok:
			break
	check(pending() == id, "Reach " + id + " (got " + pending() + ")")

func opening() -> void:
	check(state.start_new_run(1, 8302), "Start authored opening")
	check(not state.depart_expedition("act_2_gate", true), "Gate unavailable before Protocol")
	check(state.depart_expedition("refuel_station_1", true), "Course to Meridian")
	state.expedition_simulation.set_speed(8)
	reach("meridian_welcome")
	check(not state.battle_pending and not state.expedition_simulation.state.flags.get("meridian_incident", false), "Civilian opening has no aliens")
	choose("meridian_welcome", "dock")
	check(state.can_use_shipyard(), "Meridian services before departure")
	check(state.depart_expedition("settlement_1", true), "Depart ordinary port")
	check(pending().is_empty(), "Course selection alone does not cause incident")
	state.expedition_simulation.set_pause(Travel.PauseReason.USER, true)
	state.advance_expedition(1)
	check(pending().is_empty(), "Paused departure does not cause incident")
	state.expedition_simulation.set_pause(Travel.PauseReason.USER, false)
	reach("meridian_departure")
	check(state.expedition_simulation.state.position_nu != Vector2(240, -35), "Incident follows actual movement")
	check(state.load_run_checkpoint() and pending() == "meridian_departure", "Continue preserves departure choice")
	state.expedition_simulation.set_pause(Travel.PauseReason.USER, false)

func settle(phase: int) -> void:
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0,
		state.battle_simulation_seed(), state.battle_support_context()), "Initialize Meridian outcome fixture")
	sim.battle_id = state.battle_identity()
	sim.phase = phase as BattleSimulation.Phase
	var before: Dictionary = state.hangar_snapshot()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-story.json"
	check(not state.settle_battle(sim) and state.hangar_snapshot() == before, "Failed settlement preserves outcome and reward")
	state.run_save_path = path
	check(state.settle_battle(sim), "Commit Meridian outcome")
	before = state.hangar_snapshot()
	check(not state.settle_battle(sim) and state.hangar_snapshot() == before, "No duplicate battle outcome")

func protocol(report: String) -> void:
	reach(report)
	choose(report, "continue")
	reach("protocol_broadcast")
	var before: int = state.credits
	choose("protocol_broadcast", "acknowledge")
	check(state.credits == before + 150 and state.expedition_simulation.state.flags.get("leviathan_protocol", false), "Protocol grants exactly requisition and access")
	check(not state.resolve_expedition_event("protocol_broadcast", "acknowledge"), "Cannot repeat broadcast reward")
	check(state.research_choice_ready(), "Ordinary M-lab opening reaches first choice by Protocol")
	print("ACT I PACING: credits=%d fuel=%.3f missiles=%d RP=%.3f distance=%.3f" % [state.credits,
		state.expedition_simulation.state.fuel, state.missiles, state.research_points, state.expedition_simulation.state.traveled_distance_nu])

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://act1-content.json"
	opening()
	var before: Dictionary = state.hangar_snapshot()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-story.json"
	check(not state.resolve_expedition_event("meridian_departure", "leave") and state.hangar_snapshot() == before, "Choice failure cannot abandon port")
	state.run_save_path = path
	choose("meridian_departure", "leave")
	protocol("meridian_left_report")
	var sim = state.expedition_simulation
	check(sim.services_for(sim.locations.refuel_station_1).is_empty(), "Abandoned port has no services")
	check(not state.station_trade_node("refuel_station_1").inhabited, "Abandoned port cannot trade")
	check(state.load_run_checkpoint() and sim.services_for(sim.locations.refuel_station_1).is_empty(), "Continue retains abandonment")
	for phase: int in [BattleSimulation.Phase.VICTORY, BattleSimulation.Phase.WITHDRAWN]:
		opening()
		choose("meridian_departure", "return")
		check(state.expedition_simulation.state.return_destination_id == "settlement_1", "Return remembers outbound route")
		reach("first_contact")
		choose("first_contact", "fight")
		check(not state.expedition_simulation.state.flags.get("meridian_saved", false), "Fight choice is not a rescue")
		check(state.load_run_checkpoint() and state.pending_encounter.get("victory_flags", []) == ["meridian_saved"], "Pending outcome survives Continue")
		settle(phase)
		var won := phase == BattleSimulation.Phase.VICTORY
		check(state.can_use_shipyard() == won, "Only saved port keeps shipyard")
		check(state.expedition_simulation.retry_event_here().is_empty(), "Story outcome cannot farm retries")
		protocol("meridian_saved_report" if won else "meridian_withdrawn_report")
	check(not Events.valid_flags(["same", "same"]) and not Events.valid_flags([1]), "Reject malformed flags")
	check(state.expedition_option_error({"fuel": -10}) == "" , "Affordable fuel transfer")
	state.expedition_simulation.state.fuel = 9
	check(state.expedition_option_error({"fuel": -10}) == "Not enough fuel.", "Reject fuel underpayment")
	var no_incident := {}
	for event: Dictionary in state.expedition_simulation.events:
		if event.id in ["first_contact", "drone_vanguard", "swarm_scouts", "distress_call", "nebula_study", "asteroid_corridor"]:
			check(not Events.flag_ready(event, no_incident), "Alien content requires incident: " + event.id)
	print("ACT I CONTENT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
