extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func fixture(seed_value := 42, shielded := false) -> BattleSimulation:
	var value := EncounterGenerator.generate(seed_value, 20, 8, 1, "bastion_warden", 4)
	var ships: Array[FleetShip] = []
	for index in range(3):
		var owned := FleetShip.new()
		owned.initialize(BUILTINS.escort() if shielded else BUILTINS.drone(), index + 1, "Test")
		owned.formation = Vector2i(0, index * 2)
		ships.append(owned)
	var sim := BattleSimulation.new()
	check(sim.setup_owned(ships, EncounterGenerator.initial_fleet(value), 0.5, 0, seed_value,
		{"visibility_enabled": true, "enemy_roles": true, "encounter_plan": value}), "Initialize priced body and two independent pylons.")
	return sim

func arrange(sim: BattleSimulation) -> void:
	var body: BattleSimulation.Combatant = sim.entities[sim.encounter.warden.rules.body_id]
	body.position = Vector2.ZERO
	body.previous_position = body.position
	body.heading = 0
	for index in range(sim.players.size()):
		sim.players[index].position = Vector2(150, index * 100)
	for index in range(sim.encounter.warden.rules.pylon_ids.size()):
		sim.entities[sim.encounter.warden.rules.pylon_ids[index]].position = Vector2(-30, -100 if index == 0 else 100)
	sim.refresh_visibility()

