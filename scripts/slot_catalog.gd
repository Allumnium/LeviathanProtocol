class_name SlotCatalog
extends RefCounted

const TYPES := ["offense", "defense", "tech", "civic"]
const SIZES := ["S", "M", "L", "XL"]
# Explicit mount sizes, independent of the discarded material recipes.
const EQUIPMENT_SIZES := {
	"hull_plate": "S", "armor_block": "M", "mini_turret": "S", "laser": "S",
	"double_laser": "M", "shield_generator": "M", "thruster": "S", "large_thruster": "M",
	"crew_quarters": "M", "research_lab": "M", "cargo_hold": "XL", "passenger_cabin": "M",
	"repair_station": "M", "point_defense_turret": "S", "missile_rack": "M", "focusing_lens": "S",
	"beam_lance": "L", "stellar_lance": "XL", "ion_emitter": "M", "gravitic_snare": "L",
	"singularity_projector": "XL", "reactive_bulkhead": "L", "shield_relay": "L", "aegis_citadel": "XL",
	"repair_drone_bay": "L", "nanoforge": "L", "ark_restoration_core": "XL", "ammunition_magazine": "M",
	"railgun": "L", "siege_mass_driver": "XL", "flight_deck": "M", "torpedo_bomber_bay": "L",
	"hive_carrier_core": "XL", "command_uplink": "M", "tactical_computer": "L", "admiralty_nexus": "XL",
	"ecm_suite": "M", "phase_drive": "L", "ghost_network": "XL", "observation_deck": "M",
	"luxury_suites": "L", "grand_promenade": "XL", "tractor_array": "M", "sorting_refinery": "L",
	"industrial_foundry": "XL", "analysis_array": "M", "quantum_observatory": "XL", "sensor_array": "S",
	"radar_relay": "M", "cloak_generator": "L", "mining_laser": "S", "extraction_drill": "M",
	"ore_processor": "M", "seismic_cutter": "L", "planetcracker_core": "XL"
}
static var _chassis: Array[Dictionary] = []
static var _equipment: Array[Dictionary] = []

static func chassis() -> Array[Dictionary]:
	if _chassis.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/slot_chassis.json"))
		if not valid_chassis(data):
			push_error("Invalid slot chassis catalog.")
			return []
		_chassis.assign(data.chassis)
	return _chassis.duplicate(true)

static func find_chassis(id: String) -> Dictionary:
	for entry in chassis():
		if entry.id == id:
			return entry
	return {}

static func equipment() -> Array[Dictionary]:
	if _equipment.is_empty():
		for pattern in ShipPartPattern.get_catalog():
			if pattern.definition_id == "command_center":
				continue # Fixed chassis hardware, not a selectable slot item.
			if not EQUIPMENT_SIZES.has(pattern.definition_id):
				push_error("Missing slot size: " + pattern.definition_id)
				continue
			var size: String = EQUIPMENT_SIZES[pattern.definition_id]
			if pattern.definition_id == "research_lab":
				size = ["M", "L", "XL"][pattern.rank - 1]
			_equipment.append({"id": pattern.definition_id, "rank": pattern.rank,
				"name": pattern.display_name + (" %d" % pattern.rank if pattern.definition_id == "research_lab" else ""),
				"size": size, "type": TYPES[pattern.category], "part_type": pattern.part_type})
		_equipment.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	return _equipment.duplicate(true)

static func find_equipment(id: String, rank := 1) -> Dictionary:
	for item in equipment():
		if item.id == id and item.rank == rank:
			return item
	return {}

static func compatible(slot: Dictionary, item: Dictionary) -> bool:
	return not item.is_empty() and slot.size == item.size and slot.type == item.type

static func unlocked(item: Dictionary, grants: Dictionary) -> bool:
	return grants.get("error", "").is_empty() and item.id in grants.get("equipment_ids", []) and item.rank <= int(grants.get("ranks", {}).get(item.id, 0))

static func valid_chassis(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not data.get("chassis") is Array or data.chassis.is_empty():
		return false
	var ids := {}
	for entry: Variant in data.chassis:
		if not entry is Dictionary or not entry.get("id") is String or ids.has(entry.id) or not entry.get("name") is String or not entry.get("art") is String or not ResourceLoader.exists(entry.art) or not entry.get("slots") is Array or entry.slots.is_empty():
			return false
		ids[entry.id] = true
		var slots := {}
		for slot: Variant in entry.slots:
			if not slot is Dictionary or not slot.get("id") is String or slots.has(slot.id) or slot.get("type") not in TYPES or slot.get("size") not in SIZES or not slot.get("rect") is Array or slot.rect.size() != 4:
				return false
			slots[slot.id] = true
			for value: Variant in slot.rect:
				if not (value is float or value is int) or not is_finite(float(value)):
					return false
			var rect := Rect2(slot.rect[0], slot.rect[1], slot.rect[2], slot.rect[3])
			if rect.size.x <= 0 or rect.size.y <= 0 or not Rect2(0, 0, 512, 512).encloses(rect):
				return false
	return true
