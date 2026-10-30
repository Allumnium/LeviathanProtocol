extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0
var state: Node
var live: BattleSimulation

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
		check(owned.initialize(BUILTINS.drone(), index + 1, "Command ship %d" % (index + 1)), "Construct Command Centers without a lab.")
		ships.append(owned)
	var aliens: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(1, 1, 42):
		aliens.append(alien)
	var config := BattleAbilities.initial_state()
	config.auto.scan = false
	var sim := BattleSimulation.new()
	check(sim.setup_owned(ships, aliens, 0, 0, 42, {"visibility_enabled": true, "ability_ids": ["scan"], "ability_state": config}), "Initialize the live Foundation ability framework.")
	sim.players[0].position = Vector2.ZERO
	sim.players[1].position = Vector2(50, 0)
	sim.aliens[0].position = Vector2(400, 0)
	sim.visibility.reset()
	sim.refresh_visibility()
	return sim

func cast(sim: BattleSimulation, point: Vector2, source := "") -> bool:
	return sim.issue_command("ability_cast", {"ability": "scan", "position": [point.x, point.y], "source": source, "faction": 0})

func run() -> void:
	state = root.get_node("GameState")
	test_scan()
	test_auto_and_replay()
	test_persistence()
	await test_overflow()
	await test_ui()
	await test_live_controller()
	print("Ability/Scan tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func test_scan() -> void:
	var sim := fixture()
	var target := sim.aliens[0]
	var rock := sim.add_neutral_target("rock/scan", 100, Vector2(450, 0))
	rock.tags["asteroid"] = true
	rock.resource_contents = {"offense": 7, "defense": 3}
	check(not sim.team_can_see(0, target) and sim.abilities.known_resources(0, rock.entity_id).is_empty(), "Neither radar nor mere presence reveals details or ore.")
	var before := sim.abilities.snapshot()
	var origin: Vector2 = sim.abilities.origin(sim.players[0], "scan")
	check(sim.abilities.can_cast(sim, "scan", origin + Vector2.RIGHT * 450, sim.players[0].entity_id)
		and not sim.abilities.can_cast(sim, "scan", origin + Vector2.RIGHT * 450.1, sim.players[0].entity_id), "Range is measured from the actual Command Center, including offset/rotation, with an exact boundary.")
	check(not cast(sim, Vector2(1000, 0)) and sim.abilities.snapshot() == before and sim.abilities.effects.is_empty(), "Out-of-range commands consume no cooldown or effect.")
	check(cast(sim, Vector2(400, 0), sim.players[0].entity_id), "Scan can be ground-targeted into unseen space using a chosen source.")
	check(sim.team_can_see(0, target) and sim.abilities.remaining("scan") == 25, "Scan reveals radius 180 and starts the shared 25-second cooldown.")
	check(not cast(sim, Vector2(400, 0), sim.players[1].entity_id), "A second Command Center cannot bypass the per-type fleet cooldown.")
	check(sim.abilities.known_resources(0, rock.entity_id) == rock.resource_contents and not sim.abilities.resource_knowledge[0][rock.entity_id].has("position"), "Scan records contents without permanent live position tracking.")
	check(sim._analysis_multiplier(sim.players[0], target) == 1, "Foundation Scan needs no lab and grants no analysis damage bonus.")
	sim.abilities.advance(sim, 6.01)
	sim.refresh_visibility()
	check(not sim.team_can_see(0, target) and sim.abilities.effects.is_empty() and sim.abilities.known_resources(0, rock.entity_id).offense == 7, "Visibility expires after six simulation seconds while discovered contents remain known.")
	sim = fixture()
	check(cast(sim, Vector2(400, 0), sim.players[0].entity_id), "Start source-loss check.")
	var source := sim.players[0]
	source.owned_ship.units[source.owned_ship.core_index].hp = 0
	sim._refresh_owned_stats(source)
	sim.abilities.advance(sim, 0.01)
	sim.refresh_visibility()
	check(sim.abilities.effects.is_empty() and not sim.team_can_see(0, sim.aliens[0]) and sim.abilities.remaining("scan") > 24, "Source destruction cancels the cast's visibility without refunding its cooldown.")
	var bad := BattleAbilities.initial_state()
	bad.cooldowns.scan = 26
	check(not BattleAbilities.valid(bad), "Reject forged or out-of-range saved cooldowns.")
	var older := BattleAbilities.initial_state()
	older.erase("pause_aim")
	check(sim.abilities.configure({"ability_state": older}) and not sim.abilities.state.pause_aim, "An omitted optional aim preference defaults safely when an older state is loaded.")

func test_auto_and_replay() -> void:
	var failed := fixture()
	failed.ability_commit = func(_proposal: Dictionary) -> bool: return false
	check(not cast(failed, Vector2(400, 0)) and failed.command_log[0].get("persistence_rejected", false), "Persistence rejection is recorded as an explicit replay input without charging the cast.")
	failed.advance(1.0 / 30)
	var rejected_replay := fixture()
	for command: Dictionary in JSON.parse_string(JSON.stringify(failed.command_log)):
		check(rejected_replay.queue_command(command), "Queue a recorded persistence rejection without requiring disk failure during replay.")
	rejected_replay.advance(1.0 / 30)
	check(failed.authoritative_snapshot() == rejected_replay.authoritative_snapshot(), "Save-rejected casts and Auto retry throttling replay without revealing or charging anything.")
	failed.ability_commit = Callable()
	var sim := fixture()
	sim.abilities.state.auto.scan = true
	sim.abilities.auto_cast(sim)
	check(sim.abilities.effects.any(func(effect: Dictionary) -> bool: return effect.faction == 0), "Auto Scan investigates an observable radar contact.")
	sim = fixture()
	sim.aliens[0].position = Vector2(1000, 0)
	sim.refresh_visibility()
	sim.abilities.state.auto.scan = true
	sim.abilities.auto_cast(sim)
	check(sim.abilities.remaining("scan") == 0, "Auto never reads hidden live positions to discover an unobserved actor.")
	var rock := sim.add_neutral_target("rock/unknown", 100, Vector2(150, 0))
	rock.tags["asteroid"] = true
	rock.resource_contents = {}
	sim.refresh_visibility()
	sim.abilities.auto_cast(sim)
	check(sim.abilities.resource_knowledge[0].has(rock.entity_id), "Auto scans unknown visible rocks, including empty ones, without inspecting their contents first.")
	var original := fixture()
	check(cast(original, Vector2(400, 0)), "Record a manual cast for replay.")
	for tick in range(90):
		original.advance(1.0 / 30)
	var reference := original.authoritative_snapshot()
	var commands: Array = JSON.parse_string(JSON.stringify(original.command_log))
	for batch in [1, 2, 6]:
		var replay := fixture()
		for command: Dictionary in commands:
			check(replay.queue_command(command), "JSON command envelopes preserve cast identity, source, faction and ground position.")
		for group in range(int(90 / batch)):
			for tick in range(batch):
				replay.advance(1.0 / 30)
		check(replay.authoritative_snapshot() == reference, "Ability effects, cooldowns, knowledge and visibility replay identically at accelerated speed.")
		if replay.authoritative_snapshot() != reference:
			for key in reference:
				if replay.authoritative_snapshot().get(key) != reference[key]:
					print("Replay mismatch in ", key)

func commit_live(proposal: Dictionary) -> bool:
	return state.commit_battle_ability(live, proposal)

func test_persistence() -> void:
	state.run_save_path = "user://abilities/run.json"
	check(state.start_new_run(1, 42) and state.travel_to(state.get_reachable_nodes(0)[0]), "Start a production ability deployment.")
	live = BattleSimulation.new()
	check(live.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, state.battle_simulation_seed(), state.battle_support_context()), "Departure freezes authorized actions and initial cooldowns.")
	live.battle_id = state.battle_identity()
	live.ability_commit = commit_live
	live.players[0].position = Vector2.ZERO
	live.refresh_visibility()
	var before := RunCheckpoint.capture(state)
	var blocker := FileAccess.open("user://abilities/blocker", FileAccess.WRITE)
	blocker.store_string("file")
	blocker.close()
	var path: String = state.run_save_path
	state.run_save_path = "user://abilities/blocker/run.json"
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	check(not cast(live, Vector2(400, 0)) and live.abilities.remaining("scan") == 0 and live.abilities.effects.is_empty()
		and RunCheckpoint.capture(state) == before, "Failed cast persistence grants no reveal and consumes no cooldown, funds or ledger mutation.")
	Engine.print_error_messages = printed
	state.run_save_path = path
	check(cast(live, Vector2(400, 0)), "A persisted cast commits before revealing the area.")
	live.abilities.advance(live, 5)
	state.update_battle_support(live)
	check(state.cancel_battle() and state.load_run_checkpoint() and is_equal_approx(state.ability_state.cooldowns.scan, 20), "Remaining cooldown persists through withdrawal and reload.")
	var revised := BUILTINS.drone()
	BUILTINS._add_part(revised, ShipPart.Type.SINGLE_PLATE, Vector2i(6, 1))
	check(state.assign_fleet_design(0, "Drone revision", revised, true) and state.purchase_ship(revised, "Drone revision")
		and is_equal_approx(state.ability_state.cooldowns.scan, 20), "Refitting and buying a new source cannot reset the fleet cooldown.")
	check(state.travel_to(state.get_reachable_nodes(0)[0]) and is_equal_approx(state.battle_support_context().ability_state.cooldowns.scan, 20), "A retry freezes the existing cooldown, not a fresh source allowance.")
	check(state.load_run_checkpoint() and is_equal_approx(state.battle_support_context().ability_state.cooldowns.scan, 20), "Pending reload uses persisted remaining cooldowns while the original deployment retains replay inputs.")
	live.ability_commit = Callable()
	live = null

