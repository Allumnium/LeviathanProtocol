extends Control

const HULL_OVERLAY_COLOR := Color(0.38, 0.38, 0.4, 0.7)
const HULL_BASE_COLOR := Color(0.38, 0.38, 0.4, 1.0)

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
	var cells: Array[Vector2i] = []
	for unit in owned.units:
		if unit.hp <= 0.0:
			continue
		for cell in unit.cells:
			cells.append(cell)
	var hull := Ship.create_hull_polygon(cells)
	for index in range(hull.size()):
		hull[index] = size * 0.5 + (
			(hull[index] - owned.center) * owned.cell_size * scale_factor
		)
	draw_colored_polygon(hull, HULL_BASE_COLOR)
	draw_set_transform(size * 0.5, 0.0, Vector2.ONE * scale_factor)
	var hidden_cells: Dictionary[Vector2i, bool] = {}
	for unit in owned.units:
		if unit.hp > 0.0 and unit.part != null:
			for hidden_cell in unit.part.get_hidden_tile_cells():
				hidden_cells[hidden_cell] = true
	for unit in owned.units:
		var color := Color(0.25, 0.3, 0.35)
		if unit.hp <= 0.0:
			color = Color(0.8, 0.15, 0.15, 0.35)
		elif unit.hp < unit.max_hp:
			color = Color(1.0, 0.65, 0.15)
		for cell in unit.cells:
			if hidden_cells.has(cell):
				continue
			var rect := Rect2(owned.local_cell_position(cell) - Vector2.ONE * owned.cell_size * 0.5, Vector2.ONE * owned.cell_size)
			draw_rect(rect.grow(-0.2), color, unit.hp > 0.0)
		var part: ShipPart = unit.part
		if part != null and unit.hp > 0.0:
			var pattern: ShipPartPattern = patterns.get(part.type)
			if pattern != null and not pattern.renders_on_top:
				_draw_part(unit, part, pattern)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_colored_polygon(hull, HULL_OVERLAY_COLOR)
	draw_set_transform(size * 0.5, 0.0, Vector2.ONE * scale_factor)
	for unit in owned.units:
		var part: ShipPart = unit.part
		if part == null or unit.hp <= 0.0:
			continue
		var pattern: ShipPartPattern = patterns.get(part.type)
		if pattern != null and pattern.renders_on_top:
			_draw_part(unit, part, pattern)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_part(unit: Dictionary, part: ShipPart, pattern: ShipPartPattern) -> void:
	var pattern_transform := pattern.get_transform_for_offsets(part.cell_offsets)
	if pattern_transform.x < 0:
		return
	var visual_cells: Array[Vector2i] = []
	for offset in pattern.get_visual_offsets_for_transform(
		pattern_transform.x, pattern_transform.y == 1
	):
		visual_cells.append(part.origin + offset)
	if visual_cells.is_empty():
		return
	var half_cell := Vector2.ONE * owned.cell_size * 0.5
	var bounds := Rect2(owned.local_cell_position(visual_cells[0]) - half_cell, Vector2.ONE * owned.cell_size)
	for cell in visual_cells:
		bounds = bounds.expand(owned.local_cell_position(cell) - half_cell)
		bounds = bounds.expand(owned.local_cell_position(cell) + half_cell)
	draw_texture_rect(
		pattern.preview_texture,
		bounds.grow(-0.3),
		false,
		Color.WHITE if unit.hp == unit.max_hp else Color(1.0, 0.7, 0.4)
	)
