class_name SlotDesignLibrary
extends RefCounted

# Read-only prototype archive; physical equipment belongs to HangarState.

var path := "user://slot_designs.json"
var last_error := ""
var generation := 0
var designs := {}
var store := AtomicRunStore.new()

static func valid(payload: Variant) -> bool:
	if not payload is Dictionary or payload.get("version") != 3 or payload.get("format") != SlotShipDesign.FORMAT or not payload.get("designs") is Dictionary:
		return false
	for name: Variant in payload.designs:
		if not name is String or name.is_empty() or name != name.strip_edges() or name.length() > 32 or "\n" in name or "\r" in name or not SlotShipDesign.new().load_data(payload.designs[name]):
			return false
	return true

func load_library() -> bool:
	var latest := store.load_latest(path, valid)
	if latest.is_empty() and ["", ".next", ".bak"].any(func(suffix: String) -> bool: return FileAccess.file_exists(path + suffix)):
		last_error = "Could not load designs."
		return false
	designs = latest.get("payload", {}).get("designs", {}).duplicate(true)
	generation = int(latest.get("generation", 0))
	last_error = ""
	return true

func get_design(name: String) -> SlotShipDesign:
	var design := SlotShipDesign.new()
	return design if designs.has(name) and design.load_data(designs[name]) else null
