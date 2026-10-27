extends SceneTree
var failures := 0
const BUILTINS = preload("res://scripts/builtin_ships.gd")
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func inventory(state: Node) -> Array[int]:
	return [state.red_tiles_available, state.blue_tiles_available, state.green_tiles_available, state.core_tiles_available]
func run() -> void:
	var patterns := ShipPartPattern.get_catalog()
	for pattern in patterns:
		if pattern.part_type == ShipPart.Type.LASER:
			check(is_equal_approx(pattern.stats.weapons[0].get_dps(), 3), "Laser starts at 3 DPS.")
		if pattern.part_type == ShipPart.Type.DOUBLE_LASER:
			check(is_equal_approx(pattern.stats.weapons[0].get_dps(), 7.2), "Double Laser starts at 7.2 DPS.")
		if pattern.part_type == ShipPart.Type.SHIELD:
			check(pattern.stats.shields == 40, "Shield starts at 40 capacity.")
	var compact := BUILTINS.drone()
	var heavy := BUILTINS.drone()
	BUILTINS._add_part(heavy, ShipPart.Type.ARMOR_BLOCK, Vector2i(8, 0))
	var light_stats := compact.get_stats()
	var heavy_stats := heavy.get_stats()
	check(heavy_stats.footprint_size.x > light_stats.footprint_size.x, "Additional armor retains its larger battle footprint.")
	check(heavy_stats.integrity > light_stats.integrity and heavy_stats.top_speed < light_stats.top_speed \
		and heavy_stats.acceleration < light_stats.acceleration and heavy_stats.turn_rate < light_stats.turn_rate, "Armor trades mobility for durable protection on a larger footprint.")
	var speed := ShipStats.new()
	speed.weight = 100
	speed.thrust = 25
	var initial := speed.top_speed
	speed.thrust = 50
	var next := speed.top_speed
	speed.thrust = 75
	check(next - initial > speed.top_speed - next and speed.top_speed < ShipStats.MAX_SPEED, "Extra thrust has diminishing speed returns.")
	for pattern in patterns:
		if pattern.part_type == ShipPart.Type.ARMOR_BLOCK:
			var hp := ShipStats.component_integrity(4, ShipPart.new(pattern.part_type, pattern.category, Vector2i.ZERO, pattern.cell_offsets, pattern.stats))
			check(hp / (4 * Ship.BLUE_TILE_CREDIT_COST) > 2.5, "Armor remains inexpensive persistent HP after the shield retune.")
	_test_recharge(compact)
	_test_economy()
	_test_starter_encounters()
	print("Baseline tuning tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
func _test_recharge(design: Ship) -> void:
	var owned := FleetShip.new()
	owned.initialize(design, 99, "Timing")
	var sim := BattleSimulation.new()
	var ships: Array[FleetShip] = [owned]
	var aliens: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(1, 1.0, 42):
		aliens.append(alien)
	sim.setup_owned(ships, aliens, 0, 0, 42)
	sim.player.shields = 0
	sim.player.since_damage = 3.9
	sim._update_ship(sim.player, 0.05, false)
	check(is_zero_approx(sim.player.shields), "No recharge before four seconds.")
	sim._update_ship(sim.player, 0.1, false)
	check(is_equal_approx(sim.player.shields, 40 * 0.04 * 0.05), "Crossing the interruption boundary charges only the eligible part of the tick.")
	sim._update_ship(sim.player, 1, false)
	check(is_equal_approx(sim.player.shields, 40 * 0.04 * 1.05), "Shield regenerates 4% capacity per second.")
func _test_economy() -> void:
	var state = root.get_node("GameState")
	state.run_save_path = "user://tuning/run.json"
	check(state.start_new_run(1, 42), "Start reconstruction campaign.")
	state.credits = 10000
	state.red_tiles_available = 0
	state.blue_tiles_available = 0
	state.green_tiles_available = 0
	state.core_tiles_available = 0
	check(state.MATERIAL_PRICES == [5, 2, 8, 6], "Purchase and reconstruction use the same material prices.")
	var owned: FleetShip = state.fleet[0]
	var original := owned.material_counts(false)
	var turret := -1
	var armor := -1
	for index in range(owned.units.size()):
		var part: ShipPart = owned.units[index].part
		if part != null and part.type == ShipPart.Type.MINI_TURRET:
			turret = index
		if part != null and part.type == ShipPart.Type.ARMOR_BLOCK:
			armor = index
	owned.units[turret].hp = 0
	owned.units[armor].hp *= 0.5
	var quote: Dictionary = state.repair_quote(owned)
	check(quote.repair_credits == 1 and quote.reconstruction == [1, 0, 0, 0] and quote.credits == 6, "Repair rounds one invoice; reconstruction buys the destroyed turret at material cost.")
	var before: int = state.credits
	var revision := owned.visual_revision
	check(state.repair_ship(owned) and state.credits == before - 6 and not owned.needs_repair() and inventory(state) == [0, 0, 0, 0], "Automatic shortage purchase restores equipment without generating inventory.")
	check(owned.visual_revision == revision + 1, "Reconstruction invalidates destroyed-component render geometry once.")
	check(state.load_run_checkpoint() and not state.fleet[0].needs_repair() and state.credits == before - 6, "Repair payment and physical HP persist together.")
	owned = state.fleet[0]
	owned.units[turret].hp = 0
	state.red_tiles_available = 1
	quote = state.repair_quote(owned)
	check(quote.credits == 0 and quote.materials == [1, 0, 0, 0], "Stored reconstruction material is consumed before buying shortages.")
	state.credits = 0
	check(state.repair_ship(owned) and state.red_tiles_available == 0, "Inventory-only reconstruction can proceed at zero credits.")
	owned.units[turret].hp = 0
	check(not state.repair_ship(owned) and owned.units[turret].hp == 0, "Unaffordable reconstruction leaves HP and materials unchanged.")
	state.credits = 100
	var blocker := FileAccess.open("user://tuning/blocker", FileAccess.WRITE)
	blocker.store_string("file")
	blocker.close()
	var path: String = state.run_save_path
	state.run_save_path = "user://tuning/blocker/run.json"
	var print_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	check(not state.repair_ship(owned) and state.credits == 100 and owned.units[turret].hp == 0, "Failed repair save cannot charge or heal.")
	check(not state.dismantle_ship(owned) and state.fleet.has(owned) and inventory(state) == [0, 0, 0, 0], "Failed dismantle save cannot remove a hull or refund materials.")
	Engine.print_error_messages = print_errors
	state.run_save_path = path
	check(state.dismantle_ship(owned), "Dismantle the damaged physical hull.")
	var returned := inventory(state)
	check(not state.dismantle_ship(owned) and inventory(state) == returned, "A dismantled hull cannot refund twice.")
	check(returned == [original[0] - 1, original[1], original[2], original[3]], "Dismantling returns surviving atomic material only; lost turret stays lost.")
	check(state.load_run_checkpoint() and inventory(state) == returned and not state.fleet.any(func(member: FleetShip) -> bool: return member.id == owned.id), "Dismantle removal and refund persist together.")

func _test_starter_encounters() -> void:
	var state = root.get_node("GameState")
	for seed_value in [42, 1357, 12345]:
		check(state.start_new_run(1, seed_value) and state.set_destination(state.get_reachable_nodes(0)[0]), "Create a frozen first encounter for physical starter validation.")
		var aliens: Array[RefCounted] = []
		for alien in state.battle_aliens:
			aliens.append(alien)
		var sim := BattleSimulation.new()
		check(sim.setup_owned(state.get_deployed_fleet(), aliens, 0, 0, seed_value), "Initialize the real physical starting fleet.")
		for tick in range(60 * 120):
			sim.advance(1.0 / 60.0)
			if sim.phase != BattleSimulation.Phase.COMBAT:
				break
		check(sim.phase == BattleSimulation.Phase.VICTORY and sim.players.all(func(member) -> bool: return member.is_alive()), "The current starter survives the first encounter with the combined shield/movement retune.")
