class_name RunCheckpoint
extends RefCounted

const VERSION := 2


static func capture(state: Node) -> Dictionary:
	var ships: Array = []
	for owned: FleetShip in state.fleet:
		var hp: Array = []
		for unit in owned.units:
			hp.append(unit.hp)
		ships.append({"id": owned.id, "name": owned.display_name, "design": owned.design.to_design_data(),
			"formation": [owned.formation.x, owned.formation.y], "hp": hp})
	var aliens: Array = []
	for alien: AlienShip in state.battle_aliens:
		aliens.append(alien.to_snapshot())
	var positions: Array = []
	for point: Vector2 in state.NODE_POSITIONS:
		positions.append([point.x, point.y])
	var edges: Array = []
	for edge: Vector2i in state.GRAPH_EDGES:
		edges.append([edge.x, edge.y])
	return {"version": VERSION, "run_id": state.run_id, "progress": state.run_progress_snapshot(),
		"inventory": [state.red_tiles_available, state.blue_tiles_available, state.green_tiles_available, state.core_tiles_available],
		"ledger": state.transaction_ledger.duplicate(true), "economy": state.economy_state.duplicate(true),
		"fleet": ships, "editor": state.ship.to_design_data(), "editor_name": state.current_ship_design_name,
		"next_ship_id": state.next_ship_id, "laser_level": state.laser_upgrade_level,
		"build_level": state.build_area_level, "aliens": aliens,
		"encounters": state.frozen_encounters.duplicate(true),
		"encounter_progress": state.encounter_progress.duplicate(true),
		"graph": {"positions": positions, "columns": state.NODE_COLUMNS.duplicate(), "edges": edges,
			"convergences": state.CONVERGENCE_NODE_IDS.duplicate(), "final": state.FINAL_NODE_ID},
		"location": {"current": state.current_node_id, "destination": state.destination_node_id,
			"planned": state.planned_destination_node_id, "visited": state.visited_nodes.duplicate(),
			"pending": state.battle_pending}}


static func valid(data: Variant) -> bool:
	return not decode(data).is_empty()


