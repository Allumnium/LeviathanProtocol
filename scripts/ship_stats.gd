class_name ShipStats
extends RefCounted

const INTEGRITY_MULTIPLIER := 1.0 / 3.0
const BATTLE_CELL_SIZE := 8.0
const MAX_SPEED := 120.0
const MIN_TURN_RATE := 0.75
const MAX_TURN_RATE := 1.5

var shields := 0.0
var integrity := 0.0
var weight := 0.0
var thrust := 0.0
var engine_rate := 1.0
var shield_recharge := 0.0 # Effective shield capacity weighted by recharge rate.
var occupied_cells := 0
var footprint_size := Vector2.ZERO
var collision_radius := 18.0
var top_speed: float:
	get:
		return MAX_SPEED * sqrt(maxf(thrust, 0.0) / maxf(weight + maxf(thrust, 0.0), 1.0))
var acceleration: float:
	get:
		return top_speed * (0.6 + 1.2 * _thrust_fraction()) * engine_rate
var turn_rate: float:
	get:
		return lerpf(MIN_TURN_RATE, MAX_TURN_RATE, _thrust_fraction()) * engine_rate
var weapons: Array[ShipWeaponStats] = []
var dps: float:
	get:
		var total_dps := 0.0
		for weapon in weapons:
			total_dps += weapon.get_dps()
		return total_dps

func _thrust_fraction() -> float:
	return maxf(thrust, 0.0) / maxf(weight + maxf(thrust, 0.0), 1.0)


static func component_integrity(cells: int, part: ShipPart) -> float:
	return maxf(1.0, cells + (part.stats.integrity * INTEGRITY_MULTIPLIER if part != null else 0.0))


static func cell_bounds(cells: Array[Vector2i]) -> Rect2:
	if cells.is_empty():
		return Rect2()
	var bounds := Rect2(Vector2(cells[0]), Vector2.ONE)
	for cell in cells:
		bounds = bounds.expand(Vector2(cell)).expand(Vector2(cell) + Vector2.ONE)
	return bounds


static func from_units(units: Array[Dictionary], center: Vector2, laser_level := 0, energy_efficiency := 0.0) -> ShipStats:
	var result := ShipStats.new()
	var cells: Array[Vector2i] = []
	var radius_squared := 0.0
	var rates := AdjacencyRules.rates(units)
	var effective_thrust := 0.0
	for index in range(units.size()):
		var unit := units[index]
		if unit.hp <= 0.0:
			continue
		result.integrity += unit.hp
		var mount := Vector2.ZERO
		for cell: Vector2i in unit.cells:
			cells.append(cell)
			mount += (Vector2(cell) + Vector2.ONE * 0.5 - center) * BATTLE_CELL_SIZE
			for corner in [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.ONE]:
				radius_squared = maxf(radius_squared, ((Vector2(cell) + corner - center) * BATTLE_CELL_SIZE).length_squared())
		var part: ShipPart = unit.part
		if part == null:
			continue
		result.shields += part.stats.shields
		var rate: float = rates.get(index, 1.0)
		if part.type in [ShipPart.Type.LASER, ShipPart.Type.DOUBLE_LASER, ShipPart.Type.SHIELD]:
			rate = AdjacencyRules.ordinary_rate({"crew": rate - 1.0, "energy": energy_efficiency})
		result.shield_recharge += part.stats.shields * rate
		result.thrust += part.stats.thrust
		effective_thrust += part.stats.thrust * rate
		result.weight += part.stats.weight
		mount /= maxf(unit.cells.size(), 1)
		for weapon in part.stats.weapons:
			var copy := weapon.copy()
			copy.mount_offset += mount
			copy.component_index = index
			copy.fire_interval_seconds /= rate
			if part.type in [ShipPart.Type.LASER, ShipPart.Type.DOUBLE_LASER]:
				var multiplier := 1.0 + 0.1 * laser_level
				copy.damage_per_shot *= multiplier
				copy.fire_interval_seconds /= multiplier
			result.weapons.append(copy)
	result.occupied_cells = cells.size()
	result.engine_rate = effective_thrust / result.thrust if result.thrust > 0 else 1.0
	# Every physical material cell has mass, including loose and exhaust cells.
	# A visual hull polygon can bridge empty space; that space has no mass.
	result.weight += cells.size()
	result.footprint_size = cell_bounds(cells).size * BATTLE_CELL_SIZE
	result.collision_radius = sqrt(radius_squared)
	return result


func add_equipment(
	equipment_stats: ShipPartStats,
	weapon_mount_offset: Vector2 = Vector2.ZERO
) -> void:
	if equipment_stats == null:
		push_error("Cannot add missing ship-part stats.")
		return

	shields += equipment_stats.shields
	integrity += equipment_stats.integrity * INTEGRITY_MULTIPLIER
	weight += equipment_stats.weight
	thrust += equipment_stats.thrust
	for weapon in equipment_stats.weapons:
		var copied_weapon := weapon.copy()
		copied_weapon.mount_offset += weapon_mount_offset
		weapons.append(copied_weapon)
