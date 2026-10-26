class_name EncounterGenerator
extends RefCounted

const VERSION := 1
const DIFFICULTY := [0.8, 1.0, 1.25]
const MULTIPLIERS := {"standard": 1.0, "elite": 1.4, "boss": 1.8}
const MAX_SHIPS := 24
const MAX_ENEMY_ENTITIES := 40 # Leaves headroom within the 64-entity shared simulation budget.
# The legacy map has 14 combat columns. Step 10 replaces this explicit bridge
# with the actual 24 campaign rows, including noncombat stops.
const LEGACY_COMBAT_ROWS := [1, 3, 5, 8, 9, 10, 12, 13, 16, 17, 18, 20, 21, 24]
const TEMPLATES := {
	"patrol": {"type": "standard", "required": ["fighter", "scout"], "waves": 1, "craft": 0, "organs": 0},
	"elite": {"type": "elite", "required": ["sentinel", "fighter"], "waves": 1, "craft": 0, "organs": 0},
	"boss_patrol": {"type": "boss", "required": ["sentinel", "fighter"], "waves": 1, "craft": 0, "organs": 0},
	# Allocation frameworks only; later objective/boss milestones activate these.
	"relay_defense": {"type": "standard", "required": ["fighter"], "waves": 3, "craft": 0, "organs": 0},
	"boss_framework": {"type": "boss", "required": ["fighter"], "waves": 1, "craft": 4, "organs": 2},
}


static func threat(global_row: int, difficulty: int, encounter_type := "standard") -> float:
	if global_row < 1 or global_row > 24 or difficulty < 0 or difficulty > 2 or not MULTIPLIERS.has(encounter_type):
		return -1.0
	var proximity := float(global_row - 1) / 23.0
	return 100.0 * pow(5.0, proximity) * DIFFICULTY[difficulty] * MULTIPLIERS[encounter_type]


