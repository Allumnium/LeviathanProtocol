class_name ResearchFocusRules
extends RefCounted

# Focus eligibility deliberately does not depend on the unspent RP balance.
static func eligible(id: String, progress: Dictionary) -> bool:
	var r := ResearchRules.requirements(id, progress.research_ids, progress.story_flags, progress.branch_choices)
	return r.known and r.implemented and not r.owned and r.missing_prerequisites.is_empty() \
		and r.missing_story_gates.is_empty() and r.conflicts.is_empty() and not r.branch_conflict

static func validate(progress: Dictionary) -> String:
	var focus: Variant = progress.get("research_focus", "")
	var projects: Variant = progress.get("research_progress", {})
	if not focus is String or not projects is Dictionary:
		return "Invalid research focus or progress."
	for id in projects:
		if not id is String or not eligible(id, progress):
			return "Invalid research project."
		var definition := GameDefinitions.find("research", id)
		if not RunProgressData._rp_number(projects[id]) or projects[id] < 0 or projects[id] >= definition.cost_rp:
			return "Invalid research project progress."
	if not focus.is_empty() and not eligible(focus, progress):
		return "Unavailable research focus."
	return ""

# Allocation and the reward that funded it are persisted as one checkpoint.
static func allocate(checkpoint: Dictionary) -> Dictionary:
	if checkpoint.is_empty():
		return {}
	var result := checkpoint.duplicate(true)
	var progress: Dictionary = result.progress
	var id: String = progress.get("research_focus", "")
	if id.is_empty():
		return result
	if not eligible(id, progress):
		return {}
	var definition := GameDefinitions.find("research", id)
	var projects: Dictionary = progress.get("research_progress", {}).duplicate()
	var before := float(projects.get(id, 0))
	var amount := minf(float(progress.research_points), float(definition.cost_rp) - before)
	if amount <= 0:
		return result
	var after := before + amount
	var transaction := TransactionLedger.apply(result, "research", "focus/%s/%s/%s" % [id, str(before), str(after)],
		0, [0, 0, 0, 0], -amount, {"research_id": id, "progress_before": before, "progress_after": after})
	if transaction.is_empty() or transaction.replayed:
		return {}
	result = transaction.checkpoint
	projects[id] = after
	if after == int(definition.cost_rp):
		result.progress.research_ids.append(id)
		if not definition.family_id.is_empty():
			result.progress.branch_choices[definition.family_id] = definition.path_id
		result.progress.research_focus = ""
		projects.erase(id)
		# Completing a mutually exclusive branch retires incompatible partial work.
		for other in projects.keys():
			if not eligible(other, result.progress):
				projects.erase(other)
	result.progress.research_progress = projects
	return result
