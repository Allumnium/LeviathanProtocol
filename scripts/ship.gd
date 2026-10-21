class_name Ship
extends RefCounted

const NO_TILE_CATEGORY := -1

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
	for part in parts:
		_add_part_stats(stats, occupied_cells, part)
	for part in _transitioning_parts:
		_add_part_stats(stats, occupied_cells, part)

	for cell in get_tile_cells():
		if not occupied_cells.has(cell):
			stats.weight += 1.0
	return stats


func _add_part_stats(
	stats: ShipStats,
	occupied_cells: Dictionary[Vector2i, bool],
	part: ShipPart
) -> void:
	stats.add_equipment(part.stats)
	for cell in part.get_occupied_cells():
		occupied_cells[cell] = true


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