static func generate(run_seed: int, node_id: int, global_row: int, difficulty: int, template_id := "patrol", combat_index := 1) -> Dictionary:
	if not TEMPLATES.has(template_id) or combat_index < 1 or combat_index > 14:
		return {}
	var template: Dictionary = TEMPLATES[template_id]
	var budget := threat(global_row, difficulty, template.type)
	if budget <= 0.0:
		return {}
	var seed_value := hash("%s/node/%d/row/%d/difficulty/%d/%s" % [str(run_seed), node_id, global_row, difficulty, template_id])
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var rank := mini(2, int((global_row - 1) / 8))
	var roster: Array = []
	var spent := 0.0
	# Craft and organs consume the same budget as the body, escorts and all waves.
	for kind in ["organ", "craft"]:
		var count: int = template.organs if kind == "organ" else template.craft
		for index in range(count):
			var unit := AlienShip.threat_variant("sentinel" if kind == "organ" else "scout", 0)
			unit.entity_kind = kind
			unit.definition_id = "framework/" + kind
			unit.threat_cost = 20.0 if kind == "organ" else 6.0
			unit.stats.integrity = 12.0 if kind == "organ" else 1.0
			unit.stats.shields = 8.0 if kind == "organ" else 0.0
			unit.stats.thrust = 0.0 if kind == "organ" else 12.0
			unit.stats.weapons[0].damage_per_shot = 0.5 if kind == "organ" else 0.25
			unit.entity_id = "node/%d/%s/%d" % [node_id, kind, index]
			roster.append(unit.to_snapshot())
			spent += unit.threat_cost
	var required: Array = template.required.duplicate()
	# Every announced wave gets a finite participant, even at the lowest budget.
	for wave in range(1, int(template.waves)):
		required.append("scout")
	var ships := 0
	for index in range(required.size()):
		var reserve := 0.0
		for remaining in range(index + 1, required.size()):
			reserve += AlienShip.ROLE_COSTS[required[remaining]]
		var unit: AlienShip
		for candidate_rank in range(rank, -1, -1):
			var candidate := AlienShip.threat_variant(required[index], candidate_rank)
			if spent + candidate.threat_cost + reserve <= budget + 0.000001:
				unit = candidate
				break
		if unit == null:
			return {}
		unit.entity_id = "node/%d/ship/%d" % [node_id, ships]
		unit.wave_index = 0 if index < template.required.size() else index - template.required.size() + 1
		roster.append(unit.to_snapshot())
		spent += unit.threat_cost
		ships += 1
	var roles := AlienShip.ROLE_COSTS.keys()
	while ships < MAX_SHIPS and roster.size() < MAX_ENEMY_ENTITIES:
		var affordable: Array[String] = []
		for role: String in roles:
			if AlienShip.ROLE_COSTS[role] * AlienShip.TIER_COST[rank] <= budget - spent + 0.000001:
				affordable.append(role)
		if affordable.is_empty():
			break
		var unit := AlienShip.threat_variant(affordable[random.randi_range(0, affordable.size() - 1)], rank)
		unit.entity_id = "node/%d/ship/%d" % [node_id, ships]
		unit.wave_index = ships % int(template.waves)
		roster.append(unit.to_snapshot())
		spent += unit.threat_cost
		ships += 1
	var reward_multiplier := 1.4 if template.type == "elite" else (1.5 if template.type == "boss" else 1.0)
	var act := int((global_row - 1) / 8)
	var bundle := material_bundle(roundi([12, 18, 24][act] * reward_multiplier))
	var material_pool: Array[int] = []
	for amount in bundle:
		material_pool.append(amount * 2)
	var required_ids: Array[String] = []
	for unit in roster:
		if unit.kind == "ship":
			required_ids.append(unit.entity_id)
	return {"version": VERSION, "node_id": node_id, "global_row": global_row,
		"proximity": float(global_row - 1) / 23.0, "template_id": template_id,
		"encounter_type": template.type, "difficulty_multiplier": DIFFICULTY[difficulty],
		"encounter_multiplier": MULTIPLIERS[template.type], "seed": str(seed_value),
		"budget": budget, "spent": spent, "unspent_tolerance": 16.0 * AlienShip.TIER_COST[rank],
		"wave_count": template.waves, "required_roles": template.required.duplicate(),
		"allowed_roles": roles.duplicate(), "environment_ids": [], "roster": roster, "legacy": false,
		"objective": {"type": "eliminate_targets", "required_target_ids": required_ids},
		"rewards": {"credits": roundi((90 + 10 * combat_index) * reward_multiplier), "materials": bundle,
			"material_pool": material_pool, "initial_recovery_rate": 0.5}}


static func material_bundle(total: int) -> Array[int]:
	var weights := [0.30, 0.35, 0.20, 0.15] # Existing material IDs: O/D/T/C.
	var result: Array[int] = []
	var fractions: Array = []
	var assigned := 0
	for index in range(4):
		var exact: float = total * weights[index]
		result.append(floori(exact))
		assigned += result[index]
		fractions.append({"index": index, "fraction": exact - result[index]})
	fractions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.fraction > b.fraction if not is_equal_approx(a.fraction, b.fraction) else a.index < b.index)
	for index in range(total - assigned):
		result[int(fractions[index].index)] += 1
	return result


static func freeze_graph(run_seed: int, difficulty: int, columns: Array) -> Dictionary:
	var result: Dictionary = {}
	for node in range(columns.size()):
		var column := int(columns[node])
		if column == 0:
			continue
		if column < 1 or column > LEGACY_COMBAT_ROWS.size():
			return {}
		result[str(node)] = generate(run_seed, node, LEGACY_COMBAT_ROWS[column - 1], difficulty, "patrol", column)
	return result


