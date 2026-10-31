class_name Ship
extends RefCounted

const NO_TILE_CATEGORY := -1
const BUILD_CELL_SIZE := Vector2(26.0, 26.0)
# Nominal size of the original six-cell Drone; world geometry uses fixed cells.
const BATTLE_MODEL_SIZE := 48.0
const RED_TILE_CREDIT_COST := 5
const BLUE_TILE_CREDIT_COST := 2
const GREEN_TILE_CREDIT_COST := 8
const CORE_TILE_CREDIT_COST := 6
const MAX_HULL_BRIDGE_EMPTY_CELLS := 3

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


func get_stats(laser_level := 0, energy_efficiency := 0.0) -> ShipStats:
	var units: Array[Dictionary] = []
	var occupied: Dictionary = {}
	var all_parts: Array[ShipPart] = parts.duplicate()
	all_parts.append_array(_transitioning_parts)
	for part in all_parts:
		var cells := part.get_occupied_cells()
		units.append({"cells": cells, "part": part,
			"hp": ShipStats.component_integrity(cells.size(), part)})
		for cell in cells:
			occupied[cell] = true
	for cell in get_tile_cells():
		if not occupied.has(cell):
			units.append({"cells": [cell], "part": null, "hp": 1.0})
	return ShipStats.from_units(units, ShipStats.cell_bounds(get_tile_cells()).get_center(), laser_level, energy_efficiency)


func get_filled_hull_area() -> float:
	if tiles.is_empty():
		return 0.0

	var hull := create_hull_polygon(get_tile_cells())
	var excluded_cells: Dictionary[Vector2i, bool] = {}
	for part in parts:
		_add_hidden_cells(excluded_cells, part)
	for part in _transitioning_parts:
		_add_hidden_cells(excluded_cells, part)

	return maxf(_get_polygon_area(hull) - float(excluded_cells.size()), 0.0)


static func create_hull_polygon(cells: Array[Vector2i]) -> PackedVector2Array:
	if cells.is_empty():
		return PackedVector2Array()
	var boundary_edges: Dictionary = {}
	for cell in cells:
		var top_left := cell
		var top_right := cell + Vector2i.RIGHT
		var bottom_right := cell + Vector2i.ONE
		var bottom_left := cell + Vector2i.DOWN
		_add_boundary_edge(boundary_edges, top_left, top_right)
		_add_boundary_edge(boundary_edges, top_right, bottom_right)
		_add_boundary_edge(boundary_edges, bottom_right, bottom_left)
		_add_boundary_edge(boundary_edges, bottom_left, top_left)
	var loops := _trace_boundary_loops(boundary_edges)
	if loops.is_empty():
		return PackedVector2Array()
	var hull: PackedVector2Array = loops[0]
	var largest_area := _polygon_area(hull)
	for loop in loops:
		var area := _polygon_area(loop)
		if area > largest_area:
			hull = loop
			largest_area = area
	if cells.size() < 3:
		return _remove_collinear_points(hull)
	var centers := PackedVector2Array()
	for cell in cells:
		centers.append(Vector2(cell) + Vector2.ONE * 0.5)
	var triangle_indices := Geometry2D.triangulate_delaunay(centers)
	var bridge_components: Array[PackedVector2Array] = []
	for index in range(0, triangle_indices.size(), 3):
		var triangle := PackedVector2Array([
			centers[triangle_indices[index]],
			centers[triangle_indices[index + 1]],
			centers[triangle_indices[index + 2]],
		])
		if not _triangle_edges_are_short_enough(triangle):
			continue
		_merge_into_components(bridge_components, triangle)
	for bridge in bridge_components:
		if Geometry2D.is_polygon_clockwise(bridge) != Geometry2D.is_polygon_clockwise(hull):
			bridge.reverse()
		var merged := Geometry2D.merge_polygons(hull, bridge)
		if merged.size() == 1:
			hull = merged[0]
	return _remove_collinear_points(hull)


static func _merge_into_components(
	components: Array[PackedVector2Array],
	polygon: PackedVector2Array
) -> void:
	var combined := polygon
	var index := 0
	while index < components.size():
		var candidate := components[index]
		if Geometry2D.is_polygon_clockwise(candidate) != Geometry2D.is_polygon_clockwise(combined):
			candidate.reverse()
		var merged := Geometry2D.merge_polygons(candidate, combined)
		if merged.size() != 1:
			index += 1
			continue
		combined = merged[0]
		components.remove_at(index)
		index = 0
	components.append(combined)


static func _add_boundary_edge(edges: Dictionary, start: Vector2i, finish: Vector2i) -> void:
	var reverse: Dictionary = edges.get(finish, {})
	if reverse.has(start):
		reverse.erase(start)
		if reverse.is_empty():
			edges.erase(finish)
		return
	var outgoing: Dictionary = edges.get(start, {})
	outgoing[finish] = true
	edges[start] = outgoing


static func _trace_boundary_loops(edges: Dictionary) -> Array[PackedVector2Array]:
	var loops: Array[PackedVector2Array] = []
	while not edges.is_empty():
		var start: Vector2i = edges.keys()[0]
		var current := start
		var loop := PackedVector2Array()
		while true:
			loop.append(Vector2(current))
			var outgoing: Dictionary = edges.get(current, {})
			if outgoing.is_empty():
				break
			var next: Vector2i = outgoing.keys()[0]
			outgoing.erase(next)
			if outgoing.is_empty():
				edges.erase(current)
			current = next
			if current == start:
				break
		if loop.size() >= 3 and current == start:
			loops.append(_remove_collinear_points(loop))
	return loops


