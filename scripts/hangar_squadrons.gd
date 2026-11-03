class_name HangarSquadrons
extends RefCounted

const Loadouts = preload("res://scripts/ship_loadouts.gd")
const STANCES := ["seek", "defend", "evade"]
const LABELS := {"seek": "Seek & Destroy", "defend": "Defend Flagship", "evade": "Evade"}

static func for_ship(groups: Array, ship_id: int) -> Dictionary:
	for group: Dictionary in groups:
		if group.members.any(func(id: Variant) -> bool: return int(id) == ship_id):
			return group
	return {}

static func find(groups: Array, id: int) -> Dictionary:
	for group: Dictionary in groups:
		if group.id == id:
			return group
	return {}

static func add_ship(data: Dictionary, entry: Dictionary, group_id := 0) -> void:
	if not data.has("squadrons"):
		data.squadrons = []
	var group := find(data.squadrons, group_id)
	if group.is_empty() and group_id == 0:
		for candidate: Dictionary in data.squadrons:
			if candidate.chassis == entry.chassis:
				group = candidate
				break
	if group.is_empty():
		var id := 1
		for candidate: Dictionary in data.squadrons:
			id = maxi(id, int(candidate.id) + 1)
		group = {"id": id, "name": SlotCatalog.find_chassis(entry.chassis).name,
			"chassis": entry.chassis, "stance": "seek",
			"formation": entry.formation.duplicate(),
			"loadout": Loadouts.default_for(entry.chassis).id, "members": [], "overrides": []}
		data.squadrons.append(group)
	group.members.append(int(entry.id))
	update_override(data, int(entry.id))
	sync(data)

static func initial(data: Dictionary) -> Array:
	var staged := data.duplicate(true)
	staged.squadrons = []
	for entry: Dictionary in staged.ships:
		add_ship(staged, entry)
	return staged.squadrons

static func update_override(data: Dictionary, ship_id: int) -> void:
	var group := for_ship(data.get("squadrons", []), ship_id)
	if group.is_empty():
		return
	group.overrides = group.overrides.filter(func(id: Variant) -> bool: return int(id) != ship_id)
	for entry: Dictionary in data.ships:
		if int(entry.id) == ship_id and Loadouts.matching(entry.chassis, entry.mounts, data.equipment) != group.loadout:
			group.overrides.append(ship_id)

static func sync(data: Dictionary) -> void:
	var entries := {}
	for entry: Dictionary in data.ships:
		entries[int(entry.id)] = entry
	for group: Dictionary in data.get("squadrons", []):
		group.members = group.members.map(func(id: Variant) -> int: return int(id)).filter(
			func(id: int) -> bool: return entries.has(id))
		group.overrides = group.overrides.map(func(id: Variant) -> int: return int(id)).filter(
			func(id: int) -> bool: return id in group.members)
		if group.members.is_empty():
			continue
		var center := Vector2.ZERO
		for id: Variant in group.members:
			center += Vector2(entries[int(id)].formation[0], entries[int(id)].formation[1])
		center /= group.members.size()
		group.formation = [center.x, center.y]
	if data.has("squadrons"):
		data.squadrons = data.squadrons.filter(func(group: Dictionary) -> bool: return not group.members.is_empty())

static func valid(data: Dictionary) -> bool:
	if not data.has("squadrons"):
		return true
	if not data.squadrons is Array:
		return false
	var entries := {}
	for entry: Dictionary in data.ships:
		entries[int(entry.id)] = entry
	var seen := {}
	var ids := {}
	for group: Variant in data.squadrons:
		if not group is Dictionary or not SaveValidation.integer(group.get("id")) or group.id <= 0 \
				or ids.has(int(group.id)) or not group.get("name") is String or group.name.strip_edges().is_empty() \
				or group.name.length() > 40 or not group.get("chassis") is String \
				or group.get("stance") not in STANCES or not group.get("loadout") is String \
				or Loadouts.find(group.chassis, group.loadout).is_empty() \
				or not SaveValidation.vector(group.get("formation")) \
				or not group.get("members") is Array or group.members.is_empty() \
				or not group.get("overrides") is Array:
			return false
		ids[int(group.id)] = true
		var members := {}
		var overrides := {}
		for id: Variant in group.overrides:
			if not SaveValidation.integer(id) or overrides.has(int(id)):
				return false
			overrides[int(id)] = true
		var center := Vector2.ZERO
		for id: Variant in group.members:
			if not SaveValidation.integer(id) or not entries.has(int(id)) or seen.has(int(id)) \
					or entries[int(id)].chassis != group.chassis:
				return false
			seen[int(id)] = true
			members[int(id)] = true
			var entry: Dictionary = entries[int(id)]
			center += Vector2(entry.formation[0], entry.formation[1])
			if (Loadouts.matching(entry.chassis, entry.mounts, data.equipment) != group.loadout) != overrides.has(int(id)):
				return false
		center /= group.members.size()
		if not center.is_equal_approx(Vector2(group.formation[0], group.formation[1])):
			return false
		for id: int in overrides:
			if not members.has(id):
				return false
	return seen.size() == entries.size()
