class_name SwarmNavigation
extends RefCounted

const STRENGTH_PER_POINT := 0.005
const DISRUPTION_REDUCTION := 3

static func initial() -> Dictionary:
	return {"version": 2, "days": 0.0, "intensity": 0.0, "events": {}, "quests": {}, "encounters": {}}

static func valid(value: Variant, graph: Dictionary) -> bool:
	if not value is Dictionary or value.get("version") != 2:
		return false
	for key in ["days", "intensity"]:
		if not SaveValidation.bounded_number(value.get(key)) or value[key] < 0:
			return false
	if not value.get("events") is Dictionary or not value.get("quests") is Dictionary or not value.get("encounters") is Dictionary:
		return false
	for key: Variant in value.encounters:
		if not key is String or not key.is_valid_int() or not SaveValidation.node(int(key), graph.nodes.size()):
			return false
		var frozen: Variant = value.encounters[key]
		if not EncounterGenerator.valid(frozen) or frozen.get("node_id") != int(key) \
			or not SaveValidation.bounded_number(frozen.get("swarm_intensity")) or frozen.swarm_intensity < 0:
			return false
	for key: Variant in value.events:
		if not key is String or not key.is_valid_int() or event(graph, int(key)).is_empty() or value.events[key] not in ["relay", "disrupt"]:
			return false
	for key: Variant in value.quests:
		if not value.events.has(key) or value.events[key] != "relay" or value.quests[key] not in ["active", "complete"]:
			return false
	for key: String in value.events:
		if value.events[key] == "relay" and not value.quests.has(key):
			return false
	return true

static func event(graph: Dictionary, node_id: int) -> Dictionary:
	for act in range(1, 4):
		var sources: Array = graph.nodes.filter(func(node: Dictionary) -> bool:
			return node.act == act and node.local_row == (2 if act == 1 else 3))
		if sources.is_empty() or sources[0].id != node_id:
			continue
		var targets: Array = graph.nodes.filter(func(node: Dictionary) -> bool: return node.act == act and node.local_row == 6)
		return {"title": "A broken relay", "text": "Swarm data recovered.",
			"target": int(targets[-1].id), "reward": 60, "reduction": 4, "disruption": DISRUPTION_REDUCTION}
	return {}

static func arrive(data: Dictionary, graph: Dictionary) -> void:
	for key: String in data.navigation.quests:
		var quest := event(graph, int(key))
		if data.navigation.quests[key] == "active" and data.current == quest.target:
			data.navigation.quests[key] = "complete"
			data.credits += quest.reward
			data.navigation.intensity = maxf(0, data.navigation.intensity - quest.reduction)

static func encounter(base: Dictionary, intensity: float) -> Dictionary:
	if base.is_empty():
		return {}
	var result := base.duplicate(true)
	var multiplier := 1.0 + intensity * STRENGTH_PER_POINT
	result.swarm_intensity = intensity
	if result.has("warden"):
		result.warden.damage_multiplier = multiplier
	for unit: Dictionary in result.roster:
		unit.stats[0] *= multiplier
		unit.stats[1] *= multiplier
		for weapon: Array in unit.weapons:
			weapon[2] *= multiplier
	return result
