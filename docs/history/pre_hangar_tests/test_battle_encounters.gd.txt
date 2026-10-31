extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func plan(seed_value := 42, layout := "corridor") -> Dictionary:
	var result := EncounterGenerator.generate(seed_value, 7, 3, 1, "relay_defense", 2)
	result["arena_layout"] = layout
	return result

func fixture(value: Dictionary) -> BattleSimulation:
	var ships: Array[FleetShip] = []
	for index in range(3):
		var owned := FleetShip.new()
		owned.initialize(BUILTINS.drone(), index + 1, "Drone")
		owned.formation = Vector2i(index, 0)
		ships.append(owned)
	var sim := BattleSimulation.new()
	check(sim.setup_owned(ships, EncounterGenerator.initial_fleet(value), 0.5, 0, 42,
		{"visibility_enabled": true, "enemy_roles": true, "encounter_plan": value}), "Initialize frozen finite waves.")
	return sim

func run() -> void:
	var value := plan()
	check(EncounterGenerator.valid(value), "Wave roster retains its single priced budget.")
	var sim := fixture(value)
	check(sim.set_objective_targets(EncounterGenerator.objective_ids(value)), "Announced future identities are legal objective targets.")
	check(not sim.set_objective_targets(["invented"]), "Unknown identities still fail closed.")
	for member in sim.aliens:
		member.integrity = 0
	check(not sim.objective_complete(), "Clearing the first wave cannot win early.")
	for tick in range(179):
		sim.advance(1.0 / 30)
	check(sim.encounter.wave == 1 and sim.phase == BattleSimulation.Phase.COMBAT, "Wave two waits six simulation seconds.")
	sim.advance(1.0 / 30)
	check(sim.encounter.wave == 2, "Second wave arrives at six seconds.")
	for tick in range(180):
		sim.advance(1.0 / 30)
	check(sim.encounter.wave == 3 and sim.encounter.pending.is_empty(), "Final finite wave arrives at twelve seconds.")
	check(sim.aliens.size() == value.roster.size(), "Exactly the frozen roster spawns once.")
	for member in sim.aliens:
		member.integrity = 0
	check(sim.objective_complete(), "All three waves are required and sufficient.")
	check(sim.encounter.steer(Vector2(0, 260), Vector2.RIGHT * 20, 20).y < 0, "Corridor steers both factions inward.")
	check(sim.encounter.steer(Vector2(0, -260), Vector2.LEFT * 20, 20).y > 0, "Both corridor boundaries work.")
	check(sim.encounter.steer(Vector2.ZERO, Vector2.RIGHT * 20, 20) == Vector2.RIGHT * 20, "Central space keeps normal steering.")
	test_replay()
	test_capacity()
	test_late_roles()
	test_finishing_shot()
	test_campaign()
	await test_controller()
	for seed_value in [42, 1357, 12345]:
		for layout in ["open", "corridor"]:
			var actual := fixture(plan(seed_value, layout))
			for tick in range(30 * 180):
				actual.advance(1.0 / 30)
				if actual.phase != BattleSimulation.Phase.COMBAT:
					break
			check(actual.phase == BattleSimulation.Phase.VICTORY, "Ordinary Drones win %s seed %d on Auto." % [layout, seed_value])
			check(actual.encounter.pending.is_empty(), "Auto victory never skips a wave.")
	if "--capture" in OS.get_cmdline_user_args():
		await native_capture()
	print("Battle encounter tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func test_replay() -> void:
	var value: Dictionary = JSON.parse_string(JSON.stringify(plan()))
	var reference := fixture(value)
	for tick in range(720):
		reference.advance(1.0 / 30)
	var expected := JSON.stringify(reference.authoritative_snapshot())
	var expected_events := JSON.stringify(reference.event_log)
	for batch in [1, 2, 8]:
		var replay := fixture(value)
		for frame in range(720 / batch):
			for tick in range(batch):
				replay.advance(1.0 / 30)
		check(JSON.stringify(replay.authoritative_snapshot()) == expected, "Wave timing and actor ordering replay across %d-tick frame batches." % batch)
		check(JSON.stringify(replay.event_log) == expected_events, "Wave events replay across %d-tick frame batches." % batch)

func test_capacity() -> void:
	var sim := fixture(plan())
	var blockers: Array = []
	while sim._members.size() < 64:
		var member = sim._create_combatant(sim.players[0].stats)
		member.entity_id = "blocker/%d" % sim._members.size()
		member.position = Vector2.ZERO
		check(sim.register_entity(member), "Register bounded capacity fixture.")
		blockers.append(member)
	sim.encounter.advance(sim, 12)
	check(not sim.encounter.pending.is_empty() and sim._members.size() == 64, "Full live entity budget defers rather than loses or overflows waves.")
	for member in blockers:
		member.integrity = 0
	sim.encounter.advance(sim, 0)
	check(sim.encounter.pending.is_empty(), "Deferred finite roster arrives when live capacity frees.")
	var last_wave := 0
	for event: Dictionary in sim.event_log:
		if event.type == "wave_spawn":
			check(int(event.details.wave) >= last_wave, "Capacity-delayed waves retain their announced order.")
			last_wave = int(event.details.wave)

func test_late_roles() -> void:
	var value: Dictionary = {}
	for seed_value in range(256):
		var candidate := EncounterGenerator.generate(seed_value, 7, 24, 2, "relay_defense", 14)
		if candidate.roster.any(func(entry: Dictionary) -> bool: return int(entry.wave) == 0 and entry.role == "support") \
			and candidate.roster.any(func(entry: Dictionary) -> bool: return int(entry.wave) > 0 and entry.role in ["support", "chrysalis"]):
			value = candidate
			break
	check(not value.is_empty(), "Find a priced roster with early and late support sources.")
	if value.is_empty():
		return
	value["arena_layout"] = "open"
	var sim := fixture(value)
	var existing: Dictionary = sim.enemy_roles.sources.duplicate(true)
	for id: String in existing:
		if existing[id].role == "support":
			sim.enemy_roles.sources[id].reserve = 0.0
	sim.encounter.advance(sim, 12)
	var late_sources := 0
	for member in sim.aliens:
		if member.alien.role_id in ["support", "chrysalis"]:
			check(sim.enemy_roles.sources.has(member.entity_id), "Timed support/carrier arrivals initialize their finite reserves.")
			if member.alien.wave_index > 0:
				late_sources += 1
			elif member.alien.role_id == "support":
				check(sim.enemy_roles.sources[member.entity_id].reserve == 0, "New waves never replenish an existing exhausted repair reserve.")
	check(late_sources > 0, "Late-wave source fixture exercises support or carrier arrivals.")

func test_finishing_shot() -> void:
	var sim := fixture(plan())
	sim.visibility_enabled = false
	for index in range(1, sim.aliens.size()):
		sim.aliens[index].integrity = 0
	var shot := BattleSimulation.Projectile.new()
	shot.target = sim.aliens[0]
	shot.source = sim.players[0]
	shot.position = shot.target.position
	shot.damage = 10000
	shot.is_player = true
	sim.projectiles.append(shot)
	check(sim.get_finishing_projectile() == null, "A cleared early wave cannot trigger the final-kill cinematic.")

func test_campaign() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://battle-encounters/run.json"
	check(state.start_new_run(1, 42), "Generate new varied campaign.")
	var kinds := {}
	for value: Dictionary in state.frozen_encounters.values():
		kinds[value.template_id] = true
	check(kinds.has("relay_defense") and kinds.has("patrol"), "Campaign contains patrol and finite defense.")
	check(state.set_destination(state.get_reachable_nodes(0)[0]), "Freeze actual departure context.")
	var checkpoint: Dictionary = state._capture_checkpoint()
	check(RunCheckpoint.valid(checkpoint), "New encounter plan survives checkpoint validation.")
	var key := str(state.destination_node_id)
	checkpoint.encounter_progress[key].deployment.shared_context.encounter_plan.arena_layout = "bad"
	check(not RunCheckpoint.valid(checkpoint), "Reject corrupt arena identifiers.")
	checkpoint.encounter_progress[key].deployment.shared_context.encounter_plan.arena_layout = "corridor"
	check(not RunCheckpoint.valid(checkpoint), "Reject a valid but changed frozen plan.")
	checkpoint.encounter_progress[key].deployment.shared_context.erase("encounter_plan")
	check(not RunCheckpoint.valid(checkpoint), "New pending waves cannot silently lose their plan.")
	checkpoint.encounters[key].erase("arena_layout")
	check(RunCheckpoint.valid(checkpoint), "Older pending contexts remain valid without the new plan.")

func test_controller() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://battle-encounters/controller.json"
	state.reduced_motion = true
	check(state.start_new_run(1, 42, false), "Prepare actual controller fixture.")
	var value := EncounterGenerator.generate(42, 1, 1, 1, "relay_defense")
	value["arena_layout"] = "corridor"
	state.frozen_encounters["1"] = value
	check(state.set_destination(1), "Save finite defense departure before loading controller.")
	root.size = Vector2i(640, 360)
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_physics_process(false)
	await process_frame
	battle.pause_button.button_pressed = true
	var before: float = battle.simulation.encounter.clock
	for frame in range(60):
		battle._physics_process(1.0 / 30)
	check(battle.simulation.encounter.clock == before, "Pause freezes reinforcement timers in the live controller.")
	check(battle.objective_label.get_rect().end.x < 640, "Actual wave HUD fits 640 pixels.")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/ui-review/encounter-controller-640.png")
	battle.pause_button.button_pressed = false
	battle.fast_forward_button.button_pressed = true
	for frame in range(30 * 180):
		battle._physics_process(1.0 / 30)
		if battle.simulation.phase != BattleSimulation.Phase.COMBAT:
			break
	check(battle.simulation.phase == BattleSimulation.Phase.VICTORY and battle.simulation.encounter.pending.is_empty(), "Actual 2x controller wins only after the final wave.")
	for frame in range(60):
		battle._physics_process(1.0 / 30)
	check(not state.battle_pending and state.current_node_id == 1, "Controller settles the finite encounter once.")
	var paid: int = state.credits
	check(not state.settle_battle(battle.simulation) and state.credits == paid, "Duplicate wave settlement pays no second reward.")
	check(state.load_run_checkpoint(), "Completed wave battle reloads with its journal and frozen plan.")
	battle.free()
	current_scene = null

func native_capture() -> void:
	root.size = Vector2i(640, 360)
	var sim := fixture(plan())
	for index in range(sim.players.size()):
		sim.players[index].position = Vector2(-100, index * 35)
	for index in range(sim.aliens.size()):
		sim.aliens[index].position = Vector2(100, index * 35)
	sim.refresh_visibility()
	var view = load("res://scripts/battle_visuals.gd").new()
	view.simulation = sim
	view.size = Vector2(640, 360)
	view.camera_zoom = 0.65
	root.add_child(view)
	var hud := Label.new()
	hud.theme = load("res://themes/ui_theme.tres")
	hud.text = sim.encounter.label(sim)
	hud.position = Vector2(8, 38)
	view.add_child(hud)
	await process_frame
	await RenderingServer.frame_post_draw
	check(hud.get_rect().end.x < 640, "Wave HUD fits the minimum viewport with the shared font.")
	root.get_texture().get_image().save_png("res://docs/ui-review/encounters-640.png")
	view.queue_free()
	await process_frame
