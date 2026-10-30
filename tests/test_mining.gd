extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func design(type: int, processor := false) -> Ship:
	var ship := Ship.new()
	BUILTINS._add_part(ship, ShipPart.Type.COMMAND_CENTER, Vector2i(0, 1))
	BUILTINS._add_part(ship, type, Vector2i(2, 0))
	BUILTINS._add_part(ship, ShipPart.Type.THRUSTER, Vector2i(0, 4))
	if type == ShipPart.Type.EXTRACTION_DRILL:
		# Redundant propulsion lets the complete-root route survive one exposed
		# engine loss; ordinary component destruction still matters while drilling.
		BUILTINS._add_part(ship, ShipPart.Type.THRUSTER, Vector2i(3, 4))
	if type == ShipPart.Type.SEISMIC_CUTTER:
		BUILTINS._add_part(ship, ShipPart.Type.MINI_TURRET, Vector2i(0, 0))
	if processor:
		BUILTINS._add_part(ship, ShipPart.Type.ORE_PROCESSOR, Vector2i(5, 0))
		BUILTINS._add_part(ship, ShipPart.Type.ORE_PROCESSOR, Vector2i(8, 0))
	return ship

func fixture(type := ShipPart.Type.MINING_LASER, processor := false) -> BattleSimulation:
	var owned := FleetShip.new()
	check(owned.initialize(design(type, processor), 100, "Miner"), "Construct physical mining recipe.")
	var field := AsteroidField.new()
	field.add_root("root", 2, Vector2(100, 0), Vector2(1, 0), [11, 9, 7, 5])
	var sim := BattleSimulation.new()
	var context := {"visibility_enabled": true, "mining_materials": [0, 1], "asteroids": field.snapshot(),
		"ability_ids": ["scan", "seismic_cut"]}
	var aliens: Array[RefCounted] = []
	aliens.assign(AlienShip.create_random_fleet(1, 1.0, 42))
	check(sim.setup_owned([owned], aliens, 0, 0, 42, context), "Mining simulation initializes.")
	sim.player.position = Vector2.ZERO
	for alien in sim.aliens:
		alien.position = Vector2(750, 500)
		alien.stats.weapons.clear()
		alien.cooldowns.clear()
		alien.stats.thrust = 0
		sim._refresh_mobility(alien)
	sim.refresh_visibility()
	return sim

