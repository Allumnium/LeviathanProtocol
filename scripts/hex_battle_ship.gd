class_name HexBattleShip
extends FleetShip

# The battle engine shares the physical hex ship's health, never a converted save.
const ART_SCALE := ShipStats.BATTLE_CELL_SIZE / HexMaterialPalette.TILE_SIZE.x
var state: HexShipState
var hull_cells: Array[Vector2i] = []
var _polygons: Dictionary[Vector2i, PackedVector2Array] = {}
var _bounds := Rect2()
var _radius := 0.0
var _flagship_type := false

func initialize(_blueprint: Ship, _ship_id: int, _title: String) -> bool:
	# A legacy Ship cannot supply hex topology or a fixed chassis.
	return false

func initialize_hex(blueprint: HexShipDesign, ship_id: int, title: String) -> bool:
	var physical := HexShipState.new()
	return physical.initialize(blueprint) and bind_state(physical, ship_id, title)

func bind_state(physical: HexShipState, ship_id: int, title: String) -> bool:
	if physical == null or physical.design == null or ship_id <= 0:
		return false
	state = physical
	id = ship_id
	display_name = title
	in_reserve = false
	var runtime := HexBattleDesign.new()
	runtime.blueprint = state.design
	design = runtime
	units = state.units
	cell_units.clear()
	core_index = -1
	var chassis := state.design.chassis()
	_flagship_type = chassis.flagship
	hull_cells = chassis.hull.duplicate()
	center = Vector2.ZERO
	for cell in hull_cells:
		center += HexMaterialPalette.center(cell)
	center /= hull_cells.size()
	_polygons.clear()
	_radius = 0
	var first := true
	for cell in hull_cells:
		var polygon := HexMaterialPalette.polygon(cell)
		for index in range(polygon.size()):
			polygon[index] = (polygon[index] - center) * ART_SCALE
			_bounds = Rect2(polygon[index], Vector2.ZERO) if first else _bounds.expand(polygon[index])
			first = false
			_radius = maxf(_radius, polygon[index].length())
		_polygons[cell] = polygon
	for cell: Vector2i in state.design.tiles:
		design.tiles[cell] = state.design.tiles[cell]
	for index in range(units.size()):
		var unit := units[index]
		var part: ShipPart = null
		for pattern in ShipPartPattern.get_catalog():
			if pattern.definition_id == unit.equipment_id and pattern.rank == unit.rank:
				var offsets: Array[Vector2i] = []
				for cell: Vector2i in unit.cells:
					offsets.append(cell - unit.cells[0])
				part = ShipPart.new(pattern.part_type, pattern.category, unit.cells[0], offsets, pattern.stats, [], 0, false, unit.rank)
				part.hex_cells = true
				design.parts.append(part)
				break
		unit["part"] = part
		if unit.equipment_id == "command_center":
			core_index = index
		for cell: Vector2i in unit.cells:
			cell_units[cell] = index
	return core_index >= 0

func is_hex_ship() -> bool:
	return true

func is_flagship() -> bool:
	return _flagship_type

func is_alive() -> bool:
	return state != null and state.is_alive()

func has_cell(cell: Vector2i) -> bool:
	return state != null and state.has_cell(cell)

func local_cell_position(cell: Vector2i) -> Vector2:
	return (HexMaterialPalette.center(cell) - center) * ART_SCALE

func cell_polygon(cell: Vector2i) -> PackedVector2Array:
	return _polygons.get(cell, PackedVector2Array())

func get_stats(laser_level: int = 0, energy_efficiency := 0.0) -> ShipStats:
	var result := ShipStats.from_units(units, Vector2.ZERO, laser_level, energy_efficiency, local_cell_position)
	# Structure remains physical after equipment is destroyed. Never shrink the
	# outline, mass or collision bounds to the surviving equipment's square bounds.
	result.weight += hull_cells.size()
	result.integrity = state.chassis_integrity if is_alive() else 0.0
	result.footprint_size = _bounds.size
	result.collision_radius = _radius
	return result

func connected_cells() -> Dictionary:
	var result := {}
	if is_alive():
		for cell in hull_cells:
			result[cell] = true
	return result

func construction_error() -> String:
	return "" if is_alive() else "Destroyed chassis."

func needs_repair() -> bool:
	return state.chassis_integrity < state.max_chassis_integrity or super.needs_repair()

func damage_cell(cell: Vector2i, amount: float) -> Dictionary:
	var removed: Array[Vector2i] = []
	var index := state.component_at(cell)
	var damage := state.damage_cell(cell, amount)
	if index >= 0 and units[index].hp <= 0:
		# Only player materials can become salvage; compact built-ins have no
		# fabricated recipe/material cost. Their cells remain solid chassis.
		for occupied: Vector2i in units[index].cells:
			if state.design.tiles.has(occupied):
				removed.append(occupied)
		visual_revision += 1
	return {"damage": damage, "removed": removed}

func hit_cell(origin: Vector2, random: RandomNumberGenerator) -> Vector2i:
	var direction := (-origin).normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	var first := Vector2i(2147483647, 2147483647)
	var closest := INF
	for cell in hull_cells:
		if not has_cell(cell):
			continue
		var distance := _ray_distance(origin, direction, cell)
		if distance < closest:
			closest = distance
			first = cell
	if closest == INF:
		for cell in hull_cells:
			if has_cell(cell) and local_cell_position(cell).distance_squared_to(origin) < closest:
				closest = local_cell_position(cell).distance_squared_to(origin)
				first = cell
	var candidates: Array[Vector2i] = []
	for cell in hull_cells:
		if not has_cell(cell) or HexGrid.distance(cell, first) > 2:
			continue
		var ray := (local_cell_position(cell) - origin).normalized()
		var distance := _ray_distance(origin, ray, cell)
		var exposed := distance < INF
		for blocker in hull_cells:
			if _ray_distance(origin, ray, blocker) < distance - 0.001:
				exposed = false
				break
		if exposed:
			candidates.append(cell)
	return first if candidates.is_empty() else candidates[random.randi_range(0, candidates.size() - 1)]

func _ray_distance(origin: Vector2, direction: Vector2, cell: Vector2i) -> float:
	var shape := cell_polygon(cell)
	if shape.is_empty():
		return INF
	if Geometry2D.is_point_in_polygon(origin, shape):
		return 0.0
	var nearest := INF
	for index in range(6):
		var edge := shape[(index + 1) % 6] - shape[index]
		var denominator := direction.cross(edge)
		if absf(denominator) < 0.000001:
			continue
		var relative := shape[index] - origin
		var along_ray := relative.cross(edge) / denominator
		var along_edge := relative.cross(direction) / denominator
		if along_ray >= 0 and along_edge >= 0 and along_edge <= 1:
			nearest = minf(nearest, along_ray)
	return nearest
