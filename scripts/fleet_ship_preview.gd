extends Control

var owned: FleetShip
var patterns: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pattern in ShipPartPattern.get_catalog():
		patterns[pattern.part_type] = pattern
	resized.connect(queue_redraw)

func _draw() -> void:
	if owned == null:
		return
	var scale_factor := minf(size.x, size.y) / (Ship.BATTLE_MODEL_SIZE + 8.0)
	draw_set_transform(size * 0.5, 0.0, Vector2.ONE * scale_factor)
	for unit in owned.units:
		var color := Color(0.25, 0.3, 0.35)
		if unit.hp <= 0.0:
			color = Color(0.8, 0.15, 0.15, 0.35)
		elif unit.hp < unit.max_hp:
			color = Color(1.0, 0.65, 0.15)
		for cell in unit.cells:
			var rect := Rect2(owned.local_cell_position(cell) - Vector2.ONE * owned.cell_size * 0.5, Vector2.ONE * owned.cell_size)
			draw_rect(rect.grow(-0.2), color, unit.hp > 0.0)
		var part: ShipPart = unit.part
		if part != null and unit.hp > 0.0:
			var pattern: ShipPartPattern = patterns.get(part.type)
			var visual_cells: Array[Vector2i] = []
			for offset in pattern.get_visual_offsets_for_rotation(pattern.get_rotation_for_offsets(part.cell_offsets)):
				visual_cells.append(part.origin + offset)
			var bounds := Rect2(owned.local_cell_position(visual_cells[0]) - Vector2.ONE * owned.cell_size * 0.5, Vector2.ONE * owned.cell_size)
			for cell in visual_cells:
				bounds = bounds.expand(owned.local_cell_position(cell) - Vector2.ONE * owned.cell_size * 0.5)
				bounds = bounds.expand(owned.local_cell_position(cell) + Vector2.ONE * owned.cell_size * 0.5)
			if pattern != null:
				draw_texture_rect(pattern.preview_texture, bounds.grow(-0.3), false, Color.WHITE if unit.hp == unit.max_hp else Color(1.0, 0.7, 0.4))
