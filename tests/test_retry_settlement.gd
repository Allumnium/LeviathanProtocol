extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _setup(state: Node) -> BattleSimulation:
	_check(state.set_destination(1), "Retry must redeploy to the same reachable node.")
	var sim := BattleSimulation.new()
	_check(sim.setup_owned(state.fleet, state.battle_aliens, state.allied_salvage_chance(), state.laser_upgrade_level, state.battle_simulation_seed()), "Retry simulation must initialize.")
	sim.victory_materials = state.battle_material_rewards()
	sim.set_objective_targets(state.battle_objective_ids())
	return sim

func _run() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://retry_settlement/run.json"
	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 1357), "Start retry fixture.")
	var frozen: Variant = JSON.parse_string(JSON.stringify(state.get_frozen_encounter(1)))
	var credits: int = state.credits
	var rp: int = state.research_points
	var sim := _setup(state)
	var first: FleetShip = sim.players[0].owned_ship
	first.units[first.core_index].hp = 0.0
	sim.players[0].integrity = 0.0
	var survivor: FleetShip = sim.players[1].owned_ship
	survivor.units[survivor.core_index].hp *= 0.75
	var survivor_id := survivor.id
	var damaged_hp: float = survivor.units[survivor.core_index].hp
	var field := {"roots": {"root/1": {"remaining": 3, "hp": 12}}, "claimed": ["fragment/1"]}
	_check(state.commit_field_pickup("root/1/fragment/1", [2, 0, 0, 0], field), "Ore and depleted field commit atomically.")
	var materials: int = state.red_tiles_available
	_check(state.commit_field_pickup("root/1/fragment/1", [2, 0, 0, 0], field) and state.red_tiles_available == materials, "Pickup replay cannot duplicate ore.")
	_check(not state.commit_field_pickup("root/1/fragment/1", [3, 0, 0, 0], field), "Conflicting pickup identity is rejected.")
	sim.damage_entity(sim.aliens[0].entity_id, 10000.0)
	sim.collected_categories.assign([0, 0, 0, 0])
	sim.phase = BattleSimulation.Phase.WITHDRAWN
	_check(state.settle_battle(sim), "Withdrawal persists losses without granting enemy salvage.")
	_check(state.credits == credits and state.research_points == rp and state.red_tiles_available == materials, "Failed attempts award no credits, RP or enemy salvage.")
	_check(state.load_run_checkpoint() and state.fleet.size() == 2, "Destroyed ship stays lost after reload.")
	_check(state.fleet[0].id == survivor_id and is_equal_approx(state.fleet[0].units[state.fleet[0].core_index].hp, damaged_hp), "Surviving component damage persists.")
	_check(state.encounter_progress["1"].field == JSON.parse_string(JSON.stringify(field)) and state.encounter_progress["1"].outcome == "withdrawn", "Finite field survives withdrawal/reload.")
	_check(JSON.parse_string(JSON.stringify(state.get_frozen_encounter(1))) == frozen, "Failure cannot reroll frozen enemies or rewards.")

	sim = _setup(state)
	_check(sim.aliens[0].integrity == state.battle_aliens[0].stats.integrity, "Enemy HP resets on retry.")
	_check(state.commit_field_pickup("root/1/fragment/1", [2, 0, 0, 0], field) and state.red_tiles_available == materials, "Pickup stays consumed on a later attempt.")
	sim.phase = BattleSimulation.Phase.WITHDRAWN
	_check(state.settle_battle(sim) and state.load_run_checkpoint(), "A second withdrawal persists.")
	_check(state.credits == credits and state.research_points == rp and state.fleet.size() == 2, "Repeated failure pays nothing and never resurrects ships.")

	sim = _setup(state)
	for alien in sim.aliens:
		sim.damage_entity(alien.entity_id, 10000.0)
	sim.advance(0.01)
	_check(sim.phase == BattleSimulation.Phase.VICTORY, "Final attempt reaches objective victory.")
	var good_path: String = state.run_save_path
	var blocker := FileAccess.open("user://retry_settlement/blocker", FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	state.run_save_path = "user://retry_settlement/blocker/run.json"
	_check(not state.settle_battle(sim) and state.credits == credits and state.battle_pending, "Failed outcome write leaves victory retryable and unpaid.")
	state.run_save_path = good_path
	_check(state.settle_battle(sim), "Retry failed settlement successfully.")
	var paid_credits: int = state.credits
	var paid_materials: int = state.red_tiles_available
	_check(paid_credits == credits + int(state.get_frozen_encounter(1).rewards.credits), "First successful attempt pays exactly one frozen reward.")
	_check(not state.settle_battle(sim), "Already settled simulation cannot pay again.")
	_check(state.load_run_checkpoint() and state.credits == paid_credits and state.red_tiles_available == paid_materials, "Victory payout and losses persist together.")
	_check(state.encounter_progress["1"].attempts == 3 and state.encounter_progress["1"].outcome == "victory", "Attempt history records one successful result.")
	_check(state.encounter_progress["1"].journal.snapshot.phase == BattleSimulation.Phase.VICTORY,
		"The settled diagnostic journal persists with the payout.")

	_check(state.start_new_run(), "Start terminal defeat fixture.")
	sim = _setup(state)
	for member in sim.players:
		member.owned_ship.units[member.owned_ship.core_index].hp = 0.0
		member.integrity = 0.0
	sim.advance(0.01)
	_check(sim.phase == BattleSimulation.Phase.DEFEAT and state.settle_battle(sim), "Fleet wipe settles terminal defeat.")
	_check(state.credits > 0 and state.is_run_lost() and not state.can_deploy(), "Remaining credits cannot undo terminal fleet defeat.")
	_check(state.load_run_checkpoint() and state.run_ended and state.is_run_lost(), "Terminal defeat survives reload.")
	_check(state.start_new_run() and not state.run_ended, "A new run resets terminal state.")
	print("Retry settlement tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
