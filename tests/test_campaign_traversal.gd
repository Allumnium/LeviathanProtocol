extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	for seed_value in range(1000):
		var graph := CampaignContent.populate(CampaignGraph.generate(seed_value), seed_value)
		_check(CampaignContent.valid(graph), "Typed node/route content must validate for seed %d." % seed_value)
		for node in graph.nodes:
			var port_row := 4 if int(node.act) == 1 else 3
			if int(node.local_row) == port_row or node.kind in ["start", "staging"]:
				_check(node.inhabited and node.services.has("refit"), "Every mandatory preparation row must provide ports on every lane.")
	var state := root.get_node("GameState")
	state.run_save_path = "user://campaign_traversal/run.json"
	for seed_value in [17, 42, 901]:
		_check(state.start_new_run(GameState.Difficulty.MEDIUM, seed_value), "Start active 24-row campaign.")
		_check(state.campaign_active and state.NODE_COLUMNS.max() == 24, "New campaigns activate the real map.")
		_check(state.restore_run_progress(state.run_progress_snapshot()) and state.NODE_COLUMNS.max() == 24,
			"Metadata round-trips cannot replace an active campaign with the legacy adapter.")
		_check(state.story_flags.get("delivered/haven", false), "Haven is delivered without research requirements.")
		var initial_ledger: int = state.transaction_ledger.size()
		_check(state.dispatch_arrival() and state.transaction_ledger.size() == initial_ledger, "Reopening a secured arrival cannot repeat its event.")
		var initial_credits: int = state.credits
		_check(state.commit_port_service("disembark", {}) and state.commit_port_service("disembark", {}) and state.credits == initial_credits,
			"Free service hooks are replay-safe and cannot create a refund or arrival payout.")
		var combats := 0
		var visits := 0
		while state.current_node_id != state.FINAL_NODE_ID:
			var previous: int = state.current_node_id
			var choices: Array[int] = state.get_reachable_nodes(previous)
			var destination: int = choices[(visits + seed_value) % choices.size()]
			var node: Dictionary = state.campaign_node(destination)
			var before_rp: int = state.research_points
			var frozen: Variant = JSON.parse_string(JSON.stringify(state.get_frozen_encounter(destination)))
			var preview: Dictionary = state.node_preview(destination)
			_check(not preview.text.is_empty(), "Every reachable destination has a truthful preview.")
			_check(state.travel_to(destination), "Adjacent travel must dispatch the correct node type.")
			if state.battle_pending:
				combats += 1
				_check(node.kind in ["combat", "boss"], "Noncombat nodes cannot hide battles.")
				_check(not state.dispatch_arrival(), "An unsecured approach cannot settle an arrival.")
				if combats == 1:
					var sim := BattleSimulation.new()
					_check(sim.setup_owned(state.fleet, state.battle_aliens, state.allied_salvage_chance(), state.laser_upgrade_level, state.battle_simulation_seed()), "Campaign battle setup uses the frozen roster.")
					sim.phase = BattleSimulation.Phase.WITHDRAWN
					_check(state.settle_battle(sim) and state.current_node_id == previous, "Failed approaches do not advance or settle arrival.")
					_check(state.load_run_checkpoint() and state.travel_to(destination), "Retry the same frozen campaign node after reload.")
					_check(JSON.parse_string(JSON.stringify(state.get_frozen_encounter(destination))) == frozen, "Retry cannot change announced encounters.")
				_check(state.complete_battle(), "Placeholder objective completion advances once.")
			else:
				_check(node.kind not in ["combat", "boss"], "Noncombat travel never deploys aliens.")
			_check(state.current_node_id == destination and state.research_points == before_rp, "Travel/rewards do not manufacture lab RP.")
			visits += 1
			var saved: Variant = JSON.parse_string(JSON.stringify(state.campaign_dag))
			_check(state.load_run_checkpoint() and state.current_node_id == destination and state.campaign_dag == saved, "Every row reloads exact progression/content.")
			if node.inhabited:
				var count_before: int = state.transaction_ledger.size()
				_check(not state.port_services().is_empty() and state.dispatch_arrival() and state.transaction_ledger.size() == count_before, "Port reopening/reload never repeats arrivals.")
			else:
				_check(state.port_services().is_empty() and not state.dispatch_arrival(), "Uninhabited nodes cannot grant arrival income or services.")
			if node.kind == "staging":
				_check(state.story_archive().size() >= 1 + int(node.act) * 2, "Every route receives staging story and boss briefs.")
			if node.kind == "boss" and int(node.act) < 3:
				_check(state.current_act() == int(node.act) + 1, "Clearing an act boss must reveal the next act immediately.")
				for next_id in state.get_reachable_nodes(state.current_node_id):
					_check(state.node_visible(next_id), "The next act's first fork must be visible and selectable from the completed boss.")
		_check(visits == 24 and combats == 14 and state.visited_nodes.size() == 25, "Full traversal has 24 visits and 14 battles.")
		_check(state.story_flags.get("delivered/ending", false) and state.story_flags.get("delivered/last_light", false), "The corrupted ark reveal and ending persist on every route.")
		_check(state.commit_port_service("offload", {}) == false, "Uninhabited final battle cannot provide port services.")

	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 777), "Start failure atomicity fixture.")
	var path: String = state.run_save_path
	var blocker := FileAccess.open("user://campaign_traversal/blocker", FileAccess.WRITE)
	blocker.store_string("file")
	blocker.close()
	var destination: int = state.get_reachable_nodes(0)[0]
	_check(state.travel_to(destination) and state.complete_battle(), "Reach the first noncombat row.")
	destination = state.get_reachable_nodes(state.current_node_id)[0]
	var previous: int = state.current_node_id
	var ledger_before: int = state.transaction_ledger.size()
	state.run_save_path = "user://campaign_traversal/blocker/run.json"
	_check(not state.travel_to(destination) and state.current_node_id == previous and state.transaction_ledger.size() == ledger_before, "Failed noncombat writes leave progression/reward retryable.")
	state.run_save_path = path
	_check(state.travel_to(destination), "A failed noncombat arrival remains retryable.")
	await _test_map_ui(state)
	print("Campaign traversal tests finished: %d failures; 1000 content seeds; 3 complete campaigns" % failures)
	quit(0 if failures == 0 else 1)

