extends SceneTree
const Loadouts = preload("res://scripts/ship_loadouts.gd")
var checks := 0
var failures := 0
var state: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func settle() -> void:
	for index in range(5):
		await process_frame

func fleet_checks() -> void:
	for flagship: String in ["flagship_basic", "flagship_science"]:
		check(state.start_new_run(1, 7341, true, flagship), "Start the expanded fleet")
		check(state.fleet.size() == 13 and state.used_command() == 15 and state.command_limit() == 24, "Thirteen ships leave nine command points for purchases")
		check(state.fleet.filter(func(ship: HangarShip) -> bool: return ship.chassis_id == "drone").size() == 10
			and state.fleet.filter(func(ship: HangarShip) -> bool: return ship.chassis_id == "fighter").size() == 1
			and state.fleet.filter(func(ship: HangarShip) -> bool: return ship.chassis_id == "transport").size() == 1, "Approved starting class mix")
		var positions := {}
		var uids := {}
		for ship: HangarShip in state.fleet:
			check(not positions.has(ship.formation), "Starting formation positions are unique")
			positions[ship.formation] = true
			check(ship.mounts.size() == ship.chassis.slots.size()
				and state.ship_loadout_id(ship.id) == Loadouts.default_for(ship.chassis_id).id, "Every starting ship uses its full named fit")
			for instance: Dictionary in ship.mounts.values():
				check(not uids.has(instance.uid), "Every fitted instance has its own UID")
				uids[instance.uid] = true
		check(state.current_research_ids == ["foundation"] and state.credits == 700, "Starting fleet grants no research or extra cash")
		var before: Dictionary = state.hangar_snapshot()
		check(HangarCheckpoint.valid(before) and state.load_run_checkpoint()
			and SaveValidation.same(before, state.hangar_snapshot()), "Expanded fleet, groups, fits and formation survive Continue")

func encounter_checks() -> void:
	for row: Array in [[2, "patrol", false], [6, "relay_defense", false], [5, "patrol", true],
			[10, "bastion_warden", false], [8, "boss_framework", false], [24, "boss_patrol", false]]:
		var base := EncounterGenerator.generate(7341, 1001, row[0], 1, row[1], 2, row[2], {}, false)
		var expanded := EncounterGenerator.generate(7341, 1001, row[0], 1, row[1], 2, row[2])
		check(not base.is_empty() and EncounterGenerator.valid(base) and EncounterGenerator.valid(expanded), "Expanded encounter validates: " + str(row[1]))
		check(expanded.roster.size() >= base.roster.size(), "Enemy counts expand without a 24-entity balance cap")
		check(SaveValidation.same(expanded, EncounterGenerator.generate(7341, 1001, row[0], 1, row[1], 2, row[2])), "Enemy expansion is deterministic")
		for index in range(base.roster.size()):
			check(SaveValidation.same(base.roster[index], expanded.roster[index]), "Original enemy stats, rank, wave and identity are unchanged")
		check(expanded.rewards == base.rewards, "Count increase preserves authored rewards")
		if expanded.has("warden"):
			check(expanded.warden == base.warden and expanded.objective == base.objective, "Boss body, pylons, timings and objective are unchanged")
		else:
			var ships: int = base.roster.filter(func(entry: Dictionary) -> bool: return entry.kind == "ship").size()
			check(expanded.roster.size() == base.roster.size() + ships, "Ordinary ship rosters double while organs/craft stay unchanged")
		if row[1] == "boss_framework":
			check(expanded.roster.size() > 24, "Encounters can exceed the removed balance cap")
		var copy_index := -1
		for index in range(expanded.roster.size()):
			if expanded.roster[index].has("copy_of"):
				copy_index = index
				break
		if copy_index >= 0:
			var malformed := expanded.duplicate(true)
			malformed.roster[copy_index].stats[0] += 1
			check(not EncounterGenerator.valid(malformed), "Reject a wingmate with altered stats")
			malformed = expanded.duplicate(true)
			malformed.roster[copy_index].copy_of = "missing"
			check(not EncounterGenerator.valid(malformed), "Reject a wingmate without its source")
		print("FLEET COUNTS ", row[1], ": ", base.roster.size(), " -> ", expanded.roster.size())
	var plan := EncounterGenerator.generate(7341, 1001, 2, 1)
	check(EncounterGenerator.valid(SwarmNavigation.encounter(plan, 15)), "Existing hostile-strength scaling preserves expanded roster validity")

