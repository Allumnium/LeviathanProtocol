class_name ResearchRules
extends RefCounted

const STORY_GATES := ["boss_i_defeated", "boss_ii_defeated", "boss_iii_defeated"]
const FAMILY_PATHS := {"energy": ["optics", "disruption"], "survival": ["bastion", "renewal"],
	"force_projection": ["siege", "carrier"], "fleet_operations": ["command", "covert"]}


static func _unique_strings(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if not value is String or value.is_empty() or seen.has(value):
			return false
		seen[value] = true
	return true


static func _modifier_valid(modifier: Variant, materials: Array[String]) -> bool:
	if not modifier is Dictionary:
		return false
	match modifier.get("id", ""):
		"energy_efficiency":
			return _number(modifier.get("value")) and modifier.value > 0 and modifier.value <= 0.3 \
				and modifier.get("ordinary_efficiency_cap") == 0.3 and modifier.get("targets") is Array \
				and _unique_strings(modifier.targets) and modifier.targets.size() == 2 \
				and modifier.targets.has("beam") and modifier.targets.has("shield")
		"cargo_hold_capacity":
			return _number(modifier.get("value")) and modifier.value > 0 and modifier.value == floor(modifier.value) \
				and modifier.get("refill_existing") is bool and not modifier.refill_existing
		"scan_spectroscopy":
			return modifier.get("value") is bool
		"extractable_materials":
			if not modifier.get("values") is Array or modifier.values.is_empty() or not _unique_strings(modifier.values):
				return false
			for id: String in modifier.values:
				if id not in materials:
					return false
			return true
	return false


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func validate_registry(registry: Dictionary) -> Array[String]:
	# Called after GameDefinitions validates the envelope and references.
	var errors: Array[String] = []
	var nodes: Dictionary = {}
	var equipment: Dictionary = {}
	var materials: Array[String] = []
	for item: Dictionary in registry.materials:
		materials.append(item.id)
	for item: Dictionary in registry.equipment:
		equipment[item.id] = item
	for node: Dictionary in registry.research:
		nodes[node.id] = node
		for field in ["prerequisite_ids", "exclusion_ids", "story_gate_ids"]:
			if not _unique_strings(node[field]):
				errors.append("Duplicate or invalid research list: %s/%s" % [node.id, field])
		if node.prerequisite_ids.has(node.id) or node.exclusion_ids.has(node.id):
			errors.append("Research cannot depend on or exclude itself: %s" % node.id)
		for gate in node.story_gate_ids:
			if gate not in STORY_GATES:
				errors.append("Unknown research story gate: %s/%s" % [node.id, str(gate)])
		if node.family_id.is_empty() != node.path_id.is_empty() or (not node.family_id.is_empty() \
			and (not FAMILY_PATHS.has(node.family_id) or node.path_id not in FAMILY_PATHS[node.family_id])):
			errors.append("Unknown research family/path: %s" % node.id)
		var grant_count := 0
		for field in ["equipment_ids", "ability_ids"]:
			if not _unique_strings(node.grants[field]):
				errors.append("Duplicate research grants: %s/%s" % [node.id, field])
		for field in ["equipment_ids", "ability_ids", "ranks", "modifiers"]:
			grant_count += node.grants[field].size()
		if grant_count == 0:
			errors.append("Research must grant an effect: %s" % node.id)
		if node.id != "foundation" and (node.cost_rp <= 0 or node.prerequisite_ids.is_empty()):
			errors.append("Purchasable research needs a positive cost and prerequisites: %s" % node.id)
		var rank_keys: Dictionary = {}
		for rank: Dictionary in node.grants.ranks:
			var key := "%s/%d" % [rank.equipment_id, int(rank.rank)]
			if rank_keys.has(key):
				errors.append("Duplicate rank grant: %s/%s" % [node.id, key])
			rank_keys[key] = true
			var exists := false
			for physical_rank: Dictionary in equipment[rank.equipment_id].ranks:
				exists = exists or int(physical_rank.rank) == int(rank.rank)
			if not exists:
				errors.append("Research grants an undefined physical rank: %s/%s" % [node.id, key])
		var modifier_ids: Dictionary = {}
		for modifier in node.grants.modifiers:
			if not _modifier_valid(modifier, materials):
				errors.append("Invalid research modifier: %s" % node.id)
				continue
			if modifier_ids.has(modifier.id):
				errors.append("Duplicate research modifier: %s/%s" % [node.id, modifier.id])
			modifier_ids[modifier.id] = true
	if not nodes.has("foundation") or nodes.foundation.cost_rp != 0 or not nodes.foundation.prerequisite_ids.is_empty() \
		or not nodes.foundation.family_id.is_empty() or not nodes.foundation.exclusion_ids.is_empty() or not nodes.foundation.story_gate_ids.is_empty():
		errors.append("Foundation must be an unrestricted free starting node.")
	if not errors.is_empty():
		return errors
	# Topological closure also detects cycles without recursive stack limits.
	var ancestors: Dictionary = {}
	while ancestors.size() < nodes.size():
		var progressed := false
		for id: String in nodes:
			if ancestors.has(id):
				continue
			var ready := true
			var inherited: Array[String] = []
			for parent: String in nodes[id].prerequisite_ids:
				if not ancestors.has(parent):
					ready = false
					break
				inherited.append(parent)
				for prior: String in ancestors[parent]:
					if not inherited.has(prior):
						inherited.append(prior)
			if ready:
				ancestors[id] = inherited
				progressed = true
		if not progressed:
			errors.append("Research prerequisites contain a cycle.")
			return errors
	for id: String in nodes:
		var node: Dictionary = nodes[id]
		for excluded: String in node.exclusion_ids:
			if node.family_id.is_empty() or node.family_id != nodes[excluded].family_id or node.path_id == nodes[excluded].path_id:
				errors.append("Exclusions must stay within opposite paths of one family: %s/%s" % [id, excluded])
			if not nodes[excluded].exclusion_ids.has(id):
				errors.append("Research exclusions must be reciprocal: %s/%s" % [id, excluded])
			if ancestors[id].has(excluded):
				errors.append("Research excludes a required ancestor: %s/%s" % [id, excluded])
		for prior: String in ancestors[id]:
			for excluded: String in nodes[prior].exclusion_ids:
				if ancestors[id].has(excluded):
					errors.append("Research requires mutually exclusive ancestors: %s" % id)
		for other_id: String in nodes:
			var other: Dictionary = nodes[other_id]
			if not node.family_id.is_empty() and node.family_id == other.family_id and node.path_id != other.path_id \
				and not node.exclusion_ids.has(other_id):
				errors.append("Opposite research paths must exclude every tier: %s/%s" % [id, other_id])
		for rank: Dictionary in node.grants.ranks:
			var inherited_rank := 0
			for parent: String in ancestors[id]:
				if nodes[parent].grants.equipment_ids.has(rank.equipment_id):
					inherited_rank = maxi(inherited_rank, 1)
				for previous: Dictionary in nodes[parent].grants.ranks:
					if previous.equipment_id == rank.equipment_id:
						inherited_rank = maxi(inherited_rank, int(previous.rank))
			if inherited_rank < int(rank.rank) - 1:
				errors.append("Rank research requires its previous physical rank: %s" % id)
		var available_equipment: Array = node.grants.equipment_ids.duplicate()
		for parent: String in ancestors[id]:
			available_equipment.append_array(nodes[parent].grants.equipment_ids)
		for ability_id: String in node.grants.ability_ids:
			for ability: Dictionary in registry.abilities:
				if ability.id == ability_id and not available_equipment.has(ability.source_equipment_id):
					errors.append("Ability research requires its source equipment: %s/%s" % [id, ability_id])
	for domain in ["equipment", "abilities"]:
		var grant_field := "equipment_ids" if domain == "equipment" else "ability_ids"
		for item: Dictionary in registry[domain]:
			var owners := 0
			for node: Dictionary in registry.research:
				owners += 1 if node.grants[grant_field].has(item.id) else 0
			if owners != 1:
				errors.append("Each %s definition needs exactly one research grant source: %s" % [domain, item.id])
	return errors


static func selection_error(research_ids: Array, story_flags: Dictionary, branches: Dictionary) -> String:
	if not _unique_strings(research_ids) or not research_ids.has("foundation"):
		return "Current-run research must contain Foundation and unique known IDs."
	for family in branches:
		if not FAMILY_PATHS.has(family) or branches[family] not in FAMILY_PATHS[family]:
			return "Unknown current-run branch commitment."
	var catalog := GameDefinitions.entries("research")
	for id: String in research_ids:
		var required := requirements(id, research_ids, story_flags, branches, catalog)
		if not required.known:
			return "Unknown current-run research."
		if not required.missing_prerequisites.is_empty():
			return "Missing current-run research prerequisite."
		if not required.missing_story_gates.is_empty():
			return "Missing current-run research story gate."
		if not required.conflicts.is_empty() or required.branch_conflict:
			return "Current-run research conflicts with a branch commitment."
		var node := GameDefinitions.find("research", id)
		if not node.family_id.is_empty() and branches.get(node.family_id, "") != node.path_id:
			return "Current-run research is missing its branch commitment."
	return ""


static func resolve(research_ids: Array, catalog: Array[Dictionary] = []) -> Dictionary:
	var definitions := catalog if not catalog.is_empty() else GameDefinitions.entries("research")
	var by_id: Dictionary = {}
	for node in definitions:
		by_id[node.id] = node
	var result := {"equipment_ids": [], "ranks": {}, "ability_ids": [], "modifiers": {}, "error": ""}
	var seen: Dictionary = {}
	for id in research_ids:
		if not id is String or not by_id.has(id):
			return {"equipment_ids": [], "ranks": {}, "ability_ids": [], "modifiers": {}, "error": "Unknown research grant source."}
		if seen.has(id):
			continue
		seen[id] = true
		var grants: Dictionary = by_id[id].grants
		for equipment_id: String in grants.equipment_ids:
			if not result.equipment_ids.has(equipment_id):
				result.equipment_ids.append(equipment_id)
			result.ranks[equipment_id] = maxi(int(result.ranks.get(equipment_id, 0)), 1)
		for rank: Dictionary in grants.ranks:
			result.ranks[rank.equipment_id] = maxi(int(result.ranks.get(rank.equipment_id, 0)), int(rank.rank))
		for ability: String in grants.ability_ids:
			if not result.ability_ids.has(ability):
				result.ability_ids.append(ability)
		for modifier: Dictionary in grants.modifiers:
			if not result.modifiers.has(modifier.id):
				result.modifiers[modifier.id] = modifier.duplicate(true)
			elif modifier.has("values"):
				for value in modifier.values:
					if not result.modifiers[modifier.id].values.has(value):
						result.modifiers[modifier.id].values.append(value)
			elif modifier.value is bool:
				result.modifiers[modifier.id].value = result.modifiers[modifier.id].value or modifier.value
			elif modifier.value is int:
				result.modifiers[modifier.id].value = maxi(int(result.modifiers[modifier.id].value), modifier.value)
			else:
				result.modifiers[modifier.id].value = maxf(float(result.modifiers[modifier.id].value), float(modifier.value))
	result.equipment_ids.sort()
	result.ability_ids.sort()
	for modifier: Dictionary in result.modifiers.values():
		if modifier.has("values"):
			modifier.values.sort()
	return result


static func requirements(id: String, research_ids: Array, story_flags: Dictionary = {}, branches: Dictionary = {}, catalog: Array[Dictionary] = []) -> Dictionary:
	var definitions := catalog if not catalog.is_empty() else GameDefinitions.entries("research")
	var by_id: Dictionary = {}
	for definition in definitions:
		by_id[definition.id] = definition
	var node: Dictionary = by_id.get(id, {})
	var result := {"known": not node.is_empty(), "implemented": node.get("implemented", false), "owned": research_ids.has(id),
		"missing_prerequisites": [], "missing_story_gates": [], "conflicts": [], "branch_conflict": false}
	if node.is_empty():
		return result
	for prerequisite: String in node.prerequisite_ids:
		if not research_ids.has(prerequisite):
			result.missing_prerequisites.append(prerequisite)
	for gate: String in node.story_gate_ids:
		if not story_flags.get(gate, false):
			result.missing_story_gates.append(gate)
	for prior: String in research_ids:
		var selected: Dictionary = by_id.get(prior, {})
		if node.exclusion_ids.has(prior) or selected.get("exclusion_ids", []).has(id):
			result.conflicts.append(prior)
	result.branch_conflict = not node.family_id.is_empty() and branches.has(node.family_id) and branches[node.family_id] != node.path_id
	return result
