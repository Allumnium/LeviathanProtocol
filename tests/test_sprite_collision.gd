extends SceneTree

const Collision = preload("res://scripts/sprite_collision.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(2, 2, 4, 12), Color.WHITE)
	image.fill_rect(Rect2i(2, 10, 12, 4), Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var shape := Collision.transformed(Collision.outlines(texture), Vector2(16, 16), Vector2(8, 8), 0)
	check(Collision.contains(shape, Vector2(3, 3)), "Opaque pixels are inside the collision polygon")
	check(not Collision.contains(shape, Vector2(11, 3)), "Concave transparent notch remains outside the polygon")
	check(not Collision.contains(shape, Vector2(0, 8)), "Transparent sprite padding never collides")
	check(Collision.segment_contact(shape, Vector2(7, 4), Vector2(15, 4)) == INF,
		"Shots crossing only a concave notch miss")
	check(is_equal_approx(Collision.segment_contact(shape, Vector2(0, 5), Vector2(16, 5)), 0.125),
		"Segment contact is at the opaque surface, not the sprite box")
	var bullet: Array[PackedVector2Array] = [Collision.circle(0.5)]
	check(Collision.sweep(bullet, Vector2(16, 5), shape) < 1, "Swept polygon catches a fast bullet")
	var inside_notch := Collision.transformed(bullet, Vector2.ONE, Vector2(8, 4), 0)
	check(Collision.sweep(inside_notch, Vector2(6, 0), shape) == INF, "Swept bullet respects concave empty space")
	var edge_bullet := Collision.transformed(bullet, Vector2.ONE, Vector2(0, 1.75), 0)
	check(Collision.sweep(edge_bullet, Vector2(16, 0), shape) < INF,
		"Bullet silhouette can graze a surface when its center misses")
	for chassis: Dictionary in SlotCatalog.chassis():
		var ship := HangarShip.new()
		check(ship.initialize_chassis(chassis.id, 1, int(chassis.command) > 0), "Initialize collision chassis " + chassis.id)
		var actor := BattleSimulation.Combatant.new()
		actor.owned_ship = ship
		actor.position = Vector2(37, -21)
		actor.heading = 0.7
		var polygons := Collision.actor_polygons(actor)
		check(not polygons.is_empty(), "Every player chassis has artwork polygons")
		check_art_samples(ship.art_texture, Collision.hangar_rect(ship).size, actor.position, actor.heading + PI / 2, polygons)
		var unchanged := Collision.actor_polygons(actor)
		ship.mounts[chassis.slots[0].id] = {"uid": "fixture", "equipment_id": "research_lab", "rank": 1}
		ship.rebuild_units()
		check(Collision.actor_polygons(actor) == unchanged, "Equipment does not enlarge chassis collision silhouette")
	for alien: AlienShip in AlienShip.get_catalog() + [AlienShip.threat_variant("fighter", 1), AlienShip.threat_variant("fighter", 2),
			AlienShip.threat_variant("chrysalis", 1), AlienShip.threat_variant("chrysalis", 2),
			AlienShip.warden_variant(false, 100, 20, 100), AlienShip.warden_variant(true, 20, 20, 20)]:
		var actor := BattleSimulation.Combatant.new()
		actor.alien = alien
		actor.heading = 2.1
		check_art_samples(alien.texture, Collision.alien_size(alien), actor.position, actor.heading + PI / 2,
			Collision.actor_polygons(actor))
	var region_indices := {}
	for index in range(1024):
		var id := "collision-rock/%d" % index
		var region := Collision.rock_region(id)
		if region_indices.has(region):
			continue
		region_indices[region] = true
		var actor := BattleSimulation.Combatant.new()
		actor.tags["asteroid"] = true
		actor.entity_id = id
		actor.radius = 16
		var polygons := Collision.actor_polygons(actor)
		check(not polygons.is_empty(), "Each asteroid atlas frame has its own polygon")
		var rock_image := Collision.ROCK_TEXTURE.get_image().get_region(region)
		check_art_samples(ImageTexture.create_from_image(rock_image), Vector2(32, 32), Vector2.ZERO, 0, polygons)
	check(region_indices.size() == 64, "Collision coverage exercises all 64 asteroid frames")
	var projectile := BattleSimulation.Projectile.new()
	projectile.is_player = true
	projectile.weapon_name = "Mini Turret"
	projectile.position = Vector2(10, 20)
	var another_projectile := BattleSimulation.Projectile.new()
	check(is_equal_approx(Collision.bullet_angle(projectile, 1.25), Collision.bullet_angle(another_projectile, 1.25)),
		"Bullet collision rotation never depends on engine object allocation")
	check_art_samples(Collision.BULLET_TEXTURE, Collision.BULLET_TEXTURE.get_size() * Collision.BULLET_SCALE,
		projectile.position, Collision.bullet_angle(projectile, 1.25), Collision.bullet_polygons(projectile, 1.25))
	var sim := BattleSimulation.new()
	var stats := ShipStats.new()
	stats.integrity = 100
	stats.weapons.append(ShipWeaponStats.new("Fixture", 1, 10, 1))
	var enemy := AlienShip.new("Fixture", texture, stats)
	check(sim.setup(stats, [enemy], 42), "Initialize real projectile collision fixture")
	var target := sim.aliens[0]
	target.position = Vector2(8, 8)
	target.heading = -PI / 2
	target.integrity = 100
	var shot := BattleSimulation.Projectile.new()
	shot.target = target
	shot.source = sim.player
	shot.position = Vector2(-100, 5)
	shot.origin = shot.position
	shot.damage = 10
	shot.speed = 10000
	sim.projectiles.append(shot)
	sim._update_projectiles(1.0)
	check(target.integrity == 90 and sim.projectiles.is_empty(), "Fast projectile hits a real sprite collider once")
	check(shot.position.x < 2, "Impact is placed at first surface contact rather than the target center")
	var miss := BattleSimulation.Projectile.new()
	miss.target = target
	miss.position = Vector2(11, -20)
	miss.damage = 10
	miss.speed = 1000
	sim.visibility_enabled = true
	miss.guidance_lost = true
	miss.aim_position = Vector2(11, 4)
	sim.projectiles.append(miss)
	sim._update_projectiles(1.0)
	check(target.integrity == 90 and sim.projectiles.is_empty(), "A shot ending in transparent artwork does not deal damage")
	print("SPRITE COLLISION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check_art_samples(texture: Texture2D, size: Vector2, position: Vector2, angle: float, polygons: Array[PackedVector2Array]) -> void:
	var image := SurfaceArt.diffuse(texture).get_image()
	if image.is_compressed():
		image.decompress()
	var opaque := false
	var transparent := false
	for y in range(2, image.get_height() - 2, maxi(1, image.get_height() / 12)):
		for x in range(2, image.get_width() - 2, maxi(1, image.get_width() / 12)):
			var alpha := image.get_pixel(x, y).a
			if alpha > 0.99 and image.get_pixel(x - 2, y).a > 0.99 and image.get_pixel(x + 2, y).a > 0.99 \
					and image.get_pixel(x, y - 2).a > 0.99 and image.get_pixel(x, y + 2).a > 0.99:
				var world := position + ((Vector2(x + 0.5, y + 0.5) / Vector2(image.get_size()) - Vector2(0.5, 0.5)) * size).rotated(angle)
				check(Collision.contains(polygons, world), "Rotated/scaled sprite opaque interior collides")
				opaque = true
			elif alpha == 0 and image.get_pixel(x - 2, y).a == 0 and image.get_pixel(x + 2, y).a == 0 \
					and image.get_pixel(x, y - 2).a == 0 and image.get_pixel(x, y + 2).a == 0 \
					and x < image.get_width() / 4 and y < image.get_height() / 4:
				var world := position + ((Vector2(x + 0.5, y + 0.5) / Vector2(image.get_size()) - Vector2(0.5, 0.5)) * size).rotated(angle)
				check(not Collision.contains(polygons, world), "Rotated/scaled transparent padding misses")
				transparent = true
	check(opaque, "Collision sampling found an opaque sprite interior")
	check(transparent or image.get_width() <= 32, "Collision sampling includes transparent chassis/bullet padding")
