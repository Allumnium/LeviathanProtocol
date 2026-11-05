extends "res://tests/test_fleet_redesign.gd"

var selection_completed := false

func selection_checks() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://deployment-selection.json"
	check(state.start_new_run(1, 8403), "Start isolated selection fixture")
	state.pending_intro = false
	check(state.travel_to(state.get_reachable_nodes(state.current_node_id)[0]), "Save real pending encounter")
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_process(false)
	battle.set_physics_process(false)
	await settle()
	var sim: BattleSimulation = battle.simulation
	var drone: BattleSimulation.Combatant = sim.players[3]
	var neighbour: BattleSimulation.Combatant = sim.players[4]
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		battle._pan_resume_seconds = 5
		await settle()
		battle.visuals.camera_position = drone.position + Vector2(80, 10)
		battle.visuals.camera_zoom = 0.7
		battle.visuals.deployment_selection.clear()
		var origin := drone.position
		var neighbour_origin := neighbour.position
		await drag(battle, drone, Vector2(10, 5))
		check(battle.visuals.deployment_selection == [drone.entity_id] and drone.position.is_equal_approx(origin + Vector2(10, 5))
			and neighbour.position == neighbour_origin, "First ship click selects and moves only that ship")
		check(battle.selection_scroll.visible and not battle.enemy_readout.visible, "Ship details replace enemy list in right panel")
		var flag: Dictionary
		for candidate: Dictionary in battle.visuals.squadron_flags():
			if candidate.id == drone.squadron_id:
				flag = candidate
		check(not flag.is_empty(), "Squadron has a visible flag")
		var before := {}
		for member in sim.players:
			before[member.entity_id] = member.position
		var point: Vector2 = flag.rect.get_center()
		await pointer(point, true)
		var motion := InputEventMouseMotion.new()
		motion.position = point + Vector2(10, 5) * battle.visuals.camera_zoom
		motion.relative = Vector2(10, 5) * battle.visuals.camera_zoom
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		await settle()
		await pointer(motion.position, false)
		check(battle.visuals.deployment_selection.size() == 10 and battle.visuals.selected_squadron == drone.squadron_id,
			"Flag click selects entire squadron")
		for member in sim.players:
			var delta := Vector2(10, 5) if member.squadron_id == drone.squadron_id else Vector2.ZERO
			check(member.position.is_equal_approx(before[member.entity_id] + delta), "Flag moves members together without moving other groups")
		await capture("selected-squadron-%d" % resolution.x)
		origin = drone.position
		neighbour_origin = neighbour.position
		await drag(battle, drone, Vector2(12, -8))
		check(battle.visuals.deployment_selection == [drone.entity_id] and drone.position.is_equal_approx(origin + Vector2(12, -8))
			and neighbour.position == neighbour_origin and battle.visuals.selected_squadron.is_empty(), "Ship click after group selection always selects one ship")
		await capture("selected-ship-%d" % resolution.x)
		await drag(battle, drone, Vector2.ZERO)
		check(battle.visuals.deployment_selection == [drone.entity_id], "Repeated ship click stays individual")
		check(battle._select_deployment(neighbour.position, true) and battle.visuals.deployment_selection.size() == 2,
			"Additive selection adds only the hit ship")
		await click(battle.selection_details.find_child("CloseX", true, false))
		check(battle.visuals.deployment_selection.is_empty() and battle.enemy_readout.visible, "Shared X clears selection and restores enemy list")
		check(sim.elapsed == 0 and battle.deploying, "Selection and dragging do not start combat")
	# A flag uses one clamped displacement for every member, even at an edge.
	for candidate: Dictionary in battle.visuals.squadron_flags():
		if candidate.id == drone.squadron_id:
			battle._select_flag(candidate.rect.get_center())
	battle._deployment_origins.clear()
	var relative := neighbour.position - drone.position
	for id: String in battle.visuals.deployment_selection:
		battle._deployment_origins[id] = sim.entities[id].position
	battle._move_deployment(Vector2(100000, 100000))
	check((neighbour.position - drone.position).is_equal_approx(relative), "Boundary clamp preserves squadron spacing")
	for id: String in battle.visuals.deployment_selection:
		var member: BattleSimulation.Combatant = sim.entities[id]
		check(battle.visuals.deployment_area.grow(-member.radius + 0.01).has_point(member.position), "Flag cannot drag member beyond deployment area")
	battle.visuals.camera_position = Vector2.ZERO
	battle.visuals.camera_zoom = 0.08
	check(battle.visuals.squadron_flags().any(func(flag: Dictionary) -> bool: return flag.enemy), "Alien squadrons have flags too")
	var positions := {}
	for member in sim.players:
		positions[member.owned_ship.id] = member.position
	battle._begin_combat()
	check(not battle.deploying, "Changed placement saves through Begin Combat")
	# Live friendly selection must not issue fleet-wide clear-attack commands or move ships.
	battle.visuals.camera_position = drone.position
	battle.visuals.camera_zoom = 0.3
	await settle()
	var point: Vector2 = battle.visuals.world_transform() * drone.position
	await pointer(point, true)
	await pointer(point, false)
	check(battle.visuals.deployment_selection == [drone.entity_id] and battle.selection_scroll.visible,
		"Live ship click displays individual details")
	await drag(battle, drone, Vector2(15, 10))
	check(drone.position == positions[drone.owned_ship.id], "Live selection never rearranges ships")
	battle._begin_result_delay(false)
	check(not battle.selection_scroll.visible, "Selection details hide for battle results")
	check(state.load_run_checkpoint(), "Placement survives Continue")
	for ship: HangarShip in state.get_deployed_fleet():
		check((BattleSimulation.PLAYER_FORMATION_CENTER + ship.formation * BattleSimulation.DEPLOYMENT_SCALE).is_equal_approx(positions[ship.id]),
			"Saved individual and group placement remains intact")
	battle.queue_free()
	await settle()
	selection_completed = true

