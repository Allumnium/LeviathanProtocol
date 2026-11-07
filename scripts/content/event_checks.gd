extends RefCounted

# Encounter instance IDs are authored within a pack and never event indexes.
static func validate(data: Dictionary, meta: Dictionary, db: DefDatabase) -> Array:
	var authored := data.duplicate(true)
	authored.erase("id")
	if not db.schemas.validate("event", authored).problems.is_empty():
		return []
	var problems: Array = []
	for option: Dictionary in data.options:
		if not option.get("effects", {}).has("combat"):
			continue
		var combat: Dictionary = option.effects.combat
		var path := "options[%s].effects.combat.id" % option.id
		var template := db.record("encounter", combat.template, meta.pack)
		if not template.is_empty() and (not template.data.get("implemented", false) or not template.data.get("story_eligible", false)):
			problems.append({"path": "options[%s].effects.combat.template" % option.id,
				"causes": [{"type": "encounter", "id": template.qid, "path": "story_eligible"},
					{"type": "encounter", "id": template.qid, "path": "implemented"}],
				"message": "Story combat needs an implemented, story-eligible encounter template."})
		for other: Dictionary in db.records("event"):
			if other.abstract or other.pack != meta.pack:
				continue
			var choices: Variant = other.data.get("options", [])
			if not choices is Array:
				continue
			for choice: Variant in choices:
				if not choice is Dictionary or (other.qid == meta.qid and choice.get("id") == option.id):
					continue
				var effects: Variant = choice.get("effects", {})
				if not effects is Dictionary or not effects.get("combat") is Dictionary:
					continue
				if effects.combat.get("id") == combat.id:
					problems.append({"path": path, "causes": [{"type": "event", "id": other.qid,
						"path": "options[%s].effects.combat.id" % choice.get("id", "")}],
						"message": "Encounter instance ID '%s' is already used by another choice in this pack." % combat.id})
	return problems
