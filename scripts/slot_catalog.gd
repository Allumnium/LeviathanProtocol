class_name SlotCatalog
extends RefCounted

const TYPES := ["offense", "defense", "tech", "civic"]
const SIZES := ["S", "M", "L", "XL"]
const EQUIPMENT_PATH := "res://data/slot_equipment.json"
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

static func equipment(include_retired := false) -> Array[Dictionary]:
	if _equipment.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(EQUIPMENT_PATH))
		if not valid_equipment(data):
			push_error("Invalid slot equipment catalog.")
			return []
		_equipment.assign(data.equipment)
		_equipment.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	var result: Array[Dictionary] = []
	for item in _equipment:
		if include_retired or not item.get("retired", false):
			result.append(item.duplicate(true))
	return result

static func find_equipment(id: String, rank := 1) -> Dictionary:
	for item in equipment(true):
		if item.id == id and item.rank == rank:
			return item
	return {}

static func compatible(slot: Dictionary, item: Dictionary) -> bool:
	return not item.is_empty() and slot.size == item.size and slot.type == item.type

static func unlocked(item: Dictionary, grants: Dictionary) -> bool:
	return not item.is_empty() and not item.get("retired", false) and grants.get("error", "").is_empty() and item.id in grants.get("equipment_ids", []) and item.rank <= int(grants.get("ranks", {}).get(item.id, 0))

static func stats_for(id: String, rank := 1) -> ShipPartStats:
	var item := find_equipment(id, rank)
	if item.is_empty():
		return null
	var values: Dictionary = item.stats
	var stats := ShipPartStats.new(values.shields, values.integrity, values.weight, values.thrust)
	for weapon: Dictionary in values.weapons:
		var copy := ShipWeaponStats.new(weapon.name, weapon.interval, weapon.damage, int(weapon.count), weapon.range, Vector2(weapon.mount[0], weapon.mount[1]))
		copy.is_projectile_weapon = weapon.projectile
		copy.interceptable = weapon.interceptable
		copy.charge_seconds = weapon.charge
		stats.weapons.append(copy)
	return stats

static func valid_equipment(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not data.get("equipment") is Array or data.equipment.is_empty():
		return false
	var seen := {}
	for item: Variant in data.equipment:
		if not item is Dictionary or not item.get("id") is String or not item.get("name") is String or not _integer(item.get("rank")) or not _integer(item.get("revision")) or not _integer(item.get("part_type"), 0) or item.get("size") not in SIZES or item.get("type") not in TYPES or not item.get("stats") is Dictionary or not item.get("retired", false) is bool:
			return false
		var definition := GameDefinitions.find("equipment", item.id)
		var key := "%s/%d" % [item.id, item.rank]
		if definition.is_empty() or not definition.implemented or definition.type_id != item.part_type or item.id == "command_center" or seen.has(key):
			return false
		var rank_exists: bool = definition.ranks.is_empty() and item.rank == 1
		for rank: Dictionary in definition.ranks:
			rank_exists = rank_exists or rank.rank == item.rank
		if not rank_exists:
			return false
		seen[key] = true
		if not _integer(item.get("price"), 0) or not _integer(item.get("hit_points")):
			return false
		for field in ["shields", "integrity", "weight", "thrust"]:
			if not _nonnegative(item.stats.get(field)):
				return false
		if not item.stats.get("weapons") is Array:
			return false
		for weapon: Variant in item.stats.weapons:
			if not weapon is Dictionary or not weapon.get("name") is String or not _integer(weapon.get("count")) or not weapon.get("projectile") is bool or not weapon.get("interceptable") is bool or not weapon.get("mount") is Array or weapon.mount.size() != 2:
				return false
			for field in ["interval", "damage", "range", "charge"]:
				if not _nonnegative(weapon.get(field)) or (field != "charge" and weapon[field] == 0):
					return false
			for coordinate: Variant in weapon.mount:
				if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)):
					return false
	return true

static func _nonnegative(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= 0

static func _integer(value: Variant, minimum := 1) -> bool:
	return _nonnegative(value) and value >= minimum and value <= 2147483647 and value == floor(value)

static func valid_chassis(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not data.get("chassis") is Array or data.chassis.is_empty():
		return false
	var ids := {}
	for entry: Variant in data.chassis:
		if not entry is Dictionary or not entry.get("id") is String or ids.has(entry.id) or not entry.get("name") is String or not entry.get("art") is String or not ResourceLoader.exists(entry.art) or not entry.get("slots") is Array or entry.slots.is_empty():
			return false
		ids[entry.id] = true
		for field in ["price", "command", "command_cost"]:
			if not _integer(entry.get(field), 0):
				return false
		for field in ["integrity", "mass", "thrust", "radius"]:
			if not _nonnegative(entry.get(field)) or entry[field] <= 0:
				return false
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
