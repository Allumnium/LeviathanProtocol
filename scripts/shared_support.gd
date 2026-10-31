class_name SharedSupport
extends RefCounted

const REPAIR_RESERVE := 20.0
const REPAIR_RATE := 2.0

static func valid_pool(value: Variant) -> bool:
	return value is Dictionary and SaveValidation.integer(value.get("capacity")) and value.capacity >= 0 \
		and value.capacity <= 1000000 and int(value.capacity) % 20 == 0 \
		and (value.get("spent") is float or value.get("spent") is int) and is_finite(value.spent) and value.spent >= 0 and value.spent <= value.capacity

static func reserve_key(owned: FleetShip, index: int) -> String:
	return "%d/%d" % [owned.id, index]

static func valid_reserves(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in value:
		if not key is String:
			return false
		var pieces: PackedStringArray = key.split("/")
		if pieces.size() != 2 or not pieces[0].is_valid_int() or not pieces[1].is_valid_int() or int(pieces[0]) < 1 or int(pieces[1]) < 0:
			return false
		var remaining: Variant = value[key]
		if not (remaining is float or remaining is int) or not is_finite(remaining) or remaining < 0 or remaining > REPAIR_RESERVE:
			return false
	return true

static func initialize(sim) -> void:
	var stations := 0
	for member in sim.players:
		var owned: FleetShip = member.owned_ship
		if owned == null:
			continue
		for index in range(owned.units.size()):
			var part: ShipPart = owned.units[index].part
			if part != null and part.type == ShipPart.Type.REPAIR_STATION:
				if owned.is_alive() and owned.units[index].hp > 0:
					stations += 1
				var key := reserve_key(owned, index)
				if not sim.repair_reserves.has(key):
					sim.repair_reserves[key] = REPAIR_RESERVE
	# A replacement gets local coverage, but cannot refill the node's allowance.
	sim.repair_capacity = maxi(sim.repair_capacity, stations * int(REPAIR_RESERVE))

static func repair(sim, delta: float) -> void:
	for member in sim.players:
		var owned: FleetShip = member.owned_ship
		if owned == null or not member.is_alive() or not owned.is_alive():
			continue
		var rates := AdjacencyRules.rates(owned.units)
		var healed := 0.0
		for index in range(owned.units.size()):
			var source: ShipPart = owned.units[index].part
			if source == null or source.type != ShipPart.Type.REPAIR_STATION or owned.units[index].hp <= 0:
				continue
			var key := reserve_key(owned, index)
			var remaining: float = sim.repair_reserves.get(key, 0.0)
			var budget := minf(minf(remaining, maxf(0, sim.repair_capacity - sim.repair_spent)), REPAIR_RATE * float(rates.get(index, 1.0)) * delta)
			var targets: Array[Dictionary] = []
			for target in owned.units:
				if target.hp <= 0 or target.hp >= target.max_hp or target.part == null or not AdjacencyRules.touches(source, target.part):
					continue
				targets.append(target)
				if targets.size() == 2:
					break
			var recipients := targets.size()
			for target in targets:
				var amount := minf(budget / recipients, target.max_hp - target.hp)
				target.hp += amount
				budget -= amount
				remaining -= amount
				healed += amount
				sim.repair_spent = minf(sim.repair_capacity, sim.repair_spent + amount)
				recipients -= 1
			sim.repair_reserves[key] = maxf(0, remaining)
		if healed > 0:
			member.repaired_hp += healed
			sim._refresh_owned_stats(member)

static func intercept(sim, member, weapon: ShipWeaponStats, origin: Vector2) -> bool:
	if not member.is_alive():
		return false
	if not member.has_tag("interceptor"):
		if member.owned_ship == null or weapon.component_index < 0 or weapon.component_index >= member.owned_ship.units.size():
			return false
		var unit: Dictionary = member.owned_ship.units[weapon.component_index]
		if unit.hp <= 0 or unit.part == null or unit.part.type != ShipPart.Type.POINT_DEFENSE_TURRET:
			return false
	var chosen := -1
	var nearest := INF
	for index in range(sim.projectiles.size()):
		var shot = sim.projectiles[index]
		if not shot.interceptable or shot.source == null or shot.source.faction == member.faction or not shot.target.is_alive() or shot.target.faction != member.faction:
			continue
		var distance := origin.distance_to(shot.position)
		if distance <= weapon.range_units and distance < nearest:
			chosen = index
			nearest = distance
	if chosen < 0:
		return false
	var shot = sim.projectiles[chosen]
	sim._add_pending_damage(shot.target, -shot.damage)
	sim._record_event("interception", {"source": member.entity_id, "weapon": weapon.weapon_name, "target": shot.target.entity_id})
	var explosion := BattleSimulation.Explosion.new()
	explosion.position = shot.position
	sim.explosions.append(explosion)
	sim.projectiles.remove_at(chosen)
	sim.weapon_fired.emit()
	return true

static func weapon_target(sim, member, weapon: ShipWeaponStats, origin: Vector2):
	if weapon.weapon_name in MiningRules.WEAPONS:
		return MiningRules.weapon_target(sim, member, weapon, origin)
	if member.owned_ship != null and member.owned_ship.units[weapon.component_index].part.type == ShipPart.Type.POINT_DEFENSE_TURRET:
		var chosen = null
		var nearest := INF
		for candidate in sim._members:
			if not candidate.has_tag("craft") or not sim.can_attack(member, candidate) or sim._pending_projectile_damage(candidate) >= candidate.integrity + candidate.shields:
				continue
			var distance := origin.distance_to(candidate.position)
			if distance <= weapon.range_units and distance < nearest:
				chosen = candidate
				nearest = distance
		if chosen != null:
			return chosen
	return sim._choose_weapon_target(member, origin, weapon.range_units)
