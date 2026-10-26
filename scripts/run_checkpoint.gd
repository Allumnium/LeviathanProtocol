class_name RunCheckpoint
extends RefCounted

const VERSION := 1


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
		var weapons: Array = []
		for weapon in alien.stats.weapons:
			weapons.append([weapon.weapon_name, weapon.fire_interval_seconds, weapon.damage_per_shot,
				weapon.projectiles_per_activation, weapon.range_units, weapon.is_projectile_weapon])
		aliens.append({"name": alien.display_name, "stats": [alien.stats.shields,
			alien.stats.integrity, alien.stats.weight, alien.stats.thrust], "weapons": weapons})
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
		"graph": {"positions": positions, "columns": state.NODE_COLUMNS.duplicate(), "edges": edges,
			"convergences": state.CONVERGENCE_NODE_IDS.duplicate(), "final": state.FINAL_NODE_ID},
		"location": {"current": state.current_node_id, "destination": state.destination_node_id,
			"planned": state.planned_destination_node_id, "visited": state.visited_nodes.duplicate(),
			"pending": state.battle_pending}}


static func valid(data: Variant) -> bool:
	return not decode(data).is_empty()


static func decode(data: Variant) -> Dictionary:
	if not data is Dictionary or data.get("version") != VERSION:
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
	return {"data": data, "fleet": fleet, "aliens": aliens, "editor": editor}


static func _decode_alien(entry: Variant) -> AlienShip:
	if not entry is Dictionary or not entry.get("name") is String or not entry.get("stats") is Array:
		return null
	if entry.stats.size() != 4 or not entry.get("weapons") is Array or entry.weapons.is_empty():
		return null
	for value in entry.stats:
		if not _number(value) or value < 0:
			return null
	var result: AlienShip
	for definition in AlienShip.get_catalog():
		if definition.display_name == entry.name:
			result = definition
			break
	if result == null or entry.stats[1] <= 0:
		return null
	var stats := ShipStats.new()
	stats.shields = entry.stats[0]
	stats.integrity = entry.stats[1]
	stats.weight = entry.stats[2]
	stats.thrust = entry.stats[3]
	for weapon in entry.weapons:
		if not weapon is Array or weapon.size() != 6 or not weapon[0] is String or not weapon[5] is bool:
			return null
		for index in [1, 2, 4]:
			if not _number(weapon[index]) or weapon[index] <= 0:
				return null
		if not RunProgressData._integer(weapon[3]) or weapon[3] < 1:
			return null
		var stats_weapon := ShipWeaponStats.new(weapon[0], weapon[1], weapon[2], int(weapon[3]), weapon[4])
		stats_weapon.is_projectile_weapon = weapon[5]
		stats.weapons.append(stats_weapon)
	result.stats = stats
	return result


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value)


static func _vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])


static func _node(value: Variant, count: int, allow_none := false) -> bool:
	return RunProgressData._integer(value) and value >= (-1 if allow_none else 0) and value < count