func native_opening() -> void:
	check(state.start_new_run(1, 7341), "Start one natural opening playtest")
	state.pending_intro = false
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	screen.active_tab = "FLEET"
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		screen._refresh()
		await settle()
		check(screen.roster.is_visible_in_tree() and screen.formation_view.is_visible_in_tree(), "Expanded fleet is shown in the production UI")
		for ship: HangarShip in state.fleet:
			check(Rect2(Vector2.ZERO, screen.formation_view.size).encloses(screen.formation_view.ship_rect(ship)),
				"Every starting ship fits the native Fleet canvas at %s" % resolution)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("user://fleet-%d.png" % resolution.x) == OK, "Capture starting fleet")
	if "--fleet-only" in OS.get_cmdline_user_args():
		screen.queue_free()
		await settle()
		return
	check(state.depart_expedition("refuel_station_1") and state.expedition_simulation.set_speed(10), "Depart the normal opening route")
	for frame in range(1200):
		var result: Dictionary = state.advance_expedition(1.0 / 60)
		check(result.ok, "Opening travel advances normally")
		var event_id: String = state.expedition_simulation.state.pending_event_id
		if not event_id.is_empty():
			var event: Dictionary = state.expedition_simulation.Events.find(state.expedition_simulation.events, event_id)
			var options: Array = state.expedition_simulation.Events.options(event)
			var choice := "continue" if options.any(func(option: Dictionary) -> bool: return option.id == "continue") else str(options[0].id)
			check(state.resolve_expedition_event(event_id, choice), "Resolve authored opening event")
		if state.battle_pending:
			break
	check(state.battle_pending, "Reach the naturally triggered first battle")
	var enemy_count: int = state.battle_aliens.size()
	screen.queue_free()
	await settle()
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_process(false)
	battle.set_physics_process(false)
	await settle()
	var sim: BattleSimulation = battle.simulation
	check(sim.players.size() == 13 and sim.aliens.size() == enemy_count, "Both expanded fleets deploy")
	var captured := false
	for tick in range(30 * 120):
		battle._advance_fixed_simulation(1.0 / 30, 1)
		if not captured and sim.elapsed >= 2:
			captured = true
			for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
				root.size = resolution
				await settle()
				await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png("user://battle-%d.png" % resolution.x) == OK, "Capture expanded opening battle and readouts")
		if sim.phase != BattleSimulation.Phase.COMBAT:
			break
	check(sim.phase != BattleSimulation.Phase.COMBAT, "One opening battle reaches a bounded natural outcome")
	var result := {"players": 13, "enemies": enemy_count, "seconds": sim.elapsed, "phase": sim.phase,
		"survivors": sim.players.filter(func(member: BattleSimulation.Combatant) -> bool: return member.is_alive()).size()}
	print("EXPANDED OPENING: ", JSON.stringify(result))
	check(state.settle_battle(sim), "Opening outcome settles through the production transaction")
	check(state.load_run_checkpoint(), "Opening outcome survives Continue")
	battle.queue_free()
	await settle()

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://expanded-fleet.json"
	if "--opening-only" not in OS.get_cmdline_user_args() and "--fleet-only" not in OS.get_cmdline_user_args():
		fleet_checks()
		encounter_checks()
	if DisplayServer.get_name() != "headless":
		await native_opening()
	print("FLEET OPENING: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
