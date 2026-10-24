class_name Ship
extends RefCounted

const NO_TILE_CATEGORY := -1
const BUILD_CELL_SIZE := Vector2(26.0, 26.0)
const BATTLE_MODEL_SIZE := 48.0
const RED_TILE_CREDIT_COST := 5
const BLUE_TILE_CREDIT_COST := 2
const GREEN_TILE_CREDIT_COST := 10
const CORE_TILE_CREDIT_COST := 15

var tiles: Dictionary[Vector2i, int] = {}
var parts: Array[ShipPart] = []
var _transitioning_parts: Array[ShipPart] = []
func set_tile_at(cell: Vector2i, category: int) -> void:
	tiles[cell] = category


func get_tile_category_at(cell: Vector2i) -> int:
	if not tiles.has(cell):
		return NO_TILE_CATEGORY
	return tiles[cell]


func remove_tile_at(cell: Vector2i) -> int:
	var category := get_tile_category_at(cell)
	if category == NO_TILE_CATEGORY:
		return NO_TILE_CATEGORY

	tiles.erase(cell)
	return category


func get_tile_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in tiles:
		cells.append(cell)
	return cells


func get_stats() -> ShipStats:
	var stats := ShipStats.new()
	var occupied_cells: Dictionary[Vector2i, bool] = {}
	var cells := get_tile_cells()
	var ship_center := Vector2.ZERO
	var ship_scale := 0.0
	if not cells.is_empty():
		var minimum_x := cells[0].x
		var minimum_y := cells[0].y
		var maximum_x := cells[0].x
		var maximum_y := cells[0].y
		for cell in cells:
			minimum_x = mini(minimum_x, cell.x)
			minimum_y = mini(minimum_y, cell.y)
			maximum_x = maxi(maximum_x, cell.x)
			maximum_y = maxi(maximum_y, cell.y)
		ship_center = Vector2(
			float(minimum_x + maximum_x + 1) * 0.5,
			float(minimum_y + maximum_y + 1) * 0.5
		)
		var ship_size := Vector2(
			float(maximum_x - minimum_x + 1) * BUILD_CELL_SIZE.x,
			float(maximum_y - minimum_y + 1) * BUILD_CELL_SIZE.y
		)
		ship_scale = BATTLE_MODEL_SIZE / maxf(ship_size.x, ship_size.y)

	for part in parts:
		_add_part_stats(
			stats,
			occupied_cells,
			part,
			_get_weapon_mount_offset(part, ship_center, ship_scale)
		)
	for part in _transitioning_parts:
		_add_part_stats(
			stats,
			occupied_cells,
			part,
			_get_weapon_mount_offset(part, ship_center, ship_scale)
		)

	for cell in cells:
		if not occupied_cells.has(cell):
			stats.weight += 1.0

	var filled_hull_area := get_filled_hull_area()
	stats.integrity += float(tiles.size())
	stats.weight += filled_hull_area
	return stats


func get_filled_hull_area() -> float:
	if tiles.is_empty():
		return 0.0

	var tile_corners := PackedVector2Array()
	for cell in get_tile_cells():
		var top_left := Vector2(cell)
		tile_corners.append(top_left)
		tile_corners.append(top_left + Vector2.RIGHT)
		tile_corners.append(top_left + Vector2.ONE)
		tile_corners.append(top_left + Vector2.DOWN)

	var hull := Geometry2D.convex_hull(tile_corners)
	var excluded_cells: Dictionary[Vector2i, bool] = {}
	for part in parts:
		_add_hidden_cells(excluded_cells, part)
	for part in _transitioning_parts:
		_add_hidden_cells(excluded_cells, part)

	return maxf(_get_polygon_area(hull) - float(excluded_cells.size()), 0.0)


func _get_polygon_area(polygon: PackedVector2Array) -> float:
	if polygon.size() < 3:
		return 0.0

	var twice_area := 0.0
	for index in range(polygon.size()):
		var next_index := (index + 1) % polygon.size()
		var current_point := polygon[index]
		var next_point := polygon[next_index]
		twice_area += (
			current_point.x * next_point.y
			- next_point.x * current_point.y
		)
	return absf(twice_area) * 0.5


func _add_hidden_cells(
	excluded_cells: Dictionary[Vector2i, bool],
	part: ShipPart
) -> void:
	for cell in part.get_hidden_tile_cells():
		if tiles.has(cell):
			excluded_cells[cell] = true


