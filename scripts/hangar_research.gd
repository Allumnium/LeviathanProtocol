class_name HangarResearch
extends RefCounted

# Active research excludes retired extraction and undefined slot bonuses.
const DEFERRED_EQUIPMENT := ["crew_quarters", "focusing_lens", "reactive_bulkhead", "observation_deck", "repair_station"]
const OMITTED_NODES := ["basic_extraction", "deep_extraction", "optics_i", "bastion_i"]
const DEFERRED_PURCHASES := ["gravitic_snare"]
const DEFERRED_RESEARCH := ["disruption_ii"]

static func registry() -> Dictionary:
	var result := GameDefinitions.snapshot()
	var nodes: Array[Dictionary] = []
	for node: Dictionary in result.research:
		if not node.implemented or node.id in OMITTED_NODES:
			continue
		node.grants.equipment_ids = node.grants.equipment_ids.filter(func(key: String) -> bool: return key not in DEFERRED_EQUIPMENT and (key == "command_center" or not SlotCatalog.find_equipment(key).is_empty()))
		node.grants.ability_ids = []
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

static func eligible(key: String, progress: Dictionary, include_deferred := false) -> bool:
	if not include_deferred and key in DEFERRED_RESEARCH:
		return false
	var row := ResearchRules.requirements(key, progress.research_ids, progress.story_flags, progress.branch_choices, catalog())
	return row.known and row.implemented and not row.owned and row.missing_prerequisites.is_empty() and row.missing_story_gates.is_empty() and row.conflicts.is_empty() and not row.branch_conflict

static func valid(progress: Dictionary) -> bool:
	for key in ["research_ids", "story_flags", "branch_choices", "research_points", "research_focus", "research_progress", "research_pricing_version"]:
		if not progress.has(key):
			return false
	if not progress.research_focus is String or not progress.research_progress is Dictionary or progress.research_pricing_version != 1:
		return false
	if not ResearchRules.selection_error(progress.research_ids, progress.story_flags, progress.branch_choices, catalog()).is_empty():
		return false
	if not progress.research_focus.is_empty() and not eligible(progress.research_focus, progress, true):
		return false
	for key: Variant in progress.research_progress:
		var amount: Variant = progress.research_progress[key]
		if not key is String or not eligible(key, progress, true) or not HangarCheckpoint._number(amount) or amount < 0 or amount >= ResearchFocusRules.cost(key, progress):
			return false
	return true