static func decode(data: Variant) -> Dictionary:
	if not data is Dictionary or (data.get("version") != VERSION and data.get("version") != 1):
		return {}
	if not data.get("run_id") is String or data.run_id.is_empty():
		return {}
	if not RunProgressData.validate(data.get("progress")).is_empty():
		return {}
	if not data.get("inventory") is Array or data.inventory.size() != 4:
		return {}
	for amount in data.inventory:
		if not RunProgressData._integer(amount) or amount < 0:
			return {}
	if not TransactionLedger.valid(data.get("ledger"), data.run_id) or not data.get("economy") is Dictionary:
		return {}
	for key in ["next_ship_id", "laser_level", "build_level"]:
		if not RunProgressData._integer(data.get(key)) or data[key] < 0:
			return {}
	if data.next_ship_id < 1 or data.laser_level > 3 or data.build_level > 5:
		return {}
	if not data.get("editor_name") is String or not data.get("fleet") is Array or not data.get("aliens") is Array:
		return {}
	var editor := Ship.new()
	if not editor.load_design_data(data.get("editor")):
		return {}
	var fleet: Array[FleetShip] = []
	var ship_ids: Array[int] = []
	for entry in data.fleet:
		if not entry is Dictionary or not RunProgressData._integer(entry.get("id")):
			return {}
		if entry.id < 1 or int(entry.id) in ship_ids or not entry.get("name") is String:
			return {}
		if not _vector(entry.get("formation")) or not entry.get("hp") is Array:
			return {}
		var design := Ship.new()
		if not design.load_design_data(entry.get("design")) or design.tiles.is_empty():
			return {}
		var owned := FleetShip.new()
		owned.initialize(design, int(entry.id), entry.name)
		if owned.core_index < 0 or entry.hp.size() != owned.units.size():
			return {}
		for index in range(owned.units.size()):
			var hp: Variant = entry.hp[index]
			if not _number(hp) or hp < 0 or hp > owned.units[index].max_hp + 0.00000001:
				return {}
			owned.units[index].hp = minf(float(hp), owned.units[index].max_hp)
		owned.formation = Vector2(entry.formation[0], entry.formation[1])
		fleet.append(owned)
		ship_ids.append(owned.id)
	for id in ship_ids:
		if id >= int(data.next_ship_id):
			return {}
	var aliens: Array[RefCounted] = []
	for entry in data.aliens:
		var alien := _decode_alien(entry)
		if alien == null:
			return {}
		aliens.append(alien)
	var graph: Variant = data.get("graph")
	var location: Variant = data.get("location")
	if not graph is Dictionary or not location is Dictionary:
		return {}
	for key in ["positions", "columns", "edges", "convergences"]:
		if not graph.get(key) is Array:
			return {}
	var count: int = graph.positions.size()
	if count == 0 or graph.columns.size() != count or not _node(graph.get("final"), count):
		return {}
	for point in graph.positions:
		if not _vector(point):
			return {}
	for column in graph.columns:
		if not RunProgressData._integer(column) or column < 0:
			return {}
	for edge in graph.edges:
		if not edge is Array or edge.size() != 2 or not _node(edge[0], count) or not _node(edge[1], count):
			return {}
		if graph.columns[int(edge[1])] <= graph.columns[int(edge[0])]:
			return {}
	for node in graph.convergences:
		if not _node(node, count):
			return {}
	if not location.get("pending") is bool or not location.get("visited") is Array:
		return {}
	if not _node(location.get("current"), count):
		return {}
	for key in ["destination", "planned"]:
		if not _node(location.get(key), count, true):
			return {}
	for node in location.visited:
		if not _node(node, count):
			return {}
	if location.pending and (location.destination < 0 or aliens.is_empty()):
		return {}
	if data.version == 1:
		# Preserve the actual deployed legacy roster and its old reward contract.
		data = data.duplicate(true)
		data.version = VERSION
		data.encounters = EncounterGenerator.freeze_graph(int(data.progress.seed), int(data.progress.difficulty), graph.columns)
		if location.pending:
			var key := str(int(location.destination))
			if not data.encounters.has(key):
				return {}
			var frozen: Dictionary = data.encounters[key]
			frozen.legacy = true
			frozen.roster.clear()
			frozen.spent = 0.0
			frozen.wave_count = 1
			frozen.rewards = {"credits": 200, "materials": [0, 0, 0, 0]}
			data.aliens.clear()
			for index in range(aliens.size()):
				var unit: AlienShip = aliens[index]
				unit.entity_id = "node/%s/legacy/%d" % [key, index]
				unit.threat_cost = 0.0
				frozen.roster.append(unit.to_snapshot())
				data.aliens.append(unit.to_snapshot())
			var required_ids: Array[String] = []
			for unit: AlienShip in aliens:
				required_ids.append(unit.entity_id)
			frozen.objective = {"type": "eliminate_targets", "required_target_ids": required_ids}
	if not data.get("encounters") is Dictionary:
		return {}
	if not _valid_encounter_progress(data.get("encounter_progress", {}), count):
		return {}
	for node in range(count):
		if int(graph.columns[node]) == 0:
			continue
		var frozen: Variant = data.encounters.get(str(node))
		if not EncounterGenerator.valid(frozen) or int(frozen.node_id) != node:
			return {}
	return {"data": data, "fleet": fleet, "aliens": aliens, "editor": editor}


static func _valid_encounter_progress(value: Variant, count: int) -> bool:
	if not value is Dictionary:
		return false
	for key in value:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or not _node(int(key), count):
			return false
		var entry: Variant = value[key]
		if not entry is Dictionary or not RunProgressData._integer(entry.get("attempts")) or entry.attempts < 1:
			return false
		if entry.get("outcome") not in ["active", "withdrawn", "defeat", "victory"] or not entry.get("field") is Dictionary:
			return false
		if not _json_value(entry.field):
			return false
		if entry.has("journal") and (not entry.journal is Dictionary or not _json_value(entry.journal)):
			return false
		if entry.has("deployment") and (not entry.deployment is Dictionary or not _json_value(entry.deployment)):
			return false
		if entry.has("ship_ids"):
			if not entry.ship_ids is Array:
				return false
			var ship_ids: Array[int] = []
			for id in entry.ship_ids:
				if not RunProgressData._integer(id) or id < 1 or int(id) in ship_ids:
					return false
				ship_ids.append(int(id))
	return true


static func _json_value(value: Variant, depth := 0) -> bool:
	if depth > 32:
		return false
	if value == null or value is bool or value is String:
		return true
	if value is int or value is float:
		return is_finite(value)
	if value is Dictionary:
		for key in value:
			if not key is String or not _json_value(value[key], depth + 1):
				return false
		return true
	if value is Array:
		for item in value:
			if not _json_value(item, depth + 1):
				return false
		return true
	return false


static func _decode_alien(entry: Variant) -> AlienShip:
	return AlienShip.from_snapshot(entry)


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value)


static func _vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])


static func _node(value: Variant, count: int, allow_none := false) -> bool:
	return RunProgressData._integer(value) and value >= (-1 if allow_none else 0) and value < count
