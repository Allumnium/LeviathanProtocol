extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func fixture(field = null, policy := {"rate": 0.75, "materials": [0, 1]}) -> BattleSimulation:
	var sim := BattleSimulation.new()
	var ship := ShipStats.new()
	ship.integrity = 500
	ship.weapons.append(ShipWeaponStats.new("Test", 1.0, 1.0, 1, 200.0))
	var alien := AlienShip.new("Test", AlienShip.SCOUT_TEXTURE, ship)
	check(sim.setup(ship, [alien], 42), "Set up rock fixture.")
	if field != null:
		check(sim.asteroid_field.configure(field, policy), "Configure valid field.")
		sim.asteroid_field.attach(sim)
	return sim

func single(mass := 8, ore := [11, 7, 5, 3]) -> Dictionary:
	var field := AsteroidField.new()
	check(field.add_root("root", mass, Vector2.ZERO, Vector2(4, 0), ore), "Add root.")
	return field.snapshot()

func kill_tree(sim: BattleSimulation, source := "") -> void:
	for generation in range(4):
		for id in sim.asteroid_field.records.keys():
			var record: Dictionary = sim.asteroid_field.records[id]
			if record.status == "alive":
				check(sim.damage_entity(id, 100000, source), "Either faction may fracture a rock through shared damage.")
		sim.asteroid_field._flush_fractures(sim)

