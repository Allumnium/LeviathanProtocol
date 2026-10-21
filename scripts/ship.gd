class_name Ship
extends RefCounted

const NO_TILE_CATEGORY := -1

var tiles: Dictionary[Vector2i, int] = {}
var parts: Array[ShipPart] = []


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
