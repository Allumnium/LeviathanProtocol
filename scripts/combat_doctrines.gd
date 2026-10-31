class_name CombatDoctrines
extends RefCounted

# Numeric tuning is deliberately local; later campaign pacing remains step 61.
var pool: Dictionary = {}
var charges: Dictionary = {}
var drones: Array[Dictionary] = []
var launch_timers: Dictionary = {}
var serial := 0
var carriers := HangarCarriers.new()
var synchronization: Dictionary = {}
var mark_timers: Dictionary = {}
var marks: Dictionary = {}

static func valid_pool(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true # Historical deployments have no doctrine reserve.
	if value.size() != (6 if value.has("carriers") else 5) or value.get("version") != 1 or not value.get("rebuilt") is Array:
		return false
	if value.has("carriers") and not HangarCarriers.valid(value.carriers):
		return false
	for key in ["repair_capacity", "rebuild_capacity"]:
		if not SaveValidation.integer(value.get(key)) or value[key] < 0 or value[key] > 100000:
			return false
	if int(value.repair_capacity) % 20 != 0 or not SaveValidation.bounded_number(value.get("repair_spent")) \
		or value.repair_spent < 0 or value.repair_spent > value.repair_capacity or value.rebuilt.size() > value.rebuild_capacity:
		return false
	var seen := {}
	for id in value.rebuilt:
		if not id is String or not id.is_valid_int() or int(id) < 1 or str(int(id)) != id or seen.has(id):
			return false
		seen[id] = true
	return true

func configure(sim, value: Variant) -> bool:
	if not valid_pool(value):
		return false
	pool = value.duplicate(true)
	charges.clear()
	drones.clear()
	launch_timers.clear()
	serial = 0
	synchronization.clear()
	mark_timers.clear()
	marks.clear()
	if pool.is_empty():
		pool = {"version": 1, "repair_capacity": 0, "repair_spent": 0.0, "rebuild_capacity": 0, "rebuilt": []}
		for member in sim.players:
			if member.owned_ship == null or not member.is_alive():
				continue
			pool.repair_capacity += operational(member, ShipPart.Type.REPAIR_DRONE_BAY).size() * 20
			if not operational(member, ShipPart.Type.NANOFORGE).is_empty():
				pool.rebuild_capacity += 1
	if not pool.has("carriers"):
		pool["carriers"] = {}
	return carriers.configure(sim, pool.carriers)

static func operational(member, type: int) -> Array[int]:
	var result: Array[int] = []
	if not member.is_alive() or member.owned_ship == null:
		return result
	for index in range(member.owned_ship.units.size()):
		var unit: Dictionary = member.owned_ship.units[index]
		if unit.hp > 0 and unit.part != null and unit.part.type == type:
			result.append(index)
	return result

static func adjacency_targets(units: Array[Dictionary], type: int, target_types: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for source in units:
		if source.hp <= 0 or source.part == null or source.part.type != type:
			continue
		var count := 0
		for index in range(units.size()):
			var unit: Dictionary = units[index]
			if unit.hp > 0 and unit.part != null and unit.part.type in target_types and AdjacencyRules.touches(source.part, unit.part):
				if not result.has(index):
					result.append(index)
				count += 1
				if count == 2:
					break
	return result

static func protected_unit(owned: FleetShip, index: int) -> bool:
	var types: Array[int] = []
	for unit in owned.units:
		if unit.part != null and not types.has(unit.part.type):
			types.append(unit.part.type)
	return adjacency_targets(owned.units, ShipPart.Type.REACTIVE_BULKHEAD, types).has(index)

func begin_charge(sim, source, weapon: ShipWeaponStats, target, origin: Vector2) -> void:
	var key := "%s/%d" % [source.entity_id, weapon.component_index]
	charges[key] = {"source": source.entity_id, "index": weapon.component_index, "target": target.entity_id,
		"remaining": weapon.charge_seconds, "weapon": weapon.copy(), "origin": origin, "aim": target.position}
	sim._record_event("beam_charge", {"source": source.entity_id, "target": target.entity_id, "seconds": weapon.charge_seconds})

func interrupt(sim, target) -> bool:
	# The Warden accepts at most one interruption per charge, as with focused fire.
	var interrupted := false
	for key in charges.keys():
		if charges[key].source == target.entity_id:
			charges.erase(key)
			interrupted = true
	var warden = sim.encounter.warden
	if not warden.rules.is_empty() and target.entity_id == warden.rules.body_id and warden.charging:
		warden.charging = false
		warden.finished_cycle = warden.cycle
		sim._record_event("warden_interrupt", {"cycle": warden.cycle})
		interrupted = true
	return interrupted

func advance(sim, delta: float) -> void:
	carriers.advance(sim, delta)
	for id: String in marks.keys():
		marks[id].remaining -= delta
		if marks[id].remaining <= 0:
			marks.erase(id)
	for key in charges.keys():
		var charge: Dictionary = charges[key]
		var source = sim.entities.get(charge.source)
		var target = sim.entities.get(charge.target)
		if source == null or not source.is_alive() or source.owned_ship == null \
			or source.owned_ship.units[charge.index].hp <= 0 or target == null or not sim.can_attack(source, target):
			charges.erase(key)
			continue
		charge.remaining -= delta
		if charge.remaining > 0:
			continue
		charges.erase(key)
		if target.position.distance_to(charge.aim) > target.radius or charge.origin.distance_to(target.position) > charge.weapon.range_units:
			continue
		var hit = sim.asteroid_field.intercept(sim, charge.origin, charge.aim)
		if hit == null:
			hit = target
		var beam := BattleSimulation.Beam.new()
		beam.source = source
		beam.origin_position = charge.origin
		beam.target = hit
		beam.aim_position = charge.aim
		sim.beams.append(beam)
		for shot in range(charge.weapon.projectiles_per_activation):
			sim._damage(hit, charge.weapon.damage_per_shot, charge.origin, source, charge.weapon.weapon_name)
		sim._record_event("beam_impact", {"source": source.entity_id, "target": hit.entity_id})
	_update_drones(sim, delta)
	for member in sim.players:
		if member.owned_ship == null or not member.is_alive():
			continue
		_relay(sim, member, delta)
		_mark(sim, member, delta)
		_synchronize(sim, member, delta)
		_rebuild(sim, member)
		_launch(sim, member, delta)

func _mark(sim, source, delta: float) -> void:
	if not source.owned_ship is HangarShip:
		return
	var uplinks := operational(source, ShipPart.Type.COMMAND_UPLINK)
	if uplinks.is_empty():
		marks.erase(source.entity_id)
		return
	mark_timers[source.entity_id] = maxf(0, float(mark_timers.get(source.entity_id, 0)) - delta)
	if mark_timers[source.entity_id] > 0:
		return
	var target = sim._choose_weapon_target(source, source.position, 500)
	if target == null:
		return
	marks[source.entity_id] = {"index": uplinks[0], "target": target.entity_id, "remaining": 5.0}
	mark_timers[source.entity_id] = 20.0
	sim._record_event("focus_mark", {"source": source.entity_id, "target": target.entity_id, "seconds": 5.0})

func mark_multiplier(sim, source, target) -> float:
	for id: String in marks:
		var host = sim.entities.get(id)
		var mark: Dictionary = marks[id]
		if mark.remaining > 0 and mark.target == target.entity_id and host != null and host.is_alive() \
			and host.faction == source.faction and host.owned_ship.units[mark.index].hp > 0:
			return 1.2
	return 1.0

func _synchronize(sim, source, delta: float) -> void:
	if not source.owned_ship is HangarShip:
		return
	var computers := operational(source, ShipPart.Type.TACTICAL_COMPUTER).size()
	if computers == 0:
		synchronization.erase(source.entity_id)
		return
	synchronization[source.entity_id] = minf(12, float(synchronization.get(source.entity_id, 0)) + delta * computers)
	if synchronization[source.entity_id] < 12:
		return
	# Hold the synchronized salvo for a visible, unshielded target in reach.
	var target = null
	for weapon: ShipWeaponStats in source.stats.weapons:
		var candidate = sim._choose_weapon_target(source, sim._get_weapon_origin(source, weapon), weapon.range_units)
		if candidate != null and candidate.shields <= 0:
			target = candidate
			break
	if target == null:
		if HangarCarriers.has_bay(source.owned_ship):
			var candidate = sim._choose_weapon_target(source, source.position, 500)
			if candidate != null and candidate.shields <= 0:
				target = candidate
		if target == null:
			return
	synchronization[source.entity_id] = 0.0
	for index in range(source.stats.weapons.size()):
		var weapon: ShipWeaponStats = source.stats.weapons[index]
		# Do not overwrite a beam already charging.
		if not charges.has("%s/%d" % [source.entity_id, weapon.component_index]):
			source.cooldowns[index] = 0.0
	for instance: Dictionary in source.owned_ship.mounts.values():
		if instance.equipment_id in HangarCarriers.CAPACITIES:
			carriers.timers[instance.uid] = 0.0
	sim._record_event("synchronized_salvo", {"source": source.entity_id, "target": target.entity_id, "computers": computers})

func _relay(sim, source, delta: float) -> void:
	if operational(source, ShipPart.Type.SHIELD_RELAY).is_empty() or source.shields <= 0 or source.stats.shields <= 0:
		return
	var chosen = null
	var ratio: float = source.shields / source.stats.shields
	for target in sim.players:
		if target == source or not target.is_alive() or target.stats.shields <= 0 or source.position.distance_to(target.position) > 180:
			continue
		var other: float = target.shields / target.stats.shields
		if other < ratio:
			ratio = other
			chosen = target
	if chosen == null:
		return
	var equalization: float = (source.shields * chosen.stats.shields - chosen.shields * source.stats.shields) / (source.stats.shields + chosen.stats.shields)
	var amount := minf(2 * delta, minf(source.shields, minf(chosen.stats.shields - chosen.shields, equalization)))
	source.shields -= amount
	chosen.shields += amount

func _rebuild(sim, member) -> void:
	var owned: FleetShip = member.owned_ship
	if pool.rebuilt.has(str(owned.id)) or pool.rebuilt.size() >= pool.rebuild_capacity or operational(member, ShipPart.Type.NANOFORGE).is_empty():
		return
	for index in range(owned.units.size()):
		var unit: Dictionary = owned.units[index]
		if unit.hp > 0 or unit.part == null or index == owned.core_index:
			continue
		unit.hp = unit.max_hp * 0.25
		owned.visual_revision += 1
		pool.rebuilt.append(str(owned.id))
		member.repaired_hp += unit.hp
		sim._refresh_owned_stats(member)
		sim._record_event("reconstruction", {"ship": member.entity_id, "unit": index, "hp": unit.hp})
		break

func _repair_target(sim, source):
	var chosen = null
	var largest := 0.0
	for member in sim.players:
		if not member.is_alive() or member.owned_ship == null or source.position.distance_to(member.position) > 220:
			continue
		for index in range(member.owned_ship.units.size()):
			var unit: Dictionary = member.owned_ship.units[index]
			if unit.hp > 0 and unit.max_hp - unit.hp > largest:
				largest = unit.max_hp - unit.hp
				chosen = {"member": member, "index": index}
	return chosen

func _launch(sim, member, delta: float) -> void:
	var bays := operational(member, ShipPart.Type.REPAIR_DRONE_BAY)
	if bays.is_empty():
		return
	var rates := AdjacencyRules.rates(member.owned_ship.units)
	for index in bays:
		var key := "%s/%d" % [member.entity_id, index]
		launch_timers[key] = maxf(0, float(launch_timers.get(key, 0)) - delta * float(rates.get(index, 1.0)))
		if launch_timers[key] > 0 or pool.repair_spent >= pool.repair_capacity:
			continue
		var alive := 0
		for actor in sim._members:
			if actor.is_alive() and actor.has_tag("combatant"):
				alive += 1
		if alive >= 64:
			return
		var target: Variant = _repair_target(sim, member)
		if target == null:
			continue
		var drone := BattleSimulation.Combatant.new()
		drone.stats = ShipStats.new()
		drone.stats.integrity = 2
		drone.stats.weight = 1
		drone.integrity = 2
		drone.radius = 4
		drone.faction = member.faction
		drone.tags.assign({"combatant": true, "craft": true, "summon": true, "repair_drone": true})
		drone.position = member.position
		serial += 1
		drone.entity_id = "repair_drone/%d" % serial
		if not sim.register_entity(drone):
			continue
		var amount := minf(4, pool.repair_capacity - pool.repair_spent)
		pool.repair_spent += amount # Interception spends the launched payload too.
		launch_timers[key] = 2
		drones.append({"actor": drone, "source": member.entity_id, "index": index, "target": target.member.entity_id,
			"unit": target.index, "amount": amount, "remaining": 6.0})
		sim._record_event("repair_launch", {"source": member.entity_id, "drone": drone.entity_id, "amount": amount})

func _update_drones(sim, delta: float) -> void:
	for index in range(drones.size() - 1, -1, -1):
		var job := drones[index]
		var drone = job.actor
		var source = sim.entities.get(job.source)
		var target = sim.entities.get(job.target)
		job.remaining -= delta
		if not drone.is_alive() or job.remaining <= 0 or source == null or not source.is_alive() \
			or source.owned_ship.units[job.index].hp <= 0 or target == null or not target.is_alive():
			drone.integrity = 0
			drones.remove_at(index)
			continue
		drone.position = drone.position.move_toward(target.position, delta * 100)
		if drone.position.distance_to(target.position) > target.radius:
			continue
		var unit: Dictionary = target.owned_ship.units[job.unit]
		if unit.hp > 0:
			var amount := minf(job.amount, unit.max_hp - unit.hp)
			unit.hp += amount
			target.repaired_hp += amount
			sim._refresh_owned_stats(target)
			sim._record_event("repair_delivery", {"target": target.entity_id, "unit": job.unit, "hp": amount})
		drone.integrity = 0
		drones.remove_at(index)

func snapshot() -> Dictionary:
	var pending := {}
	for key in charges:
		var c: Dictionary = charges[key]
		pending[key] = {"source": c.source, "target": c.target, "index": c.index, "remaining": c.remaining,
			"origin": [c.origin.x, c.origin.y], "aim": [c.aim.x, c.aim.y], "damage": c.weapon.damage_per_shot}
	var jobs: Array = []
	for job in drones:
		jobs.append({"actor": job.actor.entity_id, "source": job.source, "index": job.index,
			"target": job.target, "unit": job.unit, "amount": job.amount, "remaining": job.remaining})
	return {"pool": pool.duplicate(true), "charges": pending, "drones": jobs, "timers": launch_timers.duplicate(), "serial": serial,
		"carriers": carriers.snapshot(), "synchronization": synchronization.duplicate(),
		"marks": marks.duplicate(true), "mark_timers": mark_timers.duplicate()}
