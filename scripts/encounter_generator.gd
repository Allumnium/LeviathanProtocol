class_name EncounterGenerator
extends RefCounted

const VERSION := 1
const MAX_SHIPS := BattleSimulation.MAX_LIVE_COMBATANTS
const MAX_ENEMY_ENTITIES := BattleSimulation.MAX_LIVE_COMBATANTS
# The legacy map has 14 combat columns. Step 10 replaces this explicit bridge
# with the actual 24 campaign rows, including noncombat stops.
const LEGACY_COMBAT_ROWS := [1, 3, 5, 8, 9, 10, 12, 13, 16, 17, 18, 20, 21, 24]
const WARDEN = preload("res://scripts/warden_battle.gd")


static func tuning() -> Dictionary:
	return Content.get_def("encounter_tuning", "core:default")


static func template(id: String) -> Dictionary:
	var data := Content.get_def("encounter", id)
	return data.allocation if data.get("implemented", false) and data.has("allocation") else {}


static func rank_for(row: int) -> int:
	return mini(2, int((row - 1) / int(tuning().rank_rows)))


static func cheapest_cost(rank: int) -> float:
	var result := INF
	for id: String in tuning().allowed_units:
		result = minf(result, AlienShip.threat_cost_for(id, rank))
	return result


static func threat(global_row: int, difficulty: int, encounter_type := "standard") -> float:
	if global_row < 1 or global_row > int(tuning().rows) or difficulty < 0 or difficulty > 2 or not tuning().type_multipliers.has(encounter_type):
		return -1.0
	var proximity := float(global_row - 1) / float(tuning().rows - 1)
	return float(tuning().threat_base) * pow(float(tuning().threat_growth), proximity) * float(tuning().difficulty[difficulty]) * float(tuning().type_multipliers[encounter_type])


static func generate(run_seed: int, node_id: int, global_row: int, difficulty: int, template_id := "patrol", combat_index := 1, rocks := false, environment: Dictionary = {}, expand_fleet := true) -> Dictionary:
	if not environment.is_empty() and not NodeEnvironment.valid(environment):
		push_error("Cannot generate an encounter with invalid node conditions.")
		return {}
	if not environment.is_empty():
		rocks = int(environment.asteroid_density) > 0
	if template(template_id).is_empty() or combat_index < 1 or combat_index > 14:
		return {}
	if template(template_id).generator == "warden":
		return _generate_warden(run_seed, node_id, global_row, difficulty, template_id, combat_index, rocks, environment, expand_fleet)
	var template: Dictionary = template(template_id)
	var budget := threat(global_row, difficulty, template.type)
	if budget <= 0.0:
		return {}
	var hazard_budget := budget * float(tuning().hazard_fraction) if rocks else 0.0
	var combat_budget := budget - hazard_budget
	var seed_value := hash("%s/node/%d/row/%d/difficulty/%d/%s" % [str(run_seed), node_id, global_row, difficulty, template_id])
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var rank := rank_for(global_row)
	var roster: Array = []
	var spent := 0.0
	# Craft and organs consume the same budget as the body, escorts and all waves.
	for extra: Dictionary in template.extras:
		for index in range(int(extra.count)):
			var unit := AlienShip.from_def(extra.unit)
			unit.entity_id = "node/%d/%s/%d" % [node_id, unit.entity_kind, index]
			roster.append(unit.to_snapshot())
			spent += unit.threat_cost
	var required: Array = template.required.duplicate()
	# Every announced wave gets a finite participant, even at the lowest budget.
	for wave in range(1, int(template.waves)):
		required.append(template.wave_unit)
	var ships := 0
	for index in range(required.size()):
		var reserve := 0.0
		for remaining in range(index + 1, required.size()):
			reserve += AlienShip.threat_cost_for(required[remaining])
		var unit: AlienShip
		for candidate_rank in range(rank, -1, -1):
			var candidate := AlienShip.threat_variant(required[index], candidate_rank)
			if candidate == null:
				continue
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
	var roles: Array = tuning().allowed_units
	while ships < MAX_SHIPS and roster.size() < MAX_ENEMY_ENTITIES:
		var affordable: Array[String] = []
		for role: String in roles:
			if AlienShip.threat_cost_for(role, rank) <= combat_budget - spent + 0.000001:
				affordable.append(role)
		if affordable.is_empty():
			break
		var unit := AlienShip.threat_variant(affordable[random.randi_range(0, affordable.size() - 1)], rank)
		unit.entity_id = "node/%d/ship/%d" % [node_id, ships]
		unit.wave_index = ships % int(template.waves)
		roster.append(unit.to_snapshot())
		spent += unit.threat_cost
		ships += 1
	var required_ids: Array[String] = []
	for unit in roster:
		if unit.kind == "ship":
			required_ids.append(unit.entity_id)
	var result := {"version": VERSION, "node_id": node_id, "global_row": global_row,
		"proximity": float(global_row - 1) / float(tuning().rows - 1), "template_id": template_id,
		"encounter_type": template.type, "difficulty_multiplier": tuning().difficulty[difficulty],
		"encounter_multiplier": tuning().type_multipliers[template.type], "seed": str(seed_value),
		"budget": budget, "spent": spent, "unspent_tolerance": cheapest_cost(rank) + hazard_budget,
		"generation": {"rows": tuning().rows, "threat_base": tuning().threat_base, "threat_growth": tuning().threat_growth,
			"hazard_fraction": tuning().hazard_fraction, "fleet_multiplier": tuning().fleet_multiplier},
		"wave_count": template.waves, "required_roles": template.required.map(func(id: String) -> String: return AlienShip.definition(id).role),
		"allowed_roles": roles.map(func(id: String) -> String: return AlienShip.definition(id).role), "environment_ids": [], "roster": roster, "legacy": false, "enemy_roles": true,
		"objective": {"type": "eliminate_targets", "required_target_ids": required_ids},
		"rewards": rewards_for(global_row, combat_index, float(Content.get_def("encounter", template_id).reward_multiplier))}
	if rocks:
		var count: int = 32 if environment.is_empty() else NodeEnvironment.ROCK_COUNTS[int(environment.asteroid_density)]
		result["asteroids"] = AsteroidField.generate(hash("%s/rocks" % seed_value), count)
		result["hazard_budget"] = hazard_budget
		result.environment_ids = ["asteroid_drift"]
	if not environment.is_empty():
		result["environment"] = environment.duplicate(true)
	return _finish_fleet(result, expand_fleet)


