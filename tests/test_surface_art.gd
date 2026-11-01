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
	if DisplayServer.get_name() != "headless":
		await native_checks()
	print("Surface art checks: %d; failures: %d" % [checks, failures])
	call_deferred("quit", 1 if failures else 0)

func rendered(view: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

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

func difference(a: Image, b: Image, rotated := false) -> float:
	var total := 0.0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var other := Vector2i(a.get_width() - 1 - x, a.get_height() - 1 - y) if rotated else Vector2i(x, y)
			var left := a.get_pixel(x, y)
			var right := b.get_pixelv(other)
			total += absf(left.r - right.r) + absf(left.g - right.g) + absf(left.b - right.b)
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
	original_shader.code = SurfaceArt.SHADER.code.replace("vec3(0.30, 0.33, 0.375)", "vec3(0.40, 0.44, 0.50)")
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