static func freeze_campaign(run_seed: int, difficulty: int, graph: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for node in graph.nodes:
		if node.kind not in ["combat", "boss"]:
			continue
		var template := "boss_patrol" if node.kind == "boss" else ("elite" if node.elite else "patrol")
		result[str(int(node.id))] = generate(run_seed, int(node.id), int(node.row), difficulty, template, int(node.combat_index))
	return result


static func initial_fleet(encounter: Dictionary) -> Array[RefCounted]:
	var fleet: Array[RefCounted] = []
	for entry in encounter.get("roster", []):
		if entry.get("kind", "ship") == "ship" and int(entry.get("wave", 0)) == 0:
			var unit := AlienShip.from_snapshot(entry)
			if unit != null:
				fleet.append(unit)
	return fleet


static func objective_ids(encounter: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if encounter.has("objective"):
		result.assign(encounter.objective.required_target_ids)
	else:
		# Compatibility with frozen encounters saved before explicit objectives.
		for entry in encounter.get("roster", []):
			if entry.get("kind", "ship") == "ship":
				result.append(entry.entity_id)
	return result


static func valid(encounter: Variant) -> bool:
	if not encounter is Dictionary or encounter.get("version") != VERSION:
		return false
	for key in ["node_id", "global_row", "wave_count"]:
		if not RunProgressData._integer(encounter.get(key)):
			return false
	if encounter.global_row < 1 or encounter.global_row > 24 or encounter.wave_count < 1 or encounter.wave_count > 3:
		return false
	if not encounter.get("legacy") is bool or not encounter.get("seed") is String:
		return false
	for key in ["template_id", "encounter_type"]:
		if not encounter.get(key) is String or encounter[key].is_empty():
			return false
	for key in ["budget", "spent", "unspent_tolerance", "proximity", "difficulty_multiplier", "encounter_multiplier"]:
		if not AlienShip._finite_number(encounter.get(key)) or encounter[key] < 0:
			return false
	var proximity := float(encounter.global_row - 1) / 23.0
	if not is_equal_approx(encounter.proximity, proximity) or encounter.difficulty_multiplier <= 0 or encounter.encounter_multiplier <= 0:
		return false
	if not is_equal_approx(encounter.budget, 100.0 * pow(5.0, proximity) * encounter.difficulty_multiplier * encounter.encounter_multiplier):
		return false
	if not encounter.get("roster") is Array or encounter.roster.is_empty() or encounter.roster.size() > MAX_ENEMY_ENTITIES:
		return false
	var ids: Dictionary = {}
	var waves: Dictionary = {}
	var spent := 0.0
	var ships := 0
	var present_roles: Dictionary = {}
	for entry in encounter.roster:
		if not AlienShip.snapshot_valid(entry) or not entry.get("entity_id") is String or entry.entity_id.is_empty():
			return false
		if ids.has(entry.entity_id) or not RunProgressData._integer(entry.get("wave")):
			return false
		if entry.wave < 0 or entry.wave >= encounter.wave_count or entry.get("kind") not in ["ship", "organ", "craft"]:
			return false
		if not AlienShip._finite_number(entry.get("threat_cost")) or entry.threat_cost < 0:
			return false
		ids[entry.entity_id] = true
		waves[int(entry.wave)] = true
		spent += entry.threat_cost
		ships += 1 if entry.kind == "ship" else 0
		present_roles[entry.get("role", "")] = true
		if not encounter.legacy and entry.threat_cost <= 0:
			return false
	if not encounter.legacy:
		for role in encounter.get("required_roles", []):
			if not present_roles.has(role):
				return false
	if ships > MAX_SHIPS or waves.size() != int(encounter.wave_count):
		return false
	if encounter.has("objective"):
		var objective: Variant = encounter.objective
		if not objective is Dictionary or objective.get("type") != "eliminate_targets" or not objective.get("required_target_ids") is Array:
			return false
		var required_ids: Dictionary = {}
		for id in objective.required_target_ids:
			if not id is String or not ids.has(id) or required_ids.has(id):
				return false
			required_ids[id] = true
	if not is_equal_approx(spent, encounter.spent) or spent > encounter.budget + 0.000001:
		return false
	if not encounter.legacy and encounter.budget - spent >= encounter.unspent_tolerance + 0.000001:
		return false
	var rewards: Variant = encounter.get("rewards")
	if not rewards is Dictionary or not RunProgressData._integer(rewards.get("credits")) or rewards.credits < 0:
		return false
	if not rewards.get("materials") is Array or rewards.materials.size() != 4:
		return false
	for amount in rewards.materials:
		if not RunProgressData._integer(amount) or amount < 0 or amount > 128:
			return false
	return true
