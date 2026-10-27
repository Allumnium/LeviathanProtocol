class_name FleetRules
extends RefCounted

const ROLES := ["regular", "science", "civic"]
const ACCOMMODATION := [ShipPart.Type.PASSENGER_CABIN, ShipPart.Type.LUXURY_SUITES]
const CRAFT_BAYS := [ShipPart.Type.FLIGHT_DECK, ShipPart.Type.TORPEDO_BOMBER_BAY, ShipPart.Type.HIVE_CARRIER_CORE]
const ACT_CAPACITIES := [30, 42, 54]


static func capacity_for_act(act: int) -> int:
	return ACT_CAPACITIES[clampi(act, 1, 3) - 1]


static func lab_level(part: ShipPart) -> int:
	if part.type != ShipPart.Type.RESEARCH_LAB:
		return 0
	# Capacity uses the highest physical lab rank, once per hull.
	return clampi(part.rank, 1, 3)


static func design_capacity(design: Ship) -> int:
	if design == null or design.tiles.is_empty():
		return 0
	var labs := 0
	for part in design.parts:
		labs = maxi(labs, lab_level(part))
	return 2 + ceili(design.tiles.size() / 12.0) + labs


static func ship_capacity(owned: FleetShip) -> int:
	if not owned.is_alive():
		return 0
	var occupied: Dictionary = {}
	var labs := 0
	for unit in owned.units:
		if unit.hp <= 0:
			continue
		for cell in unit.cells:
			occupied[cell] = true
		var part: ShipPart = unit.part
		if part != null:
			labs = maxi(labs, lab_level(part))
	return 2 + ceili(occupied.size() / 12.0) + labs


static func design_error(design: Ship, role: String) -> String:
	if role not in ROLES:
		return "Unknown fleet slot role."
	var cores := 0
	var labs := 0
	var civic_sources := 0
	var offense := 0
	for category in design.tiles.values():
		if category == ShipPart.Category.OFFENSE:
			offense += 1
	for part in design.parts:
		cores += 1 if part.type == ShipPart.Type.COMMAND_CENTER else 0
		labs += 1 if part.type == ShipPart.Type.RESEARCH_LAB else 0
		civic_sources += 1 if part.type == ShipPart.Type.CARGO_HOLD or part.type in ACCOMMODATION else 0
		if role != "regular":
			var definition := GameDefinitions.equipment(part.type)
			if definition.is_empty():
				return "Unknown equipment cannot use a dedicated slot."
			if definition.regular_slots_only:
				return "Mining equipment requires a regular slot."
			if definition.offensive_capstone or part.type in CRAFT_BAYS:
				return "Dedicated slots forbid strike-craft bays and offensive capstones."
	if cores != 1:
		return "Every hull requires exactly one Command Center."
	if role == "regular":
		return ""
	if offense > 6:
		return "Dedicated ships allow at most six Offense material tiles."
	if role == "science":
		if labs != 1:
			return "Science requires exactly one Research Lab."
		if civic_sources > 0:
			return "Science forbids passenger accommodation and Cargo Holds."
	else:
		if civic_sources < 1:
			return "Civic requires a Cargo Hold or passenger accommodation."
		if labs > 0:
			return "Civic forbids Research Labs."
	return ""


static func operational_error(owned: FleetShip) -> String:
	var problem := design_error(owned.design, owned.slot_role)
	if not problem.is_empty() or owned.slot_role == "regular":
		return problem
	for unit in owned.units:
		var part: ShipPart = unit.part
		if part == null or unit.hp <= 0:
			continue
		if owned.slot_role == "science" and part.type == ShipPart.Type.RESEARCH_LAB:
			return ""
		if owned.slot_role == "civic" and (part.type == ShipPart.Type.CARGO_HOLD or part.type in ACCOMMODATION):
			return ""
	return "%s requires its support equipment to be operational." % owned.slot_role.capitalize()