func run() -> void:
	test_protection()
	test_lance()
	test_interrupt()
	test_idle_charge()
	test_objective()
	test_auto_dodge()
	test_focus()
	test_replay()
	test_validation()
	test_legacy()
	test_failed_reward()
	for seed_value in [42, 1357, 12345]:
		for shielded in [false, true]:
			var sim := fixture(seed_value, shielded)
			for tick in range(30 * 180):
				sim.advance(1.0 / 30)
				if sim.phase != BattleSimulation.Phase.COMBAT:
					break
			check(sim.phase == BattleSimulation.Phase.VICTORY, "Ordinary %s seed %d wins on Auto." % ["Escorts" if shielded else "Drones", seed_value])
			print("Warden Auto seed %d, shields %s: phase %d, seconds %.1f, surviving %d" % [seed_value, shielded, sim.phase, sim.elapsed, sim.living_player_count()])
	play_act(42, false)
	play_act(1357, true)
	await test_controller()
	if "--capture" in OS.get_cmdline_user_args():
		await native_capture()
	print("Warden tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func test_protection() -> void:
	var sim := fixture()
	var warden = sim.encounter.warden
	var body: BattleSimulation.Combatant = sim.entities[warden.rules.body_id]
	body.shields = 0
	var before := body.integrity
	check(sim.damage_entity(body.entity_id, 1), "Body always accepts ordinary damage.")
	check(is_equal_approx(before - body.integrity, 0.6), "Two pylons reduce body damage by 40%, without invulnerability.")
	sim.damage_entity(warden.rules.pylon_ids[0], 10000)
	before = body.integrity
	sim.damage_entity(body.entity_id, 1)
	check(is_equal_approx(before - body.integrity, 0.8), "One surviving pylon reduces body damage by 20%.")
	sim.damage_entity(warden.rules.pylon_ids[1], 10000)
	check(warden.exposed == 6, "Last pylon opens a six-second vulnerability once.")
	before = body.integrity
	sim.damage_entity(body.entity_id, 1)
	check(is_equal_approx(before - body.integrity, 1.25), "Exposed body takes 25% extra damage.")
	warden.advance(sim, 6)
	check(warden.exposed == 0, "Vulnerability expires without healing/resetting the body.")
	before = body.integrity
	sim.damage_entity(body.entity_id, 1)
	check(is_equal_approx(before - body.integrity, 1), "After vulnerability, ordinary damage remains fully effective.")

func test_lance() -> void:
	var sim := fixture(42, true)
	arrange(sim)
	var warden = sim.encounter.warden
	warden.advance(sim, 8.99)
	check(not warden.charging, "First warning starts at nine seconds.")
	warden.advance(sim, 0.01)
	check(warden.charging and warden.cycle == 1, "Lance warns for three seconds before the twelve-second shot.")
	check(warden.label(sim).ends_with("Lance 3s"), "Floating-point boundaries never display a four-second warning.")
	var locked: Vector2 = warden.direction
	var before := sim.players[0].integrity + sim.players[0].shields
	var off_axis := sim.players[1].integrity + sim.players[1].shields
	var desired: Vector2 = warden.avoidance(sim, sim.players[0], Vector2.LEFT * sim.players[0].speed)
	check(absf(desired.y) > 0, "Visible warning gives ordinary Auto a lateral escape route.")
	warden.advance(sim, 2.99)
	check(warden.charging and sim.players[0].integrity + sim.players[0].shields == before, "Telegraph causes no damage.")
	warden.advance(sim, 0.01)
	check(not warden.charging and warden.direction == locked and warden.finished_cycle == 1, "Shot uses the locked warning direction.")
	check(is_equal_approx(before - sim.players[0].integrity - sim.players[0].shields, 6), "A ship in the lance takes exactly one advertised hit; shields absorb it normally.")
	check(sim.players[1].integrity + sim.players[1].shields == off_axis, "Ships outside the warning corridor take no lance damage.")
	warden.advance(sim, 0)
	check(is_equal_approx(before - sim.players[0].integrity - sim.players[0].shields, 6), "Same cycle cannot fire twice.")
	warden.advance(sim, 9)
	check(warden.charging and warden.cycle == 2, "Next warning follows the twelve-second cycle.")
	var hidden := fixture()
	arrange(hidden)
	hidden.encounter.warden.advance(hidden, 9)
	var hidden_body: BattleSimulation.Combatant = hidden.entities[hidden.encounter.warden.rules.body_id]
	hidden_body.position = Vector2(2000, 0)
	hidden.refresh_visibility()
	check(not hidden.encounter.warden.visible(hidden), "Hidden body exposes no live warning origin or shield links.")
	check(not hidden.encounter.warden.label(hidden).contains("Lance"), "HUD does not reveal a hidden live charge.")
	check(hidden.encounter.warden.avoidance(hidden, hidden.players[0], Vector2.LEFT) == Vector2.LEFT, "Auto does not read hidden warning data.")

func test_interrupt() -> void:
	var sim := fixture()
	arrange(sim)
	var warden = sim.encounter.warden
	warden.advance(sim, 9)
	var body: BattleSimulation.Combatant = sim.entities[warden.rules.body_id]
	sim.damage_entity(body.entity_id, body.stats.integrity * 0.06 / 0.6 + 0.01)
	check(not warden.charging and warden.finished_cycle == 1, "Focused ordinary damage interrupts a charge through pylon protection.")
	warden.advance(sim, 3)
	check(not sim.event_log.any(func(event: Dictionary) -> bool: return event.type == "warden_lance"), "Interrupted cycle emits no lance.")
	warden.advance(sim, 9)
	check(warden.charging and warden.cycle == 2, "Interrupt postpones one attack, without permanently disabling later cycles.")

func test_objective() -> void:
	var sim := fixture()
	var warden = sim.encounter.warden
	check(sim.objective_target_ids == [warden.rules.body_id], "Only body destruction is required.")
	sim.damage_entity(warden.rules.body_id, 10000)
	check(warden.live_pylons(sim) == 2 and sim.objective_complete(), "Body kill wins with both pylons still alive.")
	sim.advance(1.0 / 30)
	check(sim.phase == BattleSimulation.Phase.VICTORY, "Body-only objective reaches victory.")
	var protected := fixture()
	protected.visibility_enabled = false
	var target: BattleSimulation.Combatant = protected.entities[protected.encounter.warden.rules.body_id]
	target.shields = 0
	var shot := BattleSimulation.Projectile.new()
	shot.target = target
	shot.source = protected.players[0]
	shot.position = target.position
	shot.is_player = true
	shot.damage = target.integrity
	protected.projectiles.append(shot)
	check(protected.get_finishing_projectile() == null, "Final-shot prediction accounts for pylon damage reduction.")
	for id in protected.encounter.warden.rules.pylon_ids:
		protected.damage_entity(id, 10000)
	check(protected.get_finishing_projectile() == shot, "Exposed-body finishing shots use the actual vulnerability multiplier.")
	var value := EncounterGenerator.generate(42, 12, 5, 1, "pylon_escort", 3)
	check(EncounterGenerator.valid(value) and value.warden.pylon_ids.size() == 1 and not value.warden.lance, "Earlier encounter teaches one weaker pylon without a lance.")

func test_replay() -> void:
	var expected := ""
	for batch in [1, 2, 8]:
		var sim := fixture()
		for frame in range(1440 / batch):
			for tick in range(batch):
				sim.advance(1.0 / 30)
		var actual := JSON.stringify({"snapshot": sim.authoritative_snapshot(), "events": sim.event_log})
		if expected.is_empty():
			expected = actual
		else:
			check(actual == expected, "Boss state and events replay identically at %d ticks/frame." % batch)

func test_validation() -> void:
	var value := EncounterGenerator.generate(42, 20, 8, 1, "bastion_warden", 4)
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(value))
	check(EncounterGenerator.valid(loaded), "Boss frozen roster survives JSON.")
	loaded.warden.pylon_ids[1] = loaded.warden.pylon_ids[0]
	check(not EncounterGenerator.valid(loaded), "Duplicate pylon identities are rejected.")
	loaded = value.duplicate(true)
	loaded.warden.warning_seconds = 0
	check(not EncounterGenerator.valid(loaded), "Missing reaction warning is rejected.")
	loaded = value.duplicate(true)
	loaded.objective.required_target_ids.append(loaded.warden.pylon_ids[0])
	check(not EncounterGenerator.valid(loaded), "Body objective cannot secretly require pylons.")
	for bad: Variant in [null, "bad", [], 1]:
		loaded = value.duplicate(true)
		loaded["warden"] = bad
		check(not EncounterGenerator.valid(loaded), "Malformed boss metadata is rejected without a script error.")
	loaded = value.duplicate(true)
	loaded.roster[1].erase("role")
	check(not EncounterGenerator.valid(loaded), "Missing organ role is rejected without a script error.")

