class_name ShipPartPattern
extends RefCounted

const SHIELD_TEXTURE = preload("res://assets/shield.png")
const LASER_TEXTURE = preload("res://assets/laser.png")
const LARGE_LASER_TEXTURE = preload("res://assets/laser_m.png")
const ARMOR_TEXTURE = preload("res://assets/armor_m.png")
const PLATE_TEXTURE = preload("res://assets/plate.png")
const MINI_TURRET_TEXTURE = preload("res://assets/mini-turret.png")
const THRUSTER_SHEET = preload("res://assets/thruster_s_animated.png")
const LARGE_THRUSTER_SHEET = preload("res://assets/thruster_l_animated.png")
const COMMAND_CENTER_TEXTURE = preload("res://assets/commandcenter.png")

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
var renders_on_top := false
var tech_category: int
var prerequisite_types: Array[int] = []
var definition_id := ""
var definition_revision := 0
var rank := 1
static var _lab_textures: Dictionary = {}


func pattern_key() -> String:
	return "%d/%d" % [part_type, rank]


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
	pattern_hidden_tile_outline_color: Color = Color.TRANSPARENT,
	pattern_tech_category: int = ShipPart.TechCategory.CORE
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
	tech_category = pattern_tech_category
	if pattern_tile_categories.is_empty():
		for _cell_offset in cell_offsets:
			tile_categories.append(pattern_category)
	elif pattern_tile_categories.size() != cell_offsets.size():
		push_error("A ship-part pattern must define a tile category for each cell.")
	else:
		tile_categories = pattern_tile_categories.duplicate()