func run() -> void:
	test_research()
	test_rates()
	test_visibility_and_ranges()
	test_auto()
	test_seismic()
	test_campaign_fields()
	test_live_pickup()
	test_pickup_replay()
	if "--capture" in OS.get_cmdline_user_args():
		await native_ui()
	print("Mining tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func test_research() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://mining-tests/run.json"
	check(state.start_new_run(1, 42), "Start research fixture.")
	check(not state.is_equipment_available(ShipPart.Type.MINING_LASER), "Mining equipment remains behind research.")
	state.research_points = 120
	check(state.purchase_research("basic_extraction") and state.purchase_research("deep_extraction"), "Basic/Deep Extraction work without optional spectroscopy.")
	check(not state.current_research_ids.has("mineral_spectroscopy") and state._mining_materials() == [0, 1, 2, 3], "Material access is granted separately from optional overlays.")
	state.credits = 2000
	check(state.purchase_ship(design(ShipPart.Type.MINING_LASER), "Miner") and state.load_run_checkpoint(), "Actual researched construction and mixed general families persist.")
	check(state.is_equipment_available(ShipPart.Type.SEISMIC_CUTTER) and not state.is_equipment_available(ShipPart.Type.PLANETCRACKER_CORE), "Deep tools work; endpoint stays gated.")
	check(not GameDefinitions.find("research", "mineral_spectroscopy").implemented and not GameDefinitions.find("research", "sensor_networks").implemented, "Optional spectroscopy and sensor upgrades stay deferred.")

func test_rates() -> void:
	for type in [ShipPart.Type.MINING_LASER, ShipPart.Type.EXTRACTION_DRILL]:
		var sim := fixture(type)
		var name := "Mining Laser" if type == ShipPart.Type.MINING_LASER else "Extraction Drill"
		var expected := 0.75 if type == ShipPart.Type.MINING_LASER else 1.0
		check(MiningRules.snapshot(sim, sim.player, name).rate == expected, "Laser/Drill recover 75/100%.")
		check(MiningRules.snapshot(sim, sim.player, "Mini Turret").rate == 0.25, "Other weapons recover 25% only with operational eligible tools.")
		sim._damage(sim.entities.root, 1.5, sim.player.position, sim.player, name)
		check(sim.entities.root.integrity == 18 and sim.asteroid_field.roots.root.extraction.rate == expected, "Mining damage is four times ship damage and snapshots first-hit extraction.")
		for unit: Dictionary in sim.player.owned_ship.units:
			if unit.part != null and unit.part.type == type:
				unit.hp = 0
		check(MiningRules.snapshot(sim, sim.player, name).rate == 0, "Destroyed tools cannot enable new root extraction.")
		check(sim.asteroid_field.roots.root.extraction.rate == expected, "Existing roots keep original extraction after source loss.")
	var enhanced := fixture(ShipPart.Type.MINING_LASER, true)
	check(is_equal_approx(MiningRules.snapshot(enhanced, enhanced.player, "Mining Laser").rate, 0.9), "Two processors add strongest-only 15 points, not 30.")
	check(MiningRules.snapshot(enhanced, enhanced.player, "Extraction Drill").rate == 1, "Recovery is capped at 100%.")
	var unarmed := fixture()
	for unit: Dictionary in unarmed.player.owned_ship.units:
		if unit.part != null and unit.part.type == ShipPart.Type.MINING_LASER:
			unit.hp = 0
	unarmed._damage(unarmed.entities.root, 1000, Vector2.ZERO, unarmed.aliens[0], "Alien bullet")
	check(unarmed.asteroid_field.roots.root.extraction.rate == 0, "Alien damage cannot extract ore for a fleet without living mining equipment.")

func test_visibility_and_ranges() -> void:
	var sim := fixture(ShipPart.Type.EXTRACTION_DRILL)
	var rock: BattleSimulation.Combatant = sim.entities.root
	check(MiningRules.target(sim, sim.player) == null, "Unscanned contents never select a mining target.")
	sim.abilities.resource_knowledge[0]["root"] = {"materials": [0, 0, 0, 0]}
	check(MiningRules.target(sim, sim.player) == null, "Known empty rocks are skipped without reading live secret ore.")
	sim.abilities.resource_knowledge[0]["root"] = {"materials": [0, 0, 4, 0]}
	check(MiningRules.target(sim, sim.player) == null, "Tech-only deposits stay ineligible before Deep Extraction.")
	sim.abilities.resource_knowledge[0]["root"] = {"materials": [11, 9, 7, 5]}
	check(MiningRules.target(sim, sim.player) == rock, "Visible scanned eligible rock is pursued.")
	rock.position = Vector2(600, 0)
	sim.refresh_visibility()
	check(MiningRules.target(sim, sim.player) == null, "Discovery never grants moving-rock tracking outside sight.")
	var weapon: ShipWeaponStats = sim.player.stats.weapons[0]
	var origin := sim._get_weapon_origin(sim.player, weapon)
	rock.position = origin + Vector2.RIGHT * (45 + rock.radius)
	check(MiningRules.in_range(origin, rock, 45), "Tool range reaches exact component-to-surface boundary.")
	rock.position.x += 0.1
	check(not MiningRules.in_range(origin, rock, 45), "Tool cannot reach past surface boundary.")
	rock.position = Vector2(55, 0)
	sim.refresh_visibility()
	sim.player.velocity = Vector2(60, 0)
	var desired := MiningRules.avoidance(sim, sim.player, Vector2(60, 0))
	check(desired != Vector2(60, 0), "Visible collision course produces steering avoidance.")
	rock.position = Vector2(600, 0)
	sim.refresh_visibility()
	check(MiningRules.avoidance(sim, sim.player, Vector2(60, 0)) == Vector2(60, 0), "Avoidance never reads hidden rock positions.")

func test_auto() -> void:
	for type in [ShipPart.Type.MINING_LASER, ShipPart.Type.EXTRACTION_DRILL]:
		var sim := fixture(type)
		for step in range(1800):
			sim.advance(1.0 / 30.0)
			if sim.asteroid_field.roots.root.processed[0] == 11:
				break
		var policy: Dictionary = sim.asteroid_field.roots.root.extraction
		print("Mining Auto ", type, ": paid ", sim.asteroid_field.roots.root.paid, "; damage ", sim.player.damage_taken, "; policy ", policy)
		var expected := 8 if type == ShipPart.Type.MINING_LASER else 11
		check(sim.abilities.resource_knowledge[0].has("root") and sim.asteroid_field.roots.root.paid[0] == expected, "Auto scans, approaches, mines and collects the entire finite root without pointer control.")
		check(sim.player.damage_taken <= 12, "Close drilling avoids repeated collisions.")
		check(sim.asteroid_field.roots.root.paid[2] == 0 and sim.asteroid_field.roots.root.paid[3] == 0, "Basic tools never pay locked materials.")
		check(AsteroidField.valid(sim.asteroid_field.snapshot()), "Live mining conserves root budgets.")

func test_seismic() -> void:
	var sim := fixture(ShipPart.Type.SEISMIC_CUTTER)
	var point := sim.entities.root.position
	check(sim.abilities.can_cast(sim, "seismic_cut", point), "Deep Cutter targets a visible rock cluster.")
	check(sim.issue_command("ability_cast", {"ability": "seismic_cut", "position": [point.x, point.y], "source": "", "faction": 0}), "Cutter executes through the shared command/persistence framework.")
	check(sim.abilities.remaining("seismic_cut") == 30 and sim.asteroid_field.records.root.status == "pending", "One finite shared cooldown fractures the parent without granting bonus ore.")
	check(sim.asteroid_field.roots.root.extraction.rate == 0.75, "Cutter snapshots laser extraction rate.")
	check(not sim.abilities.can_cast(sim, "seismic_cut", point), "Another source cannot bypass shared cooldown.")
	var replay := fixture(ShipPart.Type.SEISMIC_CUTTER)
	for command: Dictionary in JSON.parse_string(JSON.stringify(sim.command_log)):
		check(replay.queue_command(command), "Cutter command JSON loads.")
	sim.advance(1.0 / 30.0)
	replay.advance(1.0 / 30.0)
	check(JSON.stringify(sim.authoritative_snapshot()) == JSON.stringify(replay.authoritative_snapshot()), "Cutter replay matches fractures, cooldown and knowledge.")

func test_campaign_fields() -> void:
	var state := root.get_node("GameState")
	check(state.start_new_run(1, 42), "Generate new campaign with finite fields.")
	var count := 0
	for encounter: Dictionary in state.frozen_encounters.values():
		if not encounter.has("asteroids"):
			continue
		count += 1
		check(EncounterGenerator.valid(encounter) and encounter.spent + encounter.hazard_budget <= encounter.budget, "Terrain consumes frozen threat instead of scaling against the player.")
	check(count > 0 and state.load_run_checkpoint(), "Campaign fields are seeded, frozen and reloadable.")
	for encounter: Dictionary in state.frozen_encounters.values():
		if encounter.has("asteroids"):
			var preview: Dictionary = state.node_preview(int(encounter.node_id))
			# Future-act concealment intentionally hides its tactical preview.
			if state.node_visible(int(encounter.node_id)):
				check(preview.text.contains("Asteroids"), "Current-act route preview announces the physical field before departure.")

func test_live_pickup() -> void:
	var state := root.get_node("GameState")
	check(state.start_new_run(1, 42), "Start actual mining/persistence integration.")
	state.research_points = 120
	state.credits = 2000
	check(state.purchase_research("basic_extraction") and state.purchase_research("deep_extraction")
		and state.purchase_ship(design(ShipPart.Type.MINING_LASER), "Miner"), "Research and construct an actual deployed miner.")
	var destination: int = state.get_reachable_nodes(0)[0]
	check(state.set_destination(destination), "Freeze real mining departure.")
	var field := AsteroidField.new()
	field.add_root("root", 1, Vector2(-300, 0), Vector2.ZERO, [4, 4, 4, 4])
	state.encounter_progress[str(destination)].field["asteroids"] = field.snapshot()
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, 42, state.battle_support_context()), "Load frozen unlocked materials and physical miner.")
	sim.battle_id = state.battle_identity()
	var miner: BattleSimulation.Combatant
	for member in sim.players:
		if MiningRules.operational(member, [ShipPart.Type.MINING_LASER]):
			miner = member
	check(miner != null and sim.mining_materials == [0, 1, 2, 3], "Deep Extraction includes Tech/Civic on the real departure.")
	sim._damage(sim.entities.root, 100, miner.position, miner, "Mining Laser")
	sim.asteroid_field.pickup_commit = func(id: String, materials: Array, next: Dictionary) -> bool: return state.commit_asteroid_pickup(sim, id, materials, next)
	var before: Array = state._capture_checkpoint().inventory.duplicate()
	var rp: float = state.research_points
	var time := Time.get_ticks_usec()
	check(sim.asteroid_field.collect("root", sim), "Live mining pickup commits its authoritative production policy.")
	print("Mining pickup checkpoint: %.1f ms" % ((Time.get_ticks_usec() - time) / 1000.0))
	var inventory: Array = state._capture_checkpoint().inventory
	for category in range(4):
		check(inventory[category] == before[category] + 3, "Deep mining pays exactly three of each four-unit category.")
	check(state.research_points == rp, "Mining and battle time generate no research points.")
	sim.phase = BattleSimulation.Phase.WITHDRAWN
	check(state.settle_battle(sim) and state.load_run_checkpoint(), "Live mined ore survives withdrawal/reload with no enemy rewards.")
	check(state.encounter_progress[str(destination)].field.asteroids.records.root.claimed, "Actual campaign retry cannot regenerate the terminal root.")
	sim.asteroid_field.pickup_commit = Callable()

