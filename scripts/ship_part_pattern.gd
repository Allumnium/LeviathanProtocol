class_name ShipPartPattern
extends RefCounted

const SHIELD_TEXTURE = preload("res://assets/shield.png")
const LASER_TEXTURE = preload("res://assets/laser.png")
const LARGE_LASER_TEXTURE = preload("res://assets/laser_m.png")
const ARMOR_TEXTURE = preload("res://assets/armor_m.png")
const PLATE_TEXTURE = preload("res://assets/plate.png")
const MINI_TURRET_TEXTURE = preload("res://assets/mini-turret.png")
const THRUSTER_TEXTURE = preload("res://assets/thruster_s.png")
const LARGE_THRUSTER_TEXTURE = preload("res://assets/thruster_l.png")

var part_type: int
var category: int
var cell_offsets: Array[Vector2i] = []
var visual_cell_offsets: Array[Vector2i] = []
var hidden_tile_offsets: Array[Vector2i] = []
var hidden_tile_outline_color := Color.TRANSPARENT
var tile_categories: Array[int] = []
var stats: ShipPartStats
var can_rotate: bool
var display_name: String
var preview_texture: Texture2D


func _init(
	pattern_part_type: int,
	pattern_category: int,
	pattern_cell_offsets: Array[Vector2i],
	pattern_display_name: String,
	pattern_preview_texture: Texture2D,
	pattern_stats: ShipPartStats,
	pattern_can_rotate: bool = false,
	pattern_tile_categories: Array[int] = [],
	pattern_visual_cell_offsets: Array[Vector2i] = [],
	pattern_hidden_tile_offsets: Array[Vector2i] = [],
	pattern_hidden_tile_outline_color: Color = Color.TRANSPARENT
) -> void:
	part_type = pattern_part_type
	category = pattern_category
	cell_offsets = pattern_cell_offsets.duplicate()
	visual_cell_offsets = (
		pattern_visual_cell_offsets.duplicate()
		if not pattern_visual_cell_offsets.is_empty()
		else cell_offsets.duplicate()
	)
	hidden_tile_offsets = pattern_hidden_tile_offsets.duplicate()
	hidden_tile_outline_color = pattern_hidden_tile_outline_color
	stats = pattern_stats
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
			ShipPart.Type.LARGE_THRUSTER,
			ShipPart.Category.SPECIAL,
			[
				Vector2i(0, 0),
				Vector2i(1, 0),
				Vector2i(2, 0),
				Vector2i(3, 0),
				Vector2i(4, 0),
				Vector2i(0, 1),
				Vector2i(1, 1),
				Vector2i(2, 1),
				Vector2i(3, 1),
				Vector2i(4, 1),
			],
			"Large Thruster",
			LARGE_THRUSTER_TEXTURE,
			ShipPartStats.new(0.0, 0.0, 10.0, 150.0),
			false,
			[
				ShipPart.Category.OFFENSE,
				ShipPart.Category.OFFENSE,
				ShipPart.Category.OFFENSE,
				ShipPart.Category.SPECIAL,
				ShipPart.Category.SPECIAL,
				ShipPart.Category.OFFENSE,
				ShipPart.Category.OFFENSE,
				ShipPart.Category.OFFENSE,
				ShipPart.Category.SPECIAL,
				ShipPart.Category.SPECIAL,
			],
			[
				Vector2i(2, 0),
				Vector2i(3, 0),
				Vector2i(4, 0),
				Vector2i(2, 1),
				Vector2i(3, 1),
				Vector2i(4, 1),
			],
			[
				Vector2i(0, 0),
				Vector2i(1, 0),
				Vector2i(0, 1),
				Vector2i(1, 1),
			],
			Color(1.0, 0.15, 0.15, 1.0)
		)
	)
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
			ShipPartStats.new(100.0, 0.0, 9.0, 0.0),
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
			LARGE_LASER_TEXTURE,
			ShipPartStats.with_weapon("Double Laser", 6.0, 4.0, 12.0, 2)
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
			ARMOR_TEXTURE,
			ShipPartStats.new(0.0, 50.0, 4.0, 0.0)
		)
	)
	patterns.append(
		ShipPartPattern.new(
			ShipPart.Type.SINGLE_PLATE,
			ShipPart.Category.DEFENSE,
			[Vector2i(0, 0)],
			"Single Plate",
			PLATE_TEXTURE,
			ShipPartStats.new(0.0, 5.0, 1.0, 0.0)
		)
	)
	patterns.append(
		ShipPartPattern.new(
			ShipPart.Type.LASER,
			ShipPart.Category.OFFENSE,
			[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
			"Laser",
			LASER_TEXTURE,
			ShipPartStats.with_weapon("Laser", 3.0, 5.0, 12.0, 1)
		)
	)
	patterns.append(
		ShipPartPattern.new(
			ShipPart.Type.THRUSTER,
			ShipPart.Category.SPECIAL,
			[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
			"Thruster",
			THRUSTER_TEXTURE,
			ShipPartStats.new(0.0, 0.0, 3.0, 25.0),
			false,
			[
				ShipPart.Category.OFFENSE,
				ShipPart.Category.OFFENSE,
				ShipPart.Category.SPECIAL,
			],
			[Vector2i(2, 0)],
			[Vector2i(0, 0), Vector2i(1, 0)],
			Color(1.0, 0.15, 0.15, 1.0)
		)
	)
	patterns.append(
		ShipPartPattern.new(
			ShipPart.Type.MINI_TURRET,
			ShipPart.Category.OFFENSE,
			[Vector2i(0, 0)],
			"Mini Turret",
			MINI_TURRET_TEXTURE,
			ShipPartStats.with_weapon("Mini Turret", 1.0, 1.0, 1.0, 1)
		)
	)
	return patterns


func get_offsets_for_rotation(quarter_turns: int) -> Array[Vector2i]:
	return _get_offsets_for_rotation(cell_offsets, quarter_turns)


func get_visual_offsets_for_rotation(quarter_turns: int) -> Array[Vector2i]:
	return _get_offsets_for_rotation(visual_cell_offsets, quarter_turns)


func get_hidden_tile_offsets_for_rotation(quarter_turns: int) -> Array[Vector2i]:
	return _get_offsets_for_rotation(hidden_tile_offsets, quarter_turns)


func _get_offsets_for_rotation(
	offsets: Array[Vector2i],
	quarter_turns: int
) -> Array[Vector2i]:
	if offsets.is_empty() or cell_offsets.is_empty():
		return []

	var first_rotated_cell := _rotate_offset(cell_offsets[0], quarter_turns)
	var minimum_x := first_rotated_cell.x
	var minimum_y := first_rotated_cell.y
	for offset in cell_offsets:
		var rotated_offset := _rotate_offset(offset, quarter_turns)
		minimum_x = mini(minimum_x, rotated_offset.x)
		minimum_y = mini(minimum_y, rotated_offset.y)

	var normalized_offsets: Array[Vector2i] = []
	var normalization_offset := Vector2i(minimum_x, minimum_y)
	for offset in offsets:
		normalized_offsets.append(
			_rotate_offset(offset, quarter_turns) - normalization_offset
		)
	return normalized_offsets


func _rotate_offset(offset: Vector2i, quarter_turns: int) -> Vector2i:
	var rotated_offset := offset
	for _turn in range(quarter_turns):
		rotated_offset = Vector2i(-rotated_offset.y, rotated_offset.x)
	return rotated_offset
