extends RefCounted

# Named, fully fitted loadouts per ship class (data/ship_loadouts.json). The
# first loadout of a class is its default; ships are bought and refitted from
# these, and single mounts can be swapped for compatible available parts.
const PATH := "res://data/ship_loadouts.json"
const SHIP_PARTS_RATE := 0.5
static var _loadouts: Dictionary = {}
static var _obtainable: Dictionary = {}

static func parse_key(key: String) -> Dictionary:
	var parts := key.split("@")
	return {"id": parts[0], "rank": int(parts[1]) if parts.size() > 1 else 1}

static func key_for(item: Dictionary) -> String:
	return str(item.id) if int(item.rank) == 1 else "%s@%d" % [item.id, int(item.rank)]

static func item_for(key: String) -> Dictionary:
	if key.is_empty():
		return {}
	var parsed := parse_key(key)
	return SlotCatalog.find_equipment(parsed.id, parsed.rank)

# Catalog eligibility is independent of a run's earned research.
static func obtainable(item: Dictionary) -> bool:
	if item.is_empty():
		return false
	if _obtainable.is_empty():
		for node: Dictionary in HangarResearch.catalog():
			for id: String in node.grants.equipment_ids:
				if id not in HangarResearch.DEFERRED_PURCHASES:
					_obtainable[id] = true
	return _obtainable.has(item.id)

static func all() -> Dictionary:
	if not _loadouts.is_empty():
		return _loadouts
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(PATH)) != OK or not json.data is Dictionary \
			or json.data.get("version") != 1 or not json.data.get("loadouts") is Dictionary:
		push_error("Invalid ship loadout data.")
		return _loadouts
	for chassis_id: String in json.data.loadouts:
		var chassis := SlotCatalog.find_chassis(chassis_id)
		var valid: Array[Dictionary] = []
		for loadout: Variant in json.data.loadouts[chassis_id]:
			if chassis.is_empty() or not _valid(chassis, loadout):
				push_error("Invalid loadout for %s: %s" % [chassis_id, str(loadout)])
				continue
			valid.append(loadout)
		if not valid.is_empty():
			_loadouts[chassis_id] = valid
	return _loadouts

static func _valid(chassis: Dictionary, loadout: Variant) -> bool:
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
			var item := item_for(mounts[slot_id])
			if slot.is_empty() or not SlotCatalog.compatible(slot, item) or not obtainable(item):
				return false
	return true

static func for_chassis(chassis_id: String) -> Array:
	return all().get(chassis_id, [])

static func equipment_available(item: Dictionary, research_ids: Array) -> bool:
	if not obtainable(item):
		return false
	if HangarResearch.starting_equipment(item):
		return true
	var grants := ResearchRules.resolve(research_ids, HangarResearch.catalog())
	return int(grants.ranks.get(item.id, 0)) >= int(item.rank)

static func available(loadout: Dictionary, research_ids: Array) -> bool:
	return not loadout.is_empty() and loadout.mounts.values().all(func(key: Variant) -> bool:
		return equipment_available(item_for(str(key)), research_ids))

static func available_for(chassis_id: String, research_ids: Array) -> Array:
	return for_chassis(chassis_id).filter(func(loadout: Dictionary) -> bool: return available(loadout, research_ids))

static func purchase_for(chassis_id: String, research_ids: Array) -> Dictionary:
	var options := available_for(chassis_id, research_ids)
	return options[0] if not options.is_empty() else {}

static func find(chassis_id: String, loadout_id: String) -> Dictionary:
	for loadout: Dictionary in for_chassis(chassis_id):
		if loadout.id == loadout_id:
			return loadout
	return {}

static func default_for(chassis_id: String) -> Dictionary:
	var options := for_chassis(chassis_id)
	return options[0] if not options.is_empty() else {}

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

static func ship_price(chassis_id: String, loadout: Dictionary) -> int:
	var parts := 0
	for key: Variant in loadout.get("mounts", {}).values():
		parts += int(item_for(str(key)).get("price", 0))
	return int(SlotCatalog.find_chassis(chassis_id).get("price", 0)) + ceili(parts * SHIP_PARTS_RATE)

static func append_ship(data: Dictionary, chassis_id: String, loadout: Dictionary) -> void:
	var ship := HangarShip.new()
	ship.initialize_chassis(chassis_id, int(data.next_ship_id))
	var occupied := {}
	for entry: Dictionary in data.ships:
		occupied[Vector2(entry.formation[0], entry.formation[1])] = true
	ship.formation = Vector2(data.ships.size() % 3 - 1, floori(data.ships.size() / 3.0))
	for y in range(6):
		if not occupied.has(ship.formation) and ship.formation.y <= 5:
			break
		for x in range(-5, 6):
			var position := Vector2(x, y)
			if not occupied.has(position):
				ship.formation = position
				break
	var entry := ship.to_hangar_data()
	for slot_id: String in loadout.mounts:
		var parsed := parse_key(str(loadout.mounts[slot_id]))
		var uid := str(data.next_equipment_id)
		data.next_equipment_id += 1
		data.equipment[uid] = {"uid": uid, "equipment_id": parsed.id, "rank": int(parsed.rank)}
		entry.mounts[slot_id] = uid
		ship.mounts[slot_id] = data.equipment[uid]
	ship.rebuild_units()
	entry.hull_hp = ship.hull_max
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
