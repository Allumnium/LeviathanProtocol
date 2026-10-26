class_name BattleVisuals
extends Control

const BUILD_CELL_SIZE := Ship.BUILD_CELL_SIZE
const HULL_COLOR := Color(0.38, 0.38, 0.4, 1.0)
const HULL_OVERLAY_COLOR := Color(0.38, 0.38, 0.4, 0.7)
const HULL_CUTOUT_COLOR := Color(0.035, 0.045, 0.055, 1.0)
const RED_TILE_TEXTURE: Texture2D = preload("res://assets/ui/icons/red_square.png")
const BLUE_TILE_TEXTURE: Texture2D = preload("res://assets/ui/icons/blue_square.png")
const GREEN_TILE_TEXTURE: Texture2D = preload("res://assets/ui/icons/green_square.png")
const CORE_TILE_TEXTURE: Texture2D = preload("res://assets/core.png")
const MINIGUN_BULLET_TEXTURE: Texture2D = preload("res://assets/bullet.png")
const MINIGUN_BULLET_SCALE := 0.125
const MINIGUN_BULLET_ROTATION_SPEED := TAU * 2.0
const SHIELD_FLASH_TINT := Color(0.35, 0.7, 1.0, 1.0)
const SHIELD_OUTLINE_COLOR := Color(0.45, 0.85, 1.0, 1.0)
const SMALL_THRUSTER_SHEET: Texture2D = preload("res://assets/thruster_s_animated.png")
const LARGE_THRUSTER_SHEET: Texture2D = preload("res://assets/thruster_l_animated.png")
const THRUSTER_START_SECONDS := 0.1
const THRUSTER_LOOP_FPS := 12.0

var _part_patterns_by_type: Dictionary[int, ShipPartPattern] = {}
var simulation: BattleSimulation
var camera_position := Vector2.ZERO
var camera_zoom := 0.65
var interpolation_alpha := 1.0
var stars := PackedVector2Array()
var _owned_render_cache: Dictionary = {}
var _visible_world_rect := Rect2()
var _thruster_frames_by_type: Dictionary = {}


func world_transform() -> Transform2D:
	return Transform2D(0.0, Vector2.ONE * camera_zoom, 0.0,
		size * 0.5 - camera_position * camera_zoom)


func _set_ship_transform(position: Vector2, angle: float, ship_scale: float = 1.0) -> void:
	draw_set_transform_matrix(world_transform() * Transform2D(
		angle, Vector2.ONE * ship_scale, 0.0, position))


