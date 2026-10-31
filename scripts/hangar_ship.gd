class_name HangarShip
extends FleetShip

# Mount handles bridge the existing combat API; they are not construction cells.
const ART_SCALE := 0.18
var chassis_id := ""
var flagship := false
var hull_hp := 0.0
var hull_max := 0.0
var mounts: Dictionary = {} # slot ID -> unique owned equipment instance
var chassis: Dictionary = {}
var art_texture: Texture2D

func initialize_chassis(chassis_key: String, ship_id: int, is_lead := false) -> bool:
	chassis = SlotCatalog.find_chassis(chassis_key)
	if chassis.is_empty():
		return false
	chassis_id = chassis_key
	art_texture = load(chassis.art)
	id = ship_id
	display_name = chassis.name + " %d" % id
	flagship = is_lead
	hull_max = float(chassis.get("integrity", 100))
	hull_hp = hull_max
	core_index = 0
	rebuild_units()
	return true

func is_slot_ship() -> bool:
	return true

func is_flagship() -> bool:
	return flagship

func rebuild_units(previous: Dictionary = {}) -> void:
	var old_max := hull_max
	hull_max = float(chassis.integrity)
	for instance: Dictionary in mounts.values():
		var stats := SlotCatalog.stats_for(instance.equipment_id, int(instance.rank))
		hull_max += stats.integrity
	hull_hp += hull_max - old_max
	units.clear()
	cell_units.clear()
	var core := ShipPart.new(0, 0, Vector2i.ZERO, [], ShipPartStats.new())
	core.type = ShipPart.Type.COMMAND_CENTER
	core.stats = ShipPartStats.new()
	_append_mount("core", Vector2(256, 190), 30.0, core, previous.get("core", 30.0))
	var engine := ShipPart.new(0, 0, Vector2i.ZERO, [], ShipPartStats.new())
	engine.type = ShipPart.Type.THRUSTER
	engine.stats = ShipPartStats.new(0, 0, 0, float(chassis.get("thrust", 25)))
	_append_mount("engine", Vector2(256, 448), 25.0, engine, previous.get("engine", 25.0))
	for slot: Dictionary in chassis.slots:
		if not mounts.has(slot.id):
			continue
		var instance: Dictionary = mounts[slot.id]
		var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
		var part := ShipPart.new(0, 0, Vector2i.ZERO, [], ShipPartStats.new())
		part.type = int(item.part_type)
		part.definition_id = item.id
		part.rank = int(item.rank)
		part.stats = SlotCatalog.stats_for(item.id, int(item.rank))
		var max_hp := float(item.get("hit_points", 15))
		_append_mount(slot.id, Vector2(slot.rect[0] + slot.rect[2] / 2.0, slot.rect[1] + slot.rect[3] / 2.0), max_hp, part, float(instance.hp))
	visual_revision += 1

func _append_mount(key: String, source_position: Vector2, max_hp: float, part: ShipPart, hp: float) -> void:
	var handle := Vector2i(units.size(), 0)
	cell_units[handle] = units.size()
	units.append({"key": key, "position": (source_position - Vector2(256, 256)).rotated(PI / 2) * ART_SCALE,
		"cells": [handle], "part": part, "max_hp": max_hp, "hp": hp})

func health_by_mount() -> Dictionary:
	var result := {}
	for unit in units:
		result[unit.key] = unit.hp
	return result

func sync_equipment_health() -> void:
	for unit in units:
		if mounts.has(unit.key):
			mounts[unit.key].hp = unit.hp

func is_alive() -> bool:
	return hull_hp >= 0 and not units.is_empty() and units[0].hp > 0

func has_cell(cell: Vector2i) -> bool:
	return cell_units.has(cell) and units[cell_units[cell]].hp > 0

func local_cell_position(cell: Vector2i) -> Vector2:
	return units[cell_units[cell]].position if cell_units.has(cell) else Vector2.ZERO

func get_stats(_laser_level := 0, energy_efficiency := 0.0) -> ShipStats:
	var result := ShipStats.new()
	result.integrity = hull_hp
	result.weight = float(chassis.get("mass", 35))
	result.collision_radius = float(chassis.get("radius", 36))
	result.footprint_size = Vector2.ONE * 512 * ART_SCALE
	for index in range(units.size()):
		var unit: Dictionary = units[index]
		if unit.hp <= 0:
			continue
		var part: ShipPart = unit.part
		result.weight += part.stats.weight
		result.thrust += part.stats.thrust
		result.shields += part.stats.shields
		result.shield_recharge += part.stats.shields * (1 + energy_efficiency)
		for weapon in part.stats.weapons:
			var copy := weapon.copy()
			copy.fire_interval_seconds /= weapon_cycle_rate()
			if part.type in [ShipPart.Type.LASER, ShipPart.Type.DOUBLE_LASER, ShipPart.Type.BEAM_LANCE, ShipPart.Type.ION_EMITTER]:
				copy.fire_interval_seconds /= 1 + energy_efficiency
			copy.mount_offset = unit.position
			copy.component_index = index
			result.weapons.append(copy)
	return result

func weapon_cycle_rate() -> float:
	var count := 0
	for unit: Dictionary in units:
		if unit.hp > 0 and unit.part != null and unit.part.type == ShipPart.Type.AMMUNITION_MAGAZINE:
			count += 1
	return 1.0 + 0.2 * count

func hit_cell(origin: Vector2, random: RandomNumberGenerator) -> Vector2i:
	# Scatter across the silhouette. Empty hull remains a valid direct hull hit.
	var point := Vector2(random.randf_range(-30, 30), random.randf_range(-30, 30))
	var best := -1
	var distance := 13.0 * 13.0
	for index in range(units.size()):
		if units[index].hp <= 0:
			continue
		var d: float = point.distance_squared_to(units[index].position)
		if d < distance:
			distance = d
			best = index
	return Vector2i(best, 0)

func damage_cell(cell: Vector2i, amount: float) -> Dictionary:
	var removed: Array[Vector2i] = []
	if not is_alive() or amount <= 0:
		return {"damage": 0.0, "removed": removed}
	var hull_damage := amount
	var component_damage := 0.0
	if has_cell(cell):
		var unit: Dictionary = units[cell_units[cell]]
		hull_damage = amount * 0.5
		component_damage = minf(unit.hp, amount * 0.5)
		unit.hp -= component_damage
		if unit.hp <= 0:
			removed.append(cell)
			visual_revision += 1
	hull_hp -= hull_damage
	sync_equipment_health()
	return {"damage": hull_damage + component_damage, "removed": removed}

func needs_repair() -> bool:
	return hull_hp < hull_max or units.any(func(unit: Dictionary) -> bool: return unit.hp < unit.max_hp)

func repair_cost() -> int:
	var amount := maxf(0, hull_max - hull_hp)
	for unit in units:
		amount += unit.max_hp - unit.hp
	return ceili(amount)

func repair() -> void:
	if not is_alive():
		return
	hull_hp = hull_max
	for unit in units:
		unit.hp = unit.max_hp
	sync_equipment_health()
	visual_revision += 1

func to_hangar_data() -> Dictionary:
	sync_equipment_health()
	var fitted := {}
	for key in mounts:
		fitted[key] = mounts[key].uid
	return {"id": id, "chassis": chassis_id, "flagship": flagship, "hull_hp": hull_hp,
		"builtins": {"core": units[0].hp, "engine": units[1].hp}, "mounts": fitted,
		"formation": [formation.x, formation.y]}
