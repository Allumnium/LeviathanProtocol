class_name ResearchViewModel
extends RefCounted

const GROUP_NAMES := {"shared": "Foundation", "science": "Science", "civil": "Hospitality", "logistics": "Logistics",
	"sensors": "Sensors", "mining": "Mining", "energy": "Energy", "survival": "Survival",
	"force_projection": "Force projection", "fleet_operations": "Fleet operations"}
const GATE_NAMES := {"boss_i_defeated": "Defeat the Bastion Warden", "boss_ii_defeated": "Defeat the Brood Architect", "boss_iii_defeated": "Defeat the Leviathan"}

static func group_for(node: Dictionary) -> String:
	if not node.family_id.is_empty():
		return node.family_id
	if node.id in ["laboratory_ii", "laboratory_iii", "analysis_methods", "quantum_observation"]:
		return "science"
	if node.id in ["civil_hospitality", "luxury_habitation", "grand_hospitality"]:
		return "civil"
	if node.id in ["material_handling", "selective_recovery", "industrial_integration", "freight_engineering"]:
		return "logistics"
	if node.id in ["sensor_networks", "cloaking_theory"]:
		return "sensors"
	if node.id in ["mineral_spectroscopy", "basic_extraction", "deep_extraction", "planetary_fracture"]:
		return "mining"
	return "shared"

