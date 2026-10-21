class_name BattleVisuals
extends Control

const BUILD_CELL_SIZE := Vector2(26.0, 26.0)
const HULL_COLOR := Color(0.38, 0.38, 0.4, 1.0)
const HULL_CUTOUT_COLOR := Color(0.035, 0.045, 0.055, 1.0)
const RED_TILE_TEXTURE: Texture2D = preload("res://assets/ui/icons/red_square.png")
const BLUE_TILE_TEXTURE: Texture2D = preload("res://assets/ui/icons/blue_square.png")
const GREEN_TILE_TEXTURE: Texture2D = preload("res://assets/ui/icons/green_square.png")

var _part_patterns_by_type: Dictionary[int, ShipPartPattern] = {}
var simulation: BattleSimulation
var camera_position := Vector2.ZERO
var camera_zoom := 0.65
var stars := PackedVector2Array()


func world_transform() -> Transform2D:
	return Transform2D(0.0, Vector2.ONE * camera_zoom, 0.0,
		size * 0.5 - camera_position * camera_zoom)


func _set_ship_transform(position: Vector2, angle: float, ship_scale: float = 1.0) -> void:
	draw_set_transform_matrix(world_transform() * Transform2D(
		angle, Vector2.ONE * ship_scale, 0.0, position))


func _ready() -> void:
	for pattern in ShipPartPattern.get_catalog():
		_part_patterns_by_type[pattern.part_type] = pattern
	var random := RandomNumberGenerator.new()
	random.seed = 4815
	for index in range(450):
		stars.append(Vector2(random.randf_range(-1800.0, 1800.0),
			random.randf_range(-1400.0, 1400.0)))
	resized.connect(_on_resized)
	queue_redraw()


