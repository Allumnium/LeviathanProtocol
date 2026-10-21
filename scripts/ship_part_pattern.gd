class_name ShipPartPattern
extends RefCounted

const SHIELD_TEXTURE = preload("res://assets/shield.png")
const LASER_TEXTURE = preload("res://assets/laser.png")
const ARMOR_TEXTURE = preload("res://assets/armor_m.png")
const PLATE_TEXTURE = preload("res://assets/plate.png")

var part_type: int
var category: int
var cell_offsets: Array[Vector2i] = []
var tile_categories: Array[int] = []
var can_rotate: bool
var display_name: String
var preview_texture: Texture2D


func _init(
	pattern_part_type: int,
	pattern_category: int,
	pattern_cell_offsets: Array[Vector2i],
	pattern_display_name: String,
	pattern_preview_texture: Texture2D,
	pattern_can_rotate: bool = false,
	pattern_tile_categories: Array[int] = []
) -> void:
	part_type = pattern_part_type
	category = pattern_category
	cell_offsets = pattern_cell_offsets.duplicate()
	can_rotate = pattern_can_rotate
	display_name = pattern_display_name
	preview_texture = pattern_preview_texture
	if pattern_tile_categories.is_empty():
		for _cell_offset in cell_offsets:
			tile_categories.append(pattern_category)
	elif pattern_tile_categories.size() != cell_offsets.size():
		push_error("A ship-part pattern must define a tile category for each cell.")
	else:
		tile_categories = pattern_tile_categories.duplicate()


static func get_catalog() -> Array[ShipPartPattern]:
	var patterns: Array[ShipPartPattern] = []
	patterns.append(
		ShipPartPattern.new(
			ShipPart.Type.SHIELD,
			ShipPart.Category.SPECIAL,
			[
				Vector2i(0, 0),
				Vector2i(1, 0),
				Vector2i(2, 0),
				Vector2i(0, 1),
				Vector2i(1, 1),
				Vector2i(2, 1),
				Vector2i(0, 2),
				Vector2i(1, 2),
				Vector2i(2, 2),
			],
			"Shield",
			SHIELD_TEXTURE,
			false,
			[
				ShipPart.Category.DEFENSE,
				ShipPart.Category.DEFENSE,
				ShipPart.Category.DEFENSE,
				ShipPart.Category.DEFENSE,
				ShipPart.Category.SPECIAL,
				ShipPart.Category.DEFENSE,
				ShipPart.Category.DEFENSE,
				ShipPart.Category.DEFENSE,
				ShipPart.Category.DEFENSE,
			]
		)
	)
	patterns.append(
		ShipPartPattern.new(
			ShipPart.Type.DOUBLE_LASER,
			ShipPart.Category.OFFENSE,
			[
				Vector2i(0, 0),
				Vector2i(1, 0),
				Vector2i(2, 0),
				Vector2i(0, 1),
				Vector2i(1, 1),
				Vector2i(2, 1),
			],
			"Double Laser",
			LASER_TEXTURE
		)
	)
	patterns.append(
		ShipPartPattern.new(
			ShipPart.Type.ARMOR_BLOCK,
			ShipPart.Category.DEFENSE,
			[
				Vector2i(0, 0),
				Vector2i(1, 0),
				Vector2i(0, 1),
				Vector2i(1, 1),
			],
			"Armor Block",
			ARMOR_TEXTURE
		)
	)
	patterns.append(
		ShipPartPattern.new(
			ShipPart.Type.SINGLE_PLATE,
			ShipPart.Category.DEFENSE,
			[Vector2i(0, 0)],
			"Single Plate",
			PLATE_TEXTURE
		)
	)
	patterns.append(
		ShipPartPattern.new(
			ShipPart.Type.LASER,
			ShipPart.Category.OFFENSE,
			[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
			"Laser",
			LASER_TEXTURE
		)
	)
	return patterns


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