static func get_catalog() -> Array[ShipPartPattern]:
	var patterns: Array[ShipPartPattern] = []
	patterns.append(ShipPartPattern.new(
		ShipPart.Type.COMMAND_CENTER, ShipPart.Category.SPECIAL,
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		"Command Center", COMMAND_CENTER_TEXTURE,
		ShipPartStats.new(0.0, 12.0, 4.0, 0.0),
		false,
		[
			ShipPart.Category.CORE,
			ShipPart.Category.SPECIAL,
			ShipPart.Category.SPECIAL,
			ShipPart.Category.CORE
		]
	))
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
			_thruster_idle_texture(LARGE_THRUSTER_SHEET),
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
			[
				Vector2i(0, 0),
				Vector2i(1, 0),
				Vector2i(0, 1),
				Vector2i(1, 1),
			],
			Color(1.0, 0.15, 0.15, 1.0),
			ShipPart.TechCategory.UTILITY
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
			ShipPartStats.new(40.0, 0.0, 9.0, 0.0),
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
			],
			[],
			[],
			Color.TRANSPARENT,
			ShipPart.TechCategory.ENERGY
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
			ShipPartStats.with_weapon("Double Laser", 6.0, 4.0, 14.4, 2)
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
			ShipPartStats.with_weapon("Laser", 3.0, 4.0, 12.0, 1),
			false,
			[],
			[],
			[],
			Color.TRANSPARENT,
			ShipPart.TechCategory.ENERGY
		)
	)
	patterns.append(
		ShipPartPattern.new(
			ShipPart.Type.THRUSTER,
			ShipPart.Category.SPECIAL,
			[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
			"Thruster",
			_thruster_idle_texture(THRUSTER_SHEET),
			ShipPartStats.new(0.0, 0.0, 3.0, 25.0),
			false,
			[
				ShipPart.Category.OFFENSE,
				ShipPart.Category.OFFENSE,
				ShipPart.Category.SPECIAL,
			],
			[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
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
			ShipPartStats.with_weapon("Mini Turret", 1.0, 1.0, 1.0, 1, true)
		)
	)
	patterns.append(ShipPartPattern.new(ShipPart.Type.CREW_QUARTERS, ShipPart.Category.CORE,
		[Vector2i.ZERO, Vector2i.RIGHT], "Crew Quarters",
		_lab_texture({Vector2i.ZERO: ShipPart.Category.CORE, Vector2i.RIGHT: ShipPart.Category.CORE}),
		ShipPartStats.new(0, 0, 2, 0), true, [ShipPart.Category.CORE, ShipPart.Category.CORE]))
	patterns.append(_shared_pattern(ShipPart.Type.REPAIR_STATION, ShipPartStats.new(0, 0, 3, 0)))
	var pd := ShipPartStats.with_weapon("Point Defense", 4, 0.5, 0.6, 1, true)
	pd.weapons[0].range_units = 160
	patterns.append(_shared_pattern(ShipPart.Type.POINT_DEFENSE_TURRET, pd))
	var missiles := ShipPartStats.with_weapon("Missile Rack", 6, 5, 3, 3, true)
	missiles.weapons[0].range_units = 340
	missiles.weapons[0].interceptable = true
	patterns.append(_shared_pattern(ShipPart.Type.MISSILE_RACK, missiles))
	var lab_definition := GameDefinitions.equipment(ShipPart.Type.RESEARCH_LAB)
	for physical_rank: Dictionary in lab_definition.ranks:
		var offsets: Array[Vector2i] = []
		var categories: Array[int] = []
		var cells := MaterialRecipe.parse(physical_rank.recipe)
		for cell: Vector2i in cells:
			offsets.append(cell)
			categories.append(cells[cell])
		var lab := ShipPartPattern.new(ShipPart.Type.RESEARCH_LAB, ShipPart.Category.CORE, offsets,
			"Research Lab %s" % ["I", "II", "III"][int(physical_rank.rank) - 1],
			_lab_texture(cells), ShipPartStats.new(0, 0, offsets.size(), 0), true, categories)
		lab.rank = int(physical_rank.rank)
		patterns.append(lab)
	var top_layer_types := [
		ShipPart.Type.COMMAND_CENTER,
		ShipPart.Type.LASER,
		ShipPart.Type.DOUBLE_LASER,
		ShipPart.Type.MINI_TURRET,
		ShipPart.Type.THRUSTER,
		ShipPart.Type.LARGE_THRUSTER,
	]
	for pattern in patterns:
		# Preserve the current exhaust restriction while allowing other recipes
		# to rotate with their material labels and explicit component facing.
		pattern.can_rotate = pattern.part_type not in [ShipPart.Type.THRUSTER, ShipPart.Type.LARGE_THRUSTER]
		pattern.renders_on_top = pattern.part_type in top_layer_types
		if pattern.part_type == ShipPart.Type.DOUBLE_LASER:
			pattern.tech_category = ShipPart.TechCategory.ENERGY
			pattern.prerequisite_types = [ShipPart.Type.LASER]
	var implemented_patterns: Array[ShipPartPattern] = []
	for pattern in patterns:
		var definition := GameDefinitions.equipment(pattern.part_type)
		if definition.is_empty() or not definition.implemented:
			continue
		pattern.definition_id = definition.id
		pattern.definition_revision = int(definition.revision)
		implemented_patterns.append(pattern)
	return implemented_patterns


static func _lab_texture(cells: Dictionary) -> Texture2D:
	var key := MaterialRecipe.signature(cells)
	if _lab_textures.has(key):
		return _lab_textures[key]
	# Procedural component placeholder, with the exact physical rank footprint.
	var extent := Vector2i.ONE
	for cell: Vector2i in cells:
		extent.x = maxi(extent.x, cell.x + 1)
		extent.y = maxi(extent.y, cell.y + 1)
	var texture := Image.create(extent.x * 26, extent.y * 26, false, Image.FORMAT_RGBA8)
	texture.fill(Color.TRANSPARENT)
	for cell: Vector2i in cells:
		var base := cell * 26
		texture.fill_rect(Rect2i(base + Vector2i(1, 1), Vector2i(24, 24)), Color("455379") if cells[cell] == ShipPart.Category.CORE else Color("296760"))
		texture.fill_rect(Rect2i(base + Vector2i(6, 5), Vector2i(14, 16)), Color("102731"))
		texture.fill_rect(Rect2i(base + Vector2i(9, 12), Vector2i(8, 6)), Color("88ddec"))
	var result := ImageTexture.create_from_image(texture)
	_lab_textures[key] = result
	return result

static func _shared_pattern(type: int, stats: ShipPartStats) -> ShipPartPattern:
	var definition := GameDefinitions.equipment(type)
	var cells := MaterialRecipe.parse(definition.recipe)
	var offsets: Array[Vector2i] = []
	var categories: Array[int] = []
	for cell: Vector2i in cells:
		offsets.append(cell)
		categories.append(cells[cell])
	return ShipPartPattern.new(type, ShipPart.Category.SPECIAL if type == ShipPart.Type.REPAIR_STATION else ShipPart.Category.OFFENSE,
		offsets, definition.display_name, _lab_texture(cells), stats, true, categories)


static func _thruster_idle_texture(sheet: Texture2D) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = sheet
	texture.region = Rect2(Vector2.ZERO, Vector2(
		float(sheet.get_width()) / 3.0,
		float(sheet.get_height()) / 3.0
	))
	return texture


func get_offsets_for_rotation(quarter_turns: int) -> Array[Vector2i]:
	return get_offsets_for_transform(quarter_turns, false)


func get_offsets_for_transform(
	quarter_turns: int,
	horizontally_flipped: bool
) -> Array[Vector2i]:
	return _get_offsets_for_transform(cell_offsets, quarter_turns, horizontally_flipped)


func get_rotation_for_offsets(offsets: Array[Vector2i]) -> int:
	return get_transform_for_offsets(offsets).x


func get_transform_for_offsets(offsets: Array[Vector2i]) -> Vector2i:
	var rotation_count := 4 if can_rotate else 1
	for quarter_turns in range(rotation_count):
		for flip_index in range(2):
			if get_offsets_for_transform(quarter_turns, flip_index == 1) == offsets:
				return Vector2i(quarter_turns, flip_index)
	return Vector2i(-1, 0)


func get_visual_offsets_for_rotation(quarter_turns: int) -> Array[Vector2i]:
	return get_visual_offsets_for_transform(quarter_turns, false)


func get_visual_offsets_for_transform(
	quarter_turns: int,
	horizontally_flipped: bool
) -> Array[Vector2i]:
	return _get_offsets_for_transform(
		visual_cell_offsets,
		quarter_turns,
		horizontally_flipped
	)


func get_hidden_tile_offsets_for_rotation(quarter_turns: int) -> Array[Vector2i]:
	return get_hidden_tile_offsets_for_transform(quarter_turns, false)


func get_hidden_tile_offsets_for_transform(
	quarter_turns: int,
	horizontally_flipped: bool
) -> Array[Vector2i]:
	return _get_offsets_for_transform(
		hidden_tile_offsets,
		quarter_turns,
		horizontally_flipped
	)


func _get_offsets_for_transform(
	offsets: Array[Vector2i],
	quarter_turns: int,
	horizontally_flipped: bool
) -> Array[Vector2i]:
	if offsets.is_empty() or cell_offsets.is_empty():
		return []

	var first_transformed_cell := _transform_offset(
		cell_offsets[0], quarter_turns, horizontally_flipped
	)
	var minimum_x := first_transformed_cell.x
	var minimum_y := first_transformed_cell.y
	for offset in cell_offsets:
		var transformed_offset := _transform_offset(
			offset, quarter_turns, horizontally_flipped
		)
		minimum_x = mini(minimum_x, transformed_offset.x)
		minimum_y = mini(minimum_y, transformed_offset.y)

	var normalized_offsets: Array[Vector2i] = []
	var normalization_offset := Vector2i(minimum_x, minimum_y)
	for offset in offsets:
		normalized_offsets.append(
			_transform_offset(offset, quarter_turns, horizontally_flipped)
			- normalization_offset
		)
	return normalized_offsets


func _transform_offset(
	offset: Vector2i,
	quarter_turns: int,
	horizontally_flipped: bool
) -> Vector2i:
	var transformed := _rotate_offset(offset, quarter_turns)
	if horizontally_flipped:
		transformed.y = -transformed.y
	return transformed


func _rotate_offset(offset: Vector2i, quarter_turns: int) -> Vector2i:
	var rotated_offset := offset
	for _turn in range(quarter_turns):
		rotated_offset = Vector2i(-rotated_offset.y, rotated_offset.x)
	return rotated_offset
