class_name HangarCheckpoint
extends RefCounted

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("format") != "physical_hangar" or value.get("version") != 1:
		return false
	if not _integer(value.get("credits"), -2147483647):
		return false
	for key in ["next_ship_id", "next_equipment_id", "difficulty", "current"]:
		if not _integer(value.get(key), 0):
			return false
	if value.difficulty > 2 or value.next_ship_id < 1 or value.next_equipment_id < 1 or not value.get("seed") is String or not value.seed.is_valid_int() or int(value.seed) < 0 or not value.get("run_id") is String or value.run_id.is_empty():
		return false
	for key in ["pending", "ended", "completed"]:
		if not value.get(key) is bool:
			return false
	for key in ["destination", "planned"]:
		if not _integer(value.get(key), -1):
			return false
	if not _number(value.get("journey_rp")) or value.journey_rp < 0 or not value.get("equipment") is Dictionary or not value.get("ships") is Array or not value.get("visited") is Array or not value.get("research") is Dictionary:
		return false
	var graph := CampaignGraph.generate(int(value.seed))
	var reserves: Variant = value.get("battle_reserves", {})
	if not reserves is Dictionary:
		return false
	for key: Variant in reserves:
		if not key is String or not key.is_valid_int() or int(key) < 0 or int(key) >= graph.nodes.size() or not CombatDoctrines.valid_pool(reserves[key]):
			return false
		for uid: String in reserves[key].get("carriers", {}):
			if int(uid) >= value.next_equipment_id:
				return false
			if value.equipment.has(uid) and value.equipment[uid].equipment_id != reserves[key].carriers[uid].equipment_id:
				return false
	if value.current >= graph.nodes.size() or value.destination >= graph.nodes.size() or value.planned >= graph.nodes.size() or value.visited.is_empty() or value.visited[0] != 0:
		return false
	var seen_nodes := {}
	for node in value.visited:
		if not _integer(node, 0) or node >= graph.nodes.size() or seen_nodes.has(int(node)):
			return false
		seen_nodes[int(node)] = true
	if not seen_nodes.has(int(value.current)) or value.pending != (value.destination >= 0) or (not value.pending and value.journey_rp != 0):
		return false
	if value.pending and not graph.edges.any(func(edge: Array) -> bool: return int(edge[0]) == int(value.current) and int(edge[1]) == int(value.destination)):
		return false
	var encounter: Variant = value.get("pending_encounter", {})
	if not encounter is Dictionary or (value.pending and not EncounterGenerator.valid(encounter)) or (not value.pending and not encounter.is_empty()):
		return false
	var progress: Dictionary = value.research
	if not progress.get("research_ids") is Array or not progress.get("story_flags") is Dictionary or not progress.get("branch_choices") is Dictionary or not _number(progress.get("research_points")) or progress.research_points < 0:
		return false
	if not HangarResearch.valid(progress):
		return false
	var equipment: Dictionary = value.equipment
	for uid: Variant in equipment:
		var instance: Variant = equipment[uid]
		if not uid is String or not uid.is_valid_int() or str(int(uid)) != uid or int(uid) <= 0 or int(uid) >= value.next_equipment_id or not instance is Dictionary or instance.get("uid") != uid or not instance.get("equipment_id") is String or not _integer(instance.get("rank"), 1) or not _number(instance.get("hp")):
			return false
		var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
		if item.is_empty() or item.get("retired", false) or instance.hp < 0 or instance.hp > float(item.hit_points):
			return false
		if not HangarTrade.valid(instance):
			return false
	var used := {}
	var grants := ResearchRules.resolve(progress.research_ids, HangarResearch.catalog())
	var ids := {}
	var leads := 0
	var command := 0
	var cost := 0
	for entry: Variant in value.ships:
		if not entry is Dictionary or not _integer(entry.get("id"), 1) or entry.id >= value.next_ship_id or ids.has(int(entry.id)) or not entry.get("chassis") is String or not entry.get("flagship") is bool or not _number(entry.get("hull_hp")) or not entry.get("mounts") is Dictionary or not entry.get("builtins") is Dictionary or not entry.get("formation") is Array or entry.formation.size() != 2:
			return false
		ids[int(entry.id)] = true
		var chassis := SlotCatalog.find_chassis(entry.chassis)
		if chassis.is_empty() or (not value.pending and entry.hull_hp < 0):
			return false
		if entry.flagship:
			leads += 1
			command = int(chassis.command)
			if command <= 0:
				return false
		else:
			cost += int(chassis.command_cost)
			if int(chassis.command) > 0:
				return false
		for key in ["core", "engine"]:
			if not _number(entry.builtins.get(key)) or entry.builtins[key] < 0 or entry.builtins[key] > (30 if key == "core" else 25):
				return false
		if not value.pending and entry.builtins.core <= 0:
			return false
		for coordinate: Variant in entry.formation:
			if not _number(coordinate) or absf(coordinate) > 5:
				return false
		var max_hull := float(chassis.integrity)
		for slot: Variant in entry.mounts:
			var uid: Variant = entry.mounts[slot]
			if not slot is String or not uid is String or not equipment.has(uid) or used.has(uid):
				return false
			used[uid] = true
			var mount := {}
			for candidate: Dictionary in chassis.slots:
				if candidate.id == slot:
					mount = candidate
			var instance: Dictionary = equipment[uid]
			max_hull += SlotCatalog.stats_for(instance.equipment_id, int(instance.rank)).integrity
			var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
			if mount.is_empty() or not SlotCatalog.compatible(mount, item) or not SlotCatalog.unlocked(item, grants):
				return false
		if entry.hull_hp > max_hull:
			return false
	for uid: String in equipment:
		if HangarTrade.has_load(equipment[uid]) and (not used.has(uid) or (not value.pending and equipment[uid].hp <= 0)):
			return false
	return (leads == 1 and cost <= command) if not value.ended else leads <= 1

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _integer(value: Variant, minimum: int) -> bool:
	return _number(value) and value == floor(value) and value >= minimum and value <= 2147483647