func run() -> void:
	test_actors()
	test_fractures()
	test_collisions()
	test_ore()
	test_limits()
	test_replay()
	test_persistence()
	if "--capture" in OS.get_cmdline_user_args():
		await capture()
	print("Asteroid tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func test_actors() -> void:
	var seed_field := AsteroidField.generate(42, 12)
	check(seed_field == AsteroidField.generate(42, 12) and AsteroidField.valid(seed_field), "Seed freezes identities, ore, motion and empty distribution.")
	check(seed_field.roots.values().filter(func(r: Dictionary) -> bool: return r.ore == [0, 0, 0, 0]).size() == 6, "Half the initial roots are empty.")
	var sim := fixture(single())
	var rock: BattleSimulation.Combatant = sim.entities.root
	check(rock.faction == 2 and rock.has_tag("asteroid") and rock.stats.weight == 8 and rock.integrity == 96, "Neutral mass/HP use four specified classes.")
	check(is_equal_approx(rock.radius, 8 * sqrt(8.0)), "Collision radius matches sprite radius.")
	check(sim.request_attack(sim.player.entity_id, "root"), "Manual attack accepts neutral rock.")
	check(sim.damage_entity("root", 1, sim.aliens[0].entity_id), "Aliens damage neutral rocks through the same pipeline.")
	var before := rock.position
	sim.asteroid_field.advance(sim, 0.1)
	check(rock.position != before and rock.integrity == 95, "Rock drifts with independent velocity and retains damage.")
	sim.damage_entity(sim.aliens[0].entity_id, 100000)
	check(sim.objective_complete(), "Ordinary victory does not require neutral rocks.")
	check(sim.set_destroy_all_neutral_targets(true) and not sim.objective_complete(), "Opt-in neutral cleanup includes living rocks.")

func test_fractures() -> void:
	var sim := fixture(single())
	sim.abilities.resource_knowledge[0]["root"] = {"materials": [11, 7, 5, 3]}
	sim.damage_entity("root", 1000)
	check(not sim.entities.root.targetable and not sim.entities.root.is_alive(), "Destroyed parent has no live target/collider.")
	sim.asteroid_field._flush_fractures(sim)
	check(sim.entities["root/0"].integrity == 48 and sim.entities["root/1"].integrity == 48, "Two children each have half mass and class HP.")
	check(sim.asteroid_field.records["root/0"].grace == 0.5, "Children receive half-second collision grace.")
	check(sim.abilities.resource_knowledge[0].has("root/0") and not sim.abilities.resource_knowledge[1].has("root/0"), "Only legitimate discovery follows fragments.")
	check(AsteroidField.valid(sim.asteroid_field.snapshot()), "Split snapshot conserves mass and ore.")
	kill_tree(sim, sim.aliens[0].entity_id)
	var leaves: Array = sim.asteroid_field.records.values().filter(func(r: Dictionary) -> bool: return r.status == "terminal")
	check(leaves.size() == 8, "Mass-eight root terminates in exactly eight mass-one leaves.")
	check(sim.drops.is_empty(), "Fractures create no enemy salvage or player wreck material.")
	var sum := [0, 0, 0, 0]
	for leaf: Dictionary in leaves:
		for c in range(4):
			sum[c] += leaf.ore[c]
	check(sum == [11, 7, 5, 3], "Alien-caused complete fragmentation conserves every category.")
	var corrupt := sim.asteroid_field.snapshot()
	corrupt.records["root/0/0/0"].ore[0] += 1
	check(not AsteroidField.valid(corrupt), "Inflated fragment ore is rejected.")

func test_collisions() -> void:
	var sim := fixture(single(2))
	var rock: BattleSimulation.Combatant = sim.entities.root
	sim.player.position = Vector2.ZERO
	var hp := sim.player.integrity
	sim.asteroid_field.advance(sim, 0.01)
	check(sim.player.integrity == hp - 12 and rock.integrity == 18, "Impact deals six times pre-impact mass, rock loses quarter max HP.")
	for step in range(20):
		sim.player.position = rock.position
		sim.asteroid_field.advance(sim, 0.01)
	check(sim.player.integrity == hp - 12, "Repeated overlap within cooldown cannot apply per-frame damage.")
	check(sim.player.position.distance_to(rock.position) > sim.player.radius + rock.radius, "Overlap separates bodies.")
	sim.asteroid_field.advance(sim, 0.8)
	sim.player.position = rock.position
	sim.asteroid_field.advance(sim, 0.01)
	check(sim.player.integrity == hp - 24, "Pair can collide again after 0.75 seconds.")
	var other := fixture(single(1))
	other.asteroid_field.records.root.grace = 0.5
	other.aliens[0].position = Vector2.ZERO
	var alien_hp := other.aliens[0].integrity
	other.asteroid_field.advance(other, 0.1)
	check(other.aliens[0].integrity == alien_hp, "Birth grace prevents immediate child damage to either side.")
	other.asteroid_field.records.root.grace = 0
	other.asteroid_field.advance(other, 0.01)
	check(other.aliens[0].integrity == alien_hp - 6, "Aliens obey identical collision damage.")
	var blocker := fixture(single(1))
	var shot := BattleSimulation.Projectile.new()
	shot.position = Vector2(-40, 0)
	shot.target = blocker.aliens[0]
	shot.target.position = Vector2(40, 0)
	shot.damage = 5
	shot.source = blocker.player
	blocker.projectiles.append(shot)
	blocker._update_projectiles(1.0)
	check(blocker.entities.root.integrity == 7 and blocker.aliens[0].integrity == 500, "Physical projectile obstruction damages first rock and shields target behind it.")

func test_ore() -> void:
	var sim := fixture(single())
	kill_tree(sim)
	# Changing equipment after first damage never rerolls the extraction snapshot.
	sim.asteroid_field.extraction = {"rate": 1.0, "materials": [0, 1, 2, 3]}
	for id in sim.asteroid_field.records.keys():
		if sim.asteroid_field.records[id].status == "terminal":
			check(sim.asteroid_field.collect(id, sim), "Collect each terminal fragment once.")
			check(not sim.asteroid_field.collect(id, sim), "Duplicate collection rejected.")
	check(sim.asteroid_field.collected == [8, 5, 0, 0], "Root cumulative floor gives 75% without fragment rounding inflation or locked categories.")
	var data := JSON.parse_string(JSON.stringify(sim.asteroid_field.snapshot())) as Dictionary
	check(AsteroidField.valid(data), "Ore ledger validates through JSON numeric conversion.")
	var restored := fixture(data)
	check(restored.asteroid_field.records.values().all(func(r: Dictionary) -> bool: return r.status != "terminal" or r.claimed), "Reload cannot regenerate claimed fragments.")
	var failure := fixture(single(1, [4, 0, 0, 0]))
	failure.damage_entity("root", 100)
	var before := failure.asteroid_field.snapshot()
	failure.asteroid_field.pickup_commit = func(_id: String, _materials: Array, _field: Dictionary) -> bool: return false
	check(not failure.asteroid_field.collect("root", failure) and failure.asteroid_field.snapshot() == before, "Failed persistence leaves pickup/root payment retryable.")
	var batch := fixture(single(2, [8, 0, 0, 0]))
	kill_tree(batch)
	var writes := [0]
	batch.asteroid_field.pickup_commit = func(_id: String, _materials: Array, _field: Dictionary) -> bool:
		writes[0] += 1
		return true
	batch.player.position = Vector2.ZERO
	batch.asteroid_field._collect_nearby(batch)
	check(writes[0] == 1 and batch.asteroid_field.collected == [6, 0, 0, 0], "Nearby fragments share one atomic write and exact cumulative yield.")

func test_limits() -> void:
	var field := AsteroidField.new()
	for index in range(48):
		field.add_root("r%d" % index, 8, Vector2(index * 10, 200), Vector2.ZERO, [8, 0, 0, 0])
	var sim := fixture(field.snapshot())
	for id in field.records:
		sim.damage_entity(id, 1000)
	sim.asteroid_field._flush_fractures(sim)
	check(sim.asteroid_field.records.values().filter(func(r: Dictionary) -> bool: return r.status == "alive").size() == 96, "48 roots split to the separate 96-rock cap.")
	sim.damage_entity("r0/0", 1000)
	sim.asteroid_field._flush_fractures(sim)
	check(sim.asteroid_field.records["r0/0"].status == "pending" and not sim.entities["r0/0"].targetable, "Full field retains inert pending parent instead of invisible collider.")
	sim.damage_entity("r0/1", 1000)
	sim.asteroid_field._flush_fractures(sim)
	check(sim.asteroid_field.records["r0/0"].status == "split" and sim.asteroid_field.records["r0/1"].status == "pending", "Opening space releases one deferred fracture deterministically.")
	check(AsteroidField.valid(sim.asteroid_field.snapshot()), "Cap deferral preserves lineage, mass and mineral budgets.")

func test_replay() -> void:
	var first := fixture(AsteroidField.generate(111, 12))
	var second := fixture(JSON.parse_string(JSON.stringify(AsteroidField.generate(111, 12))))
	for sim in [first, second]:
		sim.request_attack(sim.player.entity_id, "rock/0")
	for step in range(120):
		first.advance(1.0 / 30.0)
	for batch in range(30):
		for step in range(4):
			second.advance(1.0 / 30.0)
	var a := first.authoritative_snapshot()
	var b := second.authoritative_snapshot()
	check(JSON.stringify(a) == JSON.stringify(b), "Normal/accelerated batches reproduce motion, collisions, fragments and pickups.")

func test_persistence() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://asteroid-tests/run.json"
	check(state.start_new_run(1, 42, false) and state.set_destination(1), "Start real deployment for field persistence.")
	var field := single(2, [8, 0, 0, 0])
	state.encounter_progress["1"].field["asteroids"] = field
	var context: Dictionary = state.battle_support_context()
	context.erase("mining_materials") # Detached extraction-policy fixture, not live tools.
	context["extraction"] = {"rate": 0.75, "materials": [0, 1]}
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0.3, 0, 42, context), "Real deployment restores asteroid field.")
	sim.battle_id = state.battle_identity()
	sim.asteroid_field.pickup_commit = func(id: String, materials: Array, next: Dictionary) -> bool: return state.commit_asteroid_pickup(sim, id, materials, next)
	kill_tree(sim)
	var before: int = state.red_tiles_available
	check(sim.asteroid_field.collect("root/0", sim), "First terminal pickup commits actual material and field together.")
	check(state.red_tiles_available == before + 3, "One half of eight at 75% pays three.")
	check(state.load_run_checkpoint(), "Reload actual committed field.")
	var restored: Dictionary = state.encounter_progress["1"].field.asteroids
	check(restored.records["root/0"].claimed and not restored.records["root/1"].claimed, "Consumed and unclaimed leaves survive interrupted battle recovery.")
	sim.asteroid_field.pickup_commit = Callable()
	sim = BattleSimulation.new()
	context = state.battle_support_context()
	context.erase("mining_materials")
	context["extraction"] = {"rate": 1.0, "materials": [0, 1, 2, 3]}
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0.3, 0, 42, context), "Retry restores remaining field rather than generating roots.")
	sim.battle_id = state.battle_identity()
	sim.asteroid_field.pickup_commit = func(id: String, materials: Array, next: Dictionary) -> bool: return state.commit_asteroid_pickup(sim, id, materials, next)
	var proposal: Dictionary = sim.asteroid_field.propose_pickup("root/1")
	check(not state.commit_asteroid_pickup(sim, "root/1", [999, 0, 0, 0], proposal.field), "Forged payout cannot bypass the authoritative root calculation.")
	var good_path: String = state.run_save_path
	var blocker := FileAccess.open("user://asteroid-tests/blocker", FileAccess.WRITE)
	blocker.store_string("file")
	blocker.close()
	state.run_save_path = "user://asteroid-tests/blocker/run.json"
	check(not sim.asteroid_field.collect("root/1", sim) and state.red_tiles_available == before + 3
		and not sim.asteroid_field.records["root/1"].claimed, "Real failed checkpoint pays nothing and does not consume remaining pickup.")
	state.run_save_path = good_path
	check(not sim.asteroid_field.collect("root/0", sim) and sim.asteroid_field.collect("root/1", sim), "Retry pays remaining half once at original rate despite changed equipment.")
	check(state.red_tiles_available == before + 6, "Full root pays six, never more than its frozen 75%.")
	sim.phase = BattleSimulation.Phase.WITHDRAWN
	check(state.settle_battle(sim) and state.load_run_checkpoint(), "Withdrawal checkpoints surviving rocks/lineage alongside losses.")
	check(state.red_tiles_available == before + 6 and state.encounter_progress["1"].field.asteroids.roots.root.paid[0] == 6, "Withdrawal/reload retains ore without granting victory salvage.")
	sim.asteroid_field.pickup_commit = Callable()

func capture() -> void:
	root.size = Vector2i(640, 360)
	var state := root.get_node("GameState")
	state.start_new_run(1, 42, false)
	state.set_destination(1)
	state.encounter_progress["1"].field["asteroids"] = AsteroidField.generate(42, 12)
	var battle = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	await process_frame
	battle.set_physics_process(false)
	battle.simulation.players[0].position = Vector2(-160, 0)
	for id in battle.simulation.asteroid_field.records:
		var actor: BattleSimulation.Combatant = battle.simulation.entities[id]
		actor.position = Vector2(-120 + int(id.get_slice("/", 1)) * 34, 70)
		actor.previous_position = actor.position
	battle.simulation.abilities.state.auto.scan = false
	battle.simulation.abilities.state.cooldowns.clear()
	battle.simulation.refresh_visibility()
	battle.visuals.camera_zoom = 0.7
	battle.visuals.camera_position = Vector2.ZERO
	battle.visuals.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://.local/asteroids/field.png")
	battle.queue_free()
	await process_frame