func test_idle_charge() -> void:
	var sim := fixture()
	arrange(sim)
	for member in sim._members:
		member.speed = 0
		member.acceleration = 0
		member.velocity = Vector2.ZERO
		for index in range(member.cooldowns.size()):
			member.cooldowns[index] = 100
	for tick in range(360):
		sim.advance(1.0 / 30)
	check(sim.phase == BattleSimulation.Phase.COMBAT and sim.event_log.any(func(event: Dictionary) -> bool: return event.type == "warden_lance"), "A live charge counts as activity instead of triggering an early idle withdrawal.")

func test_legacy() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://warden/legacy.json"
	check(state.start_new_run(1, 42), "Prepare older frozen boss compatibility fixture.")
	var boss_id: int = state.campaign_dag.bosses[0]
	var old := EncounterGenerator.generate(42, boss_id, 8, 1, "boss_patrol", 4)
	old["arena_layout"] = "open"
	state.frozen_encounters[str(boss_id)] = old
	check(state.save_run_checkpoint() and state.load_run_checkpoint(), "Older boss patrol snapshots remain loadable.")
	check(JSON.parse_string(JSON.stringify(state.get_frozen_encounter(boss_id))) == JSON.parse_string(JSON.stringify(old)), "Loading never silently replaces a historical boss roster.")

