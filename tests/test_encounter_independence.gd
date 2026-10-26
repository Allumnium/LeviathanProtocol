extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://encounter_independence/run.json"
	for difficulty in range(3):
		for seed_value in [0, 7, 12345, 987654321]:
			var expected_roster := ""
			var expected_reward := -1
			for count in [1, 4, 10]:
				_check(state.start_new_run(difficulty, seed_value), "Start a reproducible encounter fixture.")
				state.fleet.clear()
				var blueprint: Ship = preload("res://scripts/builtin_ships.gd").drone()
				# Change actual equipment for the largest fleet, alongside its resources/research.
				if count == 10:
					for pattern in ShipPartPattern.get_catalog():
						if pattern.part_type == ShipPart.Type.LASER:
							for index in range(pattern.cell_offsets.size()):
								blueprint.set_tile_at(Vector2i(8, 0) + pattern.cell_offsets[index], pattern.tile_categories[index])
							blueprint.add_part(ShipPart.new(pattern.part_type, pattern.category, Vector2i(8, 0),
								pattern.cell_offsets, pattern.stats, pattern.hidden_tile_offsets))
				state.current_research_ids.assign(["foundation", "applied_energy"] if count > 1 else ["foundation"])
				state.credits = count * 1000
				state.research_points = count * 100
				state.laser_upgrade_level = 0 if count == 1 else 3
				for index in range(count):
					var owned := FleetShip.new()
					owned.initialize(blueprint, index + 1, "Fixture %d" % index)
					if count == 4:
						# Damage/loadout strength must not influence roster generation either.
						owned.units[0].hp *= 0.5
					state.fleet.append(owned)
				state.next_ship_id = count + 1
				state._refresh_fleet()
				_check(state.set_destination(1), "Deploy the fleet independence fixture.")
				var roster := JSON.stringify(RunCheckpoint.capture(state).aliens)
				if expected_roster.is_empty():
					expected_roster = roster
				_check(roster == expected_roster, "Roster order, HP, shields, weapons and mobility cannot scale with the player fleet.")
				var credits_before: int = state.credits
				_check(state.complete_battle(), "Settle fleet-independent rewards.")
				var reward: int = state.credits - credits_before
				if expected_reward < 0:
					expected_reward = reward
				_check(reward == expected_reward, "Rewards cannot scale with the player fleet.")
	_check(AlienShip.create_random_fleet(6, 1.0, 123).size() == 6, "Explicit enemy count remains supported without player fleet input.")
	print("Encounter independence tests finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)