static func _finish_fleet(result: Dictionary, expand_fleet: bool) -> Dictionary:
	if expand_fleet:
		var originals: Array = result.roster.duplicate(true)
		for wingmate in range(1, int(tuning().fleet_multiplier)):
			for entry: Dictionary in originals:
				if result.roster.size() >= MAX_ENEMY_ENTITIES:
					break
				if entry.kind != "ship" or entry.entity_id == result.get("warden", {}).get("body_id", ""):
					continue
				var copy := entry.duplicate(true)
				copy.entity_id = str(entry.entity_id) + ("/wingmate" if wingmate == 1 else "/wingmate/%d" % wingmate)
				copy.copy_of = entry.entity_id
				result.roster.append(copy)
				result.spent += float(copy.threat_cost)
				result.budget += float(copy.threat_cost)
				if result.objective.type == "eliminate_targets":
					result.objective.required_target_ids.append(copy.entity_id)
	if result.roster.size() >= MAX_ENEMY_ENTITIES:
		# A full roster may deliberately leave budget unspent.
		result.unspent_tolerance = maxf(result.unspent_tolerance, result.budget - result.spent + 0.001)
	return result


static func _generate_warden(run_seed: int, node_id: int, row: int, difficulty: int, template_id: String, combat_index: int, rocks: bool, environment: Dictionary, expand_fleet := true) -> Dictionary:
	var settings: Dictionary = Content.get_def("encounter", template_id).warden
	var boss: bool = settings.boss
	var result := generate(run_seed, node_id, row, difficulty, str(Content.db().record("encounter", settings.base_template).id), combat_index, rocks, environment, false)
	if result.is_empty():
		return {}
	var budget: float = result.budget - result.get("hazard_budget", 0.0)
	var roster: Array = []
	var body := AlienShip.from_def(settings.body_unit)
	if boss:
		body.stats.integrity = budget * float(settings.body_hull_fraction)
		body.stats.shields = budget * float(settings.body_shield_fraction)
		body.threat_cost = budget * float(settings.body_cost_fraction)
	if settings.stationary_guard:
		# A stationary forward guard keeps the weaker pylon lesson in sight;
		# a rushing Fighter could die before the player ever saw its support.
		body.stats.thrust = 0
	body.entity_id = "node/%d/ship/0" % node_id
	roster.append(body.to_snapshot())
	var pylons: Array[String] = []
	var spent := body.threat_cost
	for index in range(int(settings.pylons)):
		var pylon := AlienShip.from_def(settings.pylon_unit)
		pylon.stats.integrity = budget * float(settings.pylon_hull) if boss else float(settings.pylon_hull)
		pylon.stats.shields = 0
		pylon.threat_cost = budget * float(settings.pylon_cost) if boss else float(settings.pylon_cost)
		pylon.entity_id = "node/%d/pylon/%d" % [node_id, index]
		roster.append(pylon.to_snapshot())
		pylons.append(pylon.entity_id)
		spent += pylon.threat_cost
	var rng := RandomNumberGenerator.new()
	result.seed = str(hash("%d/%d/%d/%s" % [run_seed, node_id, difficulty, template_id]))
	rng.seed = int(result.seed)
	var rank := rank_for(row)
	result.unspent_tolerance = AlienShip.threat_cost_for(settings.escort_units[1], rank) + float(result.get("hazard_budget", 0))
	while budget - spent >= AlienShip.threat_cost_for(settings.escort_units[1], rank) and roster.size() < MAX_SHIPS:
		var role: String = settings.escort_units[0] if budget - spent >= AlienShip.threat_cost_for(settings.escort_units[0], rank) and rng.randf() < float(settings.escort_fighter_chance) else settings.escort_units[1]
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
	result.rewards = rewards_for(row, combat_index, float(Content.get_def("encounter", template_id).reward_multiplier))
	result.roster = roster
	result.spent = spent
	result.required_roles = ["warden", "pylon"] if boss else ["fighter", "pylon"]
	result.allowed_roles = ["warden", "pylon", "fighter", "scout"]
	result.objective = {"type": "body_destroyed" if boss else "eliminate_targets", "required_target_ids": required}
	result["arena_layout"] = "open"
	result["warden"] = settings.rules.duplicate(true)
	result.warden.merge({"body_id": body.entity_id, "pylon_ids": pylons, "lance": boss,
		"lance_damage": float(settings.rules.lance_damage) * float(tuning().difficulty[difficulty])}, true)
	return _finish_fleet(result, expand_fleet)


