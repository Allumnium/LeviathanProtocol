class_name MiningRules
extends RefCounted

const TOOLS := [ShipPart.Type.MINING_LASER, ShipPart.Type.EXTRACTION_DRILL, ShipPart.Type.SEISMIC_CUTTER]
const WEAPONS := ["Mining Laser", "Extraction Drill"]

static func operational(member, types: Array) -> bool:
	if not member.is_alive() or member.owned_ship == null:
		return false
	for unit: Dictionary in member.owned_ship.units:
		if unit.hp > 0 and unit.part != null and types.has(unit.part.type):
			return true
	return false

static func snapshot(sim, source, weapon: String) -> Dictionary:
	var enabled := false
	var processor := false
	for member in sim.players:
		enabled = enabled or operational(member, TOOLS)
		processor = processor or operational(member, [ShipPart.Type.ORE_PROCESSOR])
	if not enabled or sim.mining_materials.is_empty():
		return {"rate": 0.0, "materials": []}
	var rate := 0.25
	if source != null and source.faction == 0:
		if weapon in ["Mining Laser", "Seismic Cut"]:
			rate = 0.75
		elif weapon == "Extraction Drill":
			rate = 1.0
	return {"rate": minf(1, rate + (0.15 if processor else 0.0)), "materials": sim.mining_materials.duplicate()}

static func known_eligible(sim, member, rock) -> bool:
	if not rock.has_tag("asteroid") or not sim.can_attack(member, rock):
		return false
	var knowledge: Dictionary = sim.abilities.known_resources(member.faction, rock.entity_id)
	var materials: Array = knowledge.get("materials", [])
	for category: int in sim.mining_materials:
		if category < materials.size() and materials[category] > 0:
			return true
	return false

static func target(sim, member):
	if not operational(member, TOOLS):
		return null
	var best = null
	var distance := INF
	for rock in sim.other_entities:
		if not known_eligible(sim, member, rock):
			continue
		var next: float = member.position.distance_squared_to(rock.position)
		if next < distance:
			distance = next
			best = rock
	return best

static func weapon_target(sim, member, weapon: ShipWeaponStats, origin: Vector2):
	var ordered = member.commanded_target
	if ordered != null and sim.can_attack(member, ordered):
		return ordered if in_range(origin, ordered, weapon.range_units) else null
	var current = target(sim, member)
	if current != null and in_range(origin, current, weapon.range_units):
		return current
	# Mining tools remain weak ordinary weapons when no legal rock is in reach.
	return sim._choose_weapon_target(member, origin, weapon.range_units)

static func in_range(origin: Vector2, target, range_units: float) -> bool:
	# World vectors use float32; tolerate only coordinate-rounding noise at the
	# exact surface boundary, rather than rejecting a mathematically legal shot.
	return origin.distance_to(target.position) <= range_units + (target.radius if target.has_tag("asteroid") else 0.0) + 0.0001

static func steering(sim, member, rock) -> Vector2:
	var range_units := 300.0
	var mount: Vector2 = member.position
	for weapon: ShipWeaponStats in member.stats.weapons:
		if weapon.weapon_name in WEAPONS:
			range_units = minf(range_units, weapon.range_units)
			mount = sim._get_weapon_origin(member, weapon)
	var surface: float = mount.distance_to(rock.position) - rock.radius
	var radial: Vector2 = rock.position.direction_to(member.position)
	if radial.is_zero_approx():
		radial = Vector2.UP
	var desired: Vector2 = rock.position + radial * (rock.radius + minf(range_units * 0.7, member.radius + 24))
	if surface > range_units * 0.85:
		return member.position.direction_to(desired)
	if member.position.distance_to(rock.position) < member.radius + rock.radius + 7:
		return radial
	return radial.orthogonal() * member.flyby_side * 0.15

static func avoidance(sim, member, desired: Vector2) -> Vector2:
	var result := desired
	for rock in sim.other_entities:
		if not rock.has_tag("asteroid") or not rock.is_alive() or not rock.targetable or not sim.team_can_see(member.faction, rock):
			continue
		var relative: Vector2 = rock.position - member.position
		var closing: Vector2 = member.velocity - rock.velocity
		var time := clampf(relative.dot(closing) / maxf(closing.length_squared(), 1), 0, 1.2)
		var approach: Vector2 = relative - closing * time
		var clearance: float = rock.radius + member.radius + 12
		if approach.length() > clearance or relative.length() > clearance + member.speed * 1.2:
			continue
		var normal := -approach.normalized()
		if normal.is_zero_approx():
			normal = relative.orthogonal().normalized() * member.flyby_side
		result += normal * member.speed * 2.0
	return result

static func pickup_destination(sim, member) -> Variant:
	if not operational(member, TOOLS):
		return null
	var point: Variant = null
	var nearest := INF
	for id: String in sim.asteroid_field.records:
		var r: Dictionary = sim.asteroid_field.records[id]
		if r.status != "terminal" or r.claimed:
			continue
		var position := Vector2(r.position[0], r.position[1])
		if not sim.point_visible(member.faction, position):
			continue
		var policy: Dictionary = sim.asteroid_field.roots[r.root].extraction
		if policy.get("rate", 0) <= 0 or not policy.get("materials", []).any(func(c: Variant) -> bool: return r.ore[int(c)] > 0):
			continue
		var distance: float = member.position.distance_squared_to(position)
		if distance < nearest:
			point = position
			nearest = distance
	return point
