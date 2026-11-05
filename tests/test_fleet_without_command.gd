extends "res://tests/test_fleet_redesign.gd"

var native_completed := false

func start_funded() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://fleet-without-command.json"
	check(state.start_new_run(1, 8405), "Start fleet without logistics research")
	state.pending_intro = false
	var data: Dictionary = state.hangar_snapshot()
	data.credits = 20000
	check(state._commit_hangar(data), "Fund isolated purchase fixture")

func mechanics() -> void:
	start_funded()
	check(state.buy_ships("fighter", 20) and state.buy_ships("transport", 5), "Buy fleet far beyond former command budget without research")
	check(state.fleet.size() == 38 and state.deployment_error().is_empty(), "Larger owned fleet remains deployable")
	check(state.current_research_ids == ["foundation"] and HangarCheckpoint.valid(state.hangar_snapshot()), "Checkpoint accepts large fleet without capacity grants")
	check(state.load_run_checkpoint() and state.fleet.size() == 38, "Continue preserves expanded ownership")
	var data: Dictionary = state.hangar_snapshot()
	var credits: int = data.credits
	check(state._rescue_ship(data, "transport").contains("joined") and data.ships.size() == 39 and data.credits == credits,
		"Rescue joins a larger fleet without command-full compensation")
	check(state._commit_hangar(data) and state.load_run_checkpoint() and state.fleet.size() == 39, "Rescue and empty loads survive Continue")
	var before: Dictionary = state.hangar_snapshot()
	check(not state.buy_ships("fighter", 9007199254740991) and SaveValidation.same(before, state.hangar_snapshot()), "Unaffordable huge batches fail before allocation or arithmetic overflow")
	check(not state.buy_ship("flagship_basic") and SaveValidation.same(before, state.hangar_snapshot()), "Removing command points does not permit buying a second flagship")
	data = state.hangar_snapshot()
	data.ships[0].flagship = false
	check(not HangarCheckpoint.valid(data), "Explicit flagship metadata still validates identity")
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-fleet-save.json"
	check(not state.buy_ship("drone") and SaveValidation.same(before, state.hangar_snapshot()), "Failed purchase save rolls back owned ships, credits and UIDs")
	state.run_save_path = path
	for id: String in ["fleet_logistics_i", "fleet_logistics_ii", "fleet_logistics_iii"]:
		check(GameDefinitions.find("research", id).is_empty() and not state.choose_research(id), "Removed logistics research cannot be found or selected")
	for seed_value in range(8):
		var progress := {"research_ids": ["foundation"], "research_offer": [], "research_points": 20.0, "story_flags": {}, "branch_choices": {}}
		HangarResearch.prepare_offer(progress, seed_value, 3, state.get_deployed_fleet())
		check(progress.research_offer.size() == 3 and progress.research_offer.all(func(id: String) -> bool: return not id.begins_with("fleet_logistics")), "Remaining research pool supplies choices without logistics")
	data = state.hangar_snapshot()
	data.research.research_points = 20
	data.research.research_offer = ["field_engineering"]
	check(state._commit_hangar(data) and state.choose_research("field_engineering"), "Remaining research selection still commits")
	check(state.research_points == 0 and HangarResearch.threshold(state.run_progress_snapshot()) == 40, "20/+20 research progression is unchanged")
	var sim := BattleSimulation.new()
	check(state.travel_to(state.get_reachable_nodes(state.current_node_id)[0]), "Prepare expanded fleet encounter")
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, 8405, state.battle_support_context())
		and sim.players.size() == 39, "Actual simulation deploys the full purchased/rescued fleet")

func native() -> void:
	start_funded()
	check(state.buy_ships("fighter", 20), "Native purchase exceeds former budget")
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	screen.active_tab = "FLEET"
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	await settle()
	check(not text_contains(screen, "Command ") and not text_contains(screen, "command capacity"), "Fleet contains no command-capacity readout")
	var group: Dictionary = HangarSquadrons.for_ship(state.squadrons, state.fleet[3].id)
	screen._select_squadron(int(group.id))
	await settle()
	var plus: Button = screen.details.find_child("BuyMore", true, false)
	check(plus != null and not plus.disabled, "Group quantity can increase beyond former budget")
	await click(plus)
	var count: int = state.fleet.size()
	await click(screen.details.find_child("SquadronBuy", true, false))
	check(state.fleet.size() == count + 2, "Pointer group purchase adds ships without capacity restriction")
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await capture("fleet-no-command-%d" % resolution.x)
	screen.queue_free()
	await settle()
	var setup: Control = load("res://scenes/game_setup.tscn").instantiate()
	root.add_child(setup)
	current_scene = setup
	await settle()
	check(not text_contains(setup, "Command Points"), "New-run flagship selector omits capacity")
	await capture("setup-no-command")
	setup.queue_free()
	await settle()
	native_completed = true

func text_contains(node: Node, fragment: String) -> bool:
	if node is Label and fragment in node.text:
		return true
	if node is ResourceText and fragment in node.source_text:
		return true
	for child in node.get_children():
		if text_contains(child, fragment):
			return true
	return false

func run() -> void:
	if "--native-only" not in OS.get_cmdline_user_args():
		mechanics()
	if DisplayServer.get_name() != "headless":
		await native()
		check(native_completed, "Native Fleet/setup verification completed")
	print("FLEET WITHOUT COMMAND: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