func test_failed_reward() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://warden/atomic.json"
	check(state.start_new_run(1, 1357), "Prepare boss reward atomicity fixture.")
	for visit in range(7):
		check(state.travel_to(state.get_reachable_nodes(state.current_node_id)[0]), "Reach staged boss reward fixture.")
		if state.battle_pending:
			check(state.complete_battle(), "Secure prerequisite node for reward fixture.")
	check(not state.story_flags.get("boss_i_defeated", false), "Boss gate remains closed before battle.")
	check(state.travel_to(state.get_reachable_nodes(state.current_node_id)[0]), "Freeze actual boss departure for failed-write check.")
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, state.allied_salvage_chance(), state.laser_upgrade_level,
		state.battle_simulation_seed(), state.battle_support_context()), "Initialize reward fixture from saved boss plan.")
	sim.damage_entity(sim.encounter.warden.rules.body_id, 10000)
	sim.advance(1.0 / 30)
	var paid: int = state.credits
	var path: String = state.run_save_path
	var blocker := FileAccess.open("user://warden/blocker", FileAccess.WRITE)
	blocker.store_string("file")
	blocker.close()
	state.run_save_path = "user://warden/blocker/run.json"
	check(not state.settle_battle(sim) and state.credits == paid and state.deployment_capacity() == 30 \
		and not state.story_flags.get("boss_i_defeated", false), "Failed victory write grants no credits, story gate or capacity.")
	state.run_save_path = path
	check(state.settle_battle(sim) and state.deployment_capacity() == 42 and state.story_flags.get("boss_i_defeated", false), "Retry commits the body reward and progression together.")
	paid = state.credits
	check(not state.settle_battle(sim) and state.credits == paid and state.load_run_checkpoint() and state.deployment_capacity() == 42, "Committed boss rewards remain single across duplicate settlement and reload.")

func play_act(seed_value: int, add_lab: bool) -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://warden/act-%d.json" % seed_value
	check(state.start_new_run(1, seed_value), "Start real first act.")
	if add_lab:
		check(state.purchase_ship(BUILTINS.surveyor(), "Surveyor"), "Mixed lab fleet uses ordinary construction cost and slots.")
	check(state.deployment_capacity() == 30, "First act capacity starts at 30.")
	var taught := false
	var teaching_pylon_seen := false
	for visit in range(8):
		var choices: Array = state.get_reachable_nodes(state.current_node_id)
		var destination: int = choices[(seed_value + visit) % choices.size()]
		check(state.travel_to(destination), "Travel along an actual first-act route.")
		if state.battle_pending:
			var value: Dictionary = state.get_frozen_encounter(destination)
			taught = taught or value.template_id == "pylon_escort"
			var sim := BattleSimulation.new()
			check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, state.allied_salvage_chance(), state.laser_upgrade_level,
				state.battle_simulation_seed(), state.battle_support_context()), "Load real frozen pylon/boss deployment.")
			for tick in range(30 * 180):
				sim.advance(1.0 / 30)
				if value.template_id == "pylon_escort":
					for id in value.warden.pylon_ids:
						teaching_pylon_seen = teaching_pylon_seen or sim.team_can_see(0, sim.entities[id])
				if sim.phase != BattleSimulation.Phase.COMBAT:
					break
			check(sim.phase == BattleSimulation.Phase.VICTORY, "Actual first-act fleet wins row %d seed %d on Auto." % [visit + 1, seed_value])
			if sim.phase != BattleSimulation.Phase.VICTORY:
				return
			check(state.settle_battle(sim), "Commit actual victory and progression.")
			var paid: int = state.credits
			check(not state.settle_battle(sim) and state.credits == paid, "Duplicate completion cannot replay boss rewards.")
		check(state.load_run_checkpoint(), "Reload every first-act arrival.")
		if state.is_shipyard_node(destination):
			for owned in state.get_deployed_fleet():
				if owned.needs_repair():
					check(state.repair_ship(owned), "Earned resources afford actual first-act repairs.")
	check(taught, "Every first-act route teaches a weaker pylon before the boss.")
	check(teaching_pylon_seen, "The teaching pylon is actually seen during ordinary Auto play before boss arrival.")
	check(state.story_flags.get("boss_i_defeated", false) and state.deployment_capacity() == 42, "Warden victory opens the next act and capacity 42.")
	var requirements := ResearchRules.requirements("laboratory_iii", state.current_research_ids, state.story_flags, state.research_branch_choices)
	check(requirements.missing_story_gates.is_empty(), "Laboratory III story gate opens without granting free research.")
	check(state.get_reachable_nodes(state.current_node_id).size() > 0, "Next-act route opens after body victory.")
	print("First act seed %d lab %s: credits %d, fleet %d, capacity %d" % [seed_value, add_lab, state.credits, state.fleet.size(), state.deployment_capacity()])

