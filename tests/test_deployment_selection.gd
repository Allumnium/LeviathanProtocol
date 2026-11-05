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
		check(battle.visuals.deployment_selection.size() == 10 and drone.position.is_equal_approx(origin + Vector2(10, 5))
			and neighbour.position.is_equal_approx(neighbour_origin + Vector2(10, 5)), "First click and drag selects/moves the complete squadron")
		await capture("selected-squadron-%d" % resolution.x)
		origin = drone.position
		neighbour_origin = neighbour.position
		await drag(battle, drone, Vector2(12, -8))
		check(battle.visuals.deployment_selection == [drone.entity_id] and drone.position.is_equal_approx(origin + Vector2(12, -8))
			and neighbour.position == neighbour_origin, "Second plain click highlights/drags just the clicked ship")
		await capture("selected-ship-%d" % resolution.x)
		await drag(battle, drone, Vector2.ZERO)
		check(battle.visuals.deployment_selection == [drone.entity_id], "Clicking the individual again keeps it selected")
		# Directly exercise the same additive path used by box selection.
		check(battle._select_deployment(neighbour.position, false, true) and battle.visuals.deployment_selection.size() == 10,
			"Additive group selection expands the group without drilling down")
		check(battle._select_deployment(drone.position, false, true) and battle.visuals.deployment_selection.size() == 10,
			"Repeated box/additive hits preserve the complete squadron")
		await drag(battle, neighbour, Vector2.ZERO)
		check(battle.visuals.deployment_selection == [neighbour.entity_id], "Any ship in the selected squadron can become the individual")
		var empty: Vector2 = battle.battlefield.get_global_rect().position + Vector2(12, 12)
		await pointer(empty, true)
		await pointer(empty, false)
		check(battle.visuals.deployment_selection.is_empty(), "Empty click deselects")
		await drag(battle, drone, Vector2.ZERO)
		check(battle.visuals.deployment_selection.size() == 10, "Next click after deselection selects the squadron again")
		await drag(battle, drone, Vector2.ZERO, false, true)
		check(battle.visuals.deployment_selection.size() == 10, "Shift click preserves additive squadron selection")
		check(sim.elapsed == 0 and battle.deploying, "Selection and dragging do not start combat")
	var positions := {}
	for member in sim.players:
		positions[member.owned_ship.id] = member.position
	battle._begin_combat()
	check(not battle.deploying, "Changed placement saves through Begin Combat")
	check(state.load_run_checkpoint(), "Placement survives Continue")
	for ship: HangarShip in state.get_deployed_fleet():
		check((BattleSimulation.PLAYER_FORMATION_CENTER + ship.formation * BattleSimulation.DEPLOYMENT_SCALE).is_equal_approx(positions[ship.id]),
			"Saved individual and group placement remains intact")
	battle.queue_free()
	await settle()
	selection_completed = true

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Deployment selection requires native pointer and visual checks")
		quit(1)
		return
	await selection_checks()
	check(selection_completed, "Selection interaction reaches completed summary")
	print("DEPLOYMENT SELECTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