func native_ui() -> void:
	root.size = Vector2i(640, 360)
	var state := root.get_node("GameState")
	check(state.start_new_run(1, 42), "Start native mining UI.")
	state.credits = 2000
	state.research_points = 120
	check(state.purchase_research("basic_extraction") and state.purchase_research("deep_extraction")
		and state.purchase_ship(design(ShipPart.Type.SEISMIC_CUTTER), "Cutter"), "Native Cutter construction.")
	var destination: int = state.get_reachable_nodes(0)[0]
	check(state.set_destination(destination), "Native mining departure.")
	var field := AsteroidField.new()
	field.add_root("root", 8, Vector2(100, 15), Vector2.ZERO, [32, 8, 0, 0])
	state.encounter_progress[str(destination)].field["asteroids"] = field.snapshot()
	var battle = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	await process_frame
	battle.set_physics_process(false)
	battle._auto_camera_active = false
	battle.visuals.camera_position = Vector2.ZERO
	battle.visuals.camera_zoom = 0.9
	var sim: BattleSimulation = battle.simulation
	for index in range(sim.players.size()):
		sim.players[index].position = Vector2(-120 + index * 48, -45)
		sim.players[index].previous_position = sim.players[index].position
	sim.abilities.effects.clear()
	sim.abilities.state.cooldowns.clear()
	sim.abilities.state.auto.scan = false
	sim.abilities.state.auto["seismic_cut"] = false
	sim.refresh_visibility()
	await process_frame
	var bar: Control = battle.ability_bar
	check(bar.action_buttons.has("scan") and bar.action_buttons.has("seismic_cut"), "Both required abilities appear without optional actions.")
	var button: Button = bar.action_buttons.seismic_cut
	check(button.focus_mode == Control.FOCUS_NONE and button.tooltip_text.is_empty(), "New action retains no focus navigation or hover tooltip.")
	var screen := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	root.push_input(motion, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = screen
		click.pressed = pressed
		root.push_input(click, true)
	await process_frame
	check(bar.targeting and bar.selected_id == "seismic_cut", "Real pointer selects Cutter targeting.")
	bar.set_preview(Vector2(100, 15))
	battle.visuals.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(bar.get_global_rect()), "Two-action controls fit 640x360.")
	root.get_texture().get_image().save_png("res://.local/asteroids/mining-ui.png")
	var cast_ok: bool = bar.cast_at(Vector2(100, 15))
	check(cast_ok and sim.abilities.remaining("seismic_cut") == 30, "Native Cutter casts with durable shared cooldown.")
	var target: BattleSimulation.Combatant = sim.entities.root
	screen = battle.visuals.world_transform() * target.position
	motion = InputEventMouseMotion.new()
	motion.position = screen
	root.push_input(motion, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = screen
		click.pressed = pressed
		root.push_input(click, true)
	await process_frame
	check(sim.players.all(func(member: BattleSimulation.Combatant) -> bool: return member.stats.weapons.is_empty() or member.commanded_target == target), "Real click orders armed hulls to attack the visible rock.")
	battle.visuals.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/asteroids/manual-target.png")
	var commands_before: int = sim.command_log.size()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = screen
	press.pressed = true
	root.push_input(press, true)
	for offset: Vector2 in [Vector2(20, 0), Vector2.ZERO]:
		motion = InputEventMouseMotion.new()
		motion.position = screen + offset
		motion.relative = Vector2(20, 0) if offset != Vector2.ZERO else Vector2(-20, 0)
		root.push_input(motion, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = screen
	release.pressed = false
	root.push_input(release, true)
	check(sim.command_log.size() == commands_before, "Dragging out and back pans without issuing an accidental target order.")
	target.position = Vector2(1000, 1000)
	sim.refresh_visibility()
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = screen
		click.pressed = pressed
		root.push_input(click, true)
	await process_frame
	check(sim.players.all(func(member: BattleSimulation.Combatant) -> bool: return member.commanded_target == null), "Clicking empty/hidden space clears orders without selecting hidden actors.")
	battle.queue_free()
	await process_frame

func test_pickup_replay() -> void:
	var original := fixture()
	var attempts := [0]
	original.asteroid_field.pickup_commit = func(_id: String, _materials: Array, _next: Dictionary) -> bool:
		attempts[0] += 1
		return attempts[0] > 1
	var ticks := 0
	for tick in range(1500):
		original.advance(1.0 / 30.0)
		ticks += 1
		if original.asteroid_field.roots.root.processed[0] == 11:
			break
	check(attempts[0] >= 2 and original.command_log.any(func(command: Dictionary) -> bool: return command.type == "pickup_rejection"), "Failed automatic pickup is recorded as external replay input before successful retry.")
	check(original.asteroid_field.roots.root.paid[0] == 8, "Complete automatic root extraction pays the cumulative 75% once.")
	for batch_size in [1, 2, 8]:
		var replay := fixture()
		for command: Dictionary in JSON.parse_string(JSON.stringify(original.command_log)):
			check(replay.queue_command(command), "Load actual mining/IO command history.")
		var remaining := ticks
		while remaining > 0:
			for step in range(mini(batch_size, remaining)):
				replay.advance(1.0 / 30.0)
			remaining -= mini(batch_size, remaining)
		check(original.authoritative_snapshot() == replay.authoritative_snapshot(), "Mining and pickup save rejection replay identically at batch size %d." % batch_size)
		check(original.event_log == replay.event_log, "Pickup rejection preserves event ordering after movement/collision at batch size %d." % batch_size)
