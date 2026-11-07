class_name ResearchRules
extends RefCounted

static func family_key(ref: String) -> String:
	if ref.is_empty():
		return ""
	var canonical := Content.runtime_id("research_family", ref)
	return ref if canonical.is_empty() else canonical

static func family_paths() -> Dictionary:
	var result := {}
	for record: Dictionary in Content.db().records("research_family"):
		if record.abstract:
			continue
		result[Content.runtime_id("research_family", record.qid)] = record.data.paths
	return result


static func _unique_strings(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if not value is String or value.is_empty() or seen.has(value):
			return false
		seen[value] = true
	return true


static func _modifier_valid(modifier: Variant, materials: Array[String]) -> bool:
	return preload("res://scripts/content/research_modifiers.gd").valid(modifier, materials)


static func validate_registry(registry: Dictionary) -> Array[String]:
	# Called after GameDefinitions validates the envelope and references.
	var errors: Array[String] = []
	var nodes: Dictionary = {}
	var equipment: Dictionary = {}
	var materials: Array[String] = []
	var families := family_paths()
	for item: Dictionary in registry.materials:
		materials.append(item.id)
	for item: Dictionary in registry.equipment:
		equipment[item.id] = item
	for node: Dictionary in registry.research:
		if not node.get("offered") is bool or not node.get("description") is String \
				or (node.get("offered", false) and (not node.implemented or (node.id != "foundation" and node.description.is_empty()))):
			errors.append("Invalid research offer status/description: %s" % node.id)
		if not node.get("equipment_capabilities_any", []) is Array or not _unique_strings(node.get("equipment_capabilities_any", [])):
			errors.append("Invalid research equipment capabilities: %s" % node.id)
		var canonical := node.duplicate(true)
		canonical.family_id = family_key(node.family_id)
		nodes[node.id] = canonical
		for field in ["prerequisite_ids", "exclusion_ids", "story_gate_ids"]:
			if not _unique_strings(node[field]):
				errors.append("Duplicate or invalid research list: %s/%s" % [node.id, field])
		if node.prerequisite_ids.has(node.id) or node.exclusion_ids.has(node.id):
			errors.append("Research cannot depend on or exclude itself: %s" % node.id)
		for gate in node.story_gate_ids:
			if not Content.has_def("story_gate", gate):
				errors.append("Unknown research story gate: %s/%s" % [node.id, str(gate)])
		if node.family_id.is_empty() != node.path_id.is_empty() or (not node.family_id.is_empty() \
			and (not families.has(node.family_id) or node.path_id not in families[node.family_id])):
			errors.append("Unknown research family/path: %s" % node.id)
		var grant_count := 0
		for field in ["equipment_ids", "ability_ids"]:
			if not _unique_strings(node.grants[field]):
				errors.append("Duplicate research grants: %s/%s" % [node.id, field])
		for field in ["equipment_ids", "ability_ids", "ranks", "modifiers"]:
			grant_count += node.grants[field].size()
		if node.implemented and grant_count == 0 and node.id != "foundation":
			errors.append("Research must grant an effect: %s" % node.id)
		if node.id != "foundation" and node.prerequisite_ids.is_empty():
			errors.append("Research needs prerequisites: %s" % node.id)
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
	if not nodes.has("foundation") or not nodes.foundation.prerequisite_ids.is_empty() \
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
				if ability.id == ability_id and not available_equipment.has(ability.source_equipment_id) \
						and Content.get_def("equipment", ability.source_equipment_id).get("availability", "unavailable") != "ordinary":
					errors.append("Ability research requires its source equipment: %s/%s" % [id, ability_id])
	return errors


static func selection_error(research_ids: Array, story_flags: Dictionary, branches: Dictionary, definitions: Array[Dictionary] = []) -> String:
	if not _unique_strings(research_ids) or not research_ids.has("foundation"):
		return "Current-run research must contain Foundation and unique known IDs."
	var families := family_paths()
	var canonical_branches := {}
	for family in branches:
		if not families.has(family) or branches[family] not in families[family]:
			return "Unknown current-run branch commitment."
		var key := family_key(family)
		if key != family:
			return "Current-run branch commitment needs its canonical family ID."
		if canonical_branches.has(key):
			return "Duplicate current-run branch commitment."
		canonical_branches[key] = branches[family]
	var catalog := definitions if not definitions.is_empty() else GameDefinitions.entries("research")
	for id: String in research_ids:
		var required := requirements(id, research_ids, story_flags, canonical_branches, catalog)
		if not required.known:
			return "Unknown current-run research."
		if not required.missing_prerequisites.is_empty():
			return "Missing current-run research prerequisite."
		if not required.missing_story_gates.is_empty():
			return "Missing current-run research story gate."
		if not required.conflicts.is_empty() or required.branch_conflict:
			return "Current-run research conflicts with a branch commitment."
		var node := {}
		for definition: Dictionary in catalog:
			if definition.id == id:
				node = definition
				break
		if not node.family_id.is_empty() and canonical_branches.get(family_key(node.family_id), "") != node.path_id:
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
	id = Content.runtime_id("research", id) if Content.has_def("research", id) else id
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
		var flag := str(Content.get_def("story_gate", gate).get("flag", gate))
		if not story_flags.get(flag, false):
			result.missing_story_gates.append(gate)
	for prior: String in research_ids:
		var selected: Dictionary = by_id.get(prior, {})
		if node.exclusion_ids.has(prior) or selected.get("exclusion_ids", []).has(id):
			result.conflicts.append(prior)
	var family := family_key(node.family_id)
	for key: String in branches:
		if not family.is_empty() and family_key(key) == family and branches[key] != node.path_id:
			result.branch_conflict = true
	return result
