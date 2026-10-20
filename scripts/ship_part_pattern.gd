class_name ShipPartPattern
extends RefCounted

var part_type: int
var category: int
var cell_offsets: Array[Vector2i] = []
var can_rotate: bool


func _init(
	pattern_part_type: int,
	pattern_category: int,
	pattern_cell_offsets: Array[Vector2i],
	pattern_can_rotate: bool = false
) -> void:
	part_type = pattern_part_type
	category = pattern_category
	cell_offsets = pattern_cell_offsets.duplicate()
	can_rotate = pattern_can_rotate


func get_offsets_for_rotation(quarter_turns: int) -> Array[Vector2i]:
	var rotated_offsets: Array[Vector2i] = []
	for offset in cell_offsets:
		var rotated_offset := offset
		for _turn in range(quarter_turns):
			rotated_offset = Vector2i(-rotated_offset.y, rotated_offset.x)
		rotated_offsets.append(rotated_offset)

	var minimum_x := rotated_offsets[0].x
	var minimum_y := rotated_offsets[0].y
	for offset in rotated_offsets:
		minimum_x = mini(minimum_x, offset.x)
		minimum_y = mini(minimum_y, offset.y)

	var normalized_offsets: Array[Vector2i] = []
	for offset in rotated_offsets:
		normalized_offsets.append(offset - Vector2i(minimum_x, minimum_y))
	return normalized_offsets
