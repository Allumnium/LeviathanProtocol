extends SceneTree

class LightSimulation extends BattleSimulation:
	func point_visible(_faction: int, point: Vector2) -> bool:
		return point.x >= 0

class SurfaceCanvas extends Node2D:
	var art: Texture2D
	var atlas := false
	var art_rotation := 0.0
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, art_rotation)
		if atlas:
			draw_texture_rect_region(art, Rect2(-64, -64, 128, 128), Rect2(32, 32, 32, 32))
		else:
			draw_texture_rect(art, Rect2(-128, -128, 256, 256), false)

var checks := 0
var failures := 0
# Native captures of unchanged mapped art vary by up to two 8-bit color levels.
const SNAPSHOT_NOISE := 2.0 / 255.0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var paths: Array[String] = []
	var fleet_view: Control = load("res://scripts/hangar_formation.gd").new()
	fleet_view.size = Vector2(640, 360)
	fleet_view.zoom = 1.2
	var battle_view: Control = load("res://scripts/battle_visuals.gd").new()
	var simulation := BattleSimulation.new()
	for chassis: Dictionary in SlotCatalog.chassis():
		paths.append(chassis.art)
		var ship := HangarShip.new()
		check(ship.initialize_chassis(chassis.id, 1), "Mapped chassis initializes: " + chassis.id)
		check(ship.art_texture is CanvasTexture, "Chassis uses surface maps: " + chassis.id)
		var stats := ship.get_stats()
		var fleet_rect: Rect2 = fleet_view.ship_rect(ship)
		var battle_rect: Rect2 = battle_view.hangar_ship_rect(ship)
		check(fleet_rect.size.is_equal_approx(Vector2.ONE * 52 * 1.2 * 0.25)
			and battle_rect.size.is_equal_approx(Vector2.ONE * 512 * HangarShip.ART_SCALE * 0.25),
			"Non-flagship is quarter width/height in Fleet and battle: " + chassis.id)
		check(fleet_rect.get_center().is_equal_approx(fleet_view.point(ship))
			and battle_rect.get_center().is_zero_approx(), "Scaled art remains centered: " + chassis.id)
		var actor := BattleSimulation.Combatant.new()
		actor.owned_ship = ship
		actor.position = Vector2(100, 50)
		actor.heading = PI / 2
		var weapon := ShipWeaponStats.new("Scale fixture", 1.0, 1.0, 1)
		weapon.mount_offset = Vector2(12, 8)
		check(simulation._get_weapon_origin(actor, weapon).is_equal_approx(
			actor.position + (weapon.mount_offset * 0.25).rotated(actor.heading)),
			"Escort weapon launches follow scaled mounts: " + chassis.id)
		ship.flagship = true
		check(fleet_view.ship_rect(ship).size.is_equal_approx(fleet_rect.size * 4)
			and battle_view.hangar_ship_rect(ship).size.is_equal_approx(battle_rect.size * 4),
			"Flagship retains full Fleet and battle size: " + chassis.id)
		check(is_equal_approx(ship.get_stats().collision_radius, stats.collision_radius)
			and ship.get_stats().footprint_size == stats.footprint_size,
			"View scale does not change combat geometry: " + chassis.id)
	fleet_view.free()
	battle_view.free()
	for id in ["cargo_hold", "mini_turret", "hull_plate", "armor_block", "research_lab"]:
		var item := SlotCatalog.find_equipment(id)
		check(not item.is_empty(), "Equipment fixture exists: " + id)
		if not item.is_empty():
			paths.append(item.art)
			if id in ["hull_plate", "armor_block"]:
				var expected_path := "res://assets/equipment/plate_%s_d.png" % ("small" if id == "hull_plate" else "medium")
				var plate := SlotCatalog.equipment_texture(item)
				check(plate is CanvasTexture and SurfaceArt.diffuse(plate).resource_path == expected_path,
					"Plate catalog uses supplied mapped art: " + id)
				check(plate == SlotCatalog.equipment_texture(item), "Plate texture is cached outside drawing: " + id)
				var mount_bounds := Rect2(10, 20, 31, 23)
				var fitted := SlotCatalog.fitted_art_rect(plate, mount_bounds)
				check(mount_bounds.encloses(fitted) and fitted.get_center().is_equal_approx(mount_bounds.get_center())
					and is_equal_approx(fitted.size.aspect(), plate.get_size().aspect()), "Plate fits the mount without distortion: " + id)
			if id == "research_lab":
				var lab := SlotCatalog.equipment_texture(item)
				check(lab is CanvasTexture and SurfaceArt.diffuse(lab).resource_path == "res://assets/equipment/research_lab_1_d.png",
					"Research Lab I uses supplied mapped art")
				check(lab == SlotCatalog.equipment_texture(item), "Research lab texture is cached outside drawing")
				var bounds := Rect2(10, 20, 28, 56)
				var original := SlotCatalog.fitted_art_rect(lab, bounds)
				var fitted := SlotCatalog.fitted_art_rect(lab, bounds, item.art_mount)
				check(fitted.size.is_equal_approx(original.size * 2) and fitted.get_center().is_equal_approx(bounds.get_center())
					and is_equal_approx(fitted.size.aspect(), lab.get_size().aspect()), "Research lab renders at exactly twice its previous scale without shifting its anchor")
				var ship := HangarShip.new()
				check(ship.initialize_chassis("flagship_basic", 1), "Research lab art fixture initializes")
				ship.mounts.spine = {"uid": "lab-art", "equipment_id": id, "rank": 1}
				ship.rebuild_units()
				check(ship.equipment_art.spine == lab, "Fitted lab shares catalog art with stock, drag and fleet rendering")
				check(ship.equipment_art_mounts.spine == item.art_mount, "Fitted and dragged lab share the enlarged mount anchor")
				var central: Dictionary = ship.chassis.slots.filter(func(slot: Dictionary) -> bool: return slot.id == "spine")[0]
				check(Rect2(central.rect[0], central.rect[1], central.rect[2], central.rect[3]) == Rect2(242, 296, 28, 56),
					"Flagship medium mount aligns with the lower central artwork bay")
				check(not SlotCatalog.find_equipment(id, 2).has("art") and not SlotCatalog.find_equipment(id, 3).has("art"),
					"Higher-rank labs retain text fallback until their artwork is supplied")
	paths.append("res://assets/environment/asteroids_small_d.png")
	for role: String in AlienShip.ROLE_COSTS:
		for rank in range(3):
			var alien := AlienShip.threat_variant(role, rank)
			var restored := AlienShip.from_snapshot(alien.to_snapshot())
			check(restored != null and restored.texture == alien.texture, "Alien art survives saved encounter reload: %s/%d" % [role, rank])
			check(restored != null and restored.to_snapshot() == alien.to_snapshot(), "Alien art does not alter encounter snapshot: %s/%d" % [role, rank])
			if role == "fighter" and rank == 0:
				check(not alien.texture is CanvasTexture, "Original Fighter remains unmapped")
				continue
			check(alien.texture is CanvasTexture, "Alien uses surface maps: %s/%d" % [role, rank])
			var path := SurfaceArt.diffuse(alien.texture).resource_path
			if not paths.has(path):
				paths.append(path)
			var large := rank > 0 and role in ["fighter", "chrysalis"]
			check(is_equal_approx(alien.art_scale(), 1.5 if large else 1.0), "Higher-tier alien visual size: %s/%d" % [role, rank])
			if large:
				check(path == AlienShip.LARGE_ART[role], "Higher-tier alien selects supplied large art")
	check(AlienShip.warden_variant(false, 10, 0, 1).texture is CanvasTexture, "Warden uses mapped Sentinel art")
	check(not AlienShip.warden_variant(true, 10, 0, 1).texture is CanvasTexture, "Pylon retains unmapped original art")
	var report: Control = load("res://scripts/battle_report.gd").new()
	var preview: Control = report._create_summary_preview({"is_alien": true, "alien": AlienShip.threat_variant("fighter", 1)})
	var report_art := preview.get_child(0) as TextureRect
	check(report_art.texture == SurfaceArt.texture(AlienShip.LARGE_ART.fighter) and report_art.material.shader == SurfaceArt.SHADER, "Battle report uses lit large-variant art")
	preview.free()
	report.free()
	for path in paths:
		var surface := SurfaceArt.texture(path) as CanvasTexture
		check(surface != null, "Map set loads: " + path)
		if surface == null:
			continue
		check(SurfaceArt.texture(path) == surface, "Map set is cached: " + path)
		check(surface.diffuse_texture.resource_path == path, "Original diffuse preserved")
		check(surface.normal_texture.get_size() == surface.get_size(), "Normal/height dimensions match")
		var stem := path.trim_suffix("_d.png")
		var height := (load(stem + "_p.png") as Texture2D).get_image()
		var occlusion := (load(stem + "_o.png") as Texture2D).get_image()
		var normal := surface.normal_texture.get_image()
		var specular := surface.specular_texture.get_image()
		var point := Vector2i(surface.get_size() / 2)
		check(is_equal_approx(normal.get_pixelv(point).a, height.get_pixelv(point).r), "Height retained in normal alpha")
		check(is_equal_approx(specular.get_pixelv(point).a, occlusion.get_pixelv(point).r), "Occlusion retained in specular alpha")
	var fallback := SurfaceArt.texture("res://assets/shieldGenerator_s.png")
	check(not fallback is CanvasTexture, "Unmapped art retains original texture")
	projectile_light_checks()
	projectile_impact_checks()
	var shield_visual: Control = load("res://scripts/battle_visuals.gd").new()
	var shield_art := SurfaceArt.texture("res://assets/chassis/flagship_basic_d.png")
	var mask: Texture2D = shield_visual._shield_mask(shield_art)
	check(mask == shield_visual._shield_mask(shield_art), "Shield silhouettes are cached per artwork texture")
	var original := shield_art.get_image()
	var masked := mask.get_image()
	for point in [Vector2i(0, 0), Vector2i(256, 256)]:
		check(is_equal_approx(original.get_pixelv(point).a, masked.get_pixelv(point).a)
			and masked.get_pixelv(point).r == 1, "Shield silhouette preserves source transparency without dark artwork colors")
	shield_visual.free()
	if DisplayServer.get_name() != "headless":
		await native_checks()
		await bullet_glow_checks()
	print("Surface art checks: %d; failures: %d" % [checks, failures])
	call_deferred("quit", 1 if failures else 0)

