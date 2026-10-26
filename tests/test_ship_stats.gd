extends SceneTree

var failures := 0
const BUILTINS = preload("res://scripts/builtin_ships.gd")

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _same(a: ShipStats, b: ShipStats, context: String) -> void:
	for key in ["shields", "integrity", "weight", "thrust", "dps", "top_speed", "acceleration", "turn_rate", "collision_radius"]:
		_check(is_equal_approx(a.get(key), b.get(key)), "%s: %s agrees." % [context, key])
	_check(a.occupied_cells == b.occupied_cells and a.footprint_size.is_equal_approx(b.footprint_size), context + ": footprint agrees.")
	_check(a.weapons.size() == b.weapons.size(), context + ": weapon count agrees.")
	for index in range(mini(a.weapons.size(), b.weapons.size())):
		_check(a.weapons[index].mount_offset.is_equal_approx(b.weapons[index].mount_offset), context + ": weapon mounts agree.")
		_check(a.weapons[index].component_index == b.weapons[index].component_index, context + ": weapon source agrees.")

func _run() -> void:
	var empty := Ship.new().get_stats()
	_check(empty.weight == 0 and empty.integrity == 0 and empty.collision_radius == 0 and empty.top_speed == 0, "Empty designs have no physical stats.")
	for pattern in ShipPartPattern.get_catalog():
		var design := Ship.new()
		BUILTINS._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
		if pattern.part_type != ShipPart.Type.COMMAND_CENTER:
			BUILTINS._add_part(design, pattern.part_type, Vector2i(3, 0))
		design.set_tile_at(Vector2i(-1, -1), ShipPart.Category.DEFENSE)
		var physical := FleetShip.new()
		physical.initialize(design, 1, "Stats fixture")
		_same(design.get_stats(3), physical.get_stats(3), pattern.display_name)
		var expected_mass := float(design.tiles.size())
		for part in design.parts:
			expected_mass += part.stats.weight
		_check(is_equal_approx(physical.get_stats().weight, expected_mass), "Mass includes physical cells and equipment, without polygon infill.")
		for unit in physical.units:
			var before := physical.get_stats()
			unit.hp *= 0.5
			var damaged := physical.get_stats()
			_check(is_equal_approx(before.weight, damaged.weight) and is_equal_approx(before.dps, damaged.dps)
				and is_equal_approx(before.thrust, damaged.thrust) and damaged.integrity < before.integrity,
				"Partial damage changes HP, retaining atomic component mass and output.")
			physical.repair()

	var compact := BUILTINS.drone()
	var larger := BUILTINS.drone()
	BUILTINS._add_part(larger, ShipPart.Type.ARMOR_BLOCK, Vector2i(8, 0))
	var small := FleetShip.new()
	var big := FleetShip.new()
	small.initialize(compact, 1, "Compact")
	big.initialize(larger, 2, "Larger")
	_check(big.cell_size == small.cell_size and big.get_stats().footprint_size.x > small.get_stats().footprint_size.x
		and big.get_stats().collision_radius > small.get_stats().collision_radius, "Larger hulls retain larger world and collision footprints.")
	var translated := Ship.new()
	var data := compact.to_design_data()
	for tile in data.tiles:
		tile[0] += 100
		tile[1] -= 40
	for part in data.parts:
		part.origin[0] += 100
		part.origin[1] -= 40
	_check(translated.load_design_data(data), "Translated design loads.")
	_same(compact.get_stats(), translated.get_stats(), "Translation")

	var detached_design := Ship.new()
	BUILTINS._add_part(detached_design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(detached_design, ShipPart.Type.MINI_TURRET, Vector2i(3, 0))
	detached_design.set_tile_at(Vector2i(2, 0), ShipPart.Category.DEFENSE)
	var detached := FleetShip.new()
	detached.initialize(detached_design, 3, "Bridge")
	var mount := detached.get_stats().weapons[0].mount_offset
	detached.damage_cell(Vector2i(2, 0), 100)
	_check(detached.get_stats().dps > 0 and not detached.connected_cells().has(Vector2i(3, 0)), "Disconnected intact weapons remain operational.")
	_check(detached.get_stats().weapons[0].mount_offset == mount, "Damage does not recenter or shift surviving weapon mounts.")
	_check(detached.get_stats().occupied_cells == 5 and detached.get_stats().weight == 10, "Only the destroyed bridge loses cell mass.")

	var simulation := BattleSimulation.new()
	var players: Array[FleetShip] = [small, big]
	var aliens: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(1, 1.0, 42):
		aliens.append(alien)
	_check(simulation.setup_owned(players, aliens, 0, 2, 42), "Physical stats initialize in simulation.")
	for member in simulation.players:
		_same(member.owned_ship.design.get_stats(2), member.stats, "Live battle")
		_check(member.radius == member.stats.collision_radius and member.speed == member.stats.top_speed
			and member.acceleration == member.stats.acceleration and member.turn_rate == member.stats.turn_rate,
			"Battle consumes shared footprint and movement values.")
	var target := simulation.players[0]
	var source_ids: Array[int] = []
	for index in range(target.cooldowns.size()):
		target.cooldowns[index] = index + 0.25
		source_ids.append(target.stats.weapons[index].component_index)
	var victim := source_ids[1]
	small.units[victim].hp = 0
	simulation._refresh_owned_stats(target)
	_same(small.get_stats(2), target.stats, "After weapon destruction")
	for index in range(target.stats.weapons.size()):
		var old_index := source_ids.find(target.stats.weapons[index].component_index)
		_check(is_equal_approx(target.cooldowns[index], old_index + 0.25), "Destroyed weapon removal preserves each survivor's cooldown.")
	target.shields = 0
	simulation._damage(target, 1.0, target.position + Vector2(1000, 0), simulation.aliens[0], "Fixture")
	_same(small.get_stats(2), target.stats, "After incoming damage")
	_check(target.integrity == target.stats.integrity, "Live current integrity agrees after damage.")
	print("Shared ship stats tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
