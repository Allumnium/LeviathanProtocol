class_name CampaignGraph
extends RefCounted

const VERSION := 1
const COMBAT_ROWS := [[1, 3, 5, 8], [1, 2, 4, 5, 8], [1, 2, 4, 5, 8]]


static func generate(seed_value: int) -> Dictionary:
	if seed_value < 0:
		return {}
	var graph := _build(seed_value, false)
	if errors(graph).is_empty():
		return graph
	# A fixed lane pattern and edge construction provide a deterministic fallback.
	graph = _build(seed_value, true)
	return graph if errors(graph).is_empty() else {}


static func _build(seed_value: int, fallback: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0 if fallback else seed_value
	var graph := {"version": VERSION, "seed": str(seed_value), "fallback": fallback,
		"nodes": [], "edges": [], "staging": [], "bosses": [], "final": -1}
	graph.nodes.append({"id": 0, "row": 0, "act": 0, "local_row": 0, "lane": 0,
		"kind": "start", "combat_index": 0, "elite": false, "position": [0.035, 0.5]})
	var previous: Array[int] = [0]
	var combat_index := 0
	for row in range(1, 25):
		var act := int((row - 1) / 8)
		var local_row := (row - 1) % 8 + 1
		var count := 1
		match local_row:
			1: count = 3
			2, 4, 6: count = 2 if fallback else rng.randi_range(2, 3)
			3, 5: count = 3 if fallback else rng.randi_range(3, 4)
		var combat: bool = COMBAT_ROWS[act].has(local_row)
		if combat:
			combat_index += 1
		var current: Array[int] = []
		var elite_lane := -1
		if not fallback and local_row == (3 if act == 0 else 4):
			elite_lane = rng.randi_range(0, count - 1)
		for lane in range(count):
			var id: int = graph.nodes.size()
			var y := 0.5 if count == 1 else lerpf(0.16, 0.84, float(lane) / float(count - 1))
			if count > 1 and not fallback:
				y += rng.randf_range(-0.025, 0.025)
			var kind := "combat" if combat else "noncombat"
			if local_row == 7:
				kind = "staging"
				graph.staging.append(id)
			elif local_row == 8:
				kind = "boss"
				graph.bosses.append(id)
			graph.nodes.append({"id": id, "row": row, "act": act + 1, "local_row": local_row,
				"lane": lane, "kind": kind, "combat_index": combat_index if combat else 0,
				"elite": lane == elite_lane, "position": [lerpf(0.035, 0.965, float(row) / 24.0), y]})
			current.append(id)
		# Lay down adjacent lane paths first, covering both sides of the boundary.
		for lane in range(previous.size()):
			var to_lane := 0 if previous.size() == 1 else roundi(float(lane) * float(count - 1) / float(previous.size() - 1))
			_add_edge(graph, previous[lane], current[to_lane])
		for lane in range(count):
			var from_lane := 0 if count == 1 else roundi(float(lane) * float(previous.size() - 1) / float(count - 1))
			_add_edge(graph, previous[from_lane], current[lane])
		# Two three-way forks inside every act, followed by narrower merge rows.
		if local_row in [3, 5]:
			var source: int = previous[0 if fallback else rng.randi_range(0, previous.size() - 1)]
			for lane in range(3):
				_add_edge(graph, source, current[lane])
		# Add selected cross-lane connections without exceeding three exits.
		if not fallback and previous.size() > 1 and count > 1:
			for source in previous:
				if rng.randf() < 0.45:
					_add_edge(graph, source, current[rng.randi_range(0, count - 1)])
		# Every source at an elite fork retains a direct non-elite continuation.
		if elite_lane >= 0:
			for source in previous:
				var safe := false
				for edge in graph.edges:
					if edge[0] == source and edge[1] in current and not graph.nodes[edge[1]].elite:
						safe = true
				if not safe:
					_add_edge(graph, source, current[(elite_lane + 1) % count])
		previous = current
	graph.final = previous[0]
	return graph


static func _add_edge(graph: Dictionary, source: int, target: int) -> void:
	var exits := 0
	for edge in graph.edges:
		if edge[0] == source:
			exits += 1
			if edge[1] == target:
				return
	if exits < 3:
		graph.edges.append([source, target])


static func errors(value: Variant) -> Array[String]:
	var issues: Array[String] = []
	if not value is Dictionary or value.get("version") != VERSION or not value.get("seed") is String:
		return ["Unsupported campaign graph."]
	if not value.seed.is_valid_int() or int(value.seed) < 0 or str(int(value.seed)) != value.seed:
		return ["Invalid graph seed."]
	if not value.get("nodes") is Array or not value.get("edges") is Array or not value.get("fallback") is bool:
		return ["Missing graph data."]
	var nodes: Array = value.nodes
	if nodes.size() < 25 or nodes.size() > 97:
		return ["Invalid graph size."]
	var rows: Array[Array] = []
	var incoming: Array[Array] = []
	var outgoing: Array[Array] = []
	for row in range(25):
		rows.append([])
	for id in range(nodes.size()):
		var node: Variant = nodes[id]
		if not node is Dictionary:
			return ["Invalid node."]
		for key in ["id", "row", "act", "local_row", "lane", "combat_index"]:
			if not RunProgressData._integer(node.get(key)):
				return ["Invalid node number."]
		if node.id != id or node.row < 0 or node.row > 24 or not node.get("elite") is bool:
			return ["Invalid node identity/row."]
		if not RunCheckpoint._vector(node.get("position")) or node.position[0] < 0 or node.position[0] > 1 or node.position[1] < 0 or node.position[1] > 1:
			return ["Invalid node position."]
		rows[int(node.row)].append(id)
		incoming.append([])
		outgoing.append([])
	if rows[0] != [0] or nodes[0].get("kind") != "start" or nodes[0].act != 0 or nodes[0].local_row != 0 or nodes[0].elite:
		return ["Invalid starting anchorage."]
	var expected_staging: Array[int] = []
	var expected_bosses: Array[int] = []
	var combat_index := 0
	for row in range(1, 25):
		var act := int((row - 1) / 8)
		var local_row := (row - 1) % 8 + 1
		var count: int = rows[row].size()
		if (local_row in [7, 8] and count != 1) or (local_row < 7 and (count < 2 or count > 4)):
			return ["Invalid row width."]
		var combat: bool = COMBAT_ROWS[act].has(local_row)
		if combat:
			combat_index += 1
		var last_y := -1.0
		for lane in range(count):
			var node: Dictionary = nodes[rows[row][lane]]
			var expected_kind := "combat" if combat else "noncombat"
			if local_row == 7:
				expected_kind = "staging"
				expected_staging.append(int(node.id))
			elif local_row == 8:
				expected_kind = "boss"
				expected_bosses.append(int(node.id))
			if node.act != act + 1 or node.local_row != local_row or node.lane != lane or node.get("kind") != expected_kind:
				return ["Node does not match its campaign row."]
			if node.combat_index != (combat_index if combat else 0) or (node.elite and expected_kind != "combat"):
				return ["Invalid combat cadence/elite placement."]
			if absf(node.position[0] - lerpf(0.035, 0.965, float(row) / 24.0)) > 0.00001 or node.position[1] <= last_y:
				return ["Invalid row/lane geometry."]
			last_y = node.position[1]
	for edge in value.edges:
		if not edge is Array or edge.size() != 2 or not RunCheckpoint._node(edge[0], nodes.size()) or not RunCheckpoint._node(edge[1], nodes.size()):
			return ["Invalid edge."]
		var source := int(edge[0])
		var target := int(edge[1])
		if nodes[target].row != nodes[source].row + 1 or outgoing[source].has(target):
			return ["Backward, skipped-row or duplicate edge."]
		outgoing[source].append(target)
		incoming[target].append(source)
	if not RunCheckpoint._node(value.get("final"), nodes.size()) or value.final != expected_bosses[2]:
		return ["Invalid final boss."]
	if not _same_ids(value.get("staging"), expected_staging) or not _same_ids(value.get("bosses"), expected_bosses):
		return ["Invalid checkpoint identities."]
	for id in range(nodes.size()):
		if id > 0 and incoming[id].is_empty():
			issues.append("Unreachable node.")
		if (id != int(value.final) and outgoing[id].is_empty()) or outgoing[id].size() > 3:
			issues.append("Dead end or too many exits.")
		var safe := false
		for target in outgoing[id]:
			if nodes[id].elite and nodes[target].elite:
				issues.append("Consecutive elites.")
			if not nodes[target].elite:
				safe = true
		if not outgoing[id].is_empty() and not safe:
			issues.append("Mandatory elite continuation.")
	for act in range(1, 4):
		var forks := 0
		var merges := 0
		var three_way := false
		for node in nodes:
			if node.act != act or node.local_row >= 7:
				continue
			var id := int(node.id)
			if outgoing[id].size() >= 2:
				forks += 1
				three_way = three_way or outgoing[id].size() == 3
			if incoming[id].size() >= 2:
				merges += 1
		if forks < 2 or merges < 1 or not three_way:
			issues.append("Act lacks required forks/merge/three-way choice.")
	# Adjacent-row edges and nonzero degrees prove reachability in both directions:
	# the unique row-zero start reaches all nodes, and every node reaches its boss.
	return issues


static func _same_ids(actual: Variant, expected: Array[int]) -> bool:
	if not actual is Array or actual.size() != expected.size():
		return false
	for index in range(expected.size()):
		if not RunProgressData._integer(actual[index]) or actual[index] != expected[index]:
			return false
	return true
