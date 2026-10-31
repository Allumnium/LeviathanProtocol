class_name HexDesignLibrary
extends RefCounted

const DEFAULT_PATH := "user://hex_designs.json"
var path := DEFAULT_PATH
var last_error := ""
var generation := 0
var designs := {}
var _loaded := false
var store := AtomicRunStore.new()

static func valid(payload: Variant) -> bool:
	if not payload is Dictionary or payload.get("version") != 2 or payload.get("topology") != HexRecipe.TOPOLOGY or not payload.get("designs") is Dictionary:
		return false
	for name: Variant in payload.designs:
		if not name is String or not valid_name(name):
			return false
		var design := HexShipDesign.new()
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
	_loaded = true
	last_error = ""
	return true

func save_design(name: String, design: HexShipDesign) -> bool:
	if not _loaded and not load_library():
		return false
	name = name.strip_edges()
	if not valid_name(name):
		last_error = "Use a name of 1-32 characters."
		return false
	var next := designs.duplicate(true)
	next[name] = design.to_data()
	var result := store.commit(path, {"version": 2, "topology": HexRecipe.TOPOLOGY, "designs": next}, valid, generation)
	if not result.ok:
		last_error = "Library changed. Reopen Designer." if "changed" in store.last_error else "Could not save design."
		return false
	designs = next
	generation = int(result.generation)
	last_error = ""
	return true

func get_design(name: String) -> HexShipDesign:
	var design := HexShipDesign.new()
	return design if designs.has(name) and design.load_data(designs[name]) else null
