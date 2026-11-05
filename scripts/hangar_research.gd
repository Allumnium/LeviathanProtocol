class_name HangarResearch
extends RefCounted

# Active research excludes retired extraction and undefined slot bonuses.
const DEFERRED_EQUIPMENT := ["crew_quarters", "focusing_lens", "reactive_bulkhead", "observation_deck", "repair_station"]
const OMITTED_NODES := ["basic_extraction", "deep_extraction", "optics_i", "bastion_i"]
const DEFERRED_PURCHASES := ["gravitic_snare", "nanoforge"]
const DEFERRED_RESEARCH := ["disruption_ii", "renewal_ii"]
const RESEARCH_ONLY_EQUIPMENT := ["beam_lance", "torpedo_bomber_bay"]

static func starting_equipment(item: Dictionary) -> bool:
	return not item.is_empty() and item.id not in RESEARCH_ONLY_EQUIPMENT

static func registry() -> Dictionary:
	var result := GameDefinitions.snapshot()
	var nodes: Array[Dictionary] = []
	for node: Dictionary in result.research:
		if not node.implemented or node.id in OMITTED_NODES:
			continue
		node.grants.equipment_ids = node.grants.equipment_ids.filter(func(key: String) -> bool:
			return key in RESEARCH_ONLY_EQUIPMENT or (node.id in DEFERRED_RESEARCH and key in DEFERRED_PURCHASES))
		node.grants.ranks = []
		node.grants.ability_ids = node.grants.ability_ids.filter(func(key: String) -> bool:
			return node.id == "disruption_i" and key == "ion_pulse")
		if node.id == "optics_ii":
			node.prerequisite_ids = ["applied_energy"]
		if node.id == "bastion_ii":
			node.prerequisite_ids = ["foundation"]
		node.exclusion_ids = node.exclusion_ids.filter(func(key: String) -> bool: return key not in OMITTED_NODES)
		nodes.append(node)
	result.research = nodes
	result["lab_production_by_rank"] = true
	return result

static func view_registry() -> Dictionary:
	var result := registry()
	result.research = result.research.filter(func(node: Dictionary) -> bool: return node.id not in DEFERRED_RESEARCH)
	return result

static func catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(registry().research)
	return result

static func command_limit(base: int, research_ids: Array) -> int:
	if base <= 0:
		return 0
	var grants := ResearchRules.resolve(research_ids, catalog())
	return base + int(grants.modifiers.get("command_capacity_bonus", {}).get("value", 0))

static func eligible(key: String, progress: Dictionary, include_deferred := false) -> bool:
	if not include_deferred and key in DEFERRED_RESEARCH:
		return false
	var row := ResearchRules.requirements(key, progress.research_ids, progress.story_flags, progress.branch_choices, catalog())
	return row.known and row.implemented and not row.owned and row.missing_prerequisites.is_empty() and row.missing_story_gates.is_empty() and row.conflicts.is_empty() and not row.branch_conflict

# Each choice uses a shared bar; individual catalog prices no longer gate upgrades.
static func threshold(progress: Dictionary) -> int:
	return 20 * maxi(1, progress.research_ids.size())

static func available(progress: Dictionary, deployed: Variant = null) -> Array[String]:
	var result: Array[String] = []
	for node: Dictionary in catalog():
		if eligible(node.id, progress) and (deployed == null or ResearchUpgrades.matches(node.id, deployed)):
			result.append(node.id)
	result.sort()
	return result

static func option_count(deployed: Array[FleetShip]) -> int:
	for ship: FleetShip in deployed:
		if ship is HangarShip and ship.flagship and ship.is_alive():
			return 3 + int(ship.chassis.get("research_option_bonus", 0))
	return 3

static func prepare_offer(progress: Dictionary, seed_value: int, count: int, deployed: Variant = null) -> void:
	if not progress.research_offer.is_empty() or float(progress.research_points) < threshold(progress):
		return
	var pool := available(progress, deployed)
	var ids: Array = progress.research_ids.duplicate()
	ids.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ (",".join(ids)).hash()
	while not pool.is_empty() and progress.research_offer.size() < count:
		var index := rng.randi_range(0, pool.size() - 1)
		progress.research_offer.append(pool[index])
		pool.remove_at(index)

static func valid(progress: Dictionary) -> bool:
	for key in ["research_ids", "story_flags", "branch_choices", "research_offer", "research_points"]:
		if not progress.has(key):
			return false
	if not progress.research_ids is Array or not progress.story_flags is Dictionary or not progress.branch_choices is Dictionary:
		return false
	if not HangarCheckpoint._number(progress.research_points) or progress.research_points < 0:
		return false
	if not ResearchRules.selection_error(progress.research_ids, progress.story_flags, progress.branch_choices, catalog()).is_empty():
		return false
	if not progress.research_offer is Array or progress.research_offer.size() > 4:
		return false
	var seen := {}
	for id: Variant in progress.research_offer:
		if not id is String or seen.has(id) or not eligible(id, progress):
			return false
		seen[id] = true
	return progress.research_offer.is_empty() or progress.research_points >= threshold(progress)
