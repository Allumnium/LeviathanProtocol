class_name BattleVisuals
extends Control

const BUILD_CELL_SIZE := Ship.BUILD_CELL_SIZE
const HEX_PALETTE: HexMaterialPalette = preload("res://themes/hex_material_palette.tres")
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

var _part_patterns_by_type: Dictionary[String, ShipPartPattern] = {}
var simulation: BattleSimulation
var camera_position := Vector2.ZERO
var camera_zoom := 0.65
var interpolation_alpha := 1.0
var stars := PackedVector2Array()
var _owned_render_cache: Dictionary = {}
var _visible_world_rect := Rect2()
var _thruster_frames_by_type: Dictionary = {}
var ability_preview: Dictionary = {}


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
		_part_patterns_by_type[pattern.pattern_key()] = pattern
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
	_draw_visibility()
	if simulation.encounter.plan.get("arena_layout", "open") == "corridor":
		for y in [-240, 240]:
			draw_line(Vector2(-800, y), Vector2(800, y), Color(0.35, 0.6, 0.7, 0.45), 2)
	if not simulation.encounter.pending.is_empty():
		# Announced entry zone, independent of any hidden actor's live position.
		for y in [-90, 0, 90]:
			draw_polyline(PackedVector2Array([Vector2(635, y - 12), Vector2(620, y), Vector2(635, y + 12)]), Color(1.0, 0.7, 0.3, 0.65), 2)
	for star in stars:
		if _visible_world_rect.has_point(star):
			draw_circle(star, 1.0, Color(0.3, 0.4, 0.5, 0.65))
	for drop in simulation.drops:
		if not drop.collected and _visible_world_rect.has_point(drop.position) and simulation.point_visible(BattleSimulation.Faction.PLAYER, drop.position):
			var tile_texture := _get_tile_texture(drop.category)
			if tile_texture != null:
				var drop_size := Vector2.ONE * drop.size
				if _uses_hex_materials():
					drop_size.y *= float(HexMaterialPalette.TILE_SIZE.y) / HexMaterialPalette.TILE_SIZE.x
				draw_texture_rect(
					tile_texture,
					Rect2(drop.position - drop_size * 0.5, drop_size),
					false
				)
	for player_ship in simulation.players:
		_draw_player_ship(player_ship)
	_draw_alien_fleet()
	_draw_warden()
	_draw_other_entities()
	_draw_manual_target()
	draw_set_transform_matrix(world_transform())
	for beam in simulation.beams:
		var end := beam.target.position if not simulation.visibility_enabled or simulation.team_can_see(BattleSimulation.Faction.PLAYER, beam.target) else beam.aim_position
		if not _visible_world_rect.has_point(beam.origin_position) and not _visible_world_rect.has_point(end):
			continue
		var steps := maxi(1, ceili(beam.origin_position.distance_to(end) / 24.0))
		for index in range(steps):
			var start := beam.origin_position.lerp(end, float(index) / steps)
			var finish := beam.origin_position.lerp(end, float(index + 1) / steps)
			if simulation.point_visible(BattleSimulation.Faction.PLAYER, (start + finish) * 0.5):
				draw_line(start, finish, Color(1.0, 0.03, 0.06, beam.lifetime / 0.16), 2.0, true)
	for projectile in simulation.projectiles:
		var projectile_position := projectile.previous_position.lerp(projectile.position, interpolation_alpha)
		if not _visible_world_rect.has_point(projectile_position) or not simulation.point_visible(BattleSimulation.Faction.PLAYER, projectile_position):
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
		var aim := projectile.aim_position if simulation.visibility_enabled else projectile.target.position
		var direction := (aim - projectile_position).normalized()
		var trail_color := Color(0.4, 1.0, 0.25, 0.7)
		var projectile_color := Color(0.8, 1.0, 0.3)
		if projectile.is_player:
			trail_color = Color(1.0, 0.03, 0.06, 0.7)
			projectile_color = Color(1.0, 0.12, 0.16)
		draw_line(projectile_position - direction * 12.0, projectile_position,
			trail_color, 2.0, true)
		draw_circle(projectile_position, 2.5, projectile_color)
	for explosion in simulation.explosions:
		if not _visible_world_rect.has_point(explosion.position) or not simulation.point_visible(BattleSimulation.Faction.PLAYER, explosion.position):
			continue
		var progress := 1.0 - explosion.lifetime / 0.6
		draw_arc(explosion.position, 4.0 + progress * 32.0, 0.0, TAU, 24,
			Color(1.0, 0.45, 0.1, 1.0 - progress), 3.0, true)
	if not ability_preview.is_empty():
		var definition := GameDefinitions.find("abilities", ability_preview.id)
		var color := Color("8cd4e8") if ability_preview.valid else Color("ed8975")
		draw_arc(ability_preview.position, float(definition.radius_units), 0, TAU, 48, color, 1.5)
		for source in ability_preview.sources:
			draw_arc(simulation.abilities.origin(source, ability_preview.id), float(definition.range_units), 0, TAU, 64, Color(0.5, 0.7, 0.8, 0.4), 1)
	for charge: Dictionary in simulation.doctrines.charges.values():
		var source = simulation.entities.get(charge.source)
		var target = simulation.entities.get(charge.target)
		if source != null and target != null and simulation.team_can_see(0, source) and simulation.team_can_see(0, target):
			draw_line(charge.origin, charge.aim, Color(0.9, 0.7, 0.35, 0.7), 2.0, true)
	for effect: Dictionary in simulation.abilities.effects:
		if int(effect.faction) == 0:
			draw_arc(effect.position, float(effect.radius), 0, TAU, 48, Color(0.55, 0.85, 0.95, 0.5), 1.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_visibility() -> void:
	if not simulation.visibility_enabled:
		return
	var fog = simulation.visibility
	draw_rect(_visible_world_rect, Color("010305"))
	for cell: Vector2i in fog.explored_cells.get(BattleSimulation.Faction.PLAYER, {}):
		var memory := Rect2(Vector2(cell) * fog.MEMORY_CELL, Vector2.ONE * fog.MEMORY_CELL)
		if memory.intersects(_visible_world_rect):
			draw_rect(memory, Color("081018"))
	for source: Dictionary in fog.sources.get(BattleSimulation.Faction.PLAYER, []):
		draw_circle(source.position, float(source.sight), Color("101c27"))
	for contact: Dictionary in fog.contacts(BattleSimulation.Faction.PLAYER):
		if not _visible_world_rect.has_point(contact.position):
			continue
		if contact.kind == "radar":
			var radius := 4.0 + sin(simulation.elapsed * 4.0) * 1.0
			draw_arc(contact.position, radius, 0, TAU, 16, Color("e9bb70"), 1.5)
		else:
			var color := Color("708595")
			color.a = 1.0 - float(contact.age) / fog.STALE_SECONDS
			draw_line(contact.position - Vector2(4, 4), contact.position + Vector2(4, 4), color, 1.0)
			draw_line(contact.position - Vector2(4, -4), contact.position + Vector2(4, -4), color, 1.0)


func _draw_player_ship(player_ship: BattleSimulation.Combatant) -> void:
	var render_position := player_ship.previous_position.lerp(player_ship.position, interpolation_alpha)
	if not _visible_world_rect.grow(player_ship.radius).has_point(render_position):
		return
	if player_ship.owned_ship != null:
		_draw_voxel_ship(player_ship, render_position)
		return
	var cells := GameState.ship.get_tile_cells()
	if cells.is_empty():
		return

	var ship_center := ShipStats.cell_bounds(cells).get_center() * BUILD_CELL_SIZE
	var ship_scale := ShipStats.BATTLE_CELL_SIZE / BUILD_CELL_SIZE.x
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
			ShipPartPattern.texture_for_part(pattern, part) if part.type == ShipPart.Type.PASSENGER_CABIN else _get_part_texture(pattern, player_ship, false),
			Rect2(visual_center - visual_size * 0.5, visual_size),
			false,
			texture_tint
		)
	if is_shield_flashing:
		_draw_hull_outline(hull_points)
	draw_set_transform_matrix(world_transform())


