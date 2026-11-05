extends SceneTree
const ShipLoadouts = preload("res://scripts/ship_loadouts.gd")

var checks := 0
var failures := 0
var state: Node
var integration_completed := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame in range(5):
		await process_frame

func weapon_ship(part: String, slot := "fore") -> HangarShip:
	var ship := HangarShip.new()
	check(ship.initialize_chassis("corsair", 1, true), "Initialize focused weapon host")
	var item := SlotCatalog.find_equipment(part)
	check(SlotCatalog.compatible(ShipLoadouts.slot_by_id(ship.chassis, slot), item), "Weapon fits its real mount")
	ship.mounts[slot] = {"uid": "1", "equipment_id": part, "rank": 1}
	ship.rebuild_units()
	ship.hull_hp = ship.hull_max
	return ship

func weapon_simulation(ship: HangarShip) -> BattleSimulation:
	var enemy := AlienShip.threat_variant("scout", 0)
	enemy.stats.integrity = 100000
	var sim := BattleSimulation.new()
	check(sim.setup_owned([ship], [enemy], 0, 0, 7251, {"credits_only": true, "missiles": 30}),
		"Configure controlled range/projectile fixture")
	sim.players[0].position = Vector2.ZERO
	sim.aliens[0].position = Vector2(550, 0)
	for member: BattleSimulation.Combatant in sim._members:
		member.speed = 0
		member.acceleration = 0
	return sim

func weapons() -> void:
	var previous := {"beam_lance": 360, "double_laser": 220, "extraction_drill": 45, "ion_emitter": 300,
		"laser": 220, "mini_turret": 220, "mining_laser": 300, "missile_rack": 340,
		"point_defense_turret": 160, "railgun": 500}
	for id: String in previous:
		var definition := SlotCatalog.find_equipment(id)
		var weapon: ShipWeaponStats = SlotCatalog.stats_for(id).weapons[0]
		check(weapon.range_units == previous[id] * 3 and definition.stats.weapons[0].range == weapon.range_units,
			"Catalog, runtime and displayed range are exactly tripled: " + id)
		var copy := weapon.copy()
		check(copy.range_units == weapon.range_units and copy.damage_per_shot == weapon.damage_per_shot,
			"Weapon copies do not compound range scaling: " + id)
	var alien_ranges := {"chrysalis": 600, "fighter": 540, "scout": 570, "sentinel": 690, "support": 630}
	for alien: AlienShip in AlienShip.get_catalog():
		check(alien.stats.weapons[0].range_units == alien_ranges[alien.role_id],
			"Alien weapon range is tripled: " + alien.role_id)
		check(AlienShip.from_snapshot(alien.to_snapshot()).stats.weapons[0].range_units == alien.stats.weapons[0].range_units,
			"Alien frozen snapshot roundtrip never triples range twice")
	var laser := SlotCatalog.stats_for("laser").weapons[0]
	ResearchUpgrades.apply_weapon(laser, {"laser_range_multiplier": {"value": 1.2}})
	check(is_equal_approx(laser.range_units, 792), "Optics still multiplies the new base by 1.2")
	var missile := SlotCatalog.stats_for("missile_rack").weapons[0]
	ResearchUpgrades.apply_weapon(missile, {"missile_range_multiplier": {"value": 1.25}})
	check(is_equal_approx(missile.range_units, 1275), "Guided Munitions still multiplies the new base by 1.25")
	var sim := weapon_simulation(weapon_ship("mini_turret", "aft"))
	sim._update_ship(sim.player, 0.001)
	check(not sim.projectiles.is_empty(), "Turret fires at 550 units, beyond the former 220-unit range")
	var bullet: BattleSimulation.Projectile = sim.projectiles[0]
	var start := bullet.position
	check(bullet.speed == 640 and bullet.damage == SlotCatalog.stats_for("mini_turret").weapons[0].damage_per_shot,
		"Real turret bullet speed doubles without damage changes")
	sim._update_projectiles(0.1)
	check(is_equal_approx(bullet.position.distance_to(start), 64), "Actual bullet travels 64 units in 0.1 seconds")
	var hull: float = sim.aliens[0].integrity
	sim._update_projectiles(1)
	check(sim.projectiles.is_empty() and sim.aliens[0].integrity < hull,
		"Doubled-speed swept bullet still hits its target without tunneling")
	sim._update_ship(sim.aliens[0], 0.001)
	check(sim.projectiles.any(func(shot: BattleSimulation.Projectile) -> bool:
		return not shot.is_player and shot.speed == 640), "Alien bullets also use doubled travel speed")
	sim = weapon_simulation(weapon_ship("railgun"))
	sim._update_ship(sim.player, 0.001)
	check(not sim.projectiles.is_empty() and sim.projectiles[0].speed == 640,
		"Railgun uses doubled bullet speed")
	sim = weapon_simulation(weapon_ship("missile_rack", "port"))
	sim._update_ship(sim.player, 0.001)
	check(sim.projectiles.size() == 3 and sim.projectiles[0].speed == 200 and sim.missile_supply == 27,
		"Missile travel/guidance, burst and ammo costs remain distinct from bullets")
	sim = weapon_simulation(weapon_ship("mini_turret", "aft"))
	check(sim.asteroid_field.add_root("cover", 8, Vector2(280, 0), Vector2.ZERO, [0, 0, 0, 0]),
		"Create focused asteroid cover")
	sim.asteroid_field.attach(sim)
	sim._update_ship(sim.player, 0.001)
	hull = sim.aliens[0].integrity
	sim._update_projectiles(1)
	check(sim.projectiles.is_empty() and sim.entities.cover.integrity < 96 and sim.aliens[0].integrity == hull,
		"Doubled-speed bullet still strikes asteroid cover before the ship")