func _add_part_stats(
	stats: ShipStats,
	occupied_cells: Dictionary[Vector2i, bool],
	part: ShipPart,
	weapon_mount_offset: Vector2
) -> void:
	stats.add_equipment(part.stats, weapon_mount_offset)
	for cell in part.get_occupied_cells():
		occupied_cells[cell] = true


func _get_weapon_mount_offset(
	part: ShipPart,
	ship_center: Vector2,
	ship_scale: float
) -> Vector2:
	if ship_scale <= 0.0 or part.cell_offsets.is_empty():
		return Vector2.ZERO

	var part_center := Vector2.ZERO
	for offset in part.cell_offsets:
		part_center += Vector2(part.origin + offset) + Vector2.ONE * 0.5
	part_center /= float(part.cell_offsets.size())
	return Vector2(
		(part_center.x - ship_center.x) * BUILD_CELL_SIZE.x * ship_scale,
		(part_center.y - ship_center.y) * BUILD_CELL_SIZE.y * ship_scale
	)


func add_part(part: ShipPart) -> bool:
	if part == null:
		push_error("Cannot add a null part to the ship.")
		return false
	if part.cell_offsets.is_empty():
		push_error("A ship part must occupy at least one build cell.")
		return false

	for cell in part.get_occupied_cells():
		if get_part_at(cell) != null:
			return false

	parts.append(part)
	return true


func add_transitioning_part(part: ShipPart) -> bool:
	if part == null:
		push_error("Cannot add a null transitioning part to the ship.")
		return false
	if part.cell_offsets.is_empty():
		push_error("A transitioning ship part must occupy at least one build cell.")
		return false
	if _transitioning_parts.has(part):
		push_error("A ship part cannot enter transformation more than once.")
		return false

	_transitioning_parts.append(part)
	return true


func remove_transitioning_part(part: ShipPart) -> void:
	if not _transitioning_parts.has(part):
		push_error("Cannot finish transforming a part that is not transitioning.")
		return

	_transitioning_parts.erase(part)


func clear_transitioning_parts() -> void:
	_transitioning_parts.clear()


func get_part_at(cell: Vector2i) -> ShipPart:
	for part in parts:
		if part.occupies_cell(cell):
			return part
	return null


func clear_parts() -> void:
	parts.clear()


func clear() -> void:
	tiles.clear()
	parts.clear()
	_transitioning_parts.clear()


func to_design_data() -> Dictionary:
	var serialized_tiles: Array = []
	for cell in get_tile_cells():
		serialized_tiles.append([cell.x, cell.y, get_tile_category_at(cell)])

	var serialized_parts: Array[Dictionary] = []
	for part in parts:
		serialized_parts.append({
			"type": part.type,
			"category": part.category,
			"origin": [part.origin.x, part.origin.y],
			"cell_offsets": _serialize_offsets(part.cell_offsets),
			"hidden_tile_offsets": _serialize_offsets(part.hidden_tile_offsets),
		})

	return {
		"tiles": serialized_tiles,
		"parts": serialized_parts,
	}


