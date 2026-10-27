extends RefCounted

static func drone() -> Ship:
	var design := Ship.new()
	_add_part(design, ShipPart.Type.SHIELD, Vector2i(0, 0))
	_add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i(3, 2))
	_add_part(design, ShipPart.Type.ARMOR_BLOCK, Vector2i(5, 2))
	_add_part(design, ShipPart.Type.THRUSTER, Vector2i(0, 3))
	for cell in [Vector2i(3, 0), Vector2i(4, 1), Vector2i(0, 4), Vector2i(2, 4), Vector2i(4, 4), Vector2i(3, 5)]:
		_add_part(design, ShipPart.Type.MINI_TURRET, cell)
	for cell in [Vector2i(4, 0), Vector2i(3, 1), Vector2i(5, 1), Vector2i(1, 4), Vector2i(3, 4), Vector2i(5, 4), Vector2i(0, 5), Vector2i(4, 5)]:
		_add_part(design, ShipPart.Type.SINGLE_PLATE, cell)
	return design

static func _add_part(design: Ship, type: int, origin: Vector2i, rank := 1) -> void:
	for pattern in ShipPartPattern.get_catalog():
		if pattern.part_type != type or pattern.rank != rank:
			continue
		for index in range(pattern.cell_offsets.size()):
			design.set_tile_at(origin + pattern.cell_offsets[index], pattern.tile_categories[index])
		design.add_part(ShipPart.new(type, pattern.category, origin, pattern.cell_offsets, pattern.stats, pattern.hidden_tile_offsets, 0, false, rank))
		return
