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
	if data.has("destroy_all_neutral_targets") and not data.destroy_all_neutral_targets is bool:
		return "Invalid neutral cleanup preference."
	if data.has("run_ended") and not data.run_ended is bool:
		return "Invalid terminal run state."
	for key in ["research_ids", "active_design_families", "current_run_design_names"]:
		if not data.get(key) is Array:
			return "Run progress requires %s." % key
		for value in data[key]:
			if not value is String:
				return "Invalid name in %s." % key
	if data.active_design_families.size() != 3:
		return "Run progress requires three regular design families."
	if not _integer(data.get("family_identity_version", 0)) or int(data.get("family_identity_version", 0)) not in [0, 1]:
		return "Invalid family identity version."
	var family_names: Array[String] = []
	for name: String in data.active_design_families:
		if name.is_empty():
			continue
		if family_names.has(name) and data.get("family_identity_version", 0) == 0:
			return "Duplicate active design family."
		family_names.append(name)
	if not data.get("branch_choices") is Dictionary or not data.get("story_flags") is Dictionary:
		return "Run progress requires branch choices and story flags."
	for key in data.story_flags:
		if not key is String or key.is_empty() or not data.story_flags[key] is bool:
			return "Invalid story flag."
	return ResearchRules.selection_error(data.research_ids, data.story_flags, data.branch_choices)

static func _integer(value: Variant) -> bool:
	if value is int:
		return true
	# JSON numbers use floats; reject fractional/out-of-range values before casting.
	return value is float and is_finite(value) and absf(value) <= 9007199254740991.0 and value == floor(value)
