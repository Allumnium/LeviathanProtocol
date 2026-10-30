class_name RunCheckpoint
extends RefCounted

const VERSION := 2


static func capture(state: Node) -> Dictionary:
	var ships: Array = []
	for owned: FleetShip in state.fleet:
		ships.append(ship_entry(owned))
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
		"campaign_graph": state.campaign_dag.duplicate(true),
		"campaign_active": state.campaign_active,
		"fleet_roster": state.roster_state.duplicate(true),
		"graph": {"positions": positions, "columns": state.NODE_COLUMNS.duplicate(), "edges": edges,
			"convergences": state.CONVERGENCE_NODE_IDS.duplicate(), "final": state.FINAL_NODE_ID},
		"location": {"current": state.current_node_id, "destination": state.destination_node_id,
			"planned": state.planned_destination_node_id, "visited": state.visited_nodes.duplicate(),
			"pending": state.battle_pending}}


static func ship_entry(owned: FleetShip) -> Dictionary:
	var hp: Array = []
	for unit in owned.units:
		hp.append(unit.hp)
	return {"id": owned.id, "name": owned.display_name, "design": owned.design.to_design_data(),
		"formation": [owned.formation.x, owned.formation.y], "hp": hp,
		"family_id": owned.family_id, "slot_role": owned.slot_role, "reserve": owned.in_reserve,
		"escort_target_id": owned.escort_target_id}


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
		if not entry.get("family_id", "") is String or entry.get("slot_role", "regular") not in FleetRules.ROLES or not entry.get("reserve", false) is bool:
			return {}
		if not RunProgressData._integer(entry.get("escort_target_id", 0)) or entry.get("escort_target_id", 0) < 0:
			return {}
		owned.family_id = entry.get("family_id", "")
		owned.slot_role = entry.get("slot_role", "regular")
		owned.in_reserve = entry.get("reserve", false)
		owned.escort_target_id = int(entry.get("escort_target_id", 0))
		fleet.append(owned)
		ship_ids.append(owned.id)
	for id in ship_ids:
		if id >= int(data.next_ship_id):
			return {}
	var aliens: Array[RefCounted] = []
	if not PassengerRules.valid(data.economy, fleet) or not CargoRules.valid(data.economy, fleet):
		return {}
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
	if data.has("campaign_graph"):
		if not data.campaign_graph is Dictionary:
			return {}
		if not data.campaign_graph.is_empty() and (not CampaignGraph.errors(data.campaign_graph).is_empty() or data.campaign_graph.seed != data.progress.seed):
			return {}
	if data.has("campaign_active") and not data.campaign_active is bool:
		return {}
	var active: bool = data.get("campaign_active", false)
	if data.has("fleet_roster") and not data.fleet_roster is Dictionary:
		return {}
	if active:
		if not data.has("fleet_roster"):
			data = data.duplicate(true)
			data.fleet_roster = FleetRules.migrate(fleet)
			data.progress.family_identity_version = 1
			var names: Array[String] = []
			for id in data.fleet_roster.active:
				names.append("" if str(id).is_empty() else str(data.fleet_roster.families[id].name))
			data.progress.active_design_families = names
			var deployed_ids: Array[int] = []
			for index in range(fleet.size()):
				var owned: FleetShip = fleet[index]
				data.fleet[index].family_id = owned.family_id
				data.fleet[index].slot_role = "regular"
				data.fleet[index].reserve = false
				if owned.is_alive() and data.fleet_roster.active.has(owned.family_id):
					deployed_ids.append(owned.id)
			if location.pending:
				var key := str(int(location.destination))
				if not data.has("encounter_progress"):
					data.encounter_progress = {}
				if not data.encounter_progress.has(key):
					data.encounter_progress[key] = {"attempts": 1, "outcome": "active", "field": {}}
				data.encounter_progress[key].ship_ids = deployed_ids
				if data.encounter_progress[key].has("deployment"):
					data.encounter_progress[key].deployment.fleet = data.fleet.filter(func(entry: Dictionary) -> bool: return deployed_ids.has(int(entry.id)))
			# Normalize newly inserted StringName keys to their persisted JSON form.
			data = JSON.parse_string(JSON.stringify(data))
		if data.has("fleet_roster") and not FleetRules.valid(data.fleet_roster, fleet):
			return {}
		if int(data.fleet_roster.version) == 1:
			data = data.duplicate(true)
			data.fleet_roster = FleetRules.integrate_support(data.fleet_roster, fleet)
			data.fleet.clear()
			for owned in fleet:
				data.fleet.append(ship_entry(owned))
			data.progress.active_design_families = []
			for id: String in data.fleet_roster.active:
				data.progress.active_design_families.append("" if id.is_empty() else str(data.fleet_roster.families[id].name))
			if location.pending:
				var pending_key := str(int(location.destination))
				if data.encounter_progress.has(pending_key):
					data.encounter_progress[pending_key]["migrated_support_attempt"] = true
		if not data.has("campaign_graph") or not CampaignContent.valid(data.campaign_graph) or count != data.campaign_graph.nodes.size():
			return {}
		if not _same(graph.edges, data.campaign_graph.edges) or not _same(graph.convergences, data.campaign_graph.staging) or graph.final != data.campaign_graph.final:
			return {}
		for node in data.campaign_graph.nodes:
			var point: Array = graph.positions[int(node.id)]
			if graph.columns[int(node.id)] != node.row or not is_equal_approx(float(point[0]), float(node.position[0])) or not is_equal_approx(float(point[1]), float(node.position[1])):
				return {}
	for node in range(count):
		if int(graph.columns[node]) == 0:
			continue
		if active and data.campaign_graph.nodes[node].kind not in ["combat", "boss"]:
			if data.encounters.has(str(node)):
				return {}
			continue
		var frozen: Variant = data.encounters.get(str(node))
		if not EncounterGenerator.valid(frozen) or int(frozen.node_id) != node:
			return {}
		if active and (int(frozen.global_row) != int(graph.columns[node]) or not _campaign_encounter_matches(frozen, data.campaign_graph.nodes[node])):
			return {}
		var context: Dictionary = data.encounter_progress.get(str(node), {}).get("deployment", {}).get("shared_context", {})
		if frozen.has("arena_layout") and data.encounter_progress.get(str(node), {}).has("deployment") and not context.has("encounter_plan"):
			return {}
		if context.has("encounter_plan") and not _same(context.encounter_plan, frozen):
			return {}
	return {"data": data, "fleet": fleet, "aliens": aliens, "editor": editor}


