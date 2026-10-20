class_name Ship
extends RefCounted

var parts: Array[ShipPart] = []


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


func remove_part_at(cell: Vector2i) -> ShipPart:
	var part := get_part_at(cell)
	if part == null:
		return null

	parts.erase(part)
	return part


func clear() -> void:
	parts.clear()
