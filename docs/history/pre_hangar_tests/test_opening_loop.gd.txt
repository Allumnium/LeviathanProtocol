extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0
var state: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	if not ok:
		failures += 1
		push_error(message)
	return ok

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://opening-loop/run.json"
	for seed_value in [42, 1357, 12345]:
		for approach in ["baseline", "research", "trade"]:
			play_opening(seed_value, approach)
	print("Opening loop tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func play_opening(seed_value: int, approach: String) -> void:
	if not check(state.start_new_run(1, seed_value), "Start the real opening campaign."):
		return
	check(state.credits == 300, "The reviewed opening budget is 300 credits.")
	check(state.fleet.size() == 3 and state.used_deployment_capacity() == 15, "Three starting Drones fit one general family and use 15 capacity.")
	if approach != "baseline":
		if not check(state.purchase_ship(BUILTINS.surveyor(), "Surveyor"), "A lab can be added within the 300-credit opening budget."):
			return
	if approach == "trade":
		if not check(state.purchase_ship(BUILTINS.hauler(), "Hauler"), "A player can also choose an armed cargo ship within that budget."):
			return
	check(state.set_research_focus("applied_energy"), "Choose a real research focus before departure.")
	var refitted := false
	var cargo_loaded := false
	var cargo_rebuilt_empty := false
	var total_days := 0.0
	for visit in range(7):
		var choices: Array = state.get_reachable_nodes(state.current_node_id)
		var destination: int = choices[(seed_value + visit) % choices.size()]
		var days: float = state.research_travel_time(state.current_node_id, destination)
		total_days += days
		var science := ScienceRules.snapshot(state.get_deployed_fleet())
		var expected := ScienceRules.journey_rp(science, days)
		var before_rp: float = state.research_points + state.research_progress.get("applied_energy", 0.0)
		var was_owned: bool = state.current_research_ids.has("applied_energy")
		if not check(state.travel_to(destination), "Depart along an actual reachable route."):
			return
		if state.battle_pending:
			var sim := BattleSimulation.new()
			if not check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, state.allied_salvage_chance(), state.laser_upgrade_level,
				state.battle_simulation_seed(), state.battle_support_context()), "Initialize the actual frozen encounter with physical hulls."):
				return
			for tick in range(60 * 180):
				sim.advance(1.0 / 60.0)
				if sim.phase != BattleSimulation.Phase.COMBAT:
					break
			if not check(sim.phase == BattleSimulation.Phase.VICTORY, "Opening %s seed %d visit %d wins on Auto." % [approach, seed_value, visit + 1]):
				return
			check(state.settle_battle(sim), "Settle real battle damage, rewards and research.")
		var now_owned: bool = state.current_research_ids.has("applied_energy")
		var earned: float = state.research_points + state.research_progress.get("applied_energy", 0.0) + (20.0 if now_owned and not was_owned else 0.0)
		check(is_equal_approx(earned, before_rp + expected), "Research uses frozen living labs and travel days, including quiet routes.")
		check(state.load_run_checkpoint() and state.current_node_id == destination, "Every opening arrival and partial project reloads.")
		if state.is_shipyard_node(destination):
			cargo_loaded = cargo_loaded or CargoRules.value(state.economy_state) > 0
			for owned in state.get_deployed_fleet():
				if owned.needs_repair():
					var rebuilding_hold: bool = owned.units.any(func(unit: Dictionary) -> bool:
						return unit.hp <= 0 and unit.part != null and unit.part.type == ShipPart.Type.CARGO_HOLD)
					check(state.repair_ship(owned), "Opening income/materials can pay actual repair costs.")
					if rebuilding_hold:
						cargo_rebuilt_empty = CargoRules.quantity(state.economy_state, owned.id) == 0 and CargoRules.manifest(state.fleet).values().any(func(entry: Dictionary) -> bool:
							return int(entry.ship_id) == owned.id and entry.operational)
			if now_owned and approach != "baseline" and not refitted:
				var upgraded := BUILTINS.surveyor()
				BUILTINS._add_part(upgraded, ShipPart.Type.LASER, Vector2i(3, 4))
				var index: int = state.roster_state.active.find(state.family_for_design(BUILTINS.surveyor()))
				var before: int = state.credits
				var quote: int = state.get_construction_credit_cost(upgraded)
				check(state.assign_fleet_design(index, "Surveyor", upgraded, true), "Register a researched mixed-hull revision at a real shipyard.")
				check(state.purchase_ship(upgraded, "Surveyor") and state.credits == before - quote, "Construct the researched revision at normal material/credit cost.")
				check(state.fleet.back().get_stats().dps > BUILTINS.surveyor().get_stats().dps, "Research produces a real equipment benefit.")
				refitted = true
				check(state.used_deployment_capacity() <= 30, "The refit fits normal capacity and old revisions contribute nothing.")
		print("Opening %s seed %d row %d: days %s, credits %d, progress %s, cargo %d, hulls %d" % [approach, seed_value, visit + 1,
			ScienceRules.format_rp(total_days), state.credits, ScienceRules.format_rp(state.research_progress.get("applied_energy", 0.0)), CargoRules.value(state.economy_state), state.fleet.size()])
	if approach != "baseline":
		check(refitted, "The opening lab route completes research and reaches a paid refit before the first boss.")
	if approach == "trade":
		check(cargo_loaded or cargo_rebuilt_empty, "Trade holds load at actual arrivals or, after losses, are paid for and rebuilt empty without free goods.")
