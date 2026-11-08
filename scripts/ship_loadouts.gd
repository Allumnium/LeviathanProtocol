extends RefCounted

# Named, fully fitted loadouts per ship class (loadout defs, id <chassis>/<name>).
# Chassis defs identify their default loadout explicitly. Player fitting uses
# complete loadouts; backend mount swaps also serve controlled fixtures.
const SHIP_PARTS_RATE := 0.5
static var _loadouts: Dictionary = {}
static var _database: DefDatabase

static func _ensure_database(content: DefDatabase = null) -> void:
	content = Content.db() if content == null else content
	if _database != content:
		_database = content
		_loadouts.clear()

static func parse_key(key: String) -> Dictionary:
	var parts := key.split("@")
	return {"id": parts[0], "rank": int(parts[1]) if parts.size() > 1 else 1}

static func key_for(item: Dictionary) -> String:
	return SlotCatalog.equipment_key(str(item.id), int(item.rank))

static func item_for(key: String, content: DefDatabase = null) -> Dictionary:
	if key.is_empty():
		return {}
	var parsed := parse_key(key)
	return SlotCatalog.find_equipment(parsed.id, parsed.rank, content)

# Catalog eligibility is independent of a run's earned research.
static func obtainable(item: Dictionary) -> bool:
	return not item.is_empty() and not item.get("retired", false) and item.get("availability", "unavailable") in ["ordinary", "research"]

static func all(content: DefDatabase = null) -> Dictionary:
	_ensure_database(content)
	if not _loadouts.is_empty():
		return _loadouts
	for loadout: Dictionary in Content.copies("loadout", content):
		var chassis_id := str(loadout.get("chassis", ""))
		var def_id := str(loadout.id)
		loadout.erase("chassis")
		loadout.definition_id = def_id
		loadout.id = def_id.trim_prefix(chassis_id + "/") if not def_id.contains(":") else def_id
		var chassis := SlotCatalog.find_chassis(chassis_id, content)
		if chassis.is_empty() or not _valid(chassis, loadout, content):
			push_error("Invalid loadout %s." % def_id)
			continue
		if not _loadouts.has(chassis_id):
			var options: Array[Dictionary] = []
			_loadouts[chassis_id] = options
		_loadouts[chassis_id].append(loadout)
	return _loadouts

static func _valid(chassis: Dictionary, loadout: Variant, content: DefDatabase = null) -> bool:
	if not loadout is Dictionary or not loadout.get("id") is String or not loadout.get("name") is String \
			or not loadout.get("mounts") is Dictionary:
		return false
	if loadout.mounts.size() != chassis.slots.size():
		return false
	for mounts: Variant in [loadout.mounts, loadout.get("previous_mounts", {})]:
		if not mounts is Dictionary:
			return false
		for slot_id: Variant in mounts:
			if not slot_id is String or not mounts[slot_id] is String:
				return false
			var slot := slot_by_id(chassis, slot_id)
			var item := item_for(mounts[slot_id], content)
			if slot.is_empty() or not SlotCatalog.compatible(slot, item) or not obtainable(item):
				return false
	return true

static func for_chassis(chassis_id: String, content: DefDatabase = null) -> Array:
	return all(content).get(Content.runtime_id("chassis", chassis_id, "", content), [])

static func equipment_available(item: Dictionary, research_ids: Array, content: DefDatabase = null) -> bool:
	if not obtainable(item):
		return false
	if item.availability == "ordinary":
		return true
	var grants := ResearchRules.resolve(research_ids, HangarResearch.catalog(content))
	return SlotCatalog.unlocked(item, grants)

static func available(loadout: Dictionary, research_ids: Array, content: DefDatabase = null) -> bool:
	return not loadout.is_empty() and loadout.mounts.values().all(func(key: Variant) -> bool:
		return equipment_available(item_for(str(key), content), research_ids, content))

static func available_for(chassis_id: String, research_ids: Array, content: DefDatabase = null) -> Array:
	return for_chassis(chassis_id, content).filter(func(loadout: Dictionary) -> bool: return available(loadout, research_ids, content))

