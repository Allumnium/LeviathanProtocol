class_name ShipPart
extends RefCounted

enum Type {
	ARMOR_BLOCK,
	LASER,
	DOUBLE_LASER,
	SINGLE_PLATE,
	SHIELD,
	MINI_TURRET,
	THRUSTER,
	LARGE_THRUSTER,
	COMMAND_CENTER,
}

enum Category {
	OFFENSE,
	DEFENSE,
	SPECIAL,
	CORE,
}

var type: int
var category: int
var origin: Vector2i
var cell_offsets: Array[Vector2i] = []
var hidden_tile_offsets: Array[Vector2i] = []
var stats: ShipPartStats


func _init(
	part_type: int,
	part_category: int,
	part_origin: Vector2i,
	part_cell_offsets: Array[Vector2i],
	part_stats: ShipPartStats,
	part_hidden_tile_offsets: Array[Vector2i] = []
) -> void:
	if part_stats == null:
		push_error("A ship part must have stat values.")
		return

	type = part_type
	category = part_category
	origin = part_origin
	cell_offsets = part_cell_offsets.duplicate()
	hidden_tile_offsets = part_hidden_tile_offsets.duplicate()
	stats = part_stats.copy()


func get_occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in cell_offsets:
		cells.append(origin + offset)
	return cells


func get_hidden_tile_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in hidden_tile_offsets:
		cells.append(origin + offset)
	return cells


func occupies_cell(cell: Vector2i) -> bool:
	return cell_offsets.has(cell - origin)