func _on_resized() -> void:
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or simulation == null:
		return
	draw_set_transform_matrix(world_transform())
	for star in stars:
		draw_circle(star, 1.0, Color(0.3, 0.4, 0.5, 0.65))
	for drop in simulation.drops:
		if not drop.collected:
			var color := Color.DODGER_BLUE
			if drop.category == ShipPart.Category.OFFENSE:
				color = Color.RED
			elif drop.category == ShipPart.Category.SPECIAL:
				color = Color.LIME_GREEN
			draw_rect(Rect2(drop.position - Vector2.ONE * 4.0, Vector2.ONE * 8.0), color)
			draw_rect(Rect2(drop.position - Vector2.ONE * 6.0, Vector2.ONE * 12.0),
				Color(color, 0.3), false, 1.0)
	if simulation.player.is_alive():
		_draw_player_ship()
	_draw_alien_fleet()
	draw_set_transform_matrix(world_transform())
	for beam in simulation.beams:
		draw_line(beam.source.position, beam.target.position,
			Color(1.0, 0.03, 0.06, beam.lifetime / 0.16), 2.0, true)
	for projectile in simulation.projectiles:
		var direction := (projectile.target.position - projectile.position).normalized()
		draw_line(projectile.position - direction * 12.0, projectile.position,
			Color(0.4, 1.0, 0.25, 0.7), 2.0, true)
		draw_circle(projectile.position, 2.5, Color(0.8, 1.0, 0.3))
	for explosion in simulation.explosions:
		var progress := 1.0 - explosion.lifetime / 0.6
		draw_arc(explosion.position, 4.0 + progress * 32.0, 0.0, TAU, 24,
			Color(1.0, 0.45, 0.1, 1.0 - progress), 3.0, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_player_ship() -> void:
	var cells := GameState.ship.get_tile_cells()
	if cells.is_empty():
		return

	var minimum_x := cells[0].x
	var minimum_y := cells[0].y
	var maximum_x := cells[0].x
	var maximum_y := cells[0].y
	for cell in cells:
		minimum_x = mini(minimum_x, cell.x)
		minimum_y = mini(minimum_y, cell.y)
		maximum_x = maxi(maximum_x, cell.x)
		maximum_y = maxi(maximum_y, cell.y)

	var ship_size := Vector2(
		float(maximum_x - minimum_x + 1) * BUILD_CELL_SIZE.x,
		float(maximum_y - minimum_y + 1) * BUILD_CELL_SIZE.y
	)
	var ship_center := Vector2(
		float(minimum_x + maximum_x + 1) * BUILD_CELL_SIZE.x * 0.5,
		float(minimum_y + maximum_y + 1) * BUILD_CELL_SIZE.y * 0.5
	)
	var ship_scale := 48.0 / maxf(ship_size.x, ship_size.y)
	_set_ship_transform(simulation.player.position, simulation.player.heading + PI * 0.5, ship_scale)
	var hull_points := PackedVector2Array()
	for cell in cells:
		var cell_top_left := Vector2(
			float(cell.x) * BUILD_CELL_SIZE.x,
			float(cell.y) * BUILD_CELL_SIZE.y
		) - ship_center
		hull_points.append(cell_top_left)
		hull_points.append(cell_top_left + Vector2(BUILD_CELL_SIZE.x, 0.0))
		hull_points.append(cell_top_left + BUILD_CELL_SIZE)
		hull_points.append(cell_top_left + Vector2(0.0, BUILD_CELL_SIZE.y))
	draw_colored_polygon(Geometry2D.convex_hull(hull_points), HULL_COLOR)

	var hidden_cells: Dictionary[Vector2i, bool] = {}
	for part in GameState.ship.parts:
		var pattern := _get_pattern_for_part(part)
		if pattern == null:
			continue
		for cell in part.get_hidden_tile_cells():
			if not GameState.ship.tiles.has(cell):
				continue
			hidden_cells[cell] = true
			var hidden_cell_top_left := Vector2(
				float(cell.x) * BUILD_CELL_SIZE.x,
				float(cell.y) * BUILD_CELL_SIZE.y
			) - ship_center
			var hidden_cell_rect := Rect2(hidden_cell_top_left, BUILD_CELL_SIZE)
			draw_rect(hidden_cell_rect, HULL_CUTOUT_COLOR)
			if not is_zero_approx(pattern.hidden_tile_outline_color.a):
				draw_rect(hidden_cell_rect, pattern.hidden_tile_outline_color, false, 2.0)

	for cell in cells:
		if hidden_cells.has(cell):
			continue
		var tile_texture := _get_tile_texture(GameState.ship.get_tile_category_at(cell))
		if tile_texture == null:
			continue
		var cell_center := Vector2(
			(float(cell.x) + 0.5) * BUILD_CELL_SIZE.x,
			(float(cell.y) + 0.5) * BUILD_CELL_SIZE.y
		) - ship_center
		draw_texture(tile_texture, cell_center - tile_texture.get_size() * 0.5)

	for part in GameState.ship.parts:
		var pattern := _get_pattern_for_part(part)
		if pattern == null:
			continue
		if pattern.preview_texture == null:
			push_error("No battle texture is assigned for %s." % pattern.display_name)
			continue

		var visual_cells := _get_visual_cells_for_part(part, pattern)
		if visual_cells.is_empty():
			continue
		var minimum_visual_x := visual_cells[0].x
		var minimum_visual_y := visual_cells[0].y
		var maximum_visual_x := visual_cells[0].x
		var maximum_visual_y := visual_cells[0].y
		for cell in visual_cells:
			minimum_visual_x = mini(minimum_visual_x, cell.x)
			minimum_visual_y = mini(minimum_visual_y, cell.y)
			maximum_visual_x = maxi(maximum_visual_x, cell.x)
			maximum_visual_y = maxi(maximum_visual_y, cell.y)

		var visual_size := Vector2(
			float(maximum_visual_x - minimum_visual_x + 1) * BUILD_CELL_SIZE.x,
			float(maximum_visual_y - minimum_visual_y + 1) * BUILD_CELL_SIZE.y
		)
		var visual_center := Vector2(
			float(minimum_visual_x + maximum_visual_x + 1) * BUILD_CELL_SIZE.x * 0.5,
			float(minimum_visual_y + maximum_visual_y + 1) * BUILD_CELL_SIZE.y * 0.5
		) - ship_center
		draw_texture_rect(
			pattern.preview_texture,
			Rect2(visual_center - visual_size * 0.5, visual_size),
			false
		)
	if simulation.player.hit_flash > 0.0:
		draw_arc(Vector2.ZERO, maxf(ship_size.x, ship_size.y) * 0.55, 0.0, TAU, 32,
			Color(0.4, 0.8, 1.0, 0.7), 2.0 / ship_scale, true)
	draw_set_transform_matrix(world_transform())


func _draw_alien_fleet() -> void:
	for alien in simulation.aliens:
		if not alien.is_alive():
			continue
		var texture_size := alien.alien.texture.get_size()
		var draw_size := texture_size * (32.0 / maxf(texture_size.x, texture_size.y))
		_set_ship_transform(alien.position, alien.heading + PI * 0.5)
		draw_texture_rect(alien.alien.texture, Rect2(-draw_size * 0.5, draw_size), false)
		if alien.hit_flash > 0.0:
			draw_arc(Vector2.ZERO, 19.0, 0.0, TAU, 24, Color(0.4, 0.9, 1.0, 0.8), 1.5, true)
	draw_set_transform_matrix(world_transform())


func _get_pattern_for_part(part: ShipPart) -> ShipPartPattern:
	var pattern: ShipPartPattern = _part_patterns_by_type.get(part.type)
	if pattern == null:
		push_error("Unknown ship part type in battle renderer: %s" % part.type)
	return pattern


func _get_visual_cells_for_part(
	part: ShipPart,
	pattern: ShipPartPattern
) -> Array[Vector2i]:
	for quarter_turns in range(4):
		if pattern.get_offsets_for_rotation(quarter_turns) != part.cell_offsets:
			continue
		var visual_cells: Array[Vector2i] = []
		for offset in pattern.get_visual_offsets_for_rotation(quarter_turns):
			visual_cells.append(part.origin + offset)
		return visual_cells

	push_error("Could not determine the rotation for %s." % pattern.display_name)
	return []


func _get_tile_texture(category: int) -> Texture2D:
	match category:
		ShipPart.Category.OFFENSE:
			return RED_TILE_TEXTURE
		ShipPart.Category.DEFENSE:
			return BLUE_TILE_TEXTURE
		ShipPart.Category.SPECIAL:
			return GREEN_TILE_TEXTURE
		_:
			push_error("Unknown tile category in battle renderer: %s" % category)
			return null
