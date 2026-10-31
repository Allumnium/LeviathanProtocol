class_name LegacySquareDesignLibrary
extends RefCounted

# The original unwrapped ship_designs.json format, deliberately read-only.
var path := "user://ship_designs.json"
var designs: Dictionary = {}
var last_error := ""

func load_library() -> bool:
	if not FileAccess.file_exists(path):
		designs.clear()
		last_error = ""
		return true
	var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not payload is Dictionary or payload.get("version") != 1 or not payload.get("designs") is Array:
		last_error = "Could not read historical square designs."
		return false
	var loaded := {}
	for entry: Variant in payload.designs:
		if not entry is Dictionary or not entry.get("name") is String or entry.name.strip_edges().is_empty() \
			or loaded.has(entry.name) or not Ship.new().load_design_data(entry.get("ship")):
			last_error = "Invalid historical square design."
			return false
		loaded[entry.name] = entry.ship.duplicate(true)
	designs = loaded
	last_error = ""
	return true

func get_design(name: String) -> Ship:
	var design := Ship.new()
	return design if designs.has(name) and design.load_design_data(designs[name]) else null