func _test_map_ui(state: Node) -> void:
	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 42), "Start map UI fixture.")
	var scene: PackedScene = load("res://scenes/game_map.tscn")
	var map := scene.instantiate()
	root.add_child(map)
	current_scene = map
	await process_frame
	await process_frame
	_check(map.port_button != null and not map.port_button.disabled, "Haven exposes real port services.")
	_check(map.campaign_overlay != null, "Haven story opens in a skippable archive panel.")
	_check(state.is_modal_ui_open(), "Story panels participate in modal/pause detection.")
	map.campaign_overlay.queue_free()
	await process_frame
	map._on_map_pressed()
	await process_frame
	var destination: int = state.get_reachable_nodes(0)[0]
	map.graph_view._select_node_at(map.graph_view._node_center(destination))
	_check(not map.route_travel_button.disabled and map.route_preview.text.contains("alien contacts"), "Selecting reachable combat shows contacts and an actionable route.")
	_check(map.graph_view.size.x <= 640 and map.graph_view.size.y <= 360, "Map fits the minimum viewport.")
	var graph_rect: Rect2 = map.graph_view.get_global_rect()
	var preview_rect: Rect2 = map.graph_view.get_node("RoutePreview").get_global_rect()
	_check(preview_rect.encloses(map.route_travel_button.get_global_rect()), "The travel button must fit inside its preview panel.")
	for node in state.campaign_dag.nodes:
		if int(node.act) > 1:
			_check(not state.node_visible(int(node.id)), "Future act routes remain hidden.")
		else:
			var point: Vector2 = map.graph_view.global_position + map.graph_view.world_transform() * map.graph_view._node_center(int(node.id))
			_check(point.y - 7 >= graph_rect.position.y and point.y + 7 <= preview_rect.position.y,
				"Initial act nodes must fit above the preview without clipping.")
	map._show_port_services()
	var count: int = state.transaction_ledger.size()
	map._show_port_services()
	_check(state.transaction_ledger.size() == count, "Opening port UI changes no arrival ledger.")
	map.campaign_overlay.queue_free()
	await process_frame
	map.route_travel_button.pressed.emit()
	await create_timer(0.6).timeout
	_check(current_scene != null and current_scene.scene_file_path == "res://scenes/auto_battle.tscn", "The live Travel button opens the announced battle after the short transition.")
	if current_scene != null and current_scene.scene_file_path == "res://scenes/auto_battle.tscn":
		var battle := current_scene
		battle.set_physics_process(false)
		for alien in battle.simulation.aliens:
			battle.simulation.damage_entity(alien.entity_id, 10000.0)
		for tick in range(120):
			battle._physics_process(1.0 / 30.0)
		_check(state.current_node_id == destination and not state.battle_pending, "The real battle controller settles the selected campaign node.")
		battle.queue_free()
	else:
		if current_scene != null:
			current_scene.queue_free()
	current_scene = null
	await process_frame
