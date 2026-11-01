extends RefCounted

const BULLET_TEXTURE: Texture2D = preload("res://assets/bullet.png")
const BULLET_SCALE := 0.125
const BULLET_ROTATION_SPEED := TAU * 2.0
const ROCK_TEXTURE: Texture2D = preload("res://assets/environment/asteroids_small_d.png")
static var _outlines: Dictionary = {}

static func outlines(texture: Texture2D, region := Rect2i()) -> Array[PackedVector2Array]:
	var key := "%d/%s" % [texture.get_instance_id(), region]
	if _outlines.has(key):
		return _outlines[key]
	var image := SurfaceArt.diffuse(texture).get_image()
	if image.is_compressed():
		image.decompress()
	if region.has_area():
		image = image.get_region(region)
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image, 0.1)
	var polygons: Array[PackedVector2Array] = bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, image.get_size()), 0.25)
	if polygons.is_empty():
		push_error("Collision artwork has no opaque silhouette: %s / %s" % [texture.resource_path, region])
	for polygon_index in range(polygons.size()):
		var polygon := polygons[polygon_index]
		for index in range(polygon.size()):
			polygon[index] = polygon[index] / Vector2(image.get_size()) - Vector2(0.5, 0.5)
		polygons[polygon_index] = polygon
	_outlines[key] = polygons
	return polygons

static func rock_region(id: String) -> Rect2i:
	var sprite := int(id.hash() & 63)
	return Rect2i(Vector2i(sprite % 8, sprite / 8) * 32, Vector2i(32, 32))

static func hangar_rect(owned: HangarShip) -> Rect2:
	var extent := Vector2.ONE * 512 * HangarShip.ART_SCALE * owned.fleet_view_scale()
	return Rect2(-extent * 0.5, extent)

static func alien_size(alien: AlienShip) -> Vector2:
	var size := alien.texture.get_size()
	var extent := 48.0 if alien.role_id == "warden" else (22.0 if alien.role_id == "pylon" else 16.0)
	return size * (extent * alien.art_scale() / maxf(size.x, size.y))

static func circle(radius: float) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for index in range(16):
		polygon.append(Vector2.from_angle(TAU * index / 16.0) * radius)
	return polygon

static func transformed(polygons: Array[PackedVector2Array], size: Vector2, position: Vector2, angle: float) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for polygon in polygons:
		var world := PackedVector2Array()
		for point in polygon:
			world.append(position + (point * size).rotated(angle))
		result.append(world)
	return result

static func actor_polygons(actor) -> Array[PackedVector2Array]:
	if actor.owned_ship is HangarShip:
		return transformed(outlines(actor.owned_ship.art_texture), hangar_rect(actor.owned_ship).size,
			actor.position, actor.heading + PI / 2)
	if actor.has_tag("asteroid"):
		return transformed(outlines(ROCK_TEXTURE, rock_region(actor.entity_id)), Vector2.ONE * actor.radius * 2, actor.position, 0)
	if actor.alien != null:
		var craft: bool = actor.has_tag("craft")
		return transformed(outlines(actor.alien.texture), Vector2.ONE * actor.radius * 2 if craft else alien_size(actor.alien),
			actor.position, 0 if craft else actor.heading + PI / 2)
	if actor.has_tag("interceptor") or actor.has_tag("bomber"):
		var shape := PackedVector2Array([Vector2(1.5, 0), Vector2(-1, -0.8), Vector2(-0.5, 0), Vector2(-1, 0.8)])
		return transformed([shape], Vector2.ONE * actor.radius, actor.position, actor.heading)
	# Synthetic regression combatants have no artwork.
	return transformed([circle(actor.radius)], Vector2.ONE, actor.position, 0)

static func bullet_angle(projectile, elapsed: float) -> float:
	return elapsed * BULLET_ROTATION_SPEED + projectile.rotation_phase

static func bullet_polygons(projectile, elapsed: float) -> Array[PackedVector2Array]:
	if projectile.is_player and projectile.weapon_name == "Mini Turret":
		return transformed(outlines(BULLET_TEXTURE), BULLET_TEXTURE.get_size() * BULLET_SCALE,
			projectile.position, bullet_angle(projectile, elapsed))
	return transformed([circle(2.5)], Vector2.ONE, projectile.position, 0)

static func bounds(polygons: Array[PackedVector2Array]) -> Rect2:
	var result := Rect2(polygons[0][0], Vector2.ZERO)
	for polygon in polygons:
		for point in polygon:
			result = result.expand(point)
	return result

static func contains(polygons: Array[PackedVector2Array], point: Vector2) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false

static func overlaps(first: Array[PackedVector2Array], second: Array[PackedVector2Array]) -> bool:
	if first.is_empty() or second.is_empty() or not bounds(first).intersects(bounds(second), true):
		return false
	for a in first:
		for b in second:
			if not Geometry2D.intersect_polygons(a, b).is_empty():
				return true
	return false

# Earliest contact for a translated polygon: either a moving vertex crosses a
# stationary edge, or a stationary vertex crosses a moving edge.
static func sweep(first: Array[PackedVector2Array], motion: Vector2, second: Array[PackedVector2Array]) -> float:
	if first.is_empty() or second.is_empty():
		return INF
	var box := bounds(first)
	if not box.merge(Rect2(box.position + motion, box.size)).intersects(bounds(second), true):
		return INF
	if overlaps(first, second):
		return 0.0
	if motion.is_zero_approx():
		return INF
	var contact := INF
	var length_squared := motion.length_squared()
	for a in first:
		for b in second:
			for i in range(a.size()):
				for j in range(b.size()):
					var hit: Variant = Geometry2D.segment_intersects_segment(a[i], a[i] + motion, b[j], b[(j + 1) % b.size()])
					if hit != null:
						contact = minf(contact, (hit - a[i]).dot(motion) / length_squared)
					hit = Geometry2D.segment_intersects_segment(b[j], b[j] - motion, a[i], a[(i + 1) % a.size()])
					if hit != null:
						contact = minf(contact, (b[j] - hit).dot(motion) / length_squared)
	return contact

static func segment_contact(polygons: Array[PackedVector2Array], start: Vector2, finish: Vector2) -> float:
	if contains(polygons, start):
		return 0.0
	var motion := finish - start
	if motion.is_zero_approx():
		return INF
	var contact := INF
	for polygon in polygons:
		for index in range(polygon.size()):
			var hit: Variant = Geometry2D.segment_intersects_segment(start, finish, polygon[index], polygon[(index + 1) % polygon.size()])
			if hit != null:
				contact = minf(contact, (hit - start).dot(motion) / motion.length_squared())
	return contact