static func purchase_for(chassis_id: String, research_ids: Array, content: DefDatabase = null) -> Dictionary:
	var preferred := default_for(chassis_id, content)
	if available(preferred, research_ids, content):
		return preferred
	var options := available_for(chassis_id, research_ids, content)
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return options[0] if not options.is_empty() else {}

static func find(chassis_id: String, loadout_id: String, content: DefDatabase = null) -> Dictionary:
	var canonical := Content.runtime_id("loadout", loadout_id, "", content)
	for loadout: Dictionary in for_chassis(chassis_id, content):
		if loadout.id == loadout_id or loadout.definition_id == canonical:
			return loadout
	return {}

static func default_for(chassis_id: String, content: DefDatabase = null) -> Dictionary:
	var chassis := SlotCatalog.find_chassis(chassis_id, content)
	return find(chassis.id, str(chassis.default_loadout), content) if not chassis.is_empty() else {}

static func slot_by_id(chassis: Dictionary, slot_id: String) -> Dictionary:
	for slot: Dictionary in chassis.get("slots", []):
		if slot.id == slot_id:
			return slot
	return {}

# Available parts a mount accepts, cheapest first.
static func part_options(slot: Dictionary, research_ids: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in SlotCatalog.equipment():
		if equipment_available(item, research_ids) and SlotCatalog.compatible(slot, item):
			result.append(item)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.price) < int(b.price) if int(a.price) != int(b.price) else str(a.name) < str(b.name))
	return result

static func part_fee(_item: Dictionary) -> int:
	return 0

static func ship_price(chassis_id: String, loadout: Dictionary, content: DefDatabase = null) -> int:
	var parts := 0
	for key: Variant in loadout.get("mounts", {}).values():
		parts += int(item_for(str(key), content).get("price", 0))
	return int(SlotCatalog.find_chassis(chassis_id, content).get("price", 0)) + ceili(parts * SHIP_PARTS_RATE)

static func append_ship(data: Dictionary, chassis_id: String, loadout: Dictionary, content: DefDatabase = null) -> void:
	var chassis := SlotCatalog.find_chassis(chassis_id, content)
	var formation: Vector2
	var occupied := {}
	for entry: Dictionary in data.ships:
		occupied[Vector2(entry.formation[0], entry.formation[1])] = true
	formation = Vector2(data.ships.size() % 3 - 1, floori(data.ships.size() / 3.0))
	for y in range(6):
		if not occupied.has(formation) and formation.y <= 5:
			break
		for x in range(-5, 6):
			var position := Vector2(x, y)
			if not occupied.has(position):
				formation = position
				break
	var entry := {"id": int(data.next_ship_id), "chassis": chassis.id, "flagship": false,
		"hull_hp": float(chassis.integrity), "mounts": {}, "formation": [formation.x, formation.y]}
	for slot_id: String in loadout.mounts:
		var parsed := parse_key(str(loadout.mounts[slot_id]))
		var uid := str(data.next_equipment_id)
		data.next_equipment_id += 1
		data.equipment[uid] = {"uid": uid, "equipment_id": parsed.id, "rank": int(parsed.rank)}
		entry.mounts[slot_id] = uid
		entry.hull_hp += float(item_for(str(loadout.mounts[slot_id]), content).stats.integrity)
	data.ships.append(entry)
	data.next_ship_id += 1

# Mount key ("id" or "id@rank") per slot for a ship's current fit.
static func current_keys(mounts: Dictionary, inventory: Dictionary = {}) -> Dictionary:
	var result := {}
	for slot_id: String in mounts:
		var value: Variant = mounts[slot_id]
		var instance: Dictionary = value if value is Dictionary else inventory.get(value, {})
		if not instance.is_empty():
			result[slot_id] = key_for({"id": instance.equipment_id, "rank": int(instance.rank)})
	return result

static func refit_fee(_current: Dictionary, _target: Dictionary) -> int:
	return 0

static func matching(chassis_id: String, mounts: Dictionary, inventory: Dictionary = {}) -> String:
	var keys := current_keys(mounts, inventory)
	for loadout: Dictionary in for_chassis(chassis_id):
		if SaveValidation.same(keys, loadout.mounts):
			return loadout.id
	return ""