func _draw_manual_target() -> void:
	for member in simulation.players:
		var target := member.commanded_target
		if target == null or not target.is_alive() or (simulation.visibility_enabled and not simulation.team_can_see(0, target)):
			continue
		var position := target.previous_position.lerp(target.position, interpolation_alpha)
		for quadrant in range(4):
			var angle := quadrant * PI * 0.5 + PI * 0.1
			draw_arc(position, target.radius + 5, angle, angle + PI * 0.3, 8, Color("efd580"), 1.5)
		break


func _draw_other_entities() -> void:
	var rock_texture: Texture2D = preload("res://assets/asteroids_s.png")
	for entity in simulation.other_entities:
		if not entity.is_alive() or (entity.faction != BattleSimulation.Faction.PLAYER and not simulation.team_can_see(BattleSimulation.Faction.PLAYER, entity) and simulation.visibility_enabled):
			continue
		var position := entity.previous_position.lerp(entity.position, interpolation_alpha)
		if not _visible_world_rect.has_point(position):
			continue
		if entity.has_tag("asteroid"):
			var sprite := int(entity.entity_id.hash() & 63)
			var region := Rect2(Vector2(sprite % 8, sprite / 8) * 32, Vector2(32, 32))
			draw_texture_rect_region(rock_texture, Rect2(position - Vector2.ONE * entity.radius, Vector2.ONE * entity.radius * 2), region)
			# Motion is visible only with legitimate sight; no mineral overlays.
			if entity.velocity.length_squared() > 1:
				draw_line(position, position + entity.velocity * 1.5, Color(0.7, 0.75, 0.8, 0.35), 1.0)
			continue
		if entity.has_tag("craft") and entity.alien != null:
			draw_texture_rect(entity.alien.texture, Rect2(position - Vector2.ONE * entity.radius, Vector2.ONE * entity.radius * 2), false)
			continue
		var color := Color("929b9d")
		if entity.faction == BattleSimulation.Faction.ALIEN:
			color = Color("e88974")
		elif entity.faction == BattleSimulation.Faction.PLAYER:
			color = Color("73bddc")
		draw_circle(position, entity.radius, color.darkened(0.55))
		draw_arc(position, entity.radius, 0.0, TAU, 24, color, 1.0)
	for r: Dictionary in simulation.asteroid_field.records.values():
		if r.status != "terminal" or r.claimed or not simulation.asteroid_field.recoverable(r):
			continue
		var point := Vector2(r.position[0], r.position[1])
		if simulation.point_visible(0, point):
			draw_circle(point, 3, Color("dfc26b"))