func fleet_flag_checks() -> void:
	check(state.start_new_run(1, 8404), "Start Fleet flag fixture")
	state.pending_intro = false
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	screen.active_tab = "FLEET"
	screen._refresh()
	await settle()
	var ship: HangarShip = state.fleet[3]
	var group := HangarSquadrons.for_ship(state.squadrons, ship.id)
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		var board: Control = screen.formation_view
		var point: Vector2 = board.global_position + board.flag_rect(group).get_center()
		await pointer(point, true)
		await pointer(point, false)
		check(screen.selected_squadron_id == int(group.id) and screen.formation_selection.size() == 10
			and screen.details.has_node("SquadronStatBars") and screen.details.has_node("Stance_seek"), "Fleet flag selects group settings")
		await capture("fleet-squadron-%d" % resolution.x)
		board = screen.formation_view
		point = board.global_position + board.point(ship)
		await pointer(point, true)
		await pointer(point, false)
		check(screen.selected_squadron_id == 0 and screen.formation_selection == [ship.id] and not screen.ship_editor_open
			and screen.details.has_node("ShipStatBars") and screen.refit_panel.has_node("SplitSquadron")
			and not screen.details.has_node("Stance_seek"), "Fleet ship click shows only individual settings in right panel")
		await capture("fleet-ship-%d" % resolution.x)
	var board: Control = screen.formation_view
	var layout: Dictionary = board.display_positions.duplicate()
	var point: Vector2 = board.global_position + board.flag_rect(group).get_center()
	await pointer(point, true)
	var motion := InputEventMouseMotion.new()
	motion.position = point + Vector2(15, 10)
	motion.relative = Vector2(15, 10)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await settle()
	await pointer(motion.position, false)
	check(screen.formation_view.display_positions != layout
		and screen.formation_view.display_positions[int(group.members[0])] == state.owned_ship(int(group.members[0])).formation,
		"Fleet flag dragging updates shared deployment positions")
	# First member previously shared the group's selected_id: it must still drill directly to one.
	screen._select_ship(int(group.members[0]))
	await settle()
	check(screen.formation_selection == [int(group.members[0])], "First member selection cannot restore old group highlights")
	screen._select_ship(ship.id)
	await settle()
	var change: Button = screen.refit_panel.get_node("Loadout_laser_drone")
	await click(change)
	check(state.ship_loadout_id(ship.id) == "laser_drone", "Right-panel loadout button refits only selected ship")
	await click(screen.refit_panel.get_node("SplitSquadron"))
	check(HangarSquadrons.for_ship(state.squadrons, ship.id).members.size() == 1, "Right-panel assignment splits individual ship")
	screen.queue_free()
	await settle()

func mixed_selection_checks() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://mixed-selection.json"
	check(state.start_new_run(1, 8405), "Start mixed selection fixture")
	state.pending_intro = false
	check(state.travel_to(state.get_reachable_nodes(state.current_node_id)[0]), "Open mixed selection encounter")
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_process(false)
	battle.set_physics_process(false)
	await settle()
	battle.visuals.camera_position = BattleSimulation.PLAYER_FORMATION_CENTER
	battle.visuals.camera_zoom = 0.25
	await settle()
	var flags: Array[Dictionary] = battle.visuals.squadron_flags()
	var friendly: Array[Dictionary] = flags.filter(func(flag: Dictionary) -> bool: return not flag.enemy)
	check(friendly.size() >= 2, "At least two friendly flags are visible")
	check(battle._select_flag(friendly[0].rect.get_center()), "Select first flag")
	check(battle._select_flag(friendly[1].rect.get_center(), true), "Shift/add second flag")
	check(battle.visuals.selected_squadron.is_empty() and battle.selection_details.get_child(1).text == "Selected ships",
		"Mixed squadron selection has an accurate heading")
	for flag: Dictionary in friendly:
		check(battle.battlefield.get_global_rect().encloses(flag.rect), "Visible flag stays clear of command frame")
	battle._begin_combat()
	var target: BattleSimulation.Combatant = battle.simulation.aliens[0]
	battle.visuals.camera_position = target.position
	battle.visuals.camera_zoom = 0.3
	await settle()
	var point: Vector2 = battle.visuals.world_transform() * target.position
	await pointer(point, true)
	await pointer(point, false)
	check(battle.simulation.players.any(func(actor: BattleSimulation.Combatant) -> bool: return actor.commanded_target == target),
		"Live enemy click retains fleet attack command")
	var commands: int = battle.simulation.command_log.size()
	var player: BattleSimulation.Combatant = battle.simulation.players[3]
	battle.visuals.camera_position = player.position
	await settle()
	await drag(battle, player, Vector2.ZERO)
	check(battle.simulation.command_log.size() == commands and battle.visuals.deployment_selection == [player.entity_id],
		"Friendly inspection preserves existing attack orders")
	battle.queue_free()
	await settle()
	print("MIXED SELECTION COMPLETE: %d checks, %d failures" % [checks, failures])

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Deployment selection requires native pointer and visual checks")
		quit(1)
		return
	if "--mixed-only" in OS.get_cmdline_user_args():
		await mixed_selection_checks()
		quit(1 if failures else 0)
		return
	await selection_checks()
	await fleet_flag_checks()
	check(selection_completed, "Selection interaction reaches completed summary")
	print("DEPLOYMENT SELECTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