func fields() -> void:
	for layout in ["open", "corridor"]:
		var area := BattleSimulation.deployment_area({"arena_layout": layout})
		for corner: Vector2 in [area.position, area.end]:
			var formation := (corner - BattleSimulation.PLAYER_FORMATION_CENTER) / BattleSimulation.DEPLOYMENT_SCALE
			check(absf(formation.x) <= 5 and absf(formation.y) <= 5,
				"Entire deployment area fits saved formation coordinate limits")
	check(NodeEnvironment.ROCK_COUNTS == [0, 16, 32, 48], "Densities provide zero, one, two or three dense fields")
	for density in range(4):
		var environment := {"version": 1, "asteroid_density": density, "solar_intensity": 1.0, "nebula": false}
		var plan := EncounterGenerator.generate(7251, 21, 5, 1, "patrol", 3, false, environment)
		check(EncounterGenerator.valid(plan), "Dense-field encounter retains threat/objective/reward validation")
		if density == 0:
			check(not plan.has("asteroids"), "Explicit clear locations remain clear")
			continue
		var data: Dictionary = plan.asteroids
		check(data.roots.size() == density * 16 and AsteroidField.valid(data)
			and AsteroidField.valid(JSON.parse_string(JSON.stringify(data))), "Field size and lineage survive JSON")
		var repeat := EncounterGenerator.generate(7251, 21, 5, 1, "patrol", 3, false, environment)
		check(SaveValidation.same(plan, repeat), "Clusters and frozen encounters regenerate deterministically")
		var centers: Array[Vector2] = []
		for cluster in range(density):
			var center := Vector2.ZERO
			var velocity := Vector2.ZERO
			for index in range(cluster * 16, cluster * 16 + 16):
				var rock: Dictionary = data.records["rock/%d" % index]
				center += Vector2(rock.position[0], rock.position[1])
				velocity += Vector2(rock.velocity[0], rock.velocity[1])
			center /= 16
			velocity /= 16
			centers.append(center)
			var compact := true
			var slow := true
			var clear_of_deployment := true
			for index in range(cluster * 16, cluster * 16 + 16):
				var rock: Dictionary = data.records["rock/%d" % index]
				var position := Vector2(rock.position[0], rock.position[1])
				var drift := Vector2(rock.velocity[0], rock.velocity[1])
				compact = compact and position.distance_to(center) < 160 \
					and (position + drift * 60).distance_to(center + velocity * 60) < 175
				slow = slow and drift.length() >= 1.8 and drift.length() <= 5.2
				clear_of_deployment = clear_of_deployment and absf(position.x) < 650
			check(compact and slow and clear_of_deployment,
				"16-rock field stays dense/localized for 60 seconds with 1.8-5.2 unit/s drift outside starting fleets")
		var separated := true
		for i in range(data.records.size()):
			var a: Dictionary = data.records["rock/%d" % i]
			for j in range(i):
				var b: Dictionary = data.records["rock/%d" % j]
				separated = separated and Vector2(a.position[0], a.position[1]).distance_to(Vector2(b.position[0], b.position[1])) \
					> 8 * (sqrt(float(a.mass)) + sqrt(float(b.mass)))
		check(separated, "Dense roots do not overlap one another at spawn")
		for index in range(centers.size() - 1):
			check(centers[index].distance_to(centers[index + 1]) > 450,
				"Localized fields have open space between them")
	var waves := EncounterGenerator.generate(7251, 22, 6, 1, "relay_defense", 4)
	waves.arena_layout = "corridor"
	var sim := weapon_simulation(weapon_ship("mini_turret", "aft"))
	var wave_sim := BattleSimulation.new()
	check(wave_sim.setup_owned([weapon_ship("mini_turret", "aft")], EncounterGenerator.initial_fleet(waves),
		0, 0, 7251, {"credits_only": true, "encounter_plan": waves}), "Configure a single frozen wave fixture")
	wave_sim.encounter.advance(wave_sim, 6)
	check(wave_sim.aliens.any(func(actor: BattleSimulation.Combatant) -> bool:
		return actor.alien.wave_index == 1 and absf(actor.position.x - BattleSimulation.WAVE_ENTRY_X) <= 144),
		"Compact wave squadrons enter at the larger arena's right side")
	var field := AsteroidField.new()
	check(field.add_root("edge", 1, Vector2(1200, 0), Vector2(3, 0), [0, 0, 0, 0]), "Create arena-edge drift fixture")
	field.attach(sim)
	field.advance(sim, 1)
	check(sim.entities.edge.position.is_equal_approx(Vector2(1203, 0)), "Rocks beyond the old 780-unit boundary no longer teleport")
	var actor: BattleSimulation.Combatant = sim.entities.edge
	actor.position = Vector2(BattleSimulation.ARENA_RADIUS - actor.radius - 1, 0)
	actor.velocity = Vector2(3, 0)
	field.advance(sim, 1)
	check(actor.position.length() <= BattleSimulation.ARENA_RADIUS - actor.radius and actor.velocity.x < 0,
		"Drifting rocks bounce at the new arena edge")
	var boss := EncounterGenerator.generate(7251, 23, 10, 1, "bastion_warden", 10)
	check(EncounterGenerator.valid(boss) and boss.warden.range == 1560
		and AlienShip.warden_variant(false, 10, 10, 10).stats.weapons[0].range_units == 630,
		"Boss ordinary weapons and lance range scale without adding phases")

