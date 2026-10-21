class_name ShipPart
extends RefCounted

enum Type {
	ARMOR_BLOCK,
	LASER,
	DOUBLE_LASER,
	SINGLE_PLATE,
	SHIELD,
}

enum Category {
	OFFENSE,
	DEFENSE,
	SPECIAL,
}

var type: int
var category: int
var origin: Vector2i
var cell_offsets: Array[Vector2i] = []


func _init(
	part_type: int,
	part_category: int,
	part_origin: Vector2i,
	part_cell_offsets: Array[Vector2i]
) -> void:
	type = part_type
	category = part_category
	origin = part_origin
	cell_offsets = part_cell_offsets.duplicate()


func get_occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in cell_offsets:
		cells.append(origin + offset)
	return cells


func occupies_cell(cell: Vector2i) -> bool:
	return cell_offsets.has(cell - origin)