static func fingerprint(design: Ship) -> String:
	# Names, insertion order and translation never manufacture another family.
	var cells := design.get_tile_cells()
	if cells.is_empty():
		return ""
	var origin := cells[0]
	for cell in cells:
		origin.x = mini(origin.x, cell.x)
		origin.y = mini(origin.y, cell.y)
	var tiles: Array = []
	for cell in cells:
		tiles.append([cell.x - origin.x, cell.y - origin.y, design.tiles[cell]])
	tiles.sort_custom(func(a: Array, b: Array) -> bool: return JSON.stringify(a) < JSON.stringify(b))
	var parts: Array[String] = []
	for part in design.parts:
		var occupied: Array = []
		for cell in part.get_occupied_cells():
			occupied.append([cell.x - origin.x, cell.y - origin.y])
		occupied.sort_custom(func(a: Array, b: Array) -> bool: return JSON.stringify(a) < JSON.stringify(b))
		parts.append(JSON.stringify([part.type, occupied]))
	parts.sort()
	return JSON.stringify([tiles, parts]).sha256_text()


static func empty_roster() -> Dictionary:
	return {"version": 1, "families": {}, "active": ["", "", ""], "next_family": 1,
		"support_names": {"science": "", "civic": ""}, "support_ids": {"science": 0, "civic": 0}}


static func migrate(fleet: Array[FleetShip]) -> Dictionary:
	var roster := empty_roster()
	var known: Dictionary = {}
	for owned in fleet:
		var key := fingerprint(owned.design)
		if not known.has(key):
			var id := "family/%d" % int(roster.next_family)
			roster.next_family = int(roster.next_family) + 1
			var pieces := owned.display_name.rsplit(" ", true, 1)
			var title: String = pieces[0] if pieces.size() == 2 and pieces[1].is_valid_int() else owned.display_name
			roster.families[id] = {"name": title, "blueprints": [key], "design": owned.design.to_design_data()}
			known[key] = id
			var index: int = roster.active.find("")
			if index >= 0:
				roster.active[index] = id
		owned.family_id = known[key]
		owned.slot_role = "regular"
		owned.in_reserve = false
	return roster


static func valid(roster: Variant, fleet: Array[FleetShip]) -> bool:
	if not roster is Dictionary or roster.get("version") != 1 or not roster.get("families") is Dictionary:
		return false
	if not roster.get("active") is Array or roster.active.size() != 3 or not RunProgressData._integer(roster.get("next_family")) or roster.next_family < 1:
		return false
	var keys: Dictionary = {}
	for id in roster.families:
		var family: Variant = roster.families[id]
		if not id is String or not id.begins_with("family/") or not family is Dictionary:
			return false
		var serial: String = id.trim_prefix("family/")
		if not serial.is_valid_int() or int(serial) < 1 or str(int(serial)) != serial or int(serial) >= int(roster.next_family):
			return false
		if not family.get("name") is String or not family.get("blueprints") is Array or family.blueprints.is_empty():
			return false
		for key in family.blueprints:
			if not key is String or key.length() != 64 or keys.has(key):
				return false
			keys[key] = id
	var active: Array[String] = []
	for id in roster.active:
		if not id is String or (not id.is_empty() and (not roster.families.has(id) or id in active)):
			return false
		if not id.is_empty():
			active.append(id)
	if not roster.get("support_names") is Dictionary or not roster.get("support_ids") is Dictionary:
		return false
	for role in ["science", "civic"]:
		if not roster.support_names.get(role) is String or not RunProgressData._integer(roster.support_ids.get(role)) or roster.support_ids[role] < 0:
			return false
		var found := int(roster.support_ids[role]) == 0
		for owned in fleet:
			if owned.id == int(roster.support_ids[role]):
				if owned.slot_role != role or owned.in_reserve:
					return false
				found = true
		if not found:
			return false
	for owned in fleet:
		if owned.slot_role not in ROLES:
			return false
		if owned.slot_role == "regular":
			if not roster.families.has(owned.family_id) or not roster.families[owned.family_id].blueprints.has(fingerprint(owned.design)):
				return false
		elif not design_error(owned.design, owned.slot_role).is_empty():
			return false
	return true