func setup_fixture() -> bool:
	state = root.get_node("GameState")
	state.run_save_path = "user://battlefield-scale.json"
	check(state.start_new_run(1, 7251), "Start isolated battlefield fixture")
	state.pending_intro = false
	var target: int = state.get_reachable_nodes(state.current_node_id)[0]
	check(state.travel_to(target), "Save a pending encounter")
	var proposal: Dictionary = state.hangar_snapshot()
	proposal.pending_encounter = EncounterGenerator.generate(7251, target, 5, 1, "patrol", 3, false,
		{"version": 1, "asteroid_density": 3, "solar_intensity": 1.0, "nebula": false})
	proposal.pending_encounter.arena_layout = "open"
	if proposal.has("navigation"):
		proposal.pending_encounter = SwarmNavigation.encounter(proposal.pending_encounter, proposal.navigation.intensity)
		proposal.navigation.encounters[str(target)] = proposal.pending_encounter.duplicate(true)
	var committed: bool = state._commit_hangar(proposal)
	check(committed, "Persist one dense-asteroid encounter: " + state.last_save_error)
	if not committed:
		return false
	var saved: Dictionary = state.hangar_snapshot()
	check(state.load_run_checkpoint() and SaveValidation.same(saved, state.hangar_snapshot()),
		"Continue preserves exact cluster positions, velocities, roots and equipment")
	return true