func test_auto_dodge() -> void:
	var sim := fixture()
	arrange(sim)
	for member in sim._members:
		for index in range(member.cooldowns.size()):
			member.cooldowns[index] = 100
	sim.encounter.warden.advance(sim, 9)
	for tick in range(90):
		sim.advance(1.0 / 30)
	var shots := 0
	for event: Dictionary in sim.event_log:
		if event.type == "warden_lance":
			shots += 1
			check(not event.details.hit.has(sim.players[0].entity_id), "Ordinary movement leaves the locked corridor before impact on Auto.")
	check(shots == 1, "Dodge fixture exercises an actual lance without an interrupt.")

func test_focus() -> void:
	var sim := fixture()
	var body: BattleSimulation.Combatant = sim.entities[sim.encounter.warden.rules.body_id]
	for index in range(sim.players.size()):
		sim.players[index].position = body.position + Vector2(-160, (index - 1) * 40)
	sim.refresh_visibility()
	for member in sim.players:
		check(sim.request_attack(member.entity_id, body.entity_id), "Manual focus can select the visible protected body.")
	for tick in range(30 * 180):
		sim.advance(1.0 / 30)
		if sim.phase != BattleSimulation.Phase.COMBAT:
			break
	check(sim.phase == BattleSimulation.Phase.VICTORY and sim.encounter.warden.live_pylons(sim) == 2, "Sustained ordinary focus wins through protection without mandatory pylon clearing.")

func native_capture() -> void:
	root.size = Vector2i(640, 360)
	var sim := fixture()
	arrange(sim)
	var warden = sim.encounter.warden
	warden.advance(sim, 9)
	var view = load("res://scripts/battle_visuals.gd").new()
	view.simulation = sim
	view.size = Vector2(640, 360)
	view.camera_zoom = 0.8
	view.camera_position = Vector2(120, 0)
	root.add_child(view)
	var label := Label.new()
	label.theme = load("res://themes/ui_theme.tres")
	label.text = warden.label(sim)
	label.position = Vector2(8, 38)
	view.add_child(label)
	await process_frame
	await RenderingServer.frame_post_draw
	check(label.get_rect().end.x < 640, "Boss HUD fits the minimum viewport.")
	root.get_texture().get_image().save_png("res://docs/ui-review/warden-640.png")
	var body: BattleSimulation.Combatant = sim.entities[warden.rules.body_id]
	body.position = Vector2(2000, 0)
	body.previous_position = body.position
	sim.refresh_visibility()
	label.text = warden.label(sim)
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var hidden_before := root.get_texture().get_image().get_data()
	warden.origin = Vector2(-80, 80)
	warden.direction = Vector2.DOWN
	warden.exposed = 5
	warden.flash = 0.3
	label.text = warden.label(sim)
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().get_data() == hidden_before, "Hidden boss charge, exposure and beam data change no visible pixels.")
	view.queue_free()
	await process_frame
	await native_map_capture()