func load_design_data(serialized_design: Variant) -> bool:
	if typeof(serialized_design) != TYPE_DICTIONARY:
		push_error("Ship design data must be a dictionary.")
		return false

	var serialized_tiles: Variant = serialized_design.get("tiles")
	var serialized_parts: Variant = serialized_design.get("parts")
	if typeof(serialized_tiles) != TYPE_ARRAY or typeof(serialized_parts) != TYPE_ARRAY:
		push_error("Ship design data must contain tile and part arrays.")
		return false

	var next_tiles: Dictionary[Vector2i, int] = {}
	for serialized_tile in serialized_tiles:
		if typeof(serialized_tile) != TYPE_ARRAY:
			push_error("Ship design tiles must be coordinate/category arrays.")
			return false
		if serialized_tile.size() != 3:
			push_error("Ship design tile entries must contain x, y, and category.")
			return false
		if (
			not _is_integer_value(serialized_tile[0])
			or not _is_integer_value(serialized_tile[1])
			or not _is_integer_value(serialized_tile[2])
		):
			push_error("Ship design tile coordinates and categories must be integers.")
			return false

		var cell := Vector2i(int(serialized_tile[0]), int(serialized_tile[1]))
		var category := int(serialized_tile[2])
		if not _is_known_tile_category(category):
			push_error("Ship design contains an unknown tile category: %s" % category)
			return false
		if next_tiles.has(cell):
			push_error("Ship design contains a duplicate tile at %s." % cell)
			return false
		next_tiles[cell] = category

	var patterns_by_type: Dictionary[int, ShipPartPattern] = {}
	for pattern in ShipPartPattern.get_catalog():
		patterns_by_type[pattern.part_type] = pattern

	var next_ship := Ship.new()
	next_ship.tiles = next_tiles
	for serialized_part in serialized_parts:
		if typeof(serialized_part) != TYPE_DICTIONARY:
			push_error("Ship design parts must be dictionaries.")
			return false
		if (
			not _is_integer_value(serialized_part.get("type"))
			or not _is_integer_value(serialized_part.get("category"))
		):
			push_error("Ship design parts must include integer type and category values.")
			return false

		var part_type := int(serialized_part["type"])
		var part_category := int(serialized_part["category"])
		var pattern: ShipPartPattern = patterns_by_type.get(part_type)
		if pattern == null:
			push_error("Ship design contains an unknown part type: %s" % part_type)
			return false
		if pattern.category != part_category or pattern.stats == null:
			push_error("Ship design part metadata does not match its catalog pattern.")
			return false

		var serialized_origin: Variant = serialized_part.get("origin")
		if (
			typeof(serialized_origin) != TYPE_ARRAY
			or serialized_origin.size() != 2
			or not _is_integer_value(serialized_origin[0])
			or not _is_integer_value(serialized_origin[1])
		):
			push_error("Ship design part origins must contain two integers.")
			return false
		var origin := Vector2i(
			int(serialized_origin[0]),
			int(serialized_origin[1])
		)

		var cell_offsets: Array[Vector2i] = []
		var hidden_tile_offsets: Array[Vector2i] = []
		if not _read_vector2i_array(
			serialized_part.get("cell_offsets"),
			cell_offsets,
			"part cell offsets"
		):
			return false
		if not _read_vector2i_array(
			serialized_part.get("hidden_tile_offsets"),
			hidden_tile_offsets,
			"hidden tile offsets"
		):
			return false

		var quarter_turns := pattern.get_rotation_for_offsets(cell_offsets)
		if quarter_turns < 0:
			push_error("Ship design part cells do not match its catalog pattern.")
			return false
		if (
			pattern.get_hidden_tile_offsets_for_rotation(quarter_turns)
			!= hidden_tile_offsets
		):
			push_error("Ship design hidden tiles do not match its catalog pattern.")
			return false
		if pattern.tile_categories.size() != cell_offsets.size():
			push_error("Ship design part pattern has an invalid tile layout.")
			return false
		for index in range(cell_offsets.size()):
			var cell := origin + cell_offsets[index]
			if (
				not next_tiles.has(cell)
				or next_tiles[cell] != pattern.tile_categories[index]
			):
				push_error("Ship design part tiles do not match its catalog pattern.")
				return false

		var part := ShipPart.new(
			part_type,
			part_category,
			origin,
			cell_offsets,
			pattern.stats,
			hidden_tile_offsets
		)
		if not next_ship.add_part(part):
			push_error("Ship design contains overlapping parts.")
			return false

	tiles = next_ship.tiles
	parts = next_ship.parts
	_transitioning_parts.clear()
	return true


func _serialize_offsets(offsets: Array[Vector2i]) -> Array:
	var serialized_offsets: Array = []
	for offset in offsets:
		serialized_offsets.append([offset.x, offset.y])
	return serialized_offsets


func _read_vector2i_array(
	serialized_values: Variant,
	offsets: Array[Vector2i],
	field_name: String
) -> bool:
	if typeof(serialized_values) != TYPE_ARRAY:
		push_error("Ship design %s must be an array." % field_name)
		return false
	for serialized_offset in serialized_values:
		if (
			typeof(serialized_offset) != TYPE_ARRAY
			or serialized_offset.size() != 2
			or not _is_integer_value(serialized_offset[0])
			or not _is_integer_value(serialized_offset[1])
		):
			push_error("Ship design %s must contain two-integer coordinates." % field_name)
			return false
		offsets.append(
			Vector2i(
				int(serialized_offset[0]),
				int(serialized_offset[1])
			)
		)
	return true


func _is_integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and value == roundf(value)


func _is_known_tile_category(category: int) -> bool:
	return (
		category == ShipPart.Category.OFFENSE
		or category == ShipPart.Category.DEFENSE
		or category == ShipPart.Category.SPECIAL
		or category == ShipPart.Category.CORE
	)
