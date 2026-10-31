class_name FleetRules
extends RefCounted

# Old role strings remain readable for migration; new ships are all regular.
const ROLES := ["regular", "science", "civic"]
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


static func design_error(design: Ship, role: String = "regular") -> String:
	# Legacy roles are accepted for compatibility; equipment is unrestricted.
	if role not in ROLES:
		return "Unknown fleet slot role."
	var cores := 0
	for part in design.parts:
		cores += 1 if part.type == ShipPart.Type.COMMAND_CENTER else 0
	return "" if cores == 1 else "Every hull requires exactly one Command Center."

static func operational_error(owned: FleetShip) -> String:
	# Fitting restrictions concern the physical blueprint. Battle damage disables
	# the component's benefit, but must not strand a surviving legal hull.
	return design_error(owned.design, owned.slot_role)


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
	return {"version": 2, "families": {}, "active": ["", "", ""], "next_family": 1,
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


static func integrate_support(roster: Dictionary, fleet: Array[FleetShip]) -> Dictionary:
	var result := roster.duplicate(true)
	for owned in fleet:
		if owned.slot_role == "regular":
			continue
		var key := fingerprint(owned.design)
		var family_id := ""
		for id: String in result.families:
			if result.families[id].blueprints.has(key):
				family_id = id
				break
		if family_id.is_empty():
			family_id = "family/%d" % int(result.next_family)
			result.next_family += 1
			var title := str(result.support_names.get(owned.slot_role, ""))
			result.families[family_id] = {"name": owned.display_name if title.is_empty() else title, "blueprints": [key], "design": owned.design.to_design_data()}
		if not owned.in_reserve and not result.active.has(family_id) and result.active.has(""):
			result.active[result.active.find("")] = family_id
		owned.family_id = family_id
		owned.slot_role = "regular"
	result.version = 2
	result.support_ids = {"science": 0, "civic": 0}
	result.support_names = {"science": "", "civic": ""}
	return result


static func valid(roster: Variant, fleet: Array[FleetShip]) -> bool:
	if not roster is Dictionary or (roster.get("version") != 1 and roster.get("version") != 2) or not roster.get("families") is Dictionary:
		return false
	if not roster.get("active") is Array or roster.active.size() != 3 or not SaveValidation.integer(roster.get("next_family")) or roster.next_family < 1:
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
		var selected := Ship.new()
		if not selected.load_design_data(family.get("design")) or not family.blueprints.has(fingerprint(selected)):
			return false
	var active: Array[String] = []
	for id in roster.active:
		if not id is String or (not id.is_empty() and (not roster.families.has(id) or id in active)):
			return false
		if not id.is_empty():
			active.append(id)
	if not roster.get("support_names") is Dictionary or not roster.get("support_ids") is Dictionary:
		return false
	for role in ["science", "civic"]:
		if not roster.support_names.get(role) is String or not SaveValidation.integer(roster.support_ids.get(role)) or roster.support_ids[role] < 0:
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
		if int(roster.version) >= 2 and owned.slot_role != "regular":
			return false
		if owned.slot_role == "regular":
			if not roster.families.has(owned.family_id) or not roster.families[owned.family_id].blueprints.has(fingerprint(owned.design)):
				return false
		elif not design_error(owned.design, owned.slot_role).is_empty():
			return false
	return true
