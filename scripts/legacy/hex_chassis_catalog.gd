class_name LegacyHexChassisCatalog
extends RefCounted

const DATA_PATH := "res://data/legacy/hex_chassis.json"
static var _entries: Array[Dictionary] = []

# Return fresh definitions: an editor cannot mutate the canonical hull/masks.
static func find(id: String, revision := 1) -> LegacyHexChassisDefinition:
	if _entries.is_empty():
		entries()
	for entry: Dictionary in _entries:
		if entry.id == id and entry.revision == revision:
			return LegacyHexChassisDefinition.from_data(entry)
	return null

static func entries() -> Array[Dictionary]:
	if not _entries.is_empty():
		return _entries.duplicate(true)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var errors := validate(data)
	if not errors.is_empty():
		push_error("Invalid chassis catalog: %s" % "; ".join(errors))
		return []
	_entries.assign(data.chassis)
	return _entries.duplicate(true)

static func validate(data: Variant) -> Array[String]:
	if not data is Dictionary or data.get("schema_version") != 1 or data.get("topology") != LegacyHexRecipe.TOPOLOGY or not data.get("chassis") is Array:
		return ["Unsupported chassis catalog schema."]
	var errors: Array[String] = []
	var ids := {}
	for entry: Variant in data.chassis:
		errors.append_array(LegacyHexChassisDefinition.validate(entry))
		if entry is Dictionary and entry.get("id") is String:
			var key := "%s/%s" % [entry.id, entry.get("revision")]
			if ids.has(key):
				errors.append("Duplicate chassis revision.")
			ids[key] = true
	return errors
