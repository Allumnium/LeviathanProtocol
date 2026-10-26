class_name RunProgressData
extends RefCounted

# Validation for run metadata, not a complete fleet/encounter save file.
const VERSION := 1


static func validate(data: Variant) -> String:
	if not data is Dictionary or data.get("version") != VERSION:
		return "Unsupported run progress version."
	var seed_text: Variant = data.get("seed")
	if not seed_text is String or not seed_text.is_valid_int():
		return "Run seed must be an integer string."
	if int(seed_text) < 0 or str(int(seed_text)) != seed_text:
		return "Run seed is outside the supported range."
	for key in ["credits", "research_points", "difficulty"]:
		if not _integer(data.get(key)):
			return "Run progress requires integer %s." % key
	if data.research_points < 0 or int(data.difficulty) not in [0, 1, 2]:
		return "Invalid research points or difficulty."
	for key in ["research_ids", "active_design_families", "current_run_design_names"]:
		if not data.get(key) is Array:
			return "Run progress requires %s." % key
		for value in data[key]:
			if not value is String:
				return "Invalid name in %s." % key
	if data.active_design_families.size() != 3:
		return "Run progress requires three regular design families."
	var family_names: Array[String] = []
	for name: String in data.active_design_families:
		if name.is_empty():
			continue
		if family_names.has(name):
			return "Duplicate active design family."
		family_names.append(name)
	if not data.get("branch_choices") is Dictionary or not data.get("story_flags") is Dictionary:
		return "Run progress requires branch choices and story flags."
	for key in data.story_flags:
		if not key is String or key.is_empty() or not data.story_flags[key] is bool:
			return "Invalid story flag."
	var paths: Dictionary = {}
	for research in GameDefinitions.entries("research"):
		if not research.family_id.is_empty():
			if not paths.has(research.family_id):
				paths[research.family_id] = []
			if not paths[research.family_id].has(research.path_id):
				paths[research.family_id].append(research.path_id)
	for family in data.branch_choices:
		if not paths.has(family) or not paths[family].has(data.branch_choices[family]):
			return "Unknown research branch choice."
	var seen: Array[String] = []
	for id: String in data.research_ids:
		var research := GameDefinitions.find("research", id)
		if research.is_empty() or seen.has(id):
			return "Unknown or duplicate current-run research."
		seen.append(id)
		for prerequisite in research.prerequisite_ids:
			if not data.research_ids.has(prerequisite):
				return "Missing research prerequisite."
		for gate in research.story_gate_ids:
			if not data.story_flags.get(gate, false):
				return "Missing research story gate."
		if not research.family_id.is_empty():
			if data.branch_choices.get(research.family_id, "") != research.path_id:
				return "Research conflicts with run branch choice."
		for exclusion in research.exclusion_ids:
			if data.research_ids.has(exclusion):
				return "Opposite research paths cannot coexist."
	if not seen.has("foundation"):
		return "Foundation must be known in every run."
	return ""


static func _integer(value: Variant) -> bool:
	if value is int:
		return true
	# JSON numbers use floats; reject fractional/out-of-range values before casting.
	return value is float and is_finite(value) and absf(value) <= 9007199254740991.0 and value == floor(value)