static func _same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


static func _campaign_encounter_matches(encounter: Dictionary, node: Dictionary) -> bool:
	var expected := "boss_patrol" if node.kind == "boss" else ("elite" if node.elite else "patrol")
	if encounter.has("arena_layout") and node.kind == "combat" and not node.elite and int(node.combat_index) % 2 == 0:
		expected = "relay_defense"
	if encounter.has("warden"):
		expected = "bastion_warden" if node.kind == "boss" and int(node.act) == 1 else ("pylon_escort" if node.kind == "combat" and int(node.act) == 1 and int(node.local_row) == 5 else "invalid")
	return encounter.template_id == expected


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
		if entry.has("migrated_support_attempt") and not entry.migrated_support_attempt is bool:
			return false
		if not _json_value(entry.field):
			return false
		if entry.field.has("repair_reserves") and not SharedSupport.valid_reserves(entry.field.repair_reserves):
			return false
		if entry.field.has("repair_pool") and not SharedSupport.valid_pool(entry.field.repair_pool):
			return false
		if entry.field.has("asteroids") and not AsteroidField.valid(entry.field.asteroids):
			return false
		if entry.has("journal") and (not entry.journal is Dictionary or not _json_value(entry.journal)):
			return false
		if entry.has("deployment") and (not entry.deployment is Dictionary or not _json_value(entry.deployment)):
			return false
		if entry.get("deployment", {}).has("shared_context"):
			var context: Variant = entry.deployment.shared_context
			if context is Dictionary and context.has("encounter_plan") and not EncounterGenerator.valid(context.encounter_plan):
				return false
			if context is Dictionary and context.has("asteroids") and not AsteroidField.valid(context.asteroids):
				return false
			if context is Dictionary and context.has("mining_materials") and not AsteroidField.valid_policy({"rate": 0, "materials": context.mining_materials}):
				return false
			if context is Dictionary and context.has("enemy_roles") and not context.enemy_roles is bool:
				return false
			if not context is Dictionary or not _number(context.get("energy_efficiency")) or context.energy_efficiency < 0 or context.energy_efficiency > 0.3 \
				or not SharedSupport.valid_reserves(context.get("repair_reserves")):
				return false
			if context.has("visibility_enabled") and not context.visibility_enabled is bool:
				return false
			if context.has("ability_state") and not BattleAbilities.valid(context.ability_state):
				return false
			if context.has("ability_ids"):
				if not context.ability_ids is Array:
					return false
				var seen_abilities := {}
				for id in context.ability_ids:
					if not id is String or seen_abilities.has(id) or GameDefinitions.find("abilities", id).is_empty():
						return false
					seen_abilities[id] = true
			if not SharedSupport.valid_pool(context.get("repair_pool", {"capacity": 0, "spent": 0.0})):
				return false
		if entry.has("ship_ids"):
			if not entry.ship_ids is Array:
				return false
			var ship_ids: Array[int] = []
			for id in entry.ship_ids:
				if not RunProgressData._integer(id) or id < 1 or int(id) in ship_ids:
					return false
				ship_ids.append(int(id))
		if entry.has("science_snapshot") and not ScienceRules.valid(entry.science_snapshot, entry.get("ship_ids", [])):
			return false
		if entry.has("research_distance") and (not RunProgressData._integer(entry.research_distance) or entry.research_distance < 0 or entry.research_distance > 24):
			return false
		if entry.has("research_travel_days") and (not _number(entry.research_travel_days) or entry.research_travel_days < 0 or entry.research_travel_days > 24 * 4.0):
			return false
		if not entry.has("science_snapshot") and entry.get("deployment") is Dictionary and entry.deployment.get("fleet") is Array \
			and ScienceRules.deployment_has_lab(entry.deployment.fleet):
			return false
		if entry.has("science_snapshot") and (not entry.get("deployment") is Dictionary or not entry.deployment.get("fleet") is Array \
			or not ScienceRules.matches_deployment(entry.science_snapshot, entry.deployment.fleet)):
			return false
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
