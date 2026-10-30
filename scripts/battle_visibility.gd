class_name BattleVisibility
extends RefCounted

const SIGHT := 260.0
const RADAR := 480.0
const STALE_SECONDS := 5.0
const MEMORY_CELL := 64.0

var sources: Dictionary = {}
var visible_ids: Dictionary = {}
var last_seen: Dictionary = {}
var explored_cells: Dictionary = {}
var _contacts: Dictionary = {}
var _exploration_visits: Dictionary = {}

func reset() -> void:
	sources.clear()
	visible_ids.clear()
	last_seen.clear()
	explored_cells.clear()
	_contacts.clear()
	_exploration_visits.clear()

func refresh(sim) -> void:
	for faction in [0, 1]:
		sources[faction] = []
		visible_ids[faction] = {}
		_contacts[faction] = []
		if not last_seen.has(faction):
			last_seen[faction] = {}
			explored_cells[faction] = {}
			_exploration_visits[faction] = {}
	for member in sim._members:
		if member.faction not in [0, 1] or not member.is_alive() or not member.has_tag("combatant"):
			continue
		if member.owned_ship != null:
			if member.owned_ship.core_index < 0 or member.owned_ship.units[member.owned_ship.core_index].hp <= 0:
				continue
		elif member.has_tag("craft") or member.has_tag("organ") or member.has_tag("summon") or member.has_tag("decoy"):
			continue
		var origin := source_position(member)
		sources[member.faction].append({"position": origin, "sight": SIGHT, "radar": RADAR})
		_mark_explored(member.faction, origin)
	for effect: Dictionary in sim.abilities.effects:
		var source = sim.entities.get(effect.source)
		if source == null or not sim.abilities.sources(sim, int(effect.faction), effect.id).has(source):
			continue
		sources[effect.faction].append({"position": effect.position, "sight": effect.radius, "radar": effect.radius})
		_mark_explored(int(effect.faction), effect.position, float(effect.radius))
	for faction in [0, 1]:
		for member in sim._members:
			if member.faction == faction:
				visible_ids[faction][member.entity_id] = true
				continue
			if point_visible(faction, member.position):
				visible_ids[faction][member.entity_id] = true
				if member.is_alive():
					last_seen[faction][member.entity_id] = {"position": member.position, "time": sim.elapsed}
				else:
					last_seen[faction].erase(member.entity_id)
			elif member.is_alive() and _in_radar(faction, member.position):
				# Anonymous positions are the entire radar payload. No actor ID,
				# health, faction, loadout or authoritative reference leaves here.
				_contacts[faction].append({"kind": "radar", "position": member.position})
		for id: String in last_seen[faction].keys():
			var known: Dictionary = last_seen[faction][id]
			var age: float = sim.elapsed - float(known.time)
			if age >= STALE_SECONDS:
				last_seen[faction].erase(id)
			elif not visible_ids[faction].has(id):
				_contacts[faction].append({"kind": "stale", "position": known.position, "age": age})

func can_see(faction: int, id: String) -> bool:
	return visible_ids.get(faction, {}).has(id)

static func source_position(member) -> Vector2:
	if member.owned_ship == null or member.owned_ship.core_index < 0:
		return member.position
	var local := Vector2.ZERO
	var cells: Array = member.owned_ship.units[member.owned_ship.core_index].cells
	for cell: Vector2i in cells:
		local += member.owned_ship.local_cell_position(cell)
	return member.position + (local / maxf(1, cells.size())).rotated(member.heading)

func point_visible(faction: int, point: Vector2) -> bool:
	for source: Dictionary in sources.get(faction, []):
		if point.distance_squared_to(source.position) <= float(source.sight) * float(source.sight):
			return true
	return false

func _in_radar(faction: int, point: Vector2) -> bool:
	for source: Dictionary in sources.get(faction, []):
		if point.distance_squared_to(source.position) <= float(source.radar) * float(source.radar):
			return true
	return false

func contacts(faction: int) -> Array:
	return _contacts.get(faction, []).duplicate(true)

func _mark_explored(faction: int, position: Vector2, sight := SIGHT) -> void:
	var cell := Vector2i((position / MEMORY_CELL).floor())
	var key := "%d,%d/%s" % [cell.x, cell.y, sight]
	if _exploration_visits[faction].has(key):
		return
	_exploration_visits[faction][key] = true
	var radius := ceili(sight / MEMORY_CELL)
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var next := cell + Vector2i(x, y)
			if (Vector2(next) + Vector2.ONE * 0.5).distance_to(position / MEMORY_CELL) <= sight / MEMORY_CELL:
				explored_cells[faction][next] = true

func diagnostic_snapshot() -> Dictionary:
	var result := {}
	for faction in [0, 1]:
		var memory: Array[String] = []
		for cell: Vector2i in explored_cells.get(faction, {}):
			memory.append("%d,%d" % [cell.x, cell.y])
		memory.sort()
		var seen := {}
		for id: String in last_seen.get(faction, {}):
			var known: Dictionary = last_seen[faction][id]
			seen[id] = {"position": [known.position.x, known.position.y], "time": known.time}
		result[str(faction)] = {"explored": memory, "last_seen": seen}
	return result