static func _triangle_edges_are_short_enough(triangle: PackedVector2Array) -> bool:
	var maximum_span := MAX_HULL_BRIDGE_EMPTY_CELLS + 1
	for index in range(3):
		var difference := triangle[index] - triangle[(index + 1) % 3]
		if maxf(absf(difference.x), absf(difference.y)) > maximum_span:
			return false
	return true


static func _remove_collinear_points(polygon: PackedVector2Array) -> PackedVector2Array:
	if polygon.size() <= 3:
		return polygon
	var result := PackedVector2Array()
	for index in range(polygon.size()):
		var previous := polygon[(index - 1 + polygon.size()) % polygon.size()]
		var current := polygon[index]
		var next := polygon[(index + 1) % polygon.size()]
		if not is_zero_approx((current - previous).cross(next - current)):
			result.append(current)
	return result


static func _polygon_area(polygon: PackedVector2Array) -> float:
	if polygon.size() < 3:
		return 0.0
	var twice_area := 0.0
	for index in range(polygon.size()):
		var next := polygon[(index + 1) % polygon.size()]
		twice_area += polygon[index].x * next.y - next.x * polygon[index].y
	return absf(twice_area) * 0.5


func _get_polygon_area(polygon: PackedVector2Array) -> float:
	return _polygon_area(polygon)


func _add_hidden_cells(
	excluded_cells: Dictionary[Vector2i, bool],
	part: ShipPart
) -> void:
	for cell in part.get_hidden_tile_cells():
		if tiles.has(cell):
			excluded_cells[cell] = true


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
	var patterns: Dictionary = {}
	for pattern in ShipPartPattern.get_catalog():
		patterns[pattern.pattern_key()] = pattern
	for part in parts:
		var orientation := part.get_transform(ShipPartPattern.for_cells(patterns[part.pattern_key()], part.cell_offsets)) if patterns.has(part.pattern_key()) else Vector2i.ZERO
		serialized_parts.append({
			"type": part.type,
			"definition_id": part.definition_id,
			"rank": part.rank,
			"quarter_turns": orientation.x,
			"horizontally_flipped": orientation.y == 1,
			"category": part.category,
			"origin": [part.origin.x, part.origin.y],
			"cell_offsets": _serialize_offsets(part.cell_offsets),
			"hidden_tile_offsets": _serialize_offsets(part.hidden_tile_offsets),
		})
		if part.type == ShipPart.Type.CREW_QUARTERS and part.crew_manual:
			serialized_parts.back()["crew_recipients"] = _serialize_offsets(part.crew_recipients)

	return {
		"tiles": serialized_tiles,
		"parts": serialized_parts,
	}


func load_design_data(serialized_design: Variant) -> bool:
	if typeof(serialized_design) != TYPE_DICTIONARY:
		push_error("Ship design data must be a dictionary.")
		return false
	# Versioned hex designs have a separate loader. Never treat their axial
	# coordinates as legacy square tiles, even if a payload also supplies parts.
	if serialized_design.has("topology") or serialized_design.get("version", 1) != 1:
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

	var patterns_by_type: Dictionary[String, ShipPartPattern] = {}
	for pattern in ShipPartPattern.get_catalog():
		patterns_by_type[pattern.pattern_key()] = pattern

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
		if not _is_integer_value(serialized_part.get("rank", 1)):
			return false
		var part_rank := int(serialized_part.get("rank", 1))
		var pattern: ShipPartPattern = patterns_by_type.get("%d/%d" % [part_type, part_rank])
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

		pattern = ShipPartPattern.for_cells(pattern, cell_offsets)
		var pattern_transform := pattern.get_transform_for_offsets(cell_offsets)
		if serialized_part.has("definition_id") and serialized_part.definition_id != pattern.definition_id:
			push_error("Ship design equipment identity does not match its type.")
			return false
		if part_rank < 1:
			push_error("Ship design contains an unavailable equipment rank.")
			return false
		if serialized_part.has("quarter_turns") or serialized_part.has("horizontally_flipped"):
			if not _is_integer_value(serialized_part.get("quarter_turns")) or not serialized_part.get("horizontally_flipped") is bool:
				push_error("Ship design orientation must contain turns and reflection.")
				return false
			var turns := int(serialized_part.quarter_turns)
			if turns < 0 or turns > 3 or (turns != 0 and not pattern.can_rotate):
				push_error("Ship design contains an unsupported rotation.")
				return false
			pattern_transform = Vector2i(turns, 1 if serialized_part.horizontally_flipped else 0)
			if pattern.get_offsets_for_transform(turns, serialized_part.horizontally_flipped) != cell_offsets:
				push_error("Ship design orientation differs from its occupied cells.")
				return false
		if pattern_transform.x < 0:
			push_error("Ship design part cells do not match its catalog pattern.")
			return false
		if (
			pattern.get_hidden_tile_offsets_for_transform(
				pattern_transform.x, pattern_transform.y == 1
			)
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
			hidden_tile_offsets,
			pattern_transform.x,
			pattern_transform.y == 1,
			part_rank
		)
		if not next_ship.add_part(part):
			push_error("Ship design contains overlapping parts.")
			return false
		if serialized_part.has("crew_recipients"):
			if part_type != ShipPart.Type.CREW_QUARTERS or not _read_vector2i_array(serialized_part.crew_recipients, part.crew_recipients, "crew recipients"):
				return false
			if part.crew_recipients.size() > 3:
				return false
			var unique := {}
			for recipient in part.crew_recipients:
				if unique.has(recipient) or recipient == Vector2i.ZERO:
					return false
				unique[recipient] = true
			part.crew_manual = true

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