func rendered(view: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

func bullet_glow_checks() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(128, 128)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var visual: Control = load("res://scripts/battle_visuals.gd").new()
	visual.size = Vector2(128, 128)
	visual.camera_zoom = 1.0
	view.add_child(visual)
	visual.stars.clear()
	visual.set_process(false)
	visual._surface_material.set_shader_parameter("projectile_light_count", 0)
	var sim := LightSimulation.new()
	sim.visibility_enabled = true
	visual.simulation = sim
	visual.queue_redraw()
	var background := await rendered(view)
	var shot := BattleSimulation.Projectile.new()
	shot.position = Vector2(16, 0)
	shot.previous_position = shot.position
	shot.aim_position = Vector2(80, 0)
	shot.is_player = true
	shot.weapon_name = "Mini Turret"
	sim.projectiles.append(shot)
	for mini in [true, false]:
		shot.weapon_name = "Mini Turret" if mini else "Test"
		for player in [true, false]:
			shot.is_player = player
			visual.queue_redraw()
			await rendered(view)
			var image := await rendered(view)
			var halo := image.get_pixel(85, 64)
			check(halo.a > 0.2 and (halo.r > halo.g if player else halo.g > halo.r),
				"Every projectile has an intense faction-colored halo beyond its core")
			if not mini:
				check(image.get_pixel(89, 64).is_equal_approx(background.get_pixel(89, 64)), "Bullet halo stops outside its small seven-unit radius")
	shot.position = Vector2(-16, 0)
	shot.previous_position = shot.position
	visual.queue_redraw()
	var hidden := await rendered(view)
	check(hidden.get_pixel(48, 64) == background.get_pixel(48, 64), "Hidden bullet reveals neither core nor glow")
	sim.projectiles.clear()
	visual.add_projectile_impact(Vector2(16, 0))
	sim.elapsed = 0.06
	visual.queue_redraw()
	await rendered(view)
	var burst := await rendered(view)
	var warm := 0
	var white := 0
	for y in range(55, 74):
		for x in range(70, 90):
			var pixel := burst.get_pixel(x, y)
			if pixel.r > 0.3 and pixel.r > pixel.g * 1.2:
				warm += 1
			if pixel.r > 0.3 and pixel.g > 0.3 and pixel.b > 0.3:
				white += 1
	check(warm > 0 and white > 0, "Native impact burst renders warm sparks and a white hot center")
	sim.elapsed = 0.23
	visual.queue_redraw()
	await rendered(view)
	var expired := await rendered(view)
	check(expired.get_pixel(80, 64) == background.get_pixel(80, 64), "Expired impact leaves no lingering explosion pixels")
	visual._projectile_impacts.clear()
	var ship := HangarShip.new()
	check(ship.initialize_chassis("flagship_basic", 1, true), "Thrust visual fixture initializes")
	var exhaust = preload("res://scripts/ship_exhaust.gd")
	for chassis: Dictionary in SlotCatalog.chassis():
		var candidate := HangarShip.new()
		check(candidate.initialize_chassis(chassis.id, 1, int(chassis.command) > 0), "Exhaust chassis initializes")
		var full_rect := Rect2(Vector2(10, 20), Vector2(512, 512))
		var small_rect := Rect2(Vector2(10, 20), Vector2(128, 128))
		var full_origins: PackedVector2Array = exhaust.origins(candidate, full_rect)
		var small_origins: PackedVector2Array = exhaust.origins(candidate, small_rect)
		check(not full_origins.is_empty(), "Every chassis has engine-specific exhaust anchors")
		for index in range(full_origins.size()):
			check((small_origins[index] - small_rect.position).is_equal_approx(
				(full_origins[index] - full_rect.position) * 0.25),
				"Escort exhaust anchor scales with the sprite, including transparent padding")
		if chassis.id == "fighter":
			check(full_origins == PackedVector2Array([Vector2(214, 500), Vector2(318, 500)]),
				"Fighter exhaust originates at its two actual rear engine tips")
	var member := BattleSimulation.Combatant.new()
	member.owned_ship = ship
	member.stats = ship.get_stats()
	member.faction = BattleSimulation.Faction.PLAYER
	member.position = Vector2(48, 0)
	member.previous_position = member.position
	sim.players.append(member)
	visual.queue_redraw()
	await rendered(view)
	var stationary := await rendered(view)
	member.velocity = Vector2(40, 0)
	visual.queue_redraw()
	await rendered(view)
	var moving := await rendered(view)
	check(difference(stationary, moving) > 0.00001, "Moving player ship renders a visible thrust plume")
	check(difference(stationary, moving, false, SNAPSHOT_NOISE) > 0.00001,
		"Visible thrust exceeds native snapshot quantization noise")
	var rear_pixels := 0
	var front_pixels := 0
	for y in range(128):
		for x in range(128):
			if not moving.get_pixel(x, y).is_equal_approx(stationary.get_pixel(x, y)):
				if x < 112:
					rear_pixels += 1
				else:
					front_pixels += 1
	check(rear_pixels > 0 and front_pixels == 0, "Exhaust particles appear only behind the player ship")
	var fighter := HangarShip.new()
	check(fighter.initialize_chassis("fighter", 2), "Small-ship exhaust visual fixture initializes")
	member.owned_ship = fighter
	member.velocity = Vector2.ZERO
	visual.queue_redraw()
	var fighter_stopped := await rendered(view)
	member.velocity = Vector2(40, 0)
	visual.queue_redraw()
	var fighter_moving := await rendered(view)
	check(difference(fighter_stopped, fighter_moving) > 0.000001,
		"Quarter-scale fighter still renders visible exhaust from its engines")
	member.owned_ship = ship
	member.faction = BattleSimulation.Faction.ALIEN
	visual.queue_redraw()
	await rendered(view)
	var alien := await rendered(view)
	check(difference(stationary, alien, false, SNAPSHOT_NOISE) < 0.00001, "Alien faction receives no thrust particles")
	member.faction = BattleSimulation.Faction.PLAYER
	member.velocity = Vector2.ZERO
	visual.queue_redraw()
	await rendered(view)
	var stopped := await rendered(view)
	check(difference(stationary, stopped, false, SNAPSHOT_NOISE) < 0.00001, "Stopping movement removes thrust particles")
	member.shield_flash = 0.2
	visual.queue_redraw()
	await rendered(view)
	var shielded := await rendered(view)
	check(difference(stopped, shielded) > 0.00001, "Shield hit visibly lights the ship silhouette")
	check(difference(stopped, shielded, false, SNAPSHOT_NOISE) > 0.00001,
		"Visible shield hit exceeds native snapshot quantization noise")
	member.shield_flash = 0
	visual.queue_redraw()
	await rendered(view)
	var recovered := await rendered(view)
	check(difference(stopped, recovered, false, SNAPSHOT_NOISE) < 0.00001, "Shield glow disappears when the hit flash ends")
	view.queue_free()
	await process_frame

func projectile_impact_checks() -> void:
	var visual: Control = load("res://scripts/battle_visuals.gd").new()
	visual.size = Vector2(128, 128)
	visual.camera_zoom = 1
	visual.simulation = LightSimulation.new()
	var sim: BattleSimulation = visual.simulation
	var rng := sim.random.state
	visual.add_projectile_impact(Vector2(-20, 0))
	visual.add_projectile_impact(Vector2(1000, 0))
	check(visual._projectile_impacts.is_empty(), "Hidden and offscreen collisions create no particles")
	for index in range(120):
		visual.add_projectile_impact(Vector2(20, 0))
	check(visual._projectile_impacts.size() == 96 and sim.random.state == rng,
		"Impact particles stay bounded without consuming combat randomness")
	root.add_child(visual)
	visual._process(0)
	check(visual._projectile_impacts.size() == 96, "Paused simulation preserves impact particle ages")
	sim.elapsed = 0.23
	visual._process(0)
	check(visual._projectile_impacts.is_empty(), "Impact particles expire within a quarter second of simulation time")
	var target := BattleSimulation.Combatant.new()
	target.integrity = 100
	target.stats = ShipStats.new()
	target.position = Vector2(20, 0)
	target.radius = 5
	var shot := BattleSimulation.Projectile.new()
	shot.target = target
	shot.position = Vector2(16, 0)
	shot.damage = 10
	shot.speed = 30
	sim.projectiles.append(shot)
	sim.projectile_impacted.connect(visual.add_projectile_impact)
	sim._update_projectiles(1.0 / 30.0)
	check(sim.projectiles.is_empty() and visual._projectile_impacts.size() == 1 and target.integrity == 90,
		"Real projectile collision emits one cosmetic burst without changing damage")
	visual.free()

func projectile_light_checks() -> void:
	var visual: Control = load("res://scripts/battle_visuals.gd").new()
	visual.visible = false
	visual.size = Vector2(640, 360)
	visual.camera_zoom = 0.8
	visual.interpolation_alpha = 0.25
	root.add_child(visual)
	var sim := LightSimulation.new()
	visual.simulation = sim
	var shot := BattleSimulation.Projectile.new()
	shot.previous_position = Vector2(10, 0)
	shot.position = Vector2(30, 0)
	shot.is_player = true
	sim.projectiles.append(shot)
	var hidden := BattleSimulation.Projectile.new()
	hidden.position = Vector2(-30, 0)
	hidden.previous_position = hidden.position
	sim.projectiles.append(hidden)
	var offscreen := BattleSimulation.Projectile.new()
	offscreen.position = Vector2(2000, 0)
	offscreen.previous_position = offscreen.position
	sim.projectiles.append(offscreen)
	visual._process(0)
	var material := visual.material as ShaderMaterial
	check(material.get_shader_parameter("projectile_light_count") == 1, "Projectile lights exclude hidden and offscreen shots")
	var lights: PackedVector4Array = material.get_shader_parameter("projectile_lights")
	var point: Vector2 = visual.get_global_transform_with_canvas() * visual.world_transform() * Vector2(15, 0)
	check(Vector2(lights[0].x, lights[0].y).is_equal_approx(point), "Projectile light follows interpolated bullet position")
	check(is_equal_approx(lights[0].z, 36.0 * 0.8), "Projectile light radius scales with camera zoom")
	var colors: PackedVector3Array = material.get_shader_parameter("projectile_light_colors")
	check(colors[0].is_equal_approx(Vector3(1.0, 0.12, 0.06)), "Player bullet has red light")
	shot.is_player = false
	visual._process(0)
	colors = material.get_shader_parameter("projectile_light_colors")
	check(colors[0].is_equal_approx(Vector3(0.55, 1.0, 0.25)), "Enemy bullet has green light")
	for index in range(SurfaceArt.MAX_PROJECTILE_LIGHTS + 2):
		sim.projectiles.append(shot)
	var explosion := BattleSimulation.Explosion.new()
	explosion.position = Vector2(10, 0)
	sim.explosions.append(explosion)
	visual._process(0)
	check(material.get_shader_parameter("projectile_light_count") == SurfaceArt.MAX_PROJECTILE_LIGHTS, "Projectile light count stays capped")
	check(material.get_shader_parameter("flash_count") == 1, "Projectile lights do not displace explosion lights")
	sim.projectiles.clear()
	visual._process(0)
	check(material.get_shader_parameter("projectile_light_count") == 0, "Expired bullets leave no lights")
	visual.free()

func difference(a: Image, b: Image, rotated := false, noise_floor := 0.0) -> float:
	var total := 0.0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var other := Vector2i(a.get_width() - 1 - x, a.get_height() - 1 - y) if rotated else Vector2i(x, y)
			var left := a.get_pixel(x, y)
			var right := b.get_pixelv(other)
			total += maxf(0, absf(left.r - right.r) - noise_floor) \
				+ maxf(0, absf(left.g - right.g) - noise_floor) \
				+ maxf(0, absf(left.b - right.b) - noise_floor)
	return total / (a.get_width() * a.get_height())

func native_checks() -> void:
	var navigation := root.get_node("UiNavigation")
	navigation.set_process(false)
	RenderingServer.global_shader_parameter_set("cursor_light", Vector4.ZERO)
	var view := SubViewport.new()
	view.size = Vector2i(256, 256)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var canvas := SurfaceCanvas.new()
	canvas.position = Vector2(128, 128)
	canvas.art = SurfaceArt.texture("res://assets/chassis/flagship_basic_d.png")
	var material := SurfaceArt.apply(canvas)
	view.add_child(canvas)
	var lit := await rendered(view)
	var original_shader := Shader.new()
	original_shader.code = SurfaceArt.SHADER.code.replace("vec3(0.12, 0.14, 0.17)", "vec3(0.40, 0.44, 0.50)")
	check(original_shader.code != SurfaceArt.SHADER.code, "Ambient comparison actually changes the current shader's ambient term")
	material.shader = original_shader
	var brighter_ambient := await rendered(view)
	material.shader = SurfaceArt.SHADER
	check(difference(lit, brighter_ambient) > 0.001, "Reduced ambient visibly dims mapped artwork")
	var darker_pixels := 0
	for y in range(lit.get_height()):
		for x in range(lit.get_width()):
			var dim := lit.get_pixel(x, y)
			var bright := brighter_ambient.get_pixel(x, y)
			if dim.a > 0.5 and dim.get_luminance() < bright.get_luminance():
				darker_pixels += 1
	check(darker_pixels > 1000, "Ambient reduction dims opaque ship pixels, not just transparent edges")
	RenderingServer.global_shader_parameter_set("cursor_light", Vector4(100.0 / 256, 100.0 / 256, 48.0 / 256, 0.75))
	var cursor_lit := await rendered(view)
	check(difference(lit, cursor_lit) > 0.0001, "Cursor light illuminates nearby mapped surfaces")
	check(lit.get_pixel(200, 200) == cursor_lit.get_pixel(200, 200), "Cursor light remains localized")
	RenderingServer.global_shader_parameter_set("cursor_light", Vector4(160.0 / 256, 160.0 / 256, 48.0 / 256, 0.75))
	var cursor_moved := await rendered(view)
	check(difference(cursor_lit, cursor_moved) > 0.0001, "Surface illumination follows cursor movement")
	RenderingServer.global_shader_parameter_set("cursor_light", Vector4.ZERO)
	var cursor_disabled := await rendered(view)
	check(difference(lit, cursor_disabled) < 0.0001, "Disabling cursor light restores original rendering")
	canvas.art_rotation = PI
	canvas.queue_redraw()
	var battle_rotated := await rendered(view)
	check(difference(lit, battle_rotated, true) > 0.003, "Immediate battle draw transforms rotate surface normals")
	canvas.art_rotation = 0
	canvas.queue_redraw()
	canvas.rotation = PI
	var rotated := await rendered(view)
	check(difference(lit, rotated, true) > 0.003, "Rotating a ship changes lighting in screen space")
	canvas.rotation = 0
	material.set_shader_parameter("flash_count", 1)
	var flashes := PackedVector4Array([Vector4(90, 90, 300, 3)])
	flashes.resize(SurfaceArt.MAX_FLASHES)
	material.set_shader_parameter("flash_lights", flashes)
	var flashed := await rendered(view)
	check(difference(lit, flashed) > 0.01, "Nearby transient lights affect mapped art")
	material.set_shader_parameter("flash_count", 0)
	var bullet_lights := PackedVector4Array([Vector4(100, 100, 36, 0.9)])
	bullet_lights.resize(SurfaceArt.MAX_PROJECTILE_LIGHTS)
	var bullet_colors := PackedVector3Array([Vector3(1.0, 0.12, 0.06)])
	bullet_colors.resize(SurfaceArt.MAX_PROJECTILE_LIGHTS)
	material.set_shader_parameter("projectile_light_count", 1)
	material.set_shader_parameter("projectile_lights", bullet_lights)
	material.set_shader_parameter("projectile_light_colors", bullet_colors)
	var bullet_lit := await rendered(view)
	check(difference(lit, bullet_lit) > 0.0001, "Small bullet light illuminates nearby mapped surfaces")
	check(lit.get_pixel(200, 200) == bullet_lit.get_pixel(200, 200), "Bullet light does not illuminate distant surfaces")
	bullet_lights[0] = Vector4(160, 160, 36, 0.9)
	material.set_shader_parameter("projectile_lights", bullet_lights)
	var bullet_moved := await rendered(view)
	check(difference(bullet_lit, bullet_moved) > 0.0001, "Illumination moves with the bullet")
	material.set_shader_parameter("projectile_light_count", 0)
	canvas.art = SurfaceArt.texture("res://assets/shieldGenerator_s.png")
	canvas.queue_redraw()
	RenderingServer.global_shader_parameter_set("cursor_light", Vector4(0.5, 0.5, 0.5, 0.75))
	var plain_lit := await rendered(view)
	canvas.material = null
	var plain := await rendered(view)
	check(difference(plain_lit, plain) < 0.0001, "Unmapped art is pixel-identical with lighting enabled")
	RenderingServer.global_shader_parameter_set("cursor_light", Vector4.ZERO)
	canvas.art = SurfaceArt.texture("res://assets/environment/asteroids_small_d.png")
	canvas.atlas = true
	canvas.queue_redraw()
	var plain_rock := await rendered(view)
	SurfaceArt.apply(canvas)
	var lit_rock := await rendered(view)
	check(difference(plain_rock, lit_rock) > 0.001, "Asteroid atlas regions receive mapped lighting")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/surface-art"))
	lit.save_png("res://.local/surface-art/chassis.png")
	brighter_ambient.save_png("res://.local/surface-art/chassis-before-ambient.png")
	flashed.save_png("res://.local/surface-art/flash.png")
	lit_rock.save_png("res://.local/surface-art/asteroid.png")
	canvas.atlas = false
	for id in ["hull_plate", "armor_block", "research_lab"]:
		canvas.art = SlotCatalog.equipment_texture(SlotCatalog.find_equipment(id))
		canvas.queue_redraw()
		var plate_material := SurfaceArt.apply(canvas)
		var plate_lit := await rendered(view)
		plate_material.set_shader_parameter("flash_count", 1)
		plate_material.set_shader_parameter("flash_lights", flashes)
		var plate_flash := await rendered(view)
		check(difference(plate_lit, plate_flash) > 0.001, "Equipment surface maps respond to local light: " + id)
		plate_lit.save_png("res://.local/surface-art/" + id + ".png")
	for path: String in [
		"res://assets/aliens/drone_chrysalis_d.png",
		"res://assets/aliens/drone_scout_d.png",
		"res://assets/aliens/drone_sentinel_d.png",
		"res://assets/aliens/drone_support_d.png",
		"res://assets/aliens/drone_large_wing_d.png",
		"res://assets/aliens/drone_large_sporeback_d.png",
	]:
		canvas.art = SurfaceArt.texture(path)
		canvas.art_rotation = 0
		canvas.queue_redraw()
		var alien_material := SurfaceArt.apply(canvas)
		var alien_lit := await rendered(view)
		canvas.art_rotation = PI
		canvas.queue_redraw()
		var alien_rotated := await rendered(view)
		check(difference(alien_lit, alien_rotated, true) > 0.001, "Alien normals respond to battle rotation: " + path)
		canvas.art_rotation = 0
		canvas.queue_redraw()
		alien_material.set_shader_parameter("flash_count", 1)
		alien_material.set_shader_parameter("flash_lights", flashes)
		var alien_flash := await rendered(view)
		check(difference(alien_lit, alien_flash) > 0.001, "Alien maps receive explosion illumination: " + path)
		alien_lit.save_png("res://.local/surface-art/" + path.get_file())
	view.queue_free()
	await process_frame
	navigation.set_process(true)
