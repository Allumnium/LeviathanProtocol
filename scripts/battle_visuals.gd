class_name BattleVisuals
extends Control

const BUILD_CELL_SIZE := Vector2(26.0, 26.0)
const ALIEN_COUNT_COLUMNS := 4
const ALIEN_CELL_GAP := 8.0
const ALIEN_MAX_SIZE := 64.0
const PLAYER_MAX_SCALE := 4.0
const HULL_COLOR := Color(0.38, 0.38, 0.4, 1.0)
const HULL_CUTOUT_COLOR := Color(0.035, 0.045, 0.055, 1.0)
const DIVIDER_COLOR := Color(0.2, 0.32, 0.38, 0.7)
const RED_TILE_TEXTURE: Texture2D = preload("res://assets/ui/icons/red_square.png")
const BLUE_TILE_TEXTURE: Texture2D = preload("res://assets/ui/icons/blue_square.png")
const GREEN_TILE_TEXTURE: Texture2D = preload("res://assets/ui/icons/green_square.png")
const AlienShipType = preload("res://scripts/alien_ship.gd")

var _part_patterns_by_type: Dictionary[int, ShipPartPattern] = {}


func _ready() -> void:
	for pattern in ShipPartPattern.get_catalog():
		_part_patterns_by_type[pattern.part_type] = pattern
	resized.connect(_on_resized)
	queue_redraw()


func _on_resized() -> void:
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var divider_x := size.x * 0.5
	draw_line(
		Vector2(divider_x, 16.0),
		Vector2(divider_x, size.y - 16.0),
		DIVIDER_COLOR,
		1.0
	)
	_draw_player_ship()
	_draw_alien_fleet()


func _draw_player_ship() -> void:
	var cells := GameState.ship.get_tile_cells()
	var player_area := Rect2(
		Vector2(12.0, 16.0),
		Vector2(size.x * 0.5 - 28.0, size.y - 32.0)
	)
	if cells.is_empty():
		_draw_centered_message(player_area, "NO SHIP BUILT")
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
	var rotated_size := Vector2(ship_size.y, ship_size.x)
	var available_size := player_area.size * 0.92
	var ship_scale := minf(
		available_size.x / rotated_size.x,
		available_size.y / rotated_size.y
	)
	ship_scale = minf(ship_scale, PLAYER_MAX_SCALE)
	if ship_scale <= 0.0:
		push_error("The player ship cannot be scaled into the battle viewport.")
		return

	draw_set_transform(player_area.get_center(), PI * 0.5, Vector2.ONE * ship_scale)
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
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_alien_fleet() -> void:
	var fleet: Array[RefCounted] = GameState.battle_aliens
	if fleet.is_empty():
		push_error("The battle viewport has no alien fleet to render.")
		return

	var columns := mini(ALIEN_COUNT_COLUMNS, fleet.size())
	var rows := ceili(float(fleet.size()) / float(columns))
	var alien_area := Rect2(
		Vector2(size.x * 0.5 + 16.0, 16.0),
		Vector2(size.x * 0.5 - 28.0, size.y - 32.0)
	)
	var max_cell_width := (
		alien_area.size.x - float(columns - 1) * ALIEN_CELL_GAP
	) / float(columns)
	var max_cell_height := (
		alien_area.size.y - float(rows - 1) * ALIEN_CELL_GAP
	) / float(rows)
	var cell_size := minf(ALIEN_MAX_SIZE, minf(max_cell_width, max_cell_height))
	if cell_size <= 0.0:
		push_error("The alien fleet cannot be fitted into the battle viewport.")
		return

	var total_width := float(columns) * cell_size + float(columns - 1) * ALIEN_CELL_GAP
	var total_height := float(rows) * cell_size + float(rows - 1) * ALIEN_CELL_GAP
	var first_cell_center := Vector2(
		alien_area.get_center().x - total_width * 0.5 + cell_size * 0.5,
		alien_area.get_center().y - total_height * 0.5 + cell_size * 0.5
	)
	for index in range(fleet.size()):
		var alien := fleet[index] as AlienShipType
		if alien == null:
			push_error("The battle fleet contains an invalid alien ship.")
			continue
		if alien.texture == null:
			push_error("The %s alien has no battle texture." % alien.display_name)
			continue

		var column := index % columns
		var row := floori(float(index) / float(columns))
		var cell_center := first_cell_center + Vector2(
			float(column) * (cell_size + ALIEN_CELL_GAP),
			float(row) * (cell_size + ALIEN_CELL_GAP)
		)
		var texture_size := alien.texture.get_size()
		var texture_scale := cell_size / maxf(texture_size.x, texture_size.y)
		var draw_size := texture_size * texture_scale
		draw_set_transform(cell_center, -PI * 0.5, Vector2.ONE)
		draw_texture_rect(alien.texture, Rect2(-draw_size * 0.5, draw_size), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_centered_message(area: Rect2, message: String) -> void:
	var font := get_theme_default_font()
	if font == null:
		push_error("No default font is available for the battle viewport.")
		return
	var font_size := 14
	var baseline := area.get_center().y + font.get_height(font_size) * 0.5
	draw_string(
		font,
		Vector2(area.position.x, baseline),
		message,
		HORIZONTAL_ALIGNMENT_CENTER,
		area.size.x,
		font_size,
		Color(0.75, 0.78, 0.82, 1.0)
	)


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
