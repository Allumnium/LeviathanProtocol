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
const WARDEN = preload("res://scripts/warden_battle.gd")
const TEMPLATES := {
	"bastion_warden": {"type": "boss", "required": [], "waves": 1, "craft": 0, "organs": 2},
	"pylon_escort": {"type": "standard", "required": ["fighter"], "waves": 1, "craft": 0, "organs": 1},
	"patrol": {"type": "standard", "required": ["fighter", "scout"], "waves": 1, "craft": 0, "organs": 0},
	"elite": {"type": "elite", "required": ["sentinel", "fighter"], "waves": 1, "craft": 0, "organs": 0},
	"boss_patrol": {"type": "boss", "required": ["sentinel", "fighter"], "waves": 1, "craft": 0, "organs": 0},
	# Defense is live; the generic organ/craft framework remains allocation-only.
	"relay_defense": {"type": "standard", "required": ["fighter"], "waves": 3, "craft": 0, "organs": 0},
	"boss_framework": {"type": "boss", "required": ["fighter"], "waves": 1, "craft": 4, "organs": 2},
}


static func threat(global_row: int, difficulty: int, encounter_type := "standard") -> float:
	if global_row < 1 or global_row > 24 or difficulty < 0 or difficulty > 2 or not MULTIPLIERS.has(encounter_type):
		return -1.0
	var proximity := float(global_row - 1) / 23.0
	return 100.0 * pow(5.0, proximity) * DIFFICULTY[difficulty] * MULTIPLIERS[encounter_type]


static func generate(run_seed: int, node_id: int, global_row: int, difficulty: int, template_id := "patrol", combat_index := 1, rocks := false) -> Dictionary:
	if not TEMPLATES.has(template_id) or combat_index < 1 or combat_index > 14:
		return {}
	if template_id in ["bastion_warden", "pylon_escort"]:
		return _generate_warden(run_seed, node_id, global_row, difficulty, template_id, combat_index, rocks)
	var template: Dictionary = TEMPLATES[template_id]
	var budget := threat(global_row, difficulty, template.type)
	if budget <= 0.0:
		return {}
	var hazard_budget := budget * 0.15 if rocks else 0.0
	var combat_budget := budget - hazard_budget
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
			if spent + candidate.threat_cost + reserve <= combat_budget + 0.000001:
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
			if AlienShip.ROLE_COSTS[role] * AlienShip.TIER_COST[rank] <= combat_budget - spent + 0.000001:
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
	var result := {"version": VERSION, "node_id": node_id, "global_row": global_row,
		"proximity": float(global_row - 1) / 23.0, "template_id": template_id,
		"encounter_type": template.type, "difficulty_multiplier": DIFFICULTY[difficulty],
		"encounter_multiplier": MULTIPLIERS[template.type], "seed": str(seed_value),
		"budget": budget, "spent": spent, "unspent_tolerance": 16.0 * AlienShip.TIER_COST[rank] + hazard_budget,
		"wave_count": template.waves, "required_roles": template.required.duplicate(),
		"allowed_roles": roles.duplicate(), "environment_ids": [], "roster": roster, "legacy": false, "enemy_roles": true,
		"objective": {"type": "eliminate_targets", "required_target_ids": required_ids},
		"rewards": {"credits": roundi((90 + 10 * combat_index) * reward_multiplier), "materials": bundle,
			"material_pool": material_pool, "initial_recovery_rate": 0.5}}
	if rocks:
		result["asteroids"] = AsteroidField.generate(hash("%s/rocks" % seed_value), 6)
		result["hazard_budget"] = hazard_budget
		result.environment_ids = ["asteroid_drift"]
	return result


