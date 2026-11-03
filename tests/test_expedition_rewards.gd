extends SceneTree

const Events = preload("res://scripts/expedition_events.gd")
const Loadouts = preload("res://scripts/ship_loadouts.gd")
const Travel = preload("res://scripts/expedition_state.gd")
var checks := 0
var failures := 0
var state: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func admit(id: String) -> void:
	check(state.start_new_run(1, 4242), "Start reward fixture")
	state.expedition_simulation.state.pending_event_id = id
	state.expedition_simulation.state.pause_reasons.append(Travel.PauseReason.ENCOUNTER)
	check(state.save_run_checkpoint(), "Persist admitted reward encounter")

func battle() -> BattleSimulation:
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0,
		state.battle_simulation_seed(), state.battle_support_context()), "Reward battle initializes")
	sim.battle_id = state.battle_identity()
	sim.phase = BattleSimulation.Phase.VICTORY
	return sim

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://expedition-rewards.json"
	for malformed: Dictionary in [{"rescue_ship": "missing"}, {"rescue_ship": "flagship_basic"},
		{"rescue_ship": 1}, {"fuel": -1}, {"fuel": INF}, {"research": NAN}, {"research": -1}]:
		check(not Events.valid_rewards(malformed), "Reject malformed reward: " + str(malformed))
	check(Events.valid_rewards({"fuel": -5}, true), "Event costs may still consume fuel")
	check(Events.valid_rewards({"rescue_ship": "transport", "research": 5, "fuel": 8}),
		"Valid fitted escort and resource rewards accepted")
	admit("derelict_salvage")
	state.expedition_simulation.state.fuel = 98
	var before: Dictionary = state.hangar_snapshot()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-rewards.json"
	check(not state.resolve_expedition_event("derelict_salvage", "careful")
		and state.hangar_snapshot() == before and not state.last_save_error.is_empty(),
		"Failed salvage saves neither credits, fuel nor receipt")
	state.run_save_path = path
	check(state.resolve_expedition_event("derelict_salvage", "careful")
		and state.credits == int(before.credits) + 80
		and state.expedition_simulation.state.fuel == 100
		and state.last_event_result.contains("+2.0 fuel"), "Salvage reports actual capacity-capped fuel recovery")
	var committed: Dictionary = state.hangar_snapshot()
	check(not state.resolve_expedition_event("derelict_salvage", "careful")
		and state.hangar_snapshot() == committed, "Salvage cannot pay twice")
	check(state.load_run_checkpoint() and SaveValidation.same(state.hangar_snapshot(), committed),
		"Salvage resources and receipt survive Continue")

	admit("derelict_salvage")
	check(state.resolve_expedition_event("derelict_salvage", "strip"), "Admit fuel salvage battle")
	state.expedition_simulation.state.fuel = 96
	var sim := battle()
	check(state.pending_encounter.rewards.fuel == 8, "Authored fuel reward frozen into encounter")
	check(state.settle_battle(sim) and state.expedition_simulation.state.fuel == 100
		and state.last_equipment_loot.contains("+4.0 fuel"), "Victory reports actual recovered fuel")

	admit("distress_call")
	check(state.resolve_expedition_event("distress_call", "defend"), "Admit rescue battle")
	check(state.load_run_checkpoint() and state.pending_encounter.rewards.rescue_ship == "transport",
		"Pending rescue reward survives Continue")
	sim = battle()
	before = state.hangar_snapshot()
	state.run_save_path = "res://project.godot/no-rewards.json"
	check(not state.settle_battle(sim) and state.hangar_snapshot() == before,
		"Failed rescue settlement creates no ship, equipment, RP, credits or IDs")
	state.run_save_path = path
	check(state.settle_battle(sim) and state.fleet.size() == before.ships.size() + 1,
		"Victory adds exactly one rescued ship")
	var rescued: HangarShip = state.fleet[-1]
	check(rescued.chassis_id == "transport" and not rescued.flagship
		and rescued.hull_hp == rescued.hull_max and Loadouts.matching("transport", rescued.mounts) != "",
		"Rescue is a fully fitted, healthy escort with the class default loadout")
	check(rescued.mounts.values().all(func(item: Dictionary) -> bool:
		return not HangarTrade.has_load(item)), "Rescue never fabricates passenger or cargo loads")
	check(state.last_equipment_loot.contains("Transport joined")
		and HangarCheckpoint.valid(state.hangar_snapshot()), "Report identifies rescue and snapshot ownership validates")
	committed = state.hangar_snapshot()
	check(not state.settle_battle(sim) and state.hangar_snapshot() == committed,
		"Repeated victory cannot duplicate rescued ship or equipment")
	check(state.load_run_checkpoint() and SaveValidation.same(state.hangar_snapshot(), committed),
		"Rescued ship, IDs, loadout and resources survive Continue")

	admit("distress_call")
	state.credits = 100000
	while state.used_command() < state.command_limit():
		if not state.buy_ship("drone"):
			check(false, "Fill command budget for compensation test")
			break
	check(state.resolve_expedition_event("distress_call", "defend"), "Rescue allowed at full command")
	before = state.hangar_snapshot()
	sim = battle()
	var price := Loadouts.ship_price("transport", Loadouts.default_for("transport"))
	check(state.settle_battle(sim) and state.fleet.size() == before.ships.size()
		and state.credits == int(before.credits) + 240 + price
		and state.last_equipment_loot.contains("command full: +%d cr" % price),
		"Full command grants exact fitted credit value without an undeployable ship")

	for phase: int in [BattleSimulation.Phase.WITHDRAWN, BattleSimulation.Phase.DEFEAT]:
		admit("distress_call")
		check(state.resolve_expedition_event("distress_call", "defend"), "Admit non-victory fixture")
		sim = battle()
		sim.phase = phase
		before = state.hangar_snapshot()
		check(state.settle_battle(sim) and state.fleet.size() == before.ships.size()
			and state.credits == before.credits and state.last_equipment_loot.is_empty(),
			"Non-victory grants no rescue, credits or resource rewards")
	print("EXPEDITION REWARDS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
