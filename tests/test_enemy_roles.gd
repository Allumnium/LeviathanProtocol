extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func fixture(extra_sentinel := false) -> BattleSimulation:
	var ships: Array[FleetShip] = []
	var fighter := FleetShip.new()
	fighter.initialize(BUILTINS.drone(), 1, "Escort")
	ships.append(fighter)
	var design := Ship.new()
	BUILTINS._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(design, ShipPart.Type.RESEARCH_LAB, Vector2i(2, 0))
	var support := FleetShip.new()
	support.initialize(design, 2, "Lab")
	ships.append(support)
	var aliens: Array[RefCounted] = []
	for role in ["scout", "fighter", "sentinel", "support", "chrysalis"]:
		var alien := AlienShip.threat_variant(role, 0)
		alien.entity_id = role
		aliens.append(alien)
	if extra_sentinel:
		var alien := AlienShip.threat_variant("sentinel", 0)
		alien.entity_id = "sentinel2"
		aliens.append(alien)
	var sim := BattleSimulation.new()
	check(sim.setup_owned(ships, aliens, 0, 0, 42, {"visibility_enabled": true, "enemy_roles": true}), "Initialize distinct roles.")
	for index in range(sim.aliens.size()):
		sim.aliens[index].position = Vector2(index * 20, 0)
	sim.players[0].position = Vector2(80, 0)
	sim.players[1].position = Vector2(0, 200)
	sim.refresh_visibility()
	return sim