static func rewards_for(row: int, combat_index: int, multiplier: float) -> Dictionary:
	var bundle := material_bundle(roundi(tuning().materials[rank_for(row)] * multiplier))
	var material_pool: Array[int] = []
	for amount: int in bundle:
		material_pool.append(roundi(amount / float(tuning().initial_recovery_rate)))
	return {"credits": roundi((float(tuning().credits_base) + float(tuning().credits_step) * combat_index) * multiplier),
		"materials": bundle, "material_pool": material_pool, "initial_recovery_rate": tuning().initial_recovery_rate}


static func material_bundle(total: int) -> Array[int]:
	var weights: Array = tuning().material_weights # Existing material IDs: O/D/T/C.
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
		var environment: Dictionary = node.get("environment", {})
		var rocks: bool = int(environment.asteroid_density) > 0 if not environment.is_empty() else node.kind == "combat" and int(node.local_row) in [3, 5] and int(node.id) % 2 == 0
		if node.kind == "combat" and not node.elite and int(node.combat_index) % 2 == 0:
			template = "relay_defense"
		if node.kind == "boss" and int(node.act) == 1:
			template = "bastion_warden"
		elif node.kind == "combat" and int(node.act) == 1 and int(node.local_row) == 5:
			template = "pylon_escort"
			if environment.is_empty():
				rocks = false
		var encounter := generate(run_seed, int(node.id), int(node.row), difficulty, template, int(node.combat_index), rocks, environment)
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
	if not encounter is Dictionary:
		return false
	for outcome in ["victory_flags", "withdrawal_flags"]:
		if not preload("res://scripts/expedition_events.gd").valid_flags(encounter.get(outcome, [])):
			return false
	if encounter is Dictionary and encounter.has("environment"):
		if not NodeEnvironment.valid(encounter.environment):
			return false
		var count: int = NodeEnvironment.ROCK_COUNTS[int(encounter.environment.asteroid_density)]
		if (count > 0) != encounter.has("asteroids"):
			return false
		if count > 0 and (not encounter.asteroids is Dictionary or not encounter.asteroids.get("roots") is Dictionary \
			or encounter.asteroids.roots.size() != count):
			return false
	if encounter is Dictionary and encounter.has("arena_layout") and encounter.arena_layout not in ["open", "corridor"]:
		return false
	if encounter is Dictionary and encounter.has("enemy_roles") and not encounter.enemy_roles is bool:
		return false
	if not encounter is Dictionary or encounter.get("version") != VERSION:
		return false
	if encounter.has("arena_layout") and not encounter.has("objective"):
		return false
	var generation: Variant = encounter.get("generation", tuning())
	if not generation is Dictionary:
		return false
	for key in ["rows", "threat_base", "threat_growth", "hazard_fraction", "fleet_multiplier"]:
		if not SaveValidation.bounded_number(generation.get(key)):
			return false
	if not SaveValidation.integer(generation.rows) or generation.rows < 2 or generation.rows > 24 \
		or generation.threat_base <= 0 or generation.threat_growth <= 0 or generation.hazard_fraction < 0 or generation.hazard_fraction >= 1 \
		or not SaveValidation.integer(generation.fleet_multiplier) or generation.fleet_multiplier < 1 or generation.fleet_multiplier > 10:
		return false
	for key in ["node_id", "global_row", "wave_count"]:
		if not SaveValidation.integer(encounter.get(key)):
			return false
	if encounter.global_row < 1 or encounter.global_row > int(generation.rows) or encounter.wave_count < 1 or encounter.wave_count > 3:
		return false
	if not encounter.get("legacy") is bool or not encounter.get("seed") is String:
		return false
	for key in ["template_id", "encounter_type"]:
		if not encounter.get(key) is String or encounter[key].is_empty():
			return false
	for key in ["budget", "spent", "unspent_tolerance", "proximity", "difficulty_multiplier", "encounter_multiplier"]:
		if not AlienShip._finite_number(encounter.get(key)) or encounter[key] < 0:
			return false
	var proximity := float(encounter.global_row - 1) / float(generation.rows - 1)
	if not is_equal_approx(encounter.proximity, proximity) or encounter.difficulty_multiplier <= 0 or encounter.encounter_multiplier <= 0:
		return false
	var base_budget: float = float(generation.threat_base) * pow(float(generation.threat_growth), proximity) * encounter.difficulty_multiplier * encounter.encounter_multiplier
	if not encounter.get("roster") is Array or encounter.roster.is_empty() or encounter.roster.size() > MAX_ENEMY_ENTITIES:
		return false
	var ids: Dictionary = {}
	var by_id: Dictionary = {}
	var waves: Dictionary = {}
	var spent := 0.0
	var ships := 0
	var present_roles: Dictionary = {}
	for entry in encounter.roster:
		if not AlienShip.snapshot_valid(entry) or not entry.get("entity_id") is String or entry.entity_id.is_empty():
			return false
		if ids.has(entry.entity_id) or not SaveValidation.integer(entry.get("wave")):
			return false
		if entry.wave < 0 or entry.wave >= encounter.wave_count or entry.get("kind") not in ["ship", "organ", "craft"]:
			return false
		if not AlienShip._finite_number(entry.get("threat_cost")) or entry.threat_cost < 0:
			return false
		ids[entry.entity_id] = true
		by_id[entry.entity_id] = entry
		waves[int(entry.wave)] = true
		spent += entry.threat_cost
		ships += 1 if entry.kind == "ship" else 0
		present_roles[entry.get("role", "")] = true
		if not encounter.legacy and entry.threat_cost <= 0:
			return false
	var copy_cost := 0.0
	var copied := {}
	for entry: Dictionary in encounter.roster:
		if not entry.has("copy_of"):
			continue
		if not entry.copy_of is String or not by_id.has(entry.copy_of):
			return false
		copied[entry.copy_of] = int(copied.get(entry.copy_of, 0)) + 1
		if copied[entry.copy_of] >= int(generation.fleet_multiplier):
			return false
		var original: Dictionary = by_id[entry.copy_of]
		if original.has("copy_of") or original.kind != "ship" \
				or original.entity_id == encounter.get("warden", {}).get("body_id", ""):
			return false
		var copy := entry.duplicate(true)
		copy.erase("copy_of")
		copy.entity_id = original.entity_id
		if not SaveValidation.same(copy, original):
			return false
		copy_cost += float(entry.threat_cost)
	if not is_equal_approx(encounter.budget, base_budget + copy_cost):
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
			or not is_equal_approx(encounter.hazard_budget, base_budget * float(generation.hazard_fraction)) or spent + encounter.hazard_budget > encounter.budget + 0.000001:
			return false
	if not encounter.legacy and encounter.budget - spent >= encounter.unspent_tolerance + 0.000001:
		return false
	var rewards: Variant = encounter.get("rewards")
	if not rewards is Dictionary or not SaveValidation.integer(rewards.get("credits")) or rewards.credits < 0:
		return false
	if not preload("res://scripts/expedition_events.gd").valid_rewards(rewards):
		return false
	if not rewards.get("materials") is Array or rewards.materials.size() != 4:
		return false
	for amount in rewards.materials:
		if not SaveValidation.integer(amount) or amount < 0 or amount > 128:
			return false
	# Older frozen snapshots may omit the descriptive pool. When present it
	# must describe the same finite budget that authoritative victory pays.
	if rewards.has("material_pool"):
		if not rewards.material_pool is Array or rewards.material_pool.size() != 4:
			return false
		if not SaveValidation.bounded_number(rewards.get("initial_recovery_rate")) or rewards.initial_recovery_rate <= 0 or rewards.initial_recovery_rate > 1:
			return false
		for category in range(4):
			if not SaveValidation.integer(rewards.material_pool[category]) or rewards.material_pool[category] != roundi(rewards.materials[category] / float(rewards.initial_recovery_rate)):
				return false
	if (present_roles.has("warden") or present_roles.has("pylon")) and not encounter.has("warden"):
		return false
	return true
