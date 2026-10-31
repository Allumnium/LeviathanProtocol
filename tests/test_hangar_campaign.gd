extends SceneTree

var failures := 0
var checks := 0
var state: Node

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, title: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(title)

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://hangar-campaign.json"
	var victories := 0
	for seed_value in range(6):
		check(state.start_new_run(1, seed_value), "Start seeded campaign")
		# A useful, affordable first shipyard purchase.
		check(state.buy_equipment("shield_generator"), "Starter shield purchase")
		check(state.fit_equipment(1, "inner_starboard", str(state.next_equipment_id - 1)), "Starter shield fit")
		var target: int = state.get_reachable_nodes(0)[0]
		check(state.travel_to(target), "Seeded departure")
		var sim := BattleSimulation.new()
		check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, state.battle_simulation_seed(), state.battle_support_context()), "Seeded battle setup")
		sim.battle_id = state.battle_identity()
		check(sim.set_objective_targets(state.battle_objective_ids()), "Seeded objectives")
		for tick in range(18000):
			sim.advance(1.0 / 30)
			if sim.phase != BattleSimulation.Phase.COMBAT:
				break
		check(sim.phase != BattleSimulation.Phase.COMBAT, "Battle terminates")
		if sim.phase == BattleSimulation.Phase.VICTORY:
			victories += 1
		print("SEED ", seed_value, " phase ", sim.phase, " seconds ", sim.elapsed, " hull ", state.fleet[0].hull_hp)
		check(state.settle_battle(sim), "Natural result persists")
		check(state.load_run_checkpoint(), "Natural result reloads")
		check(sim.drops.is_empty(), "Credit-only battle")
	check(victories >= 4, "Starter fleet can win first encounter")
	# Traverse the existing complete map, committing each outcome once.
	check(state.start_new_run(1, 907), "Traversal start")
	check(state.set_research_focus("applied_energy"), "Research focus")
	var battles := 0
	var arrivals := 0
	while not state.completed and not state.run_ended:
		var routes: Array = state.get_reachable_nodes(state.current_node_id)
		check(not routes.is_empty(), "Route exists")
		if routes.is_empty():
			break
		var target: int = routes[0]
		check(state.travel_to(target), "Travel across campaign")
		if state.battle_pending:
			battles += 1
			var sim := BattleSimulation.new()
			check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, state.battle_simulation_seed(), state.battle_support_context()), "Campaign setup, bosses included")
			sim.battle_id = state.battle_identity()
			check(sim.set_objective_targets(state.battle_objective_ids()), "Campaign boss/wave objective identities")
			sim.phase = BattleSimulation.Phase.VICTORY
			check(state.settle_battle(sim), "Campaign settlement")
			check(not state.settle_battle(sim), "No replayed battle reward")
		arrivals += 1
		check(state.load_run_checkpoint() and state.current_node_id == target, "Arrival persists")
		if arrivals > 30:
			check(false, "Traversal bounded")
			break
	check(state.completed and arrivals == 24 and battles == 14, "All acts and final endpoint reachable")
	check("applied_energy" in state.current_research_ids, "Travel completes focused project")
	print("HANGAR CAMPAIGN: %d checks, %d failures, %d / 6 natural first battles won" % [checks, failures, victories])
	quit(1 if failures else 0)
