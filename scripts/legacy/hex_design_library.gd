class_name LegacyHexDesignLibrary
extends RefCounted

# Read-only compatibility reader. The actual game owns physical ships and equipment.

const DEFAULT_PATH := "user://hex_designs.json"
var path := DEFAULT_PATH
var last_error := ""
var generation := 0
var designs := {}

var store := AtomicRunStore.new()

static func valid(payload: Variant) -> bool:
	if not payload is Dictionary or payload.get("version") != 2 or payload.get("topology") != LegacyHexRecipe.TOPOLOGY or not payload.get("designs") is Dictionary:
		return false
	for name: Variant in payload.designs:
		if not name is String or not valid_name(name):
			return false
		var design := LegacyHexShipDesign.new()
		if not design.load_data(payload.designs[name]):
			return false
	return true

static func valid_name(name: String) -> bool:
	return not name.is_empty() and name == name.strip_edges() and name.length() <= 32 and not "\n" in name and not "\r" in name

func load_library() -> bool:
	var latest := store.load_latest(path, valid)
	if latest.is_empty() and ["", ".next", ".bak"].any(func(suffix: String) -> bool: return FileAccess.file_exists(path + suffix)):
		last_error = "Could not load hex designs."
		return false
	designs = latest.get("payload", {}).get("designs", {}).duplicate(true)
	generation = int(latest.get("generation", 0))

	last_error = ""
	return true

func get_design(name: String) -> LegacyHexShipDesign:
	var design := LegacyHexShipDesign.new()
	return design if designs.has(name) and design.load_data(designs[name]) else null
