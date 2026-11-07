extends RefCounted

const Modifiers = preload("res://scripts/content/research_modifiers.gd")

# Cross-field rules shared by Content, CLI validation and the future editor.
static func validate(data: Dictionary, meta: Dictionary, db: DefDatabase) -> Array:
	var authored := data.duplicate(true)
	authored.erase("id")
	if not db.schemas.validate("research", authored).problems.is_empty():
		return [] # Schema errors already carry their exact paths.
	var problems: Array = []
	if data.offered and not data.implemented:
		problems.append({"path": "offered", "related_paths": ["implemented"], "message": "Unimplemented research cannot be offered."})
	if data.offered and data.id != "foundation" and data.description.strip_edges().is_empty():
		problems.append({"path": "description", "related_paths": ["offered"], "message": "An offered card needs a short gameplay description."})
	if data.family_id.is_empty() != data.path_id.is_empty():
		problems.append({"path": "path_id", "related_paths": ["family_id"], "message": "Declare both a research family and its path, or leave both empty."})
	elif not data.family_id.is_empty():
		var family := db.get_def("research_family", data.family_id, meta.pack)
		if not family.is_empty() and family.get("paths") is Array and data.path_id not in family.paths:
			var family_id := db.resolve_id("research_family", data.family_id, meta.pack)
			problems.append({"path": "path_id", "related_paths": ["family_id"],
				"causes": [{"type": "research_family", "id": family_id, "path": "paths"}],
				"message": "Path '%s' is not declared by family '%s'." % [data.path_id, data.family_id]})
	if data.id != "foundation" and data.prerequisite_ids.is_empty():
		problems.append({"path": "prerequisite_ids", "message": "Research needs a starting or earlier prerequisite."})
	var grant_count := 0
	for field in ["equipment_ids", "ability_ids", "ranks", "modifiers"]:
		grant_count += data.grants[field].size()
	if data.implemented and data.id != "foundation" and grant_count == 0:
		problems.append({"path": "grants", "message": "Implemented research must grant an effect."})
	if data.offered:
		for id: String in data.grants.ability_ids:
			var ability := db.get_def("ability", id, meta.pack)
			if not ability.is_empty() and ability.get("availability") == "unavailable":
				problems.append({"path": "grants.ability_ids", "causes": [{"type": "ability", "id": db.resolve_id("ability", id, meta.pack), "path": "availability"}], "message": "Offered research cannot grant an unavailable ability."})
	var materials: Array[String] = []
	for material: Dictionary in db.all("material"):
		materials.append(str(material.id))
	var modifier_ids := {}
	for modifier: Dictionary in data.grants.modifiers:
		var path := "grants.modifiers[%s]" % modifier.id
		if modifier_ids.has(modifier.id):
			problems.append({"path": path, "message": "Research repeats modifier '%s'." % modifier.id})
		modifier_ids[modifier.id] = true
		if not Modifiers.valid(modifier, materials, db.schemas):
			problems.append({"path": path, "message": "Unknown modifier or invalid parameters for '%s'." % modifier.id})
	# A bounded graph walk catches direct and transitive cycles without recursion.
	var pending: Array = []
	for ref: String in data.prerequisite_ids:
		pending.append({"record": db.record("research", ref, meta.pack),
			"causes": [{"type": "research", "id": meta.qid, "path": "prerequisite_ids"}]})
	var visited := {}
	while not pending.is_empty():
		var step: Dictionary = pending.pop_back()
		var record: Dictionary = step.record
		if record.is_empty():
			continue # Reference validation reports unknown IDs.
		if record.qid == meta.qid:
			problems.append({"path": "prerequisite_ids", "causes": step.causes, "message": "Research prerequisites contain a cycle."})
			break
		if visited.has(record.qid):
			continue
		visited[record.qid] = true
		var causes: Array = step.causes.duplicate()
		causes.append({"type": "research", "id": record.qid, "path": "prerequisite_ids"})
		var parents: Variant = record.data.get("prerequisite_ids", [])
		if parents is Array:
			for ref: Variant in parents:
				if ref is String:
					pending.append({"record": db.record("research", ref, record.pack), "causes": causes})
	return problems
