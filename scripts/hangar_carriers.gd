class_name HangarCarriers
extends RefCounted

# Per-encounter replacement allowances follow equipment UIDs across transfers.
const CAPACITIES := {"flight_deck": 6, "torpedo_bomber_bay": 4}
const ACTIVE_LIMIT := 2
const LAUNCH_INTERVAL := 4.0
const SORTIE_SECONDS := 25.0
var reserves: Dictionary = {}
var sorties: Array[Dictionary] = []
var timers: Dictionary = {}
var serial := 0

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 10000:
		return false
	for uid: Variant in value:
		var row: Variant = value[uid]
		if not uid is String or not uid.is_valid_int() or int(uid) < 1 or str(int(uid)) != uid \
			or not row is Dictionary or row.size() != 3 or row.get("equipment_id") not in CAPACITIES:
			return false
		if not SaveValidation.integer(row.get("capacity")) or row.capacity != CAPACITIES[row.equipment_id] \
			or not SaveValidation.integer(row.get("spent")) or row.spent < 0 or row.spent > row.capacity:
			return false
	return true

static func has_bay(owned: FleetShip) -> bool:
	if not owned is HangarShip or not owned.is_alive():
		return false
	for unit: Dictionary in owned.units:
		if unit.hp > 0 and unit.part != null and unit.part.definition_id in CAPACITIES:
			return true
	return false

func configure(sim, value: Dictionary) -> bool:
	reserves = value
	sorties.clear()
	timers.clear()
	serial = 0
	for member in sim.players:
		if not member.owned_ship is HangarShip:
			continue
		for instance: Dictionary in member.owned_ship.mounts.values():
			if reserves.has(instance.uid) and reserves[instance.uid].equipment_id != instance.equipment_id:
				return false
			if instance.equipment_id in CAPACITIES and not reserves.has(instance.uid):
				reserves[instance.uid] = {"equipment_id": instance.equipment_id,
					"capacity": CAPACITIES[instance.equipment_id], "spent": 0}
	return true

func prune(sim, delta := 0.0) -> void:
	for index in range(sorties.size() - 1, -1, -1):
		var job: Dictionary = sorties[index]
		var source = sim.entities.get(job.source)
		job.remaining -= delta
		if source == null or not source.is_alive() or source.owned_ship.units[job.index].hp <= 0 \
			or not job.actor.is_alive() or job.remaining <= 0 or job.actor.sortie_ammo == 0:
			job.actor.integrity = 0
			sorties.remove_at(index)

func advance(sim, delta: float) -> void:
	prune(sim, delta)
	for member in sim.players:
		if not has_bay(member.owned_ship) or sim.objective_complete() or sim.withdrawing:
			continue
		var owned: HangarShip = member.owned_ship
		for index in range(owned.units.size()):
			var unit: Dictionary = owned.units[index]
			if unit.hp <= 0 or unit.part == null or unit.part.definition_id not in CAPACITIES:
				continue
			var uid: String = owned.mounts[unit.key].uid
			timers[uid] = maxf(0, float(timers.get(uid, 0)) - delta * owned.weapon_cycle_rate())
			if timers[uid] > 0 or reserves[uid].spent >= reserves[uid].capacity:
				continue
			var active := 0
			for job: Dictionary in sorties:
				if job.uid == uid:
					active += 1
			var living := 0
			for actor in sim._members:
				if actor.is_alive() and actor.has_tag("combatant"):
					living += 1
			if active < ACTIVE_LIMIT and living < EnemyRoles.ENTITY_LIMIT:
				_launch(sim, member, index, uid)

func _launch(sim, source, index: int, uid: String) -> void:
	var bomber: bool = reserves[uid].equipment_id == "torpedo_bomber_bay"
	var stats := ShipStats.new()
	stats.integrity = 8 if bomber else 4
	stats.weight = 3
	stats.thrust = 15 if bomber else 24
	stats.collision_radius = 6 if bomber else 4
	var weapon := ShipWeaponStats.new("Bomber Torpedo" if bomber else "Interceptor Pulse",
		3.0 if bomber else 1.0, 12.0 if bomber else 2.0, 1, 200 if bomber else 150)
	weapon.is_projectile_weapon = bomber
	weapon.interceptable = bomber
	stats.weapons.append(weapon)
	var actor = sim._create_combatant(stats)
	serial += 1
	actor.entity_id = "carrier/%s/%d" % [uid, serial]
	actor.carrier_source_id = source.entity_id
	actor.faction = source.faction
	actor.tags.assign({"combatant": true, "craft": true, "summon": true,
		"bomber" if bomber else "interceptor": true})
	actor.position = source.position + Vector2.from_angle(source.heading + PI * 0.5) * (source.radius + actor.radius)
	actor.heading = source.heading
	actor.sortie_ammo = 2 if bomber else 12
	if not sim.register_entity(actor):
		return
	reserves[uid].spent += 1
	timers[uid] = LAUNCH_INTERVAL
	sorties.append({"uid": uid, "source": source.entity_id, "index": index,
		"actor": actor, "remaining": SORTIE_SECONDS})
	sim._record_event("carrier_launch", {"source": source.entity_id, "uid": uid, "craft": actor.entity_id,
		"equipment_id": reserves[uid].equipment_id, "remaining": reserves[uid].capacity - reserves[uid].spent})

func snapshot() -> Dictionary:
	var active: Array = []
	for job: Dictionary in sorties:
		active.append({"uid": job.uid, "source": job.source, "index": job.index,
			"actor": job.actor.entity_id, "remaining": job.remaining, "ammo": job.actor.sortie_ammo})
	return {"reserves": reserves.duplicate(true), "sorties": active,
		"timers": timers.duplicate(), "serial": serial}

func available(sim) -> Vector2i:
	var result := Vector2i.ZERO
	for member in sim.players:
		if not has_bay(member.owned_ship):
			continue
		for unit: Dictionary in member.owned_ship.units:
			if unit.hp > 0 and unit.part != null and unit.part.definition_id in CAPACITIES:
				var uid: String = member.owned_ship.mounts[unit.key].uid
				result.x += int(reserves[uid].capacity) - int(reserves[uid].spent)
	for job: Dictionary in sorties:
		if job.actor.is_alive():
			result.y += 1
	return result