func integration() -> void:
	if not setup_fixture():
		return
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_process(false)
	battle.set_physics_process(false)
	await settle()
	check(BattleSimulation.ARENA_RADIUS == 2400 and BattleSimulation.DEPLOYMENT_SCALE == 130,
		"Expanded battlefield radius and saved tactical coordinate scale remain consistent")
	var sim: BattleSimulation = battle.simulation
	check(sim.other_entities.size() == 48 and sim.elapsed == 0 and battle.deploying,
		"All 48 asteroid roots appear in frozen deployment")
	var ally_max := -INF
	var enemy_min := INF
	for actor: BattleSimulation.Combatant in sim.players:
		ally_max = maxf(ally_max, actor.position.x + actor.radius)
	for actor: BattleSimulation.Combatant in sim.aliens:
		enemy_min = minf(enemy_min, actor.position.x - actor.radius)
	check(enemy_min - ally_max > 1500, "Actual starting fleets have over 1500 units of clear separation")
	var before := sim.asteroid_field.snapshot()
	battle._physics_process(30)
	check(SaveValidation.same(before, sim.asteroid_field.snapshot()), "Asteroid drift stays frozen during deployment")
	if DisplayServer.get_name() != "headless":
		for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.size = resolution
			await settle()
			var transform: Transform2D = battle.visuals.world_transform()
			var inside := true
			for actor: BattleSimulation.Combatant in sim.players + sim.aliens + sim.other_entities:
				inside = inside and battle.battlefield.get_global_rect().grow(1).has_point(transform * actor.position)
			check(inside and battle.begin_button.is_visible_in_tree() and battle.objective_label.is_visible_in_tree(),
				"Native camera shows both fleets and all localized fields at " + str(resolution))
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("user://battlefield-%d.png" % resolution.x) == OK,
				"Capture enlarged battlefield")
	battle._begin_combat()
	check(not battle.deploying, "Begin Combat saves expanded placement inside new mission bounds")
	var first_position: Vector2 = sim.other_entities[0].position
	for tick in range(90):
		battle._advance_fixed_simulation(1.0 / 30, 1)
	check(sim.elapsed > 2.9 and not sim.other_entities[0].position.is_equal_approx(first_position),
		"Three-second live sample advances slow moving asteroids and combat")
	if DisplayServer.get_name() != "headless":
		battle._update_auto_camera(1)
		await settle()
		battle.visuals.queue_redraw()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("user://battlefield-live.png") == OK, "Capture native live clustered field")
	battle.queue_free()
	await settle()
	check(state.load_run_checkpoint(), "Reload the saved Begin Combat checkpoint")
	battle = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_process(false)
	battle.set_physics_process(false)
	await settle()
	check(battle.deploying and battle.simulation.elapsed == 0 and battle.simulation.other_entities.size() == 48,
		"Continue returns to enlarged deployment with the original frozen asteroid field")
	battle._begin_combat()
	for tick in range(30 * 90):
		battle._advance_fixed_simulation(1.0 / 30, 1)
		if battle.simulation.phase != BattleSimulation.Phase.COMBAT:
			break
	check(battle.simulation.phase != BattleSimulation.Phase.COMBAT, "One enlarged dense-field battle reaches an outcome within 90 simulated seconds")
	print("DENSE-FIELD BATTLE: ", JSON.stringify({"seconds": battle.simulation.elapsed,
		"outcome": BattleSimulation.Phase.keys()[battle.simulation.phase],
		"live_rocks": battle.simulation.other_entities.filter(func(actor: BattleSimulation.Combatant) -> bool:
			return actor.has_tag("asteroid") and actor.is_alive()).size()}))
	check(state.settle_battle(battle.simulation) and not state.battle_pending, "Dense-field outcome settles once through production")
	battle.queue_free()
	await settle()
	integration_completed = true

func inspection() -> void:
	if not setup_fixture():
		return
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.size = Vector2i(1280, 720)
	root.add_child(battle)
	current_scene = battle
	battle.set_process(false)
	battle.set_physics_process(false)
	await settle()
	var center: Vector2 = battle.visuals.world_center()
	var rock: BattleSimulation.Combatant = battle.simulation.other_entities[16]
	battle.visuals.camera_position = rock.position
	battle._mark_manual_pan_input()
	var initial_zoom: float = battle.visuals.camera_zoom
	var motion := InputEventMouseMotion.new()
	motion.position = center
	root.push_input(motion, true)
	await process_frame
	for tick in range(12):
		var wheel := InputEventMouseButton.new()
		wheel.position = center
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		root.push_input(wheel, true)
		await process_frame
	check(battle.visuals.camera_zoom > initial_zoom * 5, "Actual wheel input zooms expanded arena to inspect individual asteroids")
	check((battle.visuals.world_transform() * rock.position).distance_to(center) < 1,
		"Inspection zoom stays anchored beneath the pointer")
	battle.visuals.queue_redraw()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://asteroid-closeup.png") == OK,
		"Capture native localized asteroid density at inspection zoom")
	battle.queue_free()
	await settle()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var inspection_only := "--inspection-only" in args
	var fields_only := "--fields-only" in args
	if "--native-only" in args and DisplayServer.get_name() == "headless":
		check(false, "Native integration requires native rendering")
		print("BATTLEFIELD SCALE: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	if "--native-only" not in args and not inspection_only:
		if not fields_only:
			weapons()
			print("BATTLEFIELD: weapon checks completed")
		fields()
		print("BATTLEFIELD: field checks completed")
	if inspection_only:
		check(DisplayServer.get_name() != "headless", "Inspection check requires native rendering")
		if DisplayServer.get_name() != "headless":
			await inspection()
	elif DisplayServer.get_name() != "headless" and not fields_only:
		await integration()
		check(integration_completed, "Battlefield integration reaches completion")
	print("BATTLEFIELD SCALE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
