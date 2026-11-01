extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var state: Node = root.get_node("GameState")
	state.run_save_path = "user://whole-ship-test.json"
	check(state.start_new_run(1, 42310), "Whole-ship run starts and saves")
	var ship: HangarShip = state.fleet[0]
	var before: Dictionary = state.hangar_snapshot()
	check(before.version == 2, "Whole-ship schema explicitly versioned")
	check(not before.ships[0].has("builtins"), "No builtin health persisted")
	for item: Dictionary in before.equipment.values():
		check(not item.has("hp"), "No equipment health persisted")
	check(ship.core_index == -1 and not ship.units.any(func(unit: Dictionary) -> bool: return unit.part.type == ShipPart.Type.COMMAND_CENTER),
		"Physical ship has no command-center damage unit")
	var stats := ship.get_stats()
	var units := ship.units.duplicate(true)
	var inventory: Dictionary = state.equipment_inventory.duplicate(true)
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(-1, 0)]:
		var hp := ship.hull_hp
		var result := ship.damage_cell(cell, 50)
		check(ship.hull_hp == hp - 49 and result.damage == 49 and result.removed.is_empty(), "Every hit applies armored hull damage only, regardless of target")
		check(ship.units == units and state.equipment_inventory == inventory, "Hull hits never mutate equipment or builtin operation")
	check(ship.get_stats().dps == stats.dps and ship.get_stats().thrust == stats.thrust and ship.get_stats().shields == stats.shields,
		"All weapons, engines and shields remain operational on severely damaged hull")
	check(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())) == 1, "Installed lab remains productive under hull damage")
	check(ship.repair_cost() == 196, "Repair quote is exactly missing whole-ship hull")
	check(state.save_run_checkpoint() and state.load_run_checkpoint(), "Whole-ship damage roundtrips")
	ship = state.fleet[0]
	check(ship.hull_hp == before.ships[0].hull_hp - 196
		and JSON.parse_string(JSON.stringify(state.equipment_inventory)) == JSON.parse_string(JSON.stringify(inventory)), "Reload retains hull only")
	var damaged: Dictionary = state.hangar_snapshot()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/whole-ship/invalid.json"
	check(not state.repair_all_ships() and state.hangar_snapshot() == damaged, "Failed whole-fleet repair leaves health, ownership and credits unchanged")
	state.run_save_path = path
	check(state.repair_all_ships(), "Atomic whole-fleet hull repair succeeds")
	check(state.credits == int(damaged.credits) - 196 and state.fleet[0].hull_hp == state.fleet[0].hull_max, "Repair restores whole hull for quoted credits")
	var invalid: Dictionary = before.duplicate(true)
	invalid.version = 1
	check(not HangarCheckpoint.valid(invalid), "Previous physical version rejected")
	invalid = before.duplicate(true)
	invalid.equipment["1"].hp = 1
	check(not HangarCheckpoint.valid(invalid), "Component HP rejected even under version2")
	invalid = before.duplicate(true)
	invalid.ships[0].builtins = {"core": 30, "engine": 25}
	check(not HangarCheckpoint.valid(invalid), "Builtin health rejected even under version2")
	_test_combat()
	print("Whole ship: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_combat() -> void:
	var ship := HangarShip.new()
	check(ship.initialize_chassis("flagship_basic", 1, true), "Combat whole ship initializes")
	var weapon := SlotCatalog.find_equipment("mini_turret")
	ship.mounts.port = {"uid": "1", "equipment_id": weapon.id, "rank": 1}
	ship.rebuild_units()
	var sim := BattleSimulation.new()
	sim.credits_only = true
	var target := BattleSimulation.Combatant.new()
	target.owned_ship = ship
	target.entity_id = "ship"
	target.stats = ship.get_stats()
	target.integrity = ship.hull_hp
	target.shields = target.stats.shields
	target.cooldowns = [0.5]
	target.faction = BattleSimulation.Faction.PLAYER
	sim.register_entity(target)
	var rng := sim.random.state
	sim._damage(target, 10, Vector2.ZERO, null, "Beam", false, true)
	check(target.shields == 30 and ship.hull_hp == 320, "Shield absorbs damage before hull")
	sim._damage(target, 41, Vector2.ZERO, null, "Beam", false, true)
	check(target.shields == 0 and ship.hull_hp == 310 and target.permanent_damage_taken == 10, "Only unabsorbed damage reaches hull and repair report")
	check(target.stats.weapons.size() == 1 and target.stats.thrust == 22 and target.stats.shields == 40, "Damage never disables equipment or builtin systems")
	check(sim.random.state == rng, "No per-component scatter RNG for hull damage")
	sim.visibility_enabled = true
	sim.refresh_visibility()
	check(not sim.visibility.sources[BattleSimulation.Faction.PLAYER].is_empty(), "Physical ship still supplies sight without command-center unit")
	check(ship.repair_hull(1000) == 10 and ship.hull_hp == 320, "Hull repair clamps to max")
	ship.hull_hp = 0
	check(ship.is_alive() and ship.get_stats().weapons.size() == 1 and ship.get_stats().thrust > 0, "At zero hull ship and all equipment remain active")
	sim._damage(target, 1.25, Vector2.ZERO, null, "Direct damage")
	check(not ship.is_alive(), "Hull strictly below zero destroys ship")
	check(ship.repair_hull(10) == 0, "Combat hull repair cannot revive destroyed ship")
	ship.repair()
	check(ship.hull_hp == -0.25 and not ship.is_alive(), "Credit repair cannot revive destroyed ship")