func settle() -> void:
	for frame in range(3):
		await process_frame

func test_overflow() -> void:
	# Detached catalog fixture checks the generic bar's future capacity without
	# making any unimplemented action available in the production game.
	var sim := fixture()
	sim.abilities.available.assign(["scan", "focus_mark", "ion_pulse", "gravity_well", "tether", "phase_step", "ecm_burst"])
	var bar: Control = load("res://scripts/battle_ability_bar.gd").new()
	bar.simulation = sim
	bar.visuals = Control.new()
	root.add_child(bar)
	await settle()
	var overflow: MenuButton = bar.find_child("AbilityOverflow", true, false)
	check(bar.action_buttons.size() == 6 and overflow != null and overflow.get_popup().item_count == 1, "The generic bar keeps six pinned actions and routes additional actions to click-open overflow.")
	bar.visuals.free()
	bar.free()

func click(control: Control) -> void:
	await click_point(control.get_global_rect().get_center())

func click_point(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await settle()

func test_ui() -> void:
	state.run_save_path = "user://abilities/ui.json"
	check(state.start_new_run(1, 42) and state.travel_to(state.get_reachable_nodes(0)[0]), "Prepare the real battle UI.")
	root.size = Vector2i(640, 360)
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_physics_process(false)
	await settle()
	var sim: BattleSimulation = battle.simulation
	sim.players[0].position = Vector2.ZERO
	sim.players[1].position = Vector2(0, 80)
	sim.players[2].position = Vector2(-50, 0)
	for index in range(sim.aliens.size()):
		sim.aliens[index].position = Vector2(400 + index * 30, 0)
	sim.refresh_visibility()
	battle.visuals.camera_position = Vector2(150, 0)
	battle.visuals.camera_zoom = 0.5
	battle._auto_camera_active = false
	var bar: Control = battle.ability_bar
	check(bar != null and bar.action_buttons.has("scan") and bar.source_picker.item_count == 4, "The themed battle bar exposes Scan, three source choices and Auto source.")
	check(battle.get_global_rect().encloses(bar.get_global_rect()) and not bar.get_global_rect().intersects(battle.get_node("Radar").get_global_rect()), "Ability controls and radar fit separately at 640x360.")
	await click(bar.auto_button)
	check(not sim.abilities.state.auto.scan, "Auto toggle changes the authoritative preference through a real mouse click.")
	await click(bar.pause_aim)
	await click(bar.action_buttons.scan)
	check(bar.targeting and battle.pause_button.button_pressed, "Manual targeting can pause the simulation without requiring a lab.")
	var point: Vector2 = battle.visuals.world_transform() * Vector2(400, 0)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await settle()
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/step39/scan-preview.png")
	await click_point(point)
	check(not bar.targeting and not battle.pause_button.button_pressed and sim.abilities.remaining("scan") == 25
		and sim.team_can_see(0, sim.aliens[0]), "Clicking unseen ground casts, reveals, starts cooldown and restores the prior pause state.")
	check(sim.point_visible(0, Vector2.ZERO), "Scan retains the Command Centers' normal sight coverage.")
	check(bar.action_buttons.scan.disabled and bar.action_buttons.scan.focus_mode == Control.FOCUS_NONE, "Cooldown feedback is inline and controls introduce no keyboard focus outline.")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/step39/scan-active.png")
	battle.free()
	current_scene = null

func test_live_controller() -> void:
	state.run_save_path = "user://abilities/live.json"
	state.reduced_motion = true
	check(state.start_new_run(1, 1357) and state.travel_to(state.get_reachable_nodes(0)[0]), "Prepare a real Auto controller playthrough.")
	var destination: int = state.destination_node_id
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_physics_process(false)
	await settle()
	if battle.fast_forward_button.button_pressed:
		await click(battle.fast_forward_button)
	await click(battle.fast_forward_button)
	check(battle.fast_forward_button.button_pressed, "The live battle's 2x control accepts pointer input alongside the new ability bar.")
	var captured := false
	for tick in range(60 * 180):
		battle._physics_process(1.0 / 30)
		if not captured and battle.simulation.abilities.effects.any(func(effect: Dictionary) -> bool: return effect.faction == 0):
			captured = true
			if "--capture" in OS.get_cmdline_user_args():
				await settle()
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://.local/step39/scan-auto-battle.png")
		if battle.simulation.phase != BattleSimulation.Phase.COMBAT:
			break
	check(captured and battle.simulation.phase == BattleSimulation.Phase.VICTORY, "A real starting fleet wins on Auto with visibility, enemy Scan and persisted player Scan at 2x.")
	for tick in range(60):
		battle._physics_process(1.0 / 30)
	check(not state.battle_pending and state.current_node_id == destination, "The real controller settles the encounter and its remaining fleet cooldown.")
	battle.free()
	current_scene = null