func _draw_alien_fleet() -> void:
	for alien in simulation.aliens:
		if not alien.is_alive() or (simulation.visibility_enabled and not simulation.team_can_see(BattleSimulation.Faction.PLAYER, alien)):
			continue
		var render_position := alien.previous_position.lerp(alien.position, interpolation_alpha)
		if not _visible_world_rect.has_point(render_position):
			continue
		if simulation.enemy_roles.role(alien) == "sentinel":
			draw_arc(render_position, 140, 0, TAU, 48, Color(0.4, 0.7, 0.85, 0.25), 1)
		var texture_size := alien.alien.texture.get_size()
		var extent := 48.0 if alien.alien.role_id == "warden" else (22.0 if alien.alien.role_id == "pylon" else 16.0)
		var draw_size := texture_size * (extent / maxf(texture_size.x, texture_size.y))
		var render_heading := lerp_angle(alien.previous_heading, alien.heading, interpolation_alpha)
		_set_ship_transform(render_position, render_heading + PI * 0.5)
		var color := SHIELD_FLASH_TINT if alien.shield_flash > 0.0 else Color.WHITE
		draw_texture_rect(alien.alien.texture, Rect2(-draw_size * 0.5, draw_size), false, color)
		if simulation.player != null and simulation._analysis_multiplier(simulation.player, alien) > 1.0:
			draw_arc(Vector2.ZERO, alien.radius + 3, 0, TAU, 24, Color("88ddec"), 1.0)
		if alien.alien.role_id in ["warden", "pylon"]:
			var r := alien.radius + 4
			var cue_color := Color("83c9dc") if alien.alien.role_id == "pylon" else Color("e1af69")
			draw_polyline(PackedVector2Array([Vector2(-r, 0), Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)]), cue_color, 1.5)
	draw_set_transform_matrix(world_transform())
	for alien in simulation.aliens:
		if not alien.is_alive() or alien.alien.role_id not in ["warden", "pylon"] or (simulation.visibility_enabled and not simulation.team_can_see(0, alien)):
			continue
		var r := alien.radius + 4
		var point := alien.previous_position.lerp(alien.position, interpolation_alpha) + Vector2(0, r + 5)
		var color := Color("83c9dc") if alien.alien.role_id == "pylon" else Color("e1af69")
		draw_line(point - Vector2(r, 0), point + Vector2(r, 0), Color("35434d"), 3)
		draw_line(point - Vector2(r, 0), point + Vector2(-r + 2 * r * alien.integrity / alien.stats.integrity, 0), color, 3)
	for link: Dictionary in simulation.enemy_roles.repair_links:
		var source: BattleSimulation.Combatant = simulation.entities.get(link.source)
		var target: BattleSimulation.Combatant = simulation.entities.get(link.target)
		if source != null and target != null and source.is_alive() and target.is_alive() \
			and (not simulation.visibility_enabled or (simulation.team_can_see(0, source) and simulation.team_can_see(0, target))):
			draw_line(source.position, target.position, Color(0.5, 0.85, 0.6, 0.65), 1)


