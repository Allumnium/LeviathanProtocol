extends RefCounted

const CombatChecks = preload("res://scripts/content/combat_checks.gd")
const MAX_SHIPS := 192

# Validate relationships before Playtest, using this database rather than the
# active Content singleton. Causes let edits to referenced defs blame the patch.
static func validate(data: Dictionary, meta: Dictionary, db: DefDatabase) -> Array:
	if not CombatChecks.shape_valid(data, meta.type, db):
		return []
	var problems: Array = []
	match meta.type:
		"chassis":
			var loadout := db.record("loadout", data.default_loadout, meta.pack)
			if not loadout.is_empty() and CombatChecks.shape_valid(loadout.data, "loadout", db) \
					and db.resolve_id("chassis", loadout.data.chassis, loadout.pack) != meta.qid:
				problems.append({"path": "default_loadout", "causes": [cause("loadout", loadout.qid, "chassis")],
					"message": "The default loadout must fit this chassis."})
		"loadout":
			var chassis := db.record("chassis", data.chassis, meta.pack)
			if chassis.is_empty() or not CombatChecks.shape_valid(chassis.data, "chassis", db):
				return []
			var slots := {}
			for slot: Dictionary in chassis.data.slots:
				slots[slot.id] = slot
			if data.mounts.size() != slots.size() or not slots.keys().all(func(id: String) -> bool: return data.mounts.has(id)):
				problems.append({"path": "mounts", "related_paths": ["chassis"], "causes": [cause("chassis", chassis.qid, "slots")],
					"message": "A complete loadout needs exactly one item in every chassis slot."})
			for field: String in ["mounts", "previous_mounts"]:
				for slot_id: String in data.get(field, {}):
					var item := db.record("equipment", data[field][slot_id], meta.pack)
					if item.is_empty() or not CombatChecks.shape_valid(item.data, "equipment", db):
						continue
					if not slots.has(slot_id) or not SlotCatalog.compatible(slots[slot_id], item.data) \
							or item.data.get("retired", false) or item.data.availability == "unavailable":
						problems.append({"path": field + "." + slot_id, "related_paths": ["chassis"],
							"causes": [cause("chassis", chassis.qid, "slots"), cause("equipment", item.qid, "size"),
								cause("equipment", item.qid, "type"), cause("equipment", item.qid, "availability"), cause("equipment", item.qid, "retired")],
							"message": "Loadout equipment must be obtainable and fit the named slot."})
		"fleet_package":
			var seen := {}
			var count := 0
			var flagships := 0
			var flagship_causes: Array = []
			for member: Dictionary in data.members:
				var path := "members[%s]" % member.id
				if seen.has(member.id):
					problems.append({"path": "members", "message": "Fleet member IDs must be unique."})
				seen[member.id] = true
				count += int(member.count)
				if member.get("selected_flagship", false):
					flagships += int(member.count)
					for candidate: Dictionary in db.records("chassis"):
						if not candidate.abstract and CombatChecks.shape_valid(candidate.data, "chassis", db) and candidate.data.flagship:
							problems.append_array(starting_fit(candidate, path, db))
				else:
					var chassis := db.record("chassis", member.chassis, meta.pack)
					if not chassis.is_empty() and CombatChecks.shape_valid(chassis.data, "chassis", db):
						flagships += int(chassis.data.flagship) * int(member.count)
						flagship_causes.append(cause("chassis", chassis.qid, "flagship"))
						problems.append_array(starting_fit(chassis, path + ".chassis", db))
			if count > MAX_SHIPS:
				problems.append({"path": "members", "message": "Starting fleet exceeds the %d live combatant limit." % MAX_SHIPS})
			if flagships != 1:
				problems.append({"path": "members", "causes": flagship_causes, "message": "Starting fleet requires exactly one flagship."})
		"run_start":
			var location := db.record("location", data.location, meta.pack)
			if not location.is_empty() and CombatChecks.shape_valid(location.data, "location", db) \
					and (location.data.kind != "station" or not location.data.accessible):
				problems.append({"path": "location", "causes": [cause("location", location.qid, "kind"), cause("location", location.qid, "accessible")],
					"message": "A run must start at an accessible station."})
	return problems

static func starting_fit(chassis: Dictionary, path: String, db: DefDatabase) -> Array:
	var problems: Array = []
	var fit := db.record("loadout", chassis.data.default_loadout, chassis.pack)
	if not fit.is_empty() and CombatChecks.shape_valid(fit.data, "loadout", db):
		for ref: String in fit.data.mounts.values():
			var item := db.record("equipment", ref, fit.pack)
			if not item.is_empty() and item.data.get("availability") != "ordinary":
				problems.append({"path": path, "causes": [cause("chassis", chassis.qid, "default_loadout"),
					cause("loadout", fit.qid, "mounts"), cause("equipment", item.qid, "availability")],
					"message": "Starting fleet defaults must use ordinary equipment available before research."})
	return problems

static func cause(type: String, id: String, path: String) -> Dictionary:
	return {"type": type, "id": id, "path": path}