static func _generate_warden(run_seed: int, node_id: int, row: int, difficulty: int, template_id: String, combat_index: int, rocks: bool) -> Dictionary:
	var boss := template_id == "bastion_warden"
	var result := generate(run_seed, node_id, row, difficulty, "boss_patrol" if boss else "patrol", combat_index, rocks)
	if result.is_empty():
		return {}
	var budget: float = result.budget - result.get("hazard_budget", 0.0)
	var roster: Array = []
	var body := AlienShip.warden_variant(false, budget * 0.21, budget * 0.025, budget * 0.6) if boss else AlienShip.threat_variant("fighter", 0)
	if not boss:
		# A stationary forward guard keeps the weaker pylon lesson in sight;
		# a rushing Fighter could die before the player ever saw its support.
		body.stats.thrust = 0
	body.entity_id = "node/%d/ship/0" % node_id
	roster.append(body.to_snapshot())
	var pylons: Array[String] = []
	var spent := body.threat_cost
	for index in range(2 if boss else 1):
		var pylon := AlienShip.warden_variant(true, budget * 0.04 if boss else 5.0, 0, budget * 0.1 if boss else 18.0)
		pylon.entity_id = "node/%d/pylon/%d" % [node_id, index]
		roster.append(pylon.to_snapshot())
		pylons.append(pylon.entity_id)
		spent += pylon.threat_cost
	var rng := RandomNumberGenerator.new()
	result.seed = str(hash("%d/%d/%d/%s" % [run_seed, node_id, difficulty, template_id]))
	rng.seed = int(result.seed)
	var rank := mini(2, int((row - 1) / 8))
	while budget - spent >= 16.0 * AlienShip.TIER_COST[rank] and roster.size() < MAX_SHIPS:
		var role := "fighter" if budget - spent >= 22.0 * AlienShip.TIER_COST[rank] and rng.randf() < 0.5 else "scout"
		var unit := AlienShip.threat_variant(role, rank)
		unit.entity_id = "node/%d/ship/%d" % [node_id, roster.size()]
		roster.append(unit.to_snapshot())
		spent += unit.threat_cost
	var required: Array[String] = [body.entity_id]
	if not boss:
		for entry: Dictionary in roster:
			if entry.kind == "ship" and entry.entity_id != body.entity_id:
				required.append(entry.entity_id)
	result.template_id = template_id
	result.roster = roster
	result.spent = spent
	result.required_roles = ["warden", "pylon"] if boss else ["fighter", "pylon"]
	result.allowed_roles = ["warden", "pylon", "fighter", "scout"]
	result.objective = {"type": "body_destroyed" if boss else "eliminate_targets", "required_target_ids": required}
	result["arena_layout"] = "open"
	result["warden"] = {"body_id": body.entity_id, "pylon_ids": pylons, "lance": boss,
		"cycle_seconds": 12.0, "warning_seconds": 3.0, "vulnerability_seconds": 6.0,
		"lance_damage": 6.0 * DIFFICULTY[difficulty], "range": 520.0, "half_width": 22.0}
	return result


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
		var rocks: bool = node.kind == "combat" and int(node.local_row) in [3, 5] and int(node.id) % 2 == 0
		if node.kind == "combat" and not node.elite and int(node.combat_index) % 2 == 0:
			template = "relay_defense"
		if node.kind == "boss" and int(node.act) == 1:
			template = "bastion_warden"
		elif node.kind == "combat" and int(node.act) == 1 and int(node.local_row) == 5:
			template = "pylon_escort"
			rocks = false
		var encounter := generate(run_seed, int(node.id), int(node.row), difficulty, template, int(node.combat_index), rocks)
		encounter["arena_layout"] = "corridor" if not rocks and int(node.combat_index) % 2 == 0 else "open"
		result[str(int(node.id))] = encounter
	return result


static func initial_fleet(encounter: Dictionary) -> Array[RefCounted]:
	var fleet: Array[RefCounted] = []
	for entry in encounter.get("roster", []):
		if (entry.get("kind", "ship") == "ship" or encounter.has("warden")) and int(entry.get("wave", 0)) == 0:
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
	if encounter is Dictionary and encounter.has("arena_layout") and encounter.arena_layout not in ["open", "corridor"]:
		return false
	if encounter is Dictionary and encounter.has("enemy_roles") and not encounter.enemy_roles is bool:
		return false
	if not encounter is Dictionary or encounter.get("version") != VERSION:
		return false
	if encounter.has("arena_layout") and (not encounter.has("objective") or not TEMPLATES.has(encounter.get("template_id", "")) \
		or encounter.get("wave_count") != TEMPLATES[encounter.template_id].waves):
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
	if encounter.has("warden") and not WARDEN.valid_plan(encounter):
		return false
	if encounter.has("objective"):
		var objective: Variant = encounter.objective
		if not objective is Dictionary or objective.get("type") not in ["eliminate_targets", "body_destroyed"] or not objective.get("required_target_ids") is Array:
			return false
		var required_ids: Dictionary = {}
		for id in objective.required_target_ids:
			if not id is String or not ids.has(id) or required_ids.has(id):
				return false
			required_ids[id] = true
		if objective.type == "body_destroyed" and (not encounter.has("warden") or not encounter.warden.get("lance", false) or objective.required_target_ids != [encounter.warden.get("body_id", "")]):
			return false
		if encounter.has("arena_layout") and objective.type != "body_destroyed" and required_ids.size() != ships:
			return false
	if not is_equal_approx(spent, encounter.spent) or spent > encounter.budget + 0.000001:
		return false
	if encounter.has("asteroids"):
		if not AsteroidField.valid(encounter.asteroids) or not AlienShip._finite_number(encounter.get("hazard_budget")) \
			or not is_equal_approx(encounter.hazard_budget, encounter.budget * 0.15) or spent + encounter.hazard_budget > encounter.budget + 0.000001:
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
	# Older frozen snapshots may omit the descriptive pool. When present it
	# must describe the same finite budget that authoritative victory pays.
	if rewards.has("material_pool"):
		if not rewards.material_pool is Array or rewards.material_pool.size() != 4:
			return false
		for category in range(4):
			if not RunProgressData._integer(rewards.material_pool[category]) or rewards.material_pool[category] != rewards.materials[category] * 2:
				return false
		if rewards.get("initial_recovery_rate") != 0.5:
			return false
	if encounter.template_id in ["bastion_warden", "pylon_escort"] and not encounter.has("warden"):
		return false
	return true
