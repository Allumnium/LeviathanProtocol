extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _simulation() -> BattleSimulation:
	var stats := ShipStats.new()
	stats.integrity = 100.0
	stats.weapons.append(ShipWeaponStats.new("Test laser", 0.1, 10.0, 1))
	var fleet: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(1, 1.0, 42):
		fleet.append(alien)
	var sim := BattleSimulation.new()
	_check(sim.setup(stats, fleet, 42), "Entity fixture must initialize.")
	sim.player.position = Vector2.ZERO
	sim.aliens[0].position = Vector2(60, 0)
	return sim

func _run() -> void:
	var sim := _simulation()
	var rock := sim.add_neutral_target("rock/1", 5.0, Vector2(30, 0))
	_check(rock != null and not sim.register_entity(rock), "Entity IDs must be unique.")
	_check(sim.can_attack(sim.player, rock) and sim.can_attack(sim.aliens[0], rock), "Both factions can damage neutral targets.")
	_check(not sim._auto_candidate(sim.player, rock), "Default Auto ignores neutrals.")
	_check(sim.request_attack(sim.player.entity_id, rock.entity_id), "Explicit neutral orders are valid.")
	_check(not sim.request_attack(sim.player.entity_id, sim.player.entity_id) and sim.player.commanded_target == rock, "Invalid orders preserve the previous order.")
	sim.advance(0.2)
	_check(not rock.is_alive(), "Neutral targets use the normal weapon damage pipeline.")
	_check(sim.drops.is_empty(), "Neutral destruction grants no salvage.")

	sim = _simulation()
	rock = sim.add_neutral_target("rock/default", 5.0, Vector2(30, 0))
	sim.damage_entity(sim.aliens[0].entity_id, 10000.0)
	sim.advance(0.01)
	_check(sim.phase == BattleSimulation.Phase.VICTORY and rock.is_alive(), "Neutral targets do not block default victory.")

	sim = _simulation()
	rock = sim.add_neutral_target("rock/cleanup", 5.0, Vector2(30, 0))
	_check(sim.set_destroy_all_neutral_targets(true), "Cleanup can be enabled during combat.")
	_check(not sim._auto_candidate(sim.player, rock), "Hostile threats take priority over cleanup.")
	sim.damage_entity(sim.aliens[0].entity_id, 10000.0)
	_check(not sim.objective_complete(), "Enabled neutrals block victory.")
	sim._rebuild_spatial_index()
	_check(sim._choose_target(sim.player) == rock and sim._choose_target_linear(sim.player) == rock, "Both targeting paths select cleanup targets.")
	for tick in range(300):
		sim.advance(1.0 / 60.0)
	_check(sim.phase == BattleSimulation.Phase.VICTORY and not rock.is_alive(), "Auto clears neutrals and then wins.")

	sim = _simulation()
	rock = sim.add_neutral_target("rock/toggle", 5.0, Vector2(30, 0))
	sim.set_destroy_all_neutral_targets(true)
	sim.damage_entity(sim.aliens[0].entity_id, 10000.0)
	sim.set_destroy_all_neutral_targets(false)
	sim.advance(0.01)
	_check(sim.phase == BattleSimulation.Phase.VICTORY and rock.is_alive(), "Disabling cleanup permits immediate ordinary victory.")

	sim = _simulation()
	rock = sim.add_neutral_target("decoy", 5.0, Vector2(30, 0))
	rock.tags["decoy"] = true
	sim.set_destroy_all_neutral_targets(true)
	sim.damage_entity(sim.aliens[0].entity_id, 10000.0)
	_check(sim.objective_complete(), "Decoys do not become cleanup objectives.")
	var required: Array[String] = [rock.entity_id]
	_check(sim.set_objective_targets(required) and not sim.objective_complete(), "Explicit objectives can require an otherwise optional actor.")
	var invalid: Array[String] = ["missing"]
	_check(not sim.set_objective_targets(invalid) and sim.objective_target_ids == required, "Invalid objectives cannot replace a valid objective.")
	rock.tags["drop"] = true
	_check(not sim.damage_entity(rock.entity_id, 10.0), "Drops cannot receive weapon damage.")

	var state := root.get_node("GameState")
	_check(state.start_new_run(), "Preference fixture starts a run.")
	_check(not state.destroy_all_neutral_targets, "New runs default to ordinary victory.")
	_check(state.set_destroy_all_neutral_targets(true), "Cleanup preference saves.")
	state.destroy_all_neutral_targets = false
	_check(state.load_run_checkpoint() and state.destroy_all_neutral_targets, "Cleanup preference survives reload.")
	var old: Dictionary = state.run_progress_snapshot()
	old.erase("destroy_all_neutral_targets")
	_check(state.restore_run_progress(old) and not state.destroy_all_neutral_targets, "Older saves default cleanup off.")
	print("Entity objective tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