func _ready() -> void:
	_thruster_frames_by_type[ShipPart.Type.THRUSTER] = _create_thruster_frames(SMALL_THRUSTER_SHEET)
	_thruster_frames_by_type[ShipPart.Type.LARGE_THRUSTER] = _create_thruster_frames(LARGE_THRUSTER_SHEET)
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
	_visible_world_rect = Rect2(
		camera_position - size / (camera_zoom * 2.0),
		size / camera_zoom
	).grow(80.0)
	draw_set_transform_matrix(world_transform())
	for star in stars:
		if _visible_world_rect.has_point(star):
			draw_circle(star, 1.0, Color(0.3, 0.4, 0.5, 0.65))
	for drop in simulation.drops:
		if not drop.collected and _visible_world_rect.has_point(drop.position):
			var tile_texture := _get_tile_texture(drop.category)
			if tile_texture != null:
				var drop_size := Vector2.ONE * drop.size
				draw_texture_rect(
					tile_texture,
					Rect2(drop.position - drop_size * 0.5, drop_size),
					false
				)
	for player_ship in simulation.players:
		_draw_player_ship(player_ship)
	_draw_alien_fleet()
	_draw_other_entities()
	draw_set_transform_matrix(world_transform())
	for beam in simulation.beams:
		if not _visible_world_rect.has_point(beam.origin_position) and not _visible_world_rect.has_point(beam.target.position):
			continue
		draw_line(beam.origin_position, beam.target.position,
			Color(1.0, 0.03, 0.06, beam.lifetime / 0.16), 2.0, true)
	for projectile in simulation.projectiles:
		var projectile_position := projectile.previous_position.lerp(projectile.position, interpolation_alpha)
		if not _visible_world_rect.has_point(projectile_position):
			continue
		if projectile.is_player and projectile.weapon_name == "Mini Turret":
			var initial_rotation := (
				float(projectile.get_instance_id() % 16) / 16.0 * TAU
			)
			var bullet_rotation := (
				simulation.elapsed * MINIGUN_BULLET_ROTATION_SPEED + initial_rotation
			)
			draw_set_transform_matrix(
				world_transform()
				* Transform2D(bullet_rotation, Vector2.ONE, 0.0, projectile_position)
			)
			var bullet_size := MINIGUN_BULLET_TEXTURE.get_size() * MINIGUN_BULLET_SCALE
			draw_texture_rect(
				MINIGUN_BULLET_TEXTURE,
				Rect2(-bullet_size * 0.5, bullet_size),
				false
			)
			draw_set_transform_matrix(world_transform())
			continue
		var direction := (projectile.target.position - projectile_position).normalized()
		var trail_color := Color(0.4, 1.0, 0.25, 0.7)
		var projectile_color := Color(0.8, 1.0, 0.3)
		if projectile.is_player:
			trail_color = Color(1.0, 0.03, 0.06, 0.7)
			projectile_color = Color(1.0, 0.12, 0.16)
		draw_line(projectile_position - direction * 12.0, projectile_position,
			trail_color, 2.0, true)
		draw_circle(projectile_position, 2.5, projectile_color)
	for explosion in simulation.explosions:
		if not _visible_world_rect.has_point(explosion.position):
			continue
		var progress := 1.0 - explosion.lifetime / 0.6
		draw_arc(explosion.position, 4.0 + progress * 32.0, 0.0, TAU, 24,
			Color(1.0, 0.45, 0.1, 1.0 - progress), 3.0, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_player_ship(player_ship: BattleSimulation.Combatant) -> void:
	var render_position := player_ship.previous_position.lerp(player_ship.position, interpolation_alpha)
	if not _visible_world_rect.has_point(render_position):
		return
	if player_ship.owned_ship != null:
		_draw_voxel_ship(player_ship, render_position)
		return
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
	var ship_scale := Ship.BATTLE_MODEL_SIZE / maxf(ship_size.x, ship_size.y)
	var is_shield_flashing := player_ship.shield_flash > 0.0
	var texture_tint := Color.WHITE
	var render_heading := lerp_angle(player_ship.previous_heading, player_ship.heading, interpolation_alpha)
	_set_ship_transform(render_position, render_heading, ship_scale)
	var hull_points := Ship.create_hull_polygon(cells)
	for index in range(hull_points.size()):
		hull_points[index] = hull_points[index] * BUILD_CELL_SIZE - ship_center
	draw_colored_polygon(
		hull_points,
		HULL_COLOR
	)

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
		draw_texture(tile_texture, cell_center - tile_texture.get_size() * 0.5, texture_tint)

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
			_get_part_texture(pattern, player_ship, false),
			Rect2(visual_center - visual_size * 0.5, visual_size),
			false,
			texture_tint
		)
	if is_shield_flashing:
		_draw_hull_outline(hull_points)
	draw_set_transform_matrix(world_transform())


func _draw_other_entities() -> void:
	for entity in simulation.other_entities:
		if not entity.is_alive():
			continue
		var position := entity.previous_position.lerp(entity.position, interpolation_alpha)
		if not _visible_world_rect.has_point(position):
			continue
		var color := Color("929b9d")
		if entity.faction == BattleSimulation.Faction.ALIEN:
			color = Color("e88974")
		elif entity.faction == BattleSimulation.Faction.PLAYER:
			color = Color("73bddc")
		draw_circle(position, entity.radius, color.darkened(0.55))
		draw_arc(position, entity.radius, 0.0, TAU, 24, color, 1.0)


