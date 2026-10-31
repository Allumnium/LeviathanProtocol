extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func fixture() -> BattleSimulation:
	var ships: Array[FleetShip] = []
	for index in range(2):
		var owned := FleetShip.new()
		check(owned.initialize(BUILTINS.drone(), index + 1, "Observer"), "Construct physical sight source.")
		ships.append(owned)
	var aliens: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(2, 1.0, 42):
		aliens.append(alien)
	var sim := BattleSimulation.new()
	check(sim.setup_owned(ships, aliens, 0.3, 0, 42, {"visibility_enabled": true}), "Initialize shared tactical visibility.")
	sim.players[0].position = Vector2.ZERO
	sim.players[1].position = Vector2(2000, 0)
	sim.aliens[0].position = Vector2(200, 0)
	sim.aliens[1].position = Vector2(1600, 0)
	sim.visibility.reset()
	sim.refresh_visibility()
	return sim

func run() -> void:
	test_information()
	test_projectiles()
	test_replay()
	test_departure()
	test_stress()
	if "--capture" in OS.get_cmdline_user_args():
		await native_capture()
	print("Visibility tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func test_information() -> void:
	var sim := fixture()
	var observer := sim.players[0]
	var target := sim.aliens[0]
	check(sim.team_can_see(0, target) and sim.team_can_see(1, observer), "Both teams use the same 260 sight range.")
	check(sim.request_attack(observer.entity_id, target.entity_id), "Full sight permits a precise lock.")
	target.position = Vector2(300, 0)
	sim.refresh_visibility()
	check(not sim.can_attack(observer, target) and not sim.request_attack(observer.entity_id, target.entity_id), "Radar alone grants no precise attack lock.")
	var contacts: Array = sim.visibility.contacts(0)
	check(contacts.any(func(contact: Dictionary) -> bool: return contact.kind == "radar" and contact.position == Vector2(300, 0)), "Radar sees an anonymous contact within 480.")
	for contact: Dictionary in contacts:
		for key in contact:
			check(key in ["kind", "position", "age"], "Contact payload contains no ID, HP, parts, loadout or authoritative reference.")
	target.integrity *= 0.5
	target.stats.weapons.clear()
	sim.refresh_visibility()
	check(contacts == sim.visibility.contacts(0), "Hidden HP and equipment changes do not alter radar/stale information.")
	sim.advance(1.0 / 60.0)
	check(observer.target == null and observer.commanded_target == null, "Losing sight drops current and commanded target locks.")
	target.position = Vector2(700, 0)
	sim.refresh_visibility()
	var stale: Array = sim.visibility.contacts(0).filter(func(contact: Dictionary) -> bool: return contact.kind == "stale")
	check(stale.size() == 1 and stale[0].position == Vector2(200, 0), "Last-known marker preserves its observed position, never the hidden live position.")
	sim.elapsed += 5.01
	sim.refresh_visibility()
	check(not sim.visibility.contacts(0).any(func(contact: Dictionary) -> bool: return contact.kind == "stale"), "Stale markers expire after five simulation seconds.")
	sim.players[1].position = Vector2(500, 0)
	sim.refresh_visibility()
	check(sim.team_can_see(0, target), "Team sight is the union of surviving Command Centers.")
	var source := sim.players[1]
	source.owned_ship.units[source.owned_ship.core_index].hp = 0
	sim._refresh_owned_stats(source)
	check(not sim.team_can_see(0, target), "Destroying the observing Command Center immediately removes its coverage.")
	observer.position = Vector2(-700, 0)
	sim.refresh_visibility()
	check(sim.visibility.explored_cells[0].has(Vector2i.ZERO) and not sim.point_visible(0, Vector2.ZERO), "Explored terrain memory survives the loss of current sight.")
	var before := Time.get_ticks_usec()
	for tick in range(60):
		sim.refresh_visibility()
	print("Visibility refresh mean: %.2f ms" % ((Time.get_ticks_usec() - before) / 60000.0))

func test_projectiles() -> void:
	var sim := fixture()
	var target := sim.aliens[0]
	var shot := BattleSimulation.Projectile.new()
	shot.source = sim.players[0]
	shot.is_player = true
	shot.target = target
	shot.damage = 10
	shot.aim_position = target.position
	shot.aim_radius = target.radius
	shot.speed = 100
	sim.projectiles.append(shot)
	target.position = Vector2(400, 300)
	sim.refresh_visibility()
	sim._update_projectiles(0.1)
	check(shot.guidance_lost and shot.aim_position == Vector2(200, 0) and shot.position.y == 0, "A fired shot retains its last legitimate aim point when sight is lost.")
	sim._rebuild_pending_projectile_damage()
	check(sim._pending_projectile_damage(target) == 0, "A blind ballistic shot does not reserve hidden-target damage.")
	var hp := target.integrity
	for tick in range(30):
		sim._update_projectiles(0.1)
	check(sim.projectiles.is_empty() and target.integrity == hp, "The missed shot expires at the old aim point without homing to hidden coordinates.")
	check(sim.get_finishing_projectile() == null, "Hidden targets cannot trigger a revealing finishing camera.")

func test_replay() -> void:
	var reference := {}
	for batch in [1, 2, 8]:
		var sim := fixture()
		for tick_batch in range(int(240 / batch)):
			for tick in range(batch):
				sim.advance(1.0 / 60.0)
		var snapshot := sim.authoritative_snapshot()
		if reference.is_empty():
			reference = snapshot
		else:
			check(snapshot == reference, "Sight, explored memory and last-known information replay identically at normal/accelerated speed.")

func test_departure() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://visibility/run.json"
	check(state.start_new_run(1, 42) and state.travel_to(state.get_reachable_nodes(0)[0]), "Depart through the production campaign.")
	check(state.battle_support_context().get("visibility_enabled", false) and state.load_run_checkpoint()
		and state.battle_support_context().visibility_enabled, "New departures durably freeze visibility rules for replay/retry.")
	var forged := RunCheckpoint.capture(state)
	forged.encounter_progress[str(state.destination_node_id)].deployment.shared_context.visibility_enabled = 1
	check(not RunCheckpoint.valid(forged), "Save validation rejects a forged visibility mode.")
	var sim := fixture()
	sim.aliens[0].position = Vector2(700, 0)
	sim.refresh_visibility()
	state.record_battle(sim)
	check(not state.last_battle_report.any(func(entry: Dictionary) -> bool: return entry.get("is_alien", false)), "Reports omit never-observed or currently hidden enemy details.")

func test_stress() -> void:
	var sim := fixture()
	for index in range(60):
		var member := BattleSimulation.Combatant.new()
		member.entity_id = "stress/%d" % index
		member.faction = index % 2
		member.stats = ShipStats.new()
		member.integrity = 10
		member.position = Vector2((index % 8) * 140 - 500, int(index / 8) * 140 - 500)
		check(sim.register_entity(member), "Register a bounded visibility stress actor.")
	sim.refresh_visibility()
	var before := Time.get_ticks_usec()
	for tick in range(30):
		sim.refresh_visibility()
	print("64-entity visibility refresh mean: %.2f ms" % ((Time.get_ticks_usec() - before) / 30000.0))

func native_capture() -> void:
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = Vector2i(640, 360)
	var sim := fixture()
	sim.players[1].position = Vector2(-50, 60)
	sim.aliens[0].position = Vector2(180, 0)
	sim.aliens[1].position = Vector2(380, 0)
	var hidden := sim.add_neutral_target("secret/rock", 100, Vector2(700, 100))
	sim.refresh_visibility()
	var visuals: Control = load("res://scripts/battle_visuals.gd").new()
	visuals.simulation = sim
	visuals.camera_position = Vector2(240, 0)
	visuals.camera_zoom = 0.5
	root.add_child(visuals)
	visuals.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var radar: Control = load("res://scripts/battle_radar.gd").new()
	radar.simulation = sim
	root.add_child(radar)
	radar.position = Vector2(520, 264)
	radar.size = Vector2(112, 88)
	await process_frame
	await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()
	before.save_png("res://.local/step36/visibility.png")
	hidden.position = Vector2(760, 140)
	hidden.integrity = 10
	sim.refresh_visibility()
	visuals.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(before.get_data() == root.get_texture().get_image().get_data(), "Moving/damaging a hidden on-screen actor changes no rendered pixels, including the radar.")
	var driver = load("res://scripts/auto_battle.gd").new()
	driver.simulation = sim
	driver.visuals = visuals
	sim.aliens[1].position = Vector2(700, 0)
	sim.refresh_visibility()
	driver._update_auto_camera(1.0)
	var camera: Vector2 = visuals.camera_position
	var zoom: float = visuals.camera_zoom
	sim.aliens[1].position = Vector2(900, 600)
	sim.refresh_visibility()
	driver._update_auto_camera(1.0)
	check(visuals.camera_position.is_equal_approx(camera) and is_equal_approx(visuals.camera_zoom, zoom), "Automatic camera framing cannot track an unseen enemy: %s/%s -> %s/%s." % [camera, zoom, visuals.camera_position, visuals.camera_zoom])
	driver.free()
	visuals.free()
	radar.free()
