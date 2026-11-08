class_name HangarResearch
extends RefCounted

static func registry(content: DefDatabase = null) -> Dictionary:
	var result := GameDefinitions.snapshot(content)
	result.research = result.research.filter(func(node: Dictionary) -> bool: return node.implemented)
	return result

static func view_registry(content: DefDatabase = null) -> Dictionary:
	var result := registry(content)
	result.research = result.research.filter(func(node: Dictionary) -> bool: return node.offered)
	return result

static func catalog(content: DefDatabase = null) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(registry(content).research)
	return result

static func eligible(key: String, progress: Dictionary, content: DefDatabase = null) -> bool:
	if not Content.get_def("research", key, "", content).get("offered", false):
		return false
	var row := ResearchRules.requirements(key, progress.research_ids, progress.story_flags, progress.branch_choices, catalog(content), content)
	return row.known and row.implemented and not row.owned and row.missing_prerequisites.is_empty() and row.missing_story_gates.is_empty() and row.conflicts.is_empty() and not row.branch_conflict

# Each choice uses a shared bar; individual catalog prices no longer gate upgrades.
static func threshold(progress: Dictionary, content: DefDatabase = null) -> int:
	return int(Content.get_def("research_tuning", "core:default", "", content).threshold_step) * maxi(1, progress.research_ids.size())

static func available(progress: Dictionary, deployed: Variant = null, content: DefDatabase = null) -> Array[String]:
	var result: Array[String] = []
	for node: Dictionary in catalog(content):
		if eligible(node.id, progress, content) and (deployed == null or _matches(node.id, deployed, content)):
			result.append(node.id)
	result.sort()
	return result

static func _matches(id: String, deployed: Variant, content: DefDatabase) -> bool:
	return deployed.matches_research(id) if deployed is FactView else ResearchUpgrades.matches(id, deployed, content)

static func option_count(deployed: Array[FleetShip], content: DefDatabase = null) -> int:
	var base := int(Content.get_def("research_tuning", "core:default", "", content).base_options)
	for ship: FleetShip in deployed:
		if ship is HangarShip and ship.flagship and ship.is_alive():
			return base + int(ship.chassis.get("research_option_bonus", 0))
	return base

static func prepare_offer(progress: Dictionary, seed_value: int, count: int, deployed: Variant = null, content: DefDatabase = null) -> void:
	if not progress.research_offer.is_empty() or float(progress.research_points) < threshold(progress, content):
		return
	var pool := available(progress, deployed, content)
	var ids: Array = progress.research_ids.duplicate()
	ids.sort()
	var rng := RngStreams.new(seed_value).fixed("research.offer.v1", StableHash.key(ids))
	while not pool.is_empty() and progress.research_offer.size() < count:
		var index := rng.randi_range(0, pool.size() - 1)
		progress.research_offer.append(pool[index])
		pool.remove_at(index)

static func valid(progress: Dictionary, content: DefDatabase = null) -> bool:
	for key in ["research_ids", "story_flags", "branch_choices", "research_offer", "research_points"]:
		if not progress.has(key):
			return false
	if not progress.research_ids is Array or not progress.story_flags is Dictionary or not progress.branch_choices is Dictionary:
		return false
	if not HangarCheckpoint._number(progress.research_points) or progress.research_points < 0:
		return false
	if not ResearchRules.selection_error(progress.research_ids, progress.story_flags, progress.branch_choices, catalog(content), content).is_empty():
		return false
	if not progress.research_offer is Array or progress.research_offer.size() > 4:
		return false
	var seen := {}
	for id: Variant in progress.research_offer:
		if not id is String or seen.has(id) or not eligible(id, progress, content):
			return false
		seen[id] = true
	return progress.research_offer.is_empty() or progress.research_points >= threshold(progress, content)