func _draw_alien_fleet() -> void:
	for alien in simulation.aliens:
		if not alien.is_alive():
			continue
		var render_position := alien.previous_position.lerp(alien.position, interpolation_alpha)
		if not _visible_world_rect.has_point(render_position):
			continue
		var texture_size := alien.alien.texture.get_size()
		var draw_size := texture_size * (16.0 / maxf(texture_size.x, texture_size.y))
		var render_heading := lerp_angle(alien.previous_heading, alien.heading, interpolation_alpha)
		_set_ship_transform(render_position, render_heading + PI * 0.5)
		var color := SHIELD_FLASH_TINT if alien.shield_flash > 0.0 else Color.WHITE
		draw_texture_rect(alien.alien.texture, Rect2(-draw_size * 0.5, draw_size), false, color)
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
	var pattern_transform := pattern.get_transform_for_offsets(part.cell_offsets)
	if pattern_transform.x >= 0:
		var visual_cells: Array[Vector2i] = []
		for offset in pattern.get_visual_offsets_for_transform(
			pattern_transform.x, pattern_transform.y == 1
		):
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
		ShipPart.Category.CORE:
			return CORE_TILE_TEXTURE
		_:
			push_error("Unknown tile category in battle renderer: %s" % category)
			return null


func _draw_voxel_ship(member: BattleSimulation.Combatant, render_position: Vector2) -> void:
	var owned := member.owned_ship
	var render_cache := _get_owned_render_cache(owned)
	var is_wreck := not member.is_alive()
	var wreck_tint := Color(0.4, 0.44, 0.43, 0.75)
	var is_shield_flashing := member.shield_flash > 0.0
	var ship_tint := wreck_tint if is_wreck else Color.WHITE
	var render_heading := lerp_angle(member.previous_heading, member.heading, interpolation_alpha)
	_set_ship_transform(render_position, render_heading)
	var hidden: Dictionary = render_cache.hidden
	var part_rects: Dictionary = render_cache.part_rects
	var hull: PackedVector2Array = render_cache.hull
	var base_hull_color := wreck_tint if is_wreck else HULL_COLOR
	draw_colored_polygon(hull, base_hull_color)
	for unit_index in range(owned.units.size()):
		var unit: Dictionary = owned.units[unit_index]
		if unit.hp <= 0.0:
			continue
		for cell in unit.cells:
			var rect := Rect2(owned.local_cell_position(cell) - Vector2.ONE * owned.cell_size * 0.5, Vector2.ONE * owned.cell_size)
			if hidden.has(cell):
				draw_rect(rect, HULL_CUTOUT_COLOR)
				draw_rect(rect, Color(0.35, 0.4, 0.38, 0.75) if is_wreck else Color(1.0, 0.15, 0.15), false, 0.3)
				continue
			draw_rect(rect, Color(0.15, 0.55, 1.0) if is_shield_flashing else (wreck_tint if is_wreck else HULL_COLOR))
			draw_texture_rect(_get_tile_texture(owned.design.tiles[cell]), rect.grow(-0.2), false, ship_tint)
		_draw_cached_part(member, unit_index, unit, part_rects, ship_tint, is_shield_flashing, is_wreck, false)
	draw_colored_polygon(hull, HULL_OVERLAY_COLOR if not is_wreck else Color(0.38, 0.38, 0.4, 0.35))
	for unit_index in range(owned.units.size()):
		_draw_cached_part(member, unit_index, owned.units[unit_index], part_rects, ship_tint, is_shield_flashing, is_wreck, true)
	if is_shield_flashing:
		_draw_hull_outline(hull)
	draw_set_transform_matrix(world_transform())