func run() -> void:
	test_targeting()
	test_protection()
	test_repairs()
	test_craft()
	test_replay()
	test_frozen_mode()
	if "--capture" in OS.get_cmdline_user_args():
		await native_capture()
	print("Enemy role tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func test_targeting() -> void:
	var sim := fixture()
	var scout: BattleSimulation.Combatant = sim.entities.scout
	check(sim.enemy_roles.choose_target(sim, scout) == sim.players[1], "Scout prefers a visible exposed support hull.")
	sim.players[0].position = Vector2(0, 185)
	sim.refresh_visibility()
	check(sim.enemy_roles.choose_target(sim, scout) == sim.players[0], "A nearby visible escort makes the support hull less exposed.")
	sim.players[1].position = Vector2(1000, 1000)
	sim.refresh_visibility()
	check(sim.enemy_roles.choose_target(sim, scout) != sim.players[1], "Scouts do not inspect hidden support positions or loadouts.")
	var fighter: BattleSimulation.Combatant = sim.entities.fighter
	fighter.target = sim.players[0]
	var pressure: Vector2 = sim.enemy_roles.steering(sim, fighter, Vector2.LEFT)
	check(pressure.is_equal_approx(fighter.position.direction_to(sim.players[0].position)), "Fighter applies direct close-range pressure.")
	var flank := sim._flyby_direction(scout, sim.players[0])
	check(absf(flank.dot(scout.position.direction_to(sim.players[0].position))) < 0.999, "Scout approach retains a flank rather than a direct collision line.")

func test_protection() -> void:
	var sim := fixture(true)
	var target: BattleSimulation.Combatant = sim.entities.fighter
	check(is_equal_approx(sim.enemy_roles.protection(sim, target), 0.8), "Sentinel protects nearby allies with bounded 20% reduction.")
	target.shields = 0
	var hp := target.integrity
	sim._damage(target, 2, sim.player.position, sim.player, "Test")
	check(is_equal_approx(target.integrity, hp - 1.6), "Shared damage pipeline applies one shield field, not duplicate stacking.")
	sim.entities.sentinel.integrity = 0
	check(is_equal_approx(sim.enemy_roles.protection(sim, target), 0.8), "A surviving second Sentinel retains protection.")
	sim.entities.sentinel2.integrity = 0
	check(sim.enemy_roles.protection(sim, target) == 1, "Destroying all sources immediately removes protection.")
	check(sim.enemy_roles.protection(sim, sim.player) == 1, "Enemy shield field cannot protect a hostile player.")

func test_repairs() -> void:
	var sim := fixture()
	var support: BattleSimulation.Combatant = sim.entities.support
	var target: BattleSimulation.Combatant = sim.entities.fighter
	var budget: float = sim.enemy_roles.sources.support.reserve
	target.integrity = 1
	sim.enemy_roles.advance(sim, 1)
	check(target.integrity == 2 and sim.enemy_roles.sources.support.reserve == budget - 1, "Support repairs one living ally and spends a finite reserve.")
	for step in range(20):
		target.integrity = 1
		sim.enemy_roles.advance(sim, 1)
	check(sim.enemy_roles.sources.support.reserve == 0 and target.integrity == 1, "Support cannot heal forever.")
	target.integrity = 0
	sim.enemy_roles.sources.support.reserve = 10.0
	sim.enemy_roles.advance(sim, 1)
	check(target.integrity == 0, "Support never resurrects destroyed hulls.")
	target.integrity = 1
	support.integrity = 0
	sim.enemy_roles.advance(sim, 1)
	check(target.integrity == 1, "Destroying Support stops repair immediately.")

func test_craft() -> void:
	var sim := fixture()
	var source: BattleSimulation.Combatant = sim.entities.chrysalis
	sim.enemy_roles.advance(sim, 4)
	check(sim.other_entities.size() == 1 and sim.enemy_roles.sources.chrysalis.remaining == 1, "Chrysalis incubates its first priced drone after four simulation seconds.")
	var craft: BattleSimulation.Combatant = sim.other_entities[0]
	check(craft.has_tag("craft") and craft.has_tag("summon") and craft.faction == 1 and craft.radius == 6, "Launched drone is a small faction-aware strike craft.")
	sim.enemy_roles.advance(sim, 6)
	sim.enemy_roles.advance(sim, 100)
	check(sim.other_entities.size() == 2 and sim.enemy_roles.sources.chrysalis.remaining == 0, "Tier-zero Chrysalis has exactly two drones, never an infinite factory.")
	for drone in sim.other_entities:
		sim.damage_entity(drone.entity_id, 10000)
	check(sim.drops.is_empty(), "Summoned drones cannot add salvage or enlarge the frozen reward.")
	var cap := fixture()
	while cap._members.size() < 64:
		var extra := BattleSimulation.Combatant.new()
		extra.entity_id = "cap/%d" % cap._members.size()
		extra.stats = ShipStats.new()
		extra.stats.integrity = 1
		extra.integrity = 1
		extra.faction = 1
		extra.tags.assign({"combatant": true, "craft": true, "summon": true})
		check(cap.register_entity(extra), "Register cap fixture.")
	cap.enemy_roles.advance(cap, 4)
	check(cap._members.size() == 64 and cap.enemy_roles.sources.chrysalis.remaining == 2, "Full 64-entity budget defers launch without consuming a reserve.")
	cap.other_entities[0].integrity = 0
	cap.enemy_roles.advance(cap, 0.1)
	check(cap.enemy_roles.sources.chrysalis.remaining == 1, "A freed live slot releases one finite queued drone.")
	var cancelled := fixture()
	cancelled.entities.chrysalis.integrity = 0
	cancelled.enemy_roles.advance(cancelled, 100)
	check(cancelled.other_entities.is_empty(), "Destroying a Chrysalis permanently cancels its unlaunched reserve for the attempt.")
	for alien in sim.aliens:
		sim.damage_entity(alien.entity_id, 10000)
	check(sim.objective_complete(), "Summons never extend an ordinary parent/escort objective.")
	check(source != null, "Source identity remains available for replay diagnostics.")

func test_replay() -> void:
	var first := fixture()
	var replay := fixture()
	check(first.issue_command("attack", {"source": first.player.entity_id, "target": "support"}), "Record player target priority.")
	for command: Dictionary in JSON.parse_string(JSON.stringify(first.command_log)):
		check(replay.queue_command(command), "Load role combat command through JSON.")
	for tick in range(600):
		first.advance(1.0 / 30.0)
	for batch in range(150):
		for tick in range(4):
			replay.advance(1.0 / 30.0)
	check(first.authoritative_snapshot() == replay.authoritative_snapshot(), "Normal/accelerated replay includes repair reserves, launches, movement and target decisions.")

func test_frozen_mode() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://enemy-role-tests/run.json"
	check(state.start_new_run(1, 42, false) and state.set_destination(1), "Freeze actual role-aware departure.")
	check(state.battle_support_context().get("enemy_roles", false), "New departures freeze behavior readiness alongside priced rosters.")
	var checkpoint: Dictionary = state._capture_checkpoint()
	checkpoint.encounter_progress["1"].deployment.shared_context.enemy_roles = "bad"
	check(not RunCheckpoint.valid(checkpoint), "Malformed frozen behavior mode is rejected.")
	checkpoint.encounter_progress["1"].deployment.shared_context.erase("enemy_roles")
	check(RunCheckpoint.valid(checkpoint), "Older pending deployments without role mode retain their original behavior.")

func native_capture() -> void:
	root.size = Vector2i(640, 360)
	var sim := fixture()
	sim.players[0].position = Vector2(-180, 0)
	sim.players[1].position = Vector2(-20, -60)
	var positions := {"scout": Vector2(-120, 40), "fighter": Vector2(-40, 40), "sentinel": Vector2(40, 20),
		"support": Vector2(90, 30), "chrysalis": Vector2(170, 0)}
	for id: String in positions:
		sim.entities[id].position = positions[id]
		sim.entities[id].previous_position = positions[id]
	sim.entities.fighter.integrity = 2
	sim.enemy_roles.advance(sim, 4)
	sim.refresh_visibility()
	var view = load("res://scripts/battle_visuals.gd").new()
	view.simulation = sim
	view.size = Vector2(640, 360)
	view.camera_zoom = 1.0
	root.add_child(view)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/enemy-roles/roles-640.png")
	view.queue_free()
	await process_frame
