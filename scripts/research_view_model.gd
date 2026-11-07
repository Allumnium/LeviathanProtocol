class_name ResearchViewModel
extends RefCounted

static func find(registry: Dictionary, domain: String, id: String) -> Dictionary:
	var canonical := Content.runtime_id(GameDefinitions.DEF_TYPES[domain], id)
	for entry: Dictionary in registry[domain]:
		if entry.id == canonical:
			return entry
	return {}

static func description(registry: Dictionary, id: String) -> String:
	return str(find(registry, "research", id).get("description", ""))
