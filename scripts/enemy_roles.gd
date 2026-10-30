class_name EnemyRoles
extends RefCounted

const ENTITY_LIMIT := 64
const PROTECTION_RADIUS := 140.0
const PROTECTION := 0.2
const REPAIR_RADIUS := 150.0
const REPAIR_RATE := 1.0
const DRONE_INTERVAL := 6.0
var enabled := false
var sources: Dictionary = {}
var repair_links: Array[Dictionary] = []

func configure(sim, value: bool) -> void:
	enabled = value
	sources.clear()
	repair_links.clear()
	if not enabled:
		return
	for member in sim.aliens:
		register_source(member)

func register_source(member) -> void:
	if not enabled or sources.has(member.entity_id):
		return
	if member.alien == null or member.has_tag("summon") or member.has_tag("organ"):
		return
	var role: String = member.alien.role_id
	var rank: int = member.alien.tier
	if role == "support":
		sources[member.entity_id] = {"role": role, "reserve": 10.0 * AlienShip.TIER_HULL[rank]}
	elif role == "chrysalis":
		sources[member.entity_id] = {"role": role, "remaining": 2 + rank, "spawned": 0, "cooldown": 4.0}


func role(member) -> String:
	if not enabled or member.alien == null or member.has_tag("craft") or member.has_tag("organ") or member.has_tag("summon"):
		return ""
	return member.alien.role_id

func advance(sim, delta: float) -> void:
	repair_links.clear()
	if not enabled:
		return
	var repaired: Dictionary = {}
	for id: String in sources:
		var state: Dictionary = sources[id]
		var member = sim.entities.get(id)
		if member == null or not member.is_alive():
			continue
		if state.role == "support":
			_repair(sim, member, state, delta, repaired)
		elif state.role == "chrysalis":
			state.cooldown = maxf(0, state.cooldown - delta)
			if state.remaining > 0 and state.cooldown <= 0:
				_launch(sim, member, state)

func _repair(sim, source, state: Dictionary, delta: float, repaired: Dictionary) -> void:
	if state.reserve <= 0:
		return
	var target = null
	var lowest := 1.0
	for ally in sim._members:
		if ally == source or ally.faction != source.faction or not ally.is_alive() or not ally.has_tag("combatant") \
			or ally.has_tag("craft") or repaired.has(ally.entity_id) or source.position.distance_to(ally.position) > REPAIR_RADIUS:
			continue
		var ratio: float = ally.integrity / ally.stats.integrity
		if ratio < lowest:
			target = ally
			lowest = ratio
	if target == null:
		return
	var amount := minf(minf(REPAIR_RATE * delta, state.reserve), target.stats.integrity - target.integrity)
	target.integrity += amount
	state.reserve -= amount
	repaired[target.entity_id] = true
	repair_links.append({"source": source.entity_id, "target": target.entity_id})

func protection(sim, target) -> float:
	if not enabled or target.faction != 1 or not target.is_alive():
		return 1.0
	for member in sim.aliens:
		if member != target and member.is_alive() and role(member) == "sentinel" \
			and member.position.distance_squared_to(target.position) <= PROTECTION_RADIUS * PROTECTION_RADIUS:
			return 1.0 - PROTECTION
	return 1.0

func choose_target(sim, source):
	if role(source) not in ["scout", "fighter"]:
		return null
	var best = null
	var score := INF
	for candidate in sim.players:
		if not sim.can_attack(source, candidate):
			continue
		var next: float = source.position.distance_to(candidate.position)
		if role(source) == "scout":
			var support: bool = candidate.stats.weapons.is_empty()
			if candidate.owned_ship != null:
				for unit: Dictionary in candidate.owned_ship.units:
					if unit.hp > 0 and unit.part != null and unit.part.type in [ShipPart.Type.RESEARCH_LAB, ShipPart.Type.PASSENGER_CABIN,
						ShipPart.Type.CARGO_HOLD, ShipPart.Type.REPAIR_STATION]:
						support = true
			if support:
				next -= 180
			# Nearby armed escorts make a support hull less exposed. They do not
			# make it untargetable or reveal an unseen ship's position/loadout.
			for escort in sim.players:
				if escort == candidate or not escort.is_alive() or not sim.can_attack(source, escort) or escort.stats.weapons.is_empty():
					continue
				if escort.position.distance_to(candidate.position) < 90:
					next += 220
		if next < score:
			best = candidate
			score = next
	return best

func steering(sim, member, fallback: Vector2) -> Vector2:
	var kind := role(member)
	if kind == "fighter" and member.target != null:
		var relative: Vector2 = member.target.position - member.position
		if relative.length() > member.shortest_range() * 0.65:
			return relative.normalized()
	elif kind in ["support", "sentinel", "chrysalis"]:
		var anchor = null
		var nearest := INF
		for ally in sim.aliens:
			if ally == member or not ally.is_alive() or role(ally) not in ["fighter", "scout"]:
				continue
			var distance: float = member.position.distance_squared_to(ally.position)
			if distance < nearest:
				anchor = ally
				nearest = distance
		if anchor != null:
			var offset := 65.0 if kind == "sentinel" else 100.0
			var position: Vector2 = anchor.position - Vector2.from_angle(anchor.heading) * offset
			return member.position.direction_to(position)
	return fallback

func _launch(sim, parent, state: Dictionary) -> void:
	var living := 0
	for entity in sim._members:
		if entity.is_alive() and entity.has_tag("combatant"):
			living += 1
	if living >= ENTITY_LIMIT or not parent.is_alive():
		return
	var id: String = parent.entity_id + "/drone/%d" % int(state.spawned)
	if sim.entities.has(id):
		return
	var stats := ShipStats.new()
	stats.integrity = 1.5 * AlienShip.TIER_HULL[parent.alien.tier]
	stats.weight = 3
	stats.thrust = 12
	stats.collision_radius = 6
	var weapon := ShipWeaponStats.new("Drone Pulse", 1.2, 0.2 * AlienShip.TIER_DAMAGE[parent.alien.tier], 1, 140)
	stats.weapons.append(weapon)
	var definition := AlienShip.new("Chrysalis Drone", AlienShip.SCOUT_TEXTURE, stats)
	definition.stats.collision_radius = 6
	definition.entity_id = id
	definition.entity_kind = "craft"
	definition.role_id = "drone"
	var actor = sim._create_combatant(definition.stats)
	actor.entity_id = id
	actor.alien = definition
	actor.faction = parent.faction
	actor.tags.assign({"combatant": true, "craft": true, "summon": true})
	actor.position = parent.position + Vector2.from_angle(parent.heading + PI * 0.5) * (parent.radius + 8)
	actor.heading = parent.heading
	if not sim.register_entity(actor):
		return
	state.remaining -= 1
	state.spawned += 1
	state.cooldown = DRONE_INTERVAL
	sim._record_event("launch", {"source": parent.entity_id, "craft": id, "remaining": state.remaining})

func snapshot() -> Dictionary:
	return sources.duplicate(true)