static func nodes(registry: Dictionary, owned: Array, flags: Dictionary, branches: Dictionary, rp: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var catalog: Array[Dictionary] = []
	catalog.assign(registry.research)
	var depths: Dictionary = {}
	# Topological depth within a family/group, including hidden prerequisites.
	while depths.size() < catalog.size():
		var progressed := false
		for node in catalog:
			if depths.has(node.id):
				continue
			var depth := 0
			var ready := true
			for parent: String in node.prerequisite_ids:
				if not depths.has(parent):
					ready = false
					break
				for candidate in catalog:
					if candidate.id == parent and group_for(candidate) == group_for(node):
						depth = maxi(depth, int(depths[parent]) + 1)
			if ready:
				depths[node.id] = depth
				progressed = true
		if not progressed:
			return []
	for node in catalog:
		# Planned definitions stay hidden, even in previews of downstream rewards.
		if not node.implemented and not owned.has(node.id):
			continue
		var requirements := ResearchRules.requirements(node.id, owned, flags, branches, catalog)
		var status := "Ready"
		if requirements.owned:
			status = "Owned"
		elif not requirements.conflicts.is_empty() or requirements.branch_conflict:
			status = "Excluded"
		elif not requirements.missing_prerequisites.is_empty():
			status = "Prerequisites"
		elif not requirements.missing_story_gates.is_empty():
			status = "Story gate"
		elif rp < int(node.cost_rp):
			status = "Need RP"
		elif not requirements.implemented:
			status = "Unavailable"
		result.append({"id": node.id, "name": node.display_name, "group": group_for(node), "path": node.path_id,
			"depth": depths[node.id], "cost": int(node.cost_rp), "status": status, "requirements": requirements,
			"nearby": not requirements.owned and requirements.conflicts.is_empty() and not requirements.branch_conflict
				and requirements.missing_prerequisites.is_empty() and requirements.missing_story_gates.is_empty()})
	return result

static func find(registry: Dictionary, domain: String, id: String) -> Dictionary:
	for entry: Dictionary in registry[domain]:
		if entry.id == id:
			return entry
	return {}

static func names(registry: Dictionary, domain: String, ids: Array) -> String:
	var result: Array[String] = []
	for id: String in ids:
		result.append(find(registry, domain, id).get("display_name", id))
	return ", ".join(result)

static func effect_summary(registry: Dictionary, id: String) -> String:
	var node := find(registry, "research", id)
	var lines: Array[String] = []
	for equipment_id: String in node.grants.equipment_ids:
		var equipment := find(registry, "equipment", equipment_id)
		if equipment.implemented:
			lines.append(equipment.display_name)
			match equipment_id:
				"repair_station": lines.append("2 HP/s, 2 adjacent\n20 HP reserve")
				"point_defense_turret": lines.append("Missile defense")
				"missile_rack": lines.append("3 missiles / burst")
				"passenger_cabin": lines.append("4 seats")
				"observation_deck": lines.append("+1 luxury, 2 adjacent\nExterior edge")
	for rank: Dictionary in node.grants.ranks:
		var equipment := find(registry, "equipment", rank.equipment_id)
		if equipment.implemented:
			lines.append("Lab %s\n1 RP/day" % ("II" if int(rank.rank) == 2 else "III"))
	for ability_id: String in node.grants.ability_ids:
		var ability := find(registry, "abilities", ability_id)
		if ability.implemented:
			lines.append(ability.display_name)
	for modifier: Dictionary in node.grants.modifiers:
		match modifier.id:
			"energy_efficiency": lines.append("+%d%% beams / shield recharge" % roundi(modifier.value * 100))
			"cargo_hold_capacity": lines.append("%d cargo / hold" % int(modifier.value))
			"scan_spectroscopy": lines.append("Scan: ore details")
			"extractable_materials": lines.append("Extractable materials: " + names(registry, "materials", modifier.values))
	return "\n\n".join(lines)

static func details(registry: Dictionary, id: String, visible_ids: Array) -> String:
	var node := find(registry, "research", id)
	if node.is_empty():
		return ""
	var lines: Array[String] = ["%s — %d RP" % [node.display_name, int(node.cost_rp)]]
	lines.append("Requires (all): " + (names(registry, "research", node.prerequisite_ids) if not node.prerequisite_ids.is_empty() else "Starting knowledge"))
	for gate: String in node.story_gate_ids:
		lines.append("Story: " + GATE_NAMES.get(gate, gate))
	lines.append("\nOne research unlocks:")
	for equipment_id: String in node.grants.equipment_ids:
		var equipment := find(registry, "equipment", equipment_id)
		if not equipment.implemented:
			continue
		lines.append("• %s\n  %s" % [equipment.display_name, String(equipment.recipe).replace("/", "\n  ")])
		match equipment.id:
			"repair_station": lines.append("  2 HP/s to two adjacent surviving components; 20 HP per node. No reconstruction.")
			"point_defense_turret": lines.append("  Intercepts missiles within 160; weak hull fire.")
			"missile_rack": lines.append("  Three interceptable missiles per burst; range 340.")
	for rank: Dictionary in node.grants.ranks:
		var equipment := find(registry, "equipment", rank.equipment_id)
		if not equipment.implemented:
			continue
		for physical: Dictionary in equipment.ranks:
			if int(physical.rank) == int(rank.rank):
				lines.append("• %s rank %d\n  %s" % [equipment.display_name, int(rank.rank), String(physical.recipe).replace("/", "\n  ")])
	for ability_id: String in node.grants.ability_ids:
		var ability := find(registry, "abilities", ability_id)
		if ability.implemented:
			lines.append("• Ability: " + ability.display_name)
	for modifier: Dictionary in node.grants.modifiers:
		match modifier.id:
			"energy_efficiency": lines.append("• +%d%% beam firing / shield recharge rate; ordinary efficiency cap +%d%%." % [roundi(modifier.value * 100), roundi(modifier.ordinary_efficiency_cap * 100)])
			"cargo_hold_capacity": lines.append("• Cargo Hold capacity 10 → %d. Existing loads do not refill." % int(modifier.value))
			"scan_spectroscopy": lines.append("• Scan reveals ore type, quantity and extractability.")
			"extractable_materials": lines.append("• Extractable materials: " + names(registry, "materials", modifier.values))
	if not node.family_id.is_empty():
		lines.append("\nCommits only %s to %s. No respec this run." % [GROUP_NAMES[node.family_id], String(node.path_id).capitalize()])
		lines.append("Locks the opposite path:")
		lines.append("All opposite-path tiers, including future unlocks, stay locked this run.")
		for excluded: String in node.exclusion_ids:
			if not visible_ids.has(excluded):
				continue
			var other := find(registry, "research", excluded)
			lines.append("• %s: %s" % [other.display_name, names(registry, "equipment", other.grants.equipment_ids)])
		lines.append("Later on this path:")
		for later: Dictionary in registry.research:
			if later.id == id or not visible_ids.has(later.id) or later.path_id != node.path_id or later.family_id != node.family_id:
				continue
			# Only descendants, never describe an earlier tier as a later reward.
			var prior: Array = later.prerequisite_ids.duplicate()
			var seen: Array = []
			while not prior.is_empty():
				var next: String = prior.pop_back()
				if seen.has(next):
					continue
				seen.append(next)
				prior.append_array(find(registry, "research", next).get("prerequisite_ids", []))
			if seen.has(id):
				lines.append("• %s (%d RP): %s%s" % [later.display_name, int(later.cost_rp), names(registry, "equipment", later.grants.equipment_ids),
					"; " + GATE_NAMES[later.story_gate_ids[0]] if not later.story_gate_ids.is_empty() else ""])
	lines.append("\nRecipes: O Offense · D Defense · T Tech · C Civic · . outside footprint")
	return "\n".join(lines)
