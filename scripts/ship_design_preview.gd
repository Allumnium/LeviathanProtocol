extends Control

const HULL_COLOR := Color(0.38, 0.38, 0.4, 1.0)
const PREVIEW_BACKGROUND_COLOR := Color(0.035, 0.045, 0.055, 1.0)
const RED_TILE_TEXTURE: Texture2D = preload("res://assets/ui/icons/red_square.png")
const BLUE_TILE_TEXTURE: Texture2D = preload("res://assets/ui/icons/blue_square.png")
const GREEN_TILE_TEXTURE: Texture2D = preload("res://assets/ui/icons/green_square.png")
const CORE_TILE_TEXTURE: Texture2D = preload("res://assets/core.png")
const HULL_OVERLAY_COLOR := Color(0.38, 0.38, 0.4, 0.7)

var ship: Ship
var _part_patterns_by_type: Dictionary[int, ShipPartPattern] = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pattern in ShipPartPattern.get_catalog():
		_part_patterns_by_type[pattern.part_type] = pattern
	resized.connect(queue_redraw)
	queue_redraw()


func set_ship(design_ship: Ship) -> void:
	ship = design_ship
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PREVIEW_BACKGROUND_COLOR)
	if ship == null or ship.tiles.is_empty():
		return

	var cells := ship.get_tile_cells()
	var minimum_x := cells[0].x
	var maximum_x := cells[0].x
	var minimum_y := cells[0].y
	var maximum_y := cells[0].y
	for cell in cells:
		minimum_x = mini(minimum_x, cell.x)
		maximum_x = maxi(maximum_x, cell.x)
		minimum_y = mini(minimum_y, cell.y)
		maximum_y = maxi(maximum_y, cell.y)

	var column_count := maximum_x - minimum_x + 1
	var row_count := maximum_y - minimum_y + 1
	var available_size := size - Vector2.ONE * 8.0
	var cell_size := minf(
		available_size.x / float(column_count),
		available_size.y / float(row_count)
	)
	if cell_size <= 0.0:
		return
	var ship_size := Vector2(column_count, row_count) * cell_size
	var origin := (size - ship_size) * 0.5 - Vector2(minimum_x, minimum_y) * cell_size

	var hull_points := PackedVector2Array()
	for cell in cells:
		var cell_origin := origin + Vector2(cell) * cell_size
		hull_points.append(cell_origin)
		hull_points.append(cell_origin + Vector2(cell_size, 0.0))
		hull_points.append(cell_origin + Vector2.ONE * cell_size)
		hull_points.append(cell_origin + Vector2(0.0, cell_size))
	var hull := Geometry2D.convex_hull(hull_points)
	draw_colored_polygon(hull, HULL_COLOR)

	var hidden_cells: Dictionary[Vector2i, bool] = {}
	for part in ship.parts:
		for hidden_cell in part.get_hidden_tile_cells():
			hidden_cells[hidden_cell] = true
	for cell in cells:
		if hidden_cells.has(cell):
			continue
		var texture := _get_tile_texture(ship.get_tile_category_at(cell))
		if texture == null:
			continue
		var padding := minf(cell_size * 0.06, 1.0)
		var tile_origin := origin + Vector2(cell) * cell_size + Vector2.ONE * padding
		var tile_size := maxf(cell_size - padding * 2.0, 1.0)
		draw_texture_rect(
			texture,
			Rect2(tile_origin, Vector2.ONE * tile_size),
			false
		)

	for part in ship.parts:
		var pattern: ShipPartPattern = _part_patterns_by_type.get(part.type)
		if pattern != null and not pattern.renders_on_top:
			_draw_part(part, origin, cell_size)

	draw_colored_polygon(hull, HULL_OVERLAY_COLOR)

	for part in ship.parts:
		var pattern: ShipPartPattern = _part_patterns_by_type.get(part.type)
		if pattern != null and pattern.renders_on_top:
			_draw_part(part, origin, cell_size)

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.4, 0.45, 1.0), false, 1.0)


func _draw_part(part: ShipPart, origin: Vector2, cell_size: float) -> void:
	var pattern: ShipPartPattern = _part_patterns_by_type.get(part.type)
	if pattern == null:
		push_error("Unknown ship part type in design preview: %s" % part.type)
		return
	if pattern.preview_texture == null:
		push_error("No preview texture is assigned for %s." % pattern.display_name)
		return

	var quarter_turns := pattern.get_rotation_for_offsets(part.cell_offsets)
	if quarter_turns < 0:
		push_error("Could not determine the rotation for %s." % pattern.display_name)
		return
	var visual_offsets := pattern.get_visual_offsets_for_rotation(quarter_turns)
	if visual_offsets.is_empty():
		push_error("Cannot display a ship part with no visual cells.")
		return

	var minimum_x := part.origin.x + visual_offsets[0].x
	var maximum_x := minimum_x
	var minimum_y := part.origin.y + visual_offsets[0].y
	var maximum_y := minimum_y
	for offset in visual_offsets:
		minimum_x = mini(minimum_x, part.origin.x + offset.x)
		maximum_x = maxi(maximum_x, part.origin.x + offset.x)
		minimum_y = mini(minimum_y, part.origin.y + offset.y)
		maximum_y = maxi(maximum_y, part.origin.y + offset.y)

	var texture_origin := origin + Vector2(minimum_x, minimum_y) * cell_size
	var texture_size := Vector2(
		maximum_x - minimum_x + 1,
		maximum_y - minimum_y + 1
	) * cell_size
	draw_texture_rect(
		pattern.preview_texture,
		Rect2(texture_origin, texture_size),
		false
	)


func _get_tile_texture(category: int) -> Texture2D:
	match category:
		ShipPart.Category.OFFENSE:
			return RED_TILE_TEXTURE
		ShipPart.Category.DEFENSE:
			return BLUE_TILE_TEXTURE
		ShipPart.Category.SPECIAL:
			return GREEN_TILE_TEXTURE
		ShipPart.Category.CORE:
			return CORE_TILE_TEXTURE
		_:
			push_error("Unknown tile category in design preview: %s" % category)
			return null
