extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _verify_paths(graph: Dictionary) -> void:
	var nodes: Array = graph.nodes
	var outgoing: Array[Array] = []
	var incoming: Array[Array] = []
	for node in nodes:
		outgoing.append([])
		incoming.append([])
	for edge in graph.edges:
		outgoing[int(edge[0])].append(int(edge[1]))
		incoming[int(edge[1])].append(int(edge[0]))
	var reached := {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		for target in outgoing[queue.pop_front()]:
			if not reached.has(target):
				reached[target] = true
				queue.append(target)
	_check(reached.size() == nodes.size(), "Every generated node must be reachable.")
	for boss in graph.bosses:
		var ancestors: Dictionary = {int(boss): true}
		queue.assign([int(boss)])
		while not queue.is_empty():
			for source in incoming[queue.pop_front()]:
				if not ancestors.has(source):
					ancestors[source] = true
					queue.append(source)
		for node in nodes:
			if node.act == nodes[int(boss)].act:
				_check(ancestors.has(int(node.id)), "Every act node must reach its boss.")
	# Min/max dynamic programming checks all possible routes, not sampled walks.
	var visits: Array[Vector2i] = []
	var battles: Array[Vector2i] = []
	for node in nodes:
		visits.append(Vector2i(1000, -1))
		battles.append(Vector2i(1000, -1))
	visits[0] = Vector2i.ZERO
	battles[0] = Vector2i.ZERO
	for row in range(25):
		for node in nodes:
			if int(node.row) != row:
				continue
			for target in outgoing[int(node.id)]:
				var combat := 1 if nodes[target].kind in ["combat", "boss"] else 0
				visits[target] = Vector2i(mini(visits[target].x, visits[int(node.id)].x + 1), maxi(visits[target].y, visits[int(node.id)].y + 1))
				battles[target] = Vector2i(mini(battles[target].x, battles[int(node.id)].x + combat), maxi(battles[target].y, battles[int(node.id)].y + combat))
	_check(visits[int(graph.final)] == Vector2i(24, 24), "Every full route visits exactly 24 nodes.")
	_check(battles[int(graph.final)] == Vector2i(14, 14), "Every full route contains exactly 14 objective battles.")
	for act in range(3):
		_check(battles[int(graph.bosses[act])] == Vector2i([4, 9, 14][act], [4, 9, 14][act]), "Act combat cadence must be 4/5/5.")


func _run() -> void:
	var fingerprints: Dictionary = {}
	var widths: Dictionary = {}
	var fallbacks := 0
	for seed_value in range(1000):
		var graph := CampaignGraph.generate(seed_value)
		_check(not graph.is_empty() and CampaignGraph.errors(graph).is_empty(), "Seed %d must generate a valid DAG." % seed_value)
		if graph.is_empty():
			continue
		_verify_paths(graph)
		fallbacks += 1 if graph.fallback else 0
		fingerprints[JSON.stringify(graph.edges).sha256_text()] = true
		var row_widths: Dictionary = {}
		for node in graph.nodes:
			row_widths[int(node.row)] = int(row_widths.get(int(node.row), 0)) + 1
		for count in row_widths.values():
			widths[count] = true
		if seed_value % 100 == 0:
			_check(graph == CampaignGraph.generate(seed_value), "Same seed must reproduce every node and edge.")
	_check(fingerprints.size() > 900 and widths.has(2) and widths.has(3) and widths.has(4), "Seeds must produce varied topology and row widths.")
	_check(fallbacks == 0, "Ordinary seeds should satisfy constraints without falling back.")
	var fallback := CampaignGraph._build(123, true)
	_check(CampaignGraph.errors(fallback).is_empty(), "The fixed fallback must itself satisfy every rule.")
	_verify_paths(fallback)

	var graph := CampaignGraph.generate(42)
	var corrupt := graph.duplicate(true)
	corrupt.edges.append([int(graph.final), 0])
	_check(not CampaignGraph.errors(corrupt).is_empty(), "Reject backward/cyclic edges.")
	corrupt = graph.duplicate(true)
	corrupt.edges.append(corrupt.edges[0].duplicate())
	_check(not CampaignGraph.errors(corrupt).is_empty(), "Reject duplicate edges.")
	corrupt = graph.duplicate(true)
	corrupt.edges = corrupt.edges.filter(func(edge: Array) -> bool: return int(edge[1]) != 1)
	_check(not CampaignGraph.errors(corrupt).is_empty(), "Reject unreachable nodes.")
	corrupt = graph.duplicate(true)
	for edge in corrupt.edges:
		if int(edge[0]) == 0:
			corrupt.nodes[int(edge[1])].elite = true
	_check(not CampaignGraph.errors(corrupt).is_empty(), "Reject mandatory elite choices.")
	corrupt = graph.duplicate(true)
	corrupt.nodes[1].combat_index = 14
	_check(not CampaignGraph.errors(corrupt).is_empty(), "Reject a corrupted combat cadence.")

	var state := root.get_node("GameState")
	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 4567), "New runs freeze a campaign DAG.")
	var saved: Variant = JSON.parse_string(JSON.stringify(state.campaign_dag))
	state.campaign_dag.clear()
	_check(state.load_run_checkpoint() and state.campaign_dag == saved, "Reload restores the exact frozen DAG.")
	state.credits += 100
	state.fleet[0].units[0].hp *= 0.5
	_check(state.campaign_dag == saved, "Fleet and resource changes cannot change topology.")
	var old := RunCheckpoint.capture(state)
	old.erase("campaign_graph")
	var invalid := RunCheckpoint.capture(state)
	invalid.campaign_graph.edges.append([int(invalid.campaign_graph.final), 0])
	_check(not RunCheckpoint.valid(invalid), "Checkpoint validation rejects corrupted frozen topology.")
	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 4567, false), "Prepare a historical layout fixture.")
	old = RunCheckpoint.capture(state)
	old.erase("campaign_graph")
	old.erase("campaign_active")
	_check(RunCheckpoint.valid(old), "Historical checkpoints without a campaign DAG remain valid.")
	print("Campaign graph tests finished: %d failures; 1000 seeds; %d unique topologies; %d fallbacks" % [failures, fingerprints.size(), fallbacks])
	quit(0 if failures == 0 else 1)