func _draw_warden() -> void:
	var warden = simulation.encounter.warden
	if warden.rules.is_empty():
		return
	var body: BattleSimulation.Combatant = simulation.entities.get(warden.rules.body_id)
	if not warden.visible(simulation):
		return
	draw_set_transform_matrix(world_transform())
	for id in warden.rules.pylon_ids:
		var pylon: BattleSimulation.Combatant = simulation.entities.get(id)
		if pylon != null and pylon.is_alive() and (not simulation.visibility_enabled or simulation.team_can_see(0, pylon)):
			draw_line(body.position, pylon.position, Color(0.4, 0.75, 0.9, 0.5), 1.5)
	if warden.exposed > 0:
		draw_arc(body.position, body.radius + 9, 0, TAU, 32, Color("8ad481"), 2)
	if not warden.charging and warden.flash <= 0:
		return
	var normal := Vector2(-warden.direction.y, warden.direction.x) * float(warden.rules.half_width)
	var end: Vector2 = warden.origin + warden.direction * float(warden.rules.range)
	var points := PackedVector2Array([warden.origin + normal, end + normal, end - normal, warden.origin - normal])
	var color := Color(1, 0.7, 0.3, 0.12 if warden.charging else 0.28)
	draw_colored_polygon(points, color)
	draw_line(points[0], points[1], Color(1, 0.75, 0.35, 0.8), 1.5)
	draw_line(points[2], points[3], Color(1, 0.75, 0.35, 0.8), 1.5)
	if warden.flash > 0:
		draw_line(warden.origin, end, Color(1, 0.85, 0.55, 0.8), 4)


func _get_pattern_for_part(part: ShipPart) -> ShipPartPattern:
	var pattern := ShipPartPattern.for_cells(_part_patterns_by_type.get(part.pattern_key()), part.cell_offsets)
	if pattern == null:
		push_error("Unknown ship part type in battle renderer: %s" % part.type)
	return pattern


func _get_visual_cells_for_part(
	part: ShipPart,
	pattern: ShipPartPattern
) -> Array[Vector2i]:
	var pattern_transform := part.get_transform(pattern)
	if pattern_transform.x >= 0:
		var visual_cells: Array[Vector2i] = []
		for offset in pattern.get_visual_offsets_for_transform(
			pattern_transform.x, pattern_transform.y == 1
		):
			visual_cells.append(part.origin + offset)
		return visual_cells

	push_error("Could not determine the rotation for %s." % pattern.display_name)
	return []


func _uses_hex_materials() -> bool:
	return simulation != null and not simulation.players.is_empty() and simulation.players[0].owned_ship != null and simulation.players[0].owned_ship.is_hex_ship()


func _get_tile_texture(category: int) -> Texture2D:
	if _uses_hex_materials():
		return HEX_PALETTE.material_texture(category)
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
	if owned is HexBattleShip:
		_draw_hex_ship(member, render_position)
		return
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


func _draw_hex_ship(member: BattleSimulation.Combatant, render_position: Vector2) -> void:
	var owned := member.owned_ship as HexBattleShip
	var heading := lerp_angle(member.previous_heading, member.heading, interpolation_alpha)
	var ship_view := world_transform() * Transform2D(heading, render_position)
	draw_set_transform_matrix(ship_view)
	var wreck := not member.is_alive()
	for cell in owned.hull_cells:
		var polygon := owned.cell_polygon(cell)
		draw_colored_polygon(polygon, Color("242e38") if not wreck else Color("202426"))
		var outline := polygon.duplicate()
		outline.append(polygon[0])
		draw_polyline(outline, Color("52616b"), 0.25, true)
		if owned.state.design.tiles.has(cell) and owned.state.component_at(cell) >= 0:
			var tile_size := Vector2(HexMaterialPalette.TILE_SIZE) * HexBattleShip.ART_SCALE
			draw_texture_rect(HEX_PALETTE.material_texture(owned.state.design.tiles[cell]), Rect2(owned.local_cell_position(cell) - tile_size * 0.5, tile_size), false,
				Color.WHITE if not wreck else Color(0.4, 0.44, 0.43, 0.75))
	if member.shield_flash > 0:
		for boundary in HexMaterialPalette.outlines(owned.hull_cells):
			for index in range(boundary.size()):
				boundary[index] = (boundary[index] - owned.center) * HexBattleShip.ART_SCALE
			boundary.append(boundary[0])
			draw_polyline(boundary, SHIELD_OUTLINE_COLOR, 0.6, true)
	# Names stay upright in screen space while their true footprints follow the hull.
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var group_view := ship_view * Transform2D(0.0, Vector2.ONE * HexBattleShip.ART_SCALE, 0.0, -owned.center * HexBattleShip.ART_SCALE)
	for unit in owned.units:
		if unit.hp > 0 and not unit.equipment_id.is_empty():
			HexEquipmentDrawing.draw_group(self, self, unit.cells, group_view, HexEquipmentDrawing.title(unit.equipment_id, unit.rank), 40.0)
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
	var texture := ShipPartPattern.texture_for_part(pattern, unit.part) if pattern.part_type == ShipPart.Type.PASSENGER_CABIN else _get_part_texture(pattern, member, is_wreck)
	draw_texture_rect(texture, part_rects[unit_index], false, part_tint)


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
