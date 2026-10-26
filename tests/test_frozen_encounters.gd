extends SceneTree

var failures := 0
var allocations := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))


func _run() -> void:
	_check(is_equal_approx(EncounterGenerator.threat(1, 1), 100.0), "Normal row 1 budget is 100.")
	_check(absf(EncounterGenerator.threat(8, 1, "boss") - 293.0) < 1.0, "First boss budget is about 293.")
	_check(absf(EncounterGenerator.threat(16, 1, "boss") - 514.0) < 1.0, "Second boss budget is about 514.")
	_check(is_equal_approx(EncounterGenerator.threat(24, 1, "boss"), 900.0), "Final boss budget is 900.")
	_check(is_equal_approx(EncounterGenerator.threat(1, 0), 80.0) and is_equal_approx(EncounterGenerator.threat(1, 2), 125.0),
		"Difficulty applies the declared 0.8/1/1.25 multipliers.")
	for row in range(1, 25):
		for difficulty in range(3):
			for template: String in EncounterGenerator.TEMPLATES:
				for seed_value in [0, 17, 901]:
					var encounter := EncounterGenerator.generate(seed_value, row, row, difficulty, template, mini(14, row))
					_check(EncounterGenerator.valid(encounter), "Every allocation must fit its declared budget/limits: row %d/%s." % [row, template])
					allocations += 1
					if encounter.is_empty():
						continue
					_check(encounter.spent <= encounter.budget + 0.000001, "Waves, craft and organs cannot overspend threat.")
					_check(encounter.roster.size() <= 40, "Finite reserves must respect the entity budget.")
	var late := EncounterGenerator.generate(5, 24, 24, 2)
	for category in range(4):
		_check(late.rewards.material_pool[category] == 2 * late.rewards.materials[category],
			"Freeze the finite material pool at twice the initial recovery bundle.")
	_check(late.roster.all(func(unit: Dictionary) -> bool: return int(unit.tier) == 2), "Late encounters buy stronger variants instead of masses of Scouts.")
	_check(late.roster.size() <= 24, "Late ordinary rosters stay within the regular ship limit.")
	var framework := EncounterGenerator.generate(5, 24, 24, 2, "boss_framework", 14)
	_check(framework.roster.filter(func(unit: Dictionary) -> bool: return unit.kind == "organ").size() == 2
		and framework.roster.filter(func(unit: Dictionary) -> bool: return unit.kind == "craft").size() == 4,
		"The boss allocation framework includes finite organs and craft in the same budget.")
	var malformed := late.duplicate(true)
	malformed.budget += 100.0
	_check(not EncounterGenerator.valid(malformed), "Reject a changed budget that disagrees with frozen proximity.")
	malformed = late.duplicate(true)
	malformed.roster.append(malformed.roster[0].duplicate(true))
	_check(not EncounterGenerator.valid(malformed), "Reject duplicate entity identities.")
	for size in [12, 18, 24, 36]:
		var bundle := EncounterGenerator.material_bundle(size)
		_check(bundle.reduce(func(a: int, b: int) -> int: return a + b, 0) == size, "Rounding must preserve material bundle totals.")

	var state := root.get_node("GameState")
	state.run_save_path = "user://frozen_encounter_test/run.json"
	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 77), "Freeze all encounters at run creation.")
	var frozen: Dictionary = state.get_frozen_encounter(1)
	var original := _canonical(state.frozen_encounters)
	_check(frozen.global_row == 1 and state.get_frozen_encounter(state.FINAL_NODE_ID).global_row == 24,
		"The legacy map bridge preserves first/final global rows.")
	var preview: Dictionary = state.get_frozen_encounter(1)
	preview.roster.clear()
	_check(not state.get_frozen_encounter(1).roster.is_empty(), "Preview callers cannot mutate a frozen roster.")
	_check(state.set_destination(1), "Deploy the frozen initial roster.")
	var roster := _canonical(RunCheckpoint.capture(state).aliens)
	state.battle_aliens[0].stats.integrity = 0.1
	state.fleet[0].units[0].hp *= 0.5
	_check(state.cancel_battle(), "Save a withdrawal while keeping the frozen encounter.")
	state.current_research_ids.append("applied_energy")
	state.laser_upgrade_level = 2
	_check(state.set_destination(1) and _canonical(RunCheckpoint.capture(state).aliens) == roster,
		"Withdrawal and changed equipment/research cannot reroll the node.")
	_check(state.load_run_checkpoint() and _canonical(state.frozen_encounters) == original,
		"Reload restores every actual roster/reward without regeneration.")
	_check(_canonical(RunCheckpoint.capture(state).aliens) == roster and state.fleet[0].repair_cost() > 0,
		"Reload preserves the deployed roster and player damage independently.")
	var credit_before: int = state.credits
	_check(state.complete_battle(-1, [3, 3, 3]), "Settle the frozen reward, not a caller-generated salvage reroll.")
	_check(state.credits == credit_before + int(frozen.rewards.credits), "Victory uses frozen credits.")
	_check(_canonical(state.frozen_encounters) == original, "Victory does not mutate the frozen encounter catalog.")
	# A historical content snapshot must win over today's generator definitions.
	state.frozen_encounters["2"].roster[0].stats[1] = 777.0
	state.frozen_encounters["2"].rewards.credits = 123
	_check(state.save_run_checkpoint(), "Save explicit historical stats/rewards.")
	state.frozen_encounters.clear()
	_check(state.load_run_checkpoint() and state.get_frozen_encounter(2).rewards.credits == 123,
		"Loading must retain saved reward values rather than regenerate from the seed.")
	var historical: Array = EncounterGenerator.initial_fleet(state.get_frozen_encounter(2))
	_check(is_equal_approx(historical[0].stats.integrity, 777.0), "Instantiate the actual saved historical stats.")

	# Version-1 checkpoints did not store future-node rosters. Migrate once while
	# retaining an already deployed legacy roster and its old 200-credit contract.
	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 88) and state.set_destination(1), "Prepare a legacy migration fixture.")
	_check(state.commit_event("arrival", "legacy-port", 32), "Prepare a legacy ledger entry.")
	var old: Dictionary = RunCheckpoint.capture(state)
	old.version = 1
	old.erase("encounters")
	old.aliens[0].stats[1] = 123.456
	var decoded := RunCheckpoint.decode(JSON.parse_string(JSON.stringify(old)))
	_check(not decoded.is_empty(), "Accept version-1 checkpoint migration.")
	if not decoded.is_empty():
		_check(decoded.data.version == 2 and decoded.data.encounters["1"].legacy,
			"Mark the preserved legacy encounter explicitly.")
		_check(is_equal_approx(decoded.aliens[0].stats.integrity, 123.456)
			and decoded.data.encounters["1"].rewards.credits == 200,
			"Migration must preserve deployed stats/rewards instead of regenerating them.")
		_check(RunCheckpoint.valid(decoded.data), "A migrated checkpoint must validate in the new format.")
		var migration_path := "user://frozen_encounter_test/legacy.json"
		var store := AtomicRunStore.new()
		_check(store.commit(migration_path, old, RunCheckpoint.valid).ok, "Write a legacy checkpoint fixture.")
		state.run_save_path = migration_path
		_check(state.load_run_checkpoint(), "Load and durably migrate the legacy checkpoint.")
		_check(store.load_latest(migration_path, RunCheckpoint.valid).payload.version == 2,
			"Migration must be persisted before new frozen previews can be exposed.")
		var migrated_credits: int = state.credits
		_check(state.commit_event("arrival", "legacy-port", 32) and state.credits == migrated_credits,
			"Migration must preserve existing transaction deduplication.")
	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 901) and state.set_destination(1), "Prepare a real opening encounter.")
	var simulation := BattleSimulation.new()
	_check(simulation.setup_owned(state.fleet, state.battle_aliens, state.allied_salvage_chance(), 0, state.battle_simulation_seed()),
		"Initialize the real starter fleet against allocated enemies.")
	simulation.victory_materials = state.battle_material_rewards()
	for tick in range(60 * 120):
		simulation.advance(1.0 / 60.0)
		if simulation.phase != BattleSimulation.Phase.COMBAT:
			break
	_check(simulation.phase == BattleSimulation.Phase.VICTORY, "The opening allocation must remain playable on Auto with current starters.")
	_check(simulation.collected_categories == state.battle_material_rewards(), "Real battle salvage must match the frozen bundle.")
	print("Frozen encounter tests finished: %d failures; %d allocations" % [failures, allocations])
	quit(1 if failures > 0 else 0)