func _draw_hull_outline(hull: PackedVector2Array) -> void:
	if hull.size() < 3:
		return
	var outline := hull.duplicate()
	outline.append(hull[0])
	draw_polyline(outline, SHIELD_OUTLINE_COLOR, 2.0, true)


func _draw_cached_part(
	member: BattleSimulation.Combatant,
	unit_index: int,
	unit: Dictionary,
	part_rects: Dictionary,
	ship_tint: Color,
	is_shield_flashing: bool,
	is_wreck: bool,
	renders_on_top: bool
) -> void:
	if unit.hp <= 0.0 or unit.part == null or not part_rects.has(unit_index):
		return
	var pattern := _get_pattern_for_part(unit.part)
	if pattern == null or pattern.renders_on_top != renders_on_top:
		return
	var part_tint := ship_tint if is_shield_flashing or is_wreck else (Color.WHITE if unit.hp == unit.max_hp else Color(1.0, 0.7, 0.5))
	draw_texture_rect(_get_part_texture(pattern, member, is_wreck), part_rects[unit_index], false, part_tint)


func _create_thruster_frames(sheet: Texture2D) -> Array[AtlasTexture]:
	var frames: Array[AtlasTexture] = []
	var frame_size := Vector2(
		float(sheet.get_width()) / 3.0,
		float(sheet.get_height()) / 3.0
	)
	for frame_index in range(9):
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(
			Vector2(frame_index % 3, frame_index / 3) * frame_size,
			frame_size
		)
		frames.append(frame)
	return frames


func _get_part_texture(
	pattern: ShipPartPattern,
	member: BattleSimulation.Combatant,
	is_wreck: bool
) -> Texture2D:
	var frames: Array = _thruster_frames_by_type.get(pattern.part_type, [])
	if frames.is_empty():
		return pattern.preview_texture
	if is_wreck or member == null or member.target == null or not member.is_alive():
		return frames[0]
	if member.thruster_activation_elapsed <= THRUSTER_START_SECONDS:
		return frames[1]
	var loop_frame := int(floor(
		(member.thruster_activation_elapsed - THRUSTER_START_SECONDS)
			* THRUSTER_LOOP_FPS
	)) % 7
	return frames[2 + loop_frame]


func _get_owned_render_cache(owned: FleetShip) -> Dictionary:
	var cached: Dictionary = _owned_render_cache.get(owned, {})
	if not cached.is_empty() and cached.revision == owned.visual_revision:
		return cached
	var hidden: Dictionary = {}
	var part_rects: Dictionary = {}
	var hull_cells: Array[Vector2i] = []
	for unit_index in range(owned.units.size()):
		var unit: Dictionary = owned.units[unit_index]
		if unit.hp <= 0.0:
			continue
		for cell in unit.cells:
			hull_cells.append(cell)
		if unit.part == null:
			continue
		for cell in unit.part.get_hidden_tile_cells():
			hidden[cell] = true
		var part: ShipPart = unit.part
		var pattern := _get_pattern_for_part(part)
		var cells := _get_visual_cells_for_part(part, pattern)
		if cells.is_empty():
			continue
		var half_cell := Vector2.ONE * owned.cell_size * 0.5
		var rect := Rect2(owned.local_cell_position(cells[0]) - half_cell, Vector2.ONE * owned.cell_size)
		for cell in cells:
			rect = rect.expand(owned.local_cell_position(cell) - half_cell)
			rect = rect.expand(owned.local_cell_position(cell) + half_cell)
		part_rects[unit_index] = rect
	var hull := Ship.create_hull_polygon(hull_cells)
	for index in range(hull.size()):
		hull[index] = (hull[index] - owned.center) * owned.cell_size
	cached = {
		"revision": owned.visual_revision,
		"hidden": hidden,
		"part_rects": part_rects,
		"hull": hull
	}
	_owned_render_cache[owned] = cached
	return cached
