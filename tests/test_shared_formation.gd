extends "res://tests/test_fleet_redesign.gd"

func board_drag(screen: Control, point: Vector2, delta: Vector2, expect_save := true) -> void:
	var before: Dictionary = state.hangar_snapshot()
	var board: Control = screen.formation_view
	await pointer(point, true)
	check(is_instance_valid(board) and board == screen.formation_view and board.dragging, "Selection preserves board throughout gesture")
	var motion := InputEventMouseMotion.new()
	motion.position = point + delta * board.VIEW_SCALE * board.zoom
	motion.relative = delta * board.VIEW_SCALE * board.zoom
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await settle()
	check(SaveValidation.same(before, state.hangar_snapshot()), "Drag preview does not mutate saved formation")
	await pointer(motion.position, false)
	check(not SaveValidation.same(before, state.hangar_snapshot()) if expect_save else SaveValidation.same(before, state.hangar_snapshot()),
		"Release commits atomically or rolls back failed save")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Shared formation requires native interaction checks")
		quit(1)
		return
	state = root.get_node("GameState")
	state.run_save_path = "user://shared-formation.json"
	check(state.start_new_run(1, 8502), "Start shared formation fixture")
	state.pending_intro = false
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	screen.active_tab = "FLEET"
	screen._refresh()
	await settle()
	var ship_id: int = state.fleet[3].id
	var group_id: int = state.owned_ship(ship_id).squadron_id
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		var board: Control = screen.formation_view
		for owned: HangarShip in state.fleet:
			check(board.display_positions[owned.id] == owned.formation, "Fleet uses saved deployment position")
		var group := HangarSquadrons.find(state.squadrons, group_id)
		var before := {}
		for owned: HangarShip in state.fleet:
			before[owned.id] = owned.formation
		var point: Vector2 = board.global_position + board.flag_rect(group).get_center()
		await board_drag(screen, point, Vector2(0.12, 0.08))
		check(screen.selected_squadron_id == group_id and screen.details.has_node("SquadronStatBars"), "Dragged flag keeps squadron settings")
		for owned: HangarShip in state.fleet:
			var delta := Vector2(0.12, 0.08) if owned.squadron_id == group_id else Vector2.ZERO
			check(owned.formation.is_equal_approx(before[owned.id] + delta), "Group movement preserves spacing and other groups")
		board = screen.formation_view
		var ship: HangarShip = state.owned_ship(ship_id)
		var original := ship.formation
		var neighbour: HangarShip = state.fleet[4]
		var neighbour_origin := neighbour.formation
		point = board.global_position + board.point(ship)
		await board_drag(screen, point, Vector2(0.1, -0.08))
		check(state.owned_ship(ship_id).formation.is_equal_approx(original + Vector2(0.1, -0.08))
			and state.fleet[4].formation == neighbour_origin, "Ship gesture moves only individual")
		check(screen.selected_squadron_id == 0 and screen.details.has_node("ShipStatBars"), "Ship gesture keeps individual details")
		await capture("shared-fleet-%d" % resolution.x)
	# Pan and zoom remain cursor anchored and do not change formation.
	var before: Dictionary = state.hangar_snapshot()
	var board: Control = screen.formation_view
	var point: Vector2 = board.global_position + board.point(state.owned_ship(ship_id))
	var old_zoom: float = board.zoom
	await pointer(point, true, false, MOUSE_BUTTON_WHEEL_UP)
	check(board.zoom > old_zoom and SaveValidation.same(before, state.hangar_snapshot()), "Fleet zoom preserves formation")
	await pointer(point, true, false, MOUSE_BUTTON_MIDDLE)
	var motion := InputEventMouseMotion.new()
	motion.position = point + Vector2(12, 8)
	motion.relative = Vector2(12, 8)
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	root.push_input(motion, true)
	await pointer(motion.position, false, false, MOUSE_BUTTON_MIDDLE)
	check(board.camera != Vector2.ZERO and SaveValidation.same(before, state.hangar_snapshot()), "Fleet pan preserves formation")
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-formation.json"
	point = board.global_position + board.point(state.owned_ship(ship_id))
	await board_drag(screen, point, Vector2(-0.15, 0.1), false)
	check(not screen.feedback.text.is_empty() and board.display_positions[ship_id] == state.owned_ship(ship_id).formation,
		"Failed save surfaces error and restores drawn position")
	state.run_save_path = path
	check(state.load_run_checkpoint(), "Continue restores shared formation")
	await settle()
	for owned: HangarShip in state.fleet:
		check(screen.formation_view.display_positions[owned.id] == owned.formation, "Continue canvas follows saved formation")
	var area := BattleSimulation.formation_area()
	before = state.hangar_snapshot()
	check(not state.move_ships({ship_id: area.end}) and SaveValidation.same(before, state.hangar_snapshot()), "Shared bounds reject hull crossing edge")
	# Preview a clamped group gesture without committing an offscreen layout.
	board = screen.formation_view
	var group := HangarSquadrons.find(state.squadrons, group_id)
	board.selected_ids.assign(group.members)
	board._start_drag(Vector2.ZERO)
	var relative: Vector2 = board.display_positions[group.members[1]] - board.display_positions[ship_id]
	board._preview_drag(Vector2(100000, 100000))
	check((board.display_positions[group.members[1]] - board.display_positions[ship_id]).is_equal_approx(relative), "Fleet boundary clamp preserves group spacing")
	for id: int in group.members:
		var radius: float = state.owned_ship(id).get_stats().collision_radius / BattleSimulation.DEPLOYMENT_SCALE
		check(area.grow(-radius + 0.0001).has_point(board.display_positions[id]), "Fleet clamp contains every hull")
	board._load_formation()
	board.dragging = false
	var saved := {}
	for owned: HangarShip in state.fleet:
		saved[owned.id] = owned.formation
	screen.queue_free()
	await settle()
	check(state.travel_to(state.get_reachable_nodes(state.current_node_id)[0]), "Open actual encounter from shared Fleet placement")
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_process(false)
	battle.set_physics_process(false)
	await settle()
	for actor: BattleSimulation.Combatant in battle.simulation.players:
		check(actor.position.is_equal_approx(BattleSimulation.PLAYER_FORMATION_CENTER + saved[actor.owned_ship.id] * BattleSimulation.DEPLOYMENT_SCALE),
			"Battle setup uses exact Fleet placement")
	await capture("shared-battle-setup")
	var actor: BattleSimulation.Combatant = battle.simulation.players[3]
	battle.visuals.camera_position = actor.position
	battle.visuals.camera_zoom = 0.4
	await settle()
	var original := actor.position
	await drag(battle, actor, Vector2(18, -10))
	check(actor.position.is_equal_approx(original + Vector2(18, -10)), "Battle setup can revise shared placement")
	battle._begin_combat()
	check(not battle.deploying and state.load_run_checkpoint(), "Begin Combat and Continue persist revised formation")
	var expected := (actor.position - BattleSimulation.PLAYER_FORMATION_CENTER) / BattleSimulation.DEPLOYMENT_SCALE
	check(state.owned_ship(actor.owned_ship.id).formation.is_equal_approx(expected), "Battle edit becomes Fleet saved position")
	# Use the production Fleet canvas directly while encounter is pending, avoiding scene routing.
	var return_board: Control = load("res://scripts/hangar_formation.gd").new()
	root.add_child(return_board)
	return_board.size = Vector2(320, 240)
	await settle()
	check(return_board.display_positions[actor.owned_ship.id].is_equal_approx(expected), "Returning Fleet canvas renders battle edit")
	return_board.queue_free()
	battle.queue_free()
	await settle()
	print("SHARED FORMATION COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
