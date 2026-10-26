class_name FleetShip
extends RefCounted

# A constructed ship owns an immutable blueprint and persistent component health.
# Combined parts are atomic damage units; their occupied cells stay until HP is zero.
const REPAIR_PER_TILE := [2.0, 0.1, 4.0, 20]
const NEIGHBORS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var id := 0
var family_id := ""
var slot_role := "regular"
var in_reserve := false
var escort_target_id := 0
var display_name := "Ship"
var design: Ship
var formation := Vector2.ZERO
var units: Array[Dictionary] = []
var cell_units: Dictionary[Vector2i, int] = {}
var core_index := -1
var center := Vector2.ZERO
var cell_size := ShipStats.BATTLE_CELL_SIZE
var visual_revision := 0

func initialize(blueprint: Ship, ship_id: int, title: String) -> void:
	id = ship_id
	display_name = title
	design = Ship.new()
	design.load_design_data(blueprint.to_design_data())
	units.clear()
	cell_units.clear()
	core_index = -1
	for part in design.parts:
		var hp := ShipStats.component_integrity(part.cell_offsets.size(), part)
		_add_unit(part.get_occupied_cells(), hp, part)
		if part.type == ShipPart.Type.COMMAND_CENTER:
			core_index = units.size() - 1
	for cell in design.get_tile_cells():
		if not cell_units.has(cell):
			_add_unit([cell], 1.0, null)
	center = ShipStats.cell_bounds(design.get_tile_cells()).get_center()
	cell_size = ShipStats.BATTLE_CELL_SIZE


func _add_unit(cells: Array[Vector2i], hp: float, part: ShipPart) -> void:
	for cell in cells:
		cell_units[cell] = units.size()
	units.append({"cells": cells, "hp": hp, "max_hp": hp, "part": part})

func is_alive() -> bool:
	return core_index >= 0 and units[core_index].hp > 0.0

func has_cell(cell: Vector2i) -> bool:
	return cell_units.has(cell) and units[cell_units[cell]].hp > 0.0

func local_cell_position(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2.ONE * 0.5 - center) * cell_size

func get_stats(laser_level: int = 0) -> ShipStats:
	return ShipStats.from_units(units, center, laser_level)


func repair_cost() -> int:
	var total := 0.0
	for unit in units:
		var fraction: float = 1.0 - unit.hp / unit.max_hp
		for cell in unit.cells:
			total += REPAIR_PER_TILE[design.tiles[cell]] * fraction
	return ceili(total - 0.00001)

func repair() -> void:
	for unit in units:
		unit.hp = unit.max_hp

func connected_cells() -> Dictionary:
	var visited := {}
	if not is_alive():
		return visited
	var pending: Array[Vector2i] = [units[core_index].cells[0]]
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		if visited.has(cell) or not has_cell(cell):
			continue
		visited[cell] = true
		for offset in NEIGHBORS:
			pending.append(cell + offset)
	return visited

func construction_error() -> String:
	var cores := 0
	for part in design.parts:
		if part.type == ShipPart.Type.COMMAND_CENTER:
			cores += 1
	if cores != 1:
		return "Requires one command center (2 × 2 green and purple checkerboard)."
	if get_stats().weapons.is_empty():
		return "Requires a weapon."
	return ""

# Trace from the attack origin to the ship center, then scatter only among
# exposed cells within two grid cells of the first intersection.
func hit_cell(origin: Vector2, random: RandomNumberGenerator) -> Vector2i:
	var direction := (-origin).normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	var first := Vector2i(2147483647, 2147483647)
	var closest := INF
	for cell in cell_units:
		if not has_cell(cell):
			continue
		var distance := _ray_distance(origin, direction, cell)
		if distance < closest:
			closest = distance
			first = cell
	if closest == INF:
		# A center ray can pass through a hole: use the nearest surviving cell.
		for cell in cell_units:
			if has_cell(cell) and local_cell_position(cell).distance_squared_to(origin) < closest:
				closest = local_cell_position(cell).distance_squared_to(origin)
				first = cell
	var candidates: Array[Vector2i] = []
	for cell in cell_units:
		if not has_cell(cell) or Vector2(cell - first).length() > 2.0:
			continue
		var ray := (local_cell_position(cell) - origin).normalized()
		var distance := _ray_distance(origin, ray, cell)
		var exposed := true
		for blocker in cell_units:
			if has_cell(blocker) and _ray_distance(origin, ray, blocker) < distance - 0.001:
				exposed = false
				break
		if exposed:
			candidates.append(cell)
	return first if candidates.is_empty() else candidates[random.randi_range(0, candidates.size() - 1)]

func _ray_distance(origin: Vector2, direction: Vector2, cell: Vector2i) -> float:
	var lower := local_cell_position(cell) - Vector2.ONE * cell_size * 0.5
	var upper := lower + Vector2.ONE * cell_size
	var near := 0.0
	var far := INF
	for axis in range(2):
		if absf(direction[axis]) < 0.00001:
			if origin[axis] < lower[axis] or origin[axis] > upper[axis]:
				return INF
		else:
			var a := (lower[axis] - origin[axis]) / direction[axis]
			var b := (upper[axis] - origin[axis]) / direction[axis]
			near = maxf(near, minf(a, b))
			far = minf(far, maxf(a, b))
	return near if near <= far else INF

func damage_cell(cell: Vector2i, amount: float) -> Dictionary:
	var removed: Array[Vector2i] = []
	if not has_cell(cell) or not is_alive():
		return {"damage": 0.0, "removed": removed}
	var unit: Dictionary = units[cell_units[cell]]
	var dealt := minf(unit.hp, amount)
	unit.hp -= dealt
	if unit.hp <= 0.0:
		removed.append_array(unit.cells)
		visual_revision += 1
		# Losing the command center destroys the ship, but does not physically
		# erase every other intact block from its wreckage.
		if cell_units[cell] == core_index:
			return {"damage": dealt, "removed": removed}
	return {"damage": dealt, "removed": removed}