func native_map_capture() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://warden/map.json"
	check(state.start_new_run(1, 42), "Prepare actual boss route preview.")
	for visit in range(7):
		check(state.travel_to(state.get_reachable_nodes(state.current_node_id)[0]), "Reach pre-boss map fixture.")
		if state.battle_pending:
			check(state.complete_battle(), "Secure pre-boss map fixture.")
	var map: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await process_frame
	await process_frame
	map._on_map_pressed()
	await process_frame
	map.graph_view._select_node_at(map.graph_view._node_center(state.campaign_dag.bosses[0]))
	await process_frame
	await process_frame
	var scroll := map.route_preview.get_parent() as ScrollContainer
	check(not scroll.get_v_scroll_bar().visible, "Essential boss briefing fits without scrolling at 640x360.")
	check(not map.route_travel_button.disabled and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(map.route_travel_button.get_global_rect()), "Boss travel action remains visible and usable at minimum resolution.")
	check(map.graph_view.get_global_rect().encloses(map.graph_view.get_node("RoutePreview").get_global_rect()) \
		and map.graph_view.get_global_rect().encloses(map.route_travel_button.get_global_rect()), "Route preview and complete button frame fit inside the clipping map canvas.")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/ui-review/warden-preview-640.png")
	map.free()
	current_scene = null
	await process_frame

func test_controller() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://warden/controller.json"
	state.reduced_motion = true
	check(state.start_new_run(1, 42, false), "Prepare real boss controller fixture.")
	state.frozen_encounters["1"] = EncounterGenerator.generate(42, 1, 8, 1, "bastion_warden", 4)
	check(state.set_destination(1), "Persist boss deployment before entering battle.")
	root.size = Vector2i(640, 360)
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_physics_process(false)
	await process_frame
	battle.pause_button.button_pressed = true
	var before: float = battle.simulation.encounter.warden.clock
	for frame in range(60):
		battle._physics_process(1.0 / 30)
	check(battle.simulation.encounter.warden.clock == before, "Real pause freezes boss charge/cycle timers.")
	check(battle.objective_label.get_rect().end.x < 640, "Actual boss controller objective fits at 640 pixels.")
	battle.pause_button.button_pressed = false
	battle.fast_forward_button.button_pressed = true
	var captured := false
	for frame in range(30 * 180):
		battle._physics_process(1.0 / 30)
		if not captured and battle.simulation.encounter.warden.charging and battle.simulation.encounter.warden.visible(battle.simulation):
			captured = true
			if "--capture" in OS.get_cmdline_user_args():
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://docs/ui-review/warden-controller-640.png")
				var pylon: BattleSimulation.Combatant = battle.simulation.entities[battle.simulation.encounter.warden.rules.pylon_ids[1]]
				check(pylon.is_alive() and battle.simulation.team_can_see(0, pylon), "Native targeting fixture presents a visible independent pylon.")
				await click_screen(battle.visuals.world_transform() * pylon.position)
				check(battle.simulation.players.all(func(member: BattleSimulation.Combatant) -> bool: return member.commanded_target == pylon), "Actual pointer targets the pylon independently.")
				var body: BattleSimulation.Combatant = battle.simulation.entities[battle.simulation.encounter.warden.rules.body_id]
				await click_screen(battle.visuals.world_transform() * body.position)
				check(battle.simulation.players.all(func(member: BattleSimulation.Combatant) -> bool: return member.commanded_target == body), "Actual pointer can focus the protected body.")
		if battle.simulation.phase != BattleSimulation.Phase.COMBAT:
			break
	check(captured and battle.simulation.phase == BattleSimulation.Phase.VICTORY, "Actual 2x controller telegraphs and wins the boss battle.")
	for frame in range(60):
		battle._physics_process(1.0 / 30)
	check(not state.battle_pending and state.current_node_id == 1 and state.load_run_checkpoint(), "Body victory settles and reloads through the production controller.")
	battle.free()
	current_scene = null

func click_screen(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.pressed = pressed
		root.push_input(click, true)
	await process_frame
