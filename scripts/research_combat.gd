class_name ResearchCombat
extends RefCounted

const EFFECTS := ["prismatic_lasers", "splinter_missiles", "pulse_shields"]
const RAMP_SECONDS := 4.0
const SPLIT_DISTANCE := 100.0
const SPLIT_RADIUS := 140.0
const PULSE_INTERVAL := 8.0
const PULSE_FRACTION := 0.25
var enabled: Dictionary = {}
var channels: Dictionary = {}
var bursts: Dictionary = {}
var shield_clocks: Dictionary = {}
var pulse_rings: Array[Dictionary] = []

static func valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: Variant in value:
		if key not in EFFECTS or not value[key] is bool:
			return false
	return true

func configure(value: Dictionary) -> void:
	enabled = value.duplicate()
	channels.clear()
	bursts.clear()
	shield_clocks.clear()
	pulse_rings.clear()

func is_prismatic(source, weapon: ShipWeaponStats) -> bool:
	return enabled.get("prismatic_lasers", false) and source.owned_ship is HangarShip \
		and source.faction == BattleSimulation.Faction.PLAYER and "prismatic" in weapon.research_capabilities

func begin_step(sim, delta: float) -> void:
	for channel: Dictionary in channels.values():
		channel.active = false
	for index in range(pulse_rings.size() - 1, -1, -1):
		pulse_rings[index].remaining -= delta
		if pulse_rings[index].remaining <= 0:
			pulse_rings.remove_at(index)
	if not enabled.get("pulse_shields", false):
		return
	for member in sim.players:
		if not member.owned_ship is HangarShip or not member.is_alive() or member.stats.shields <= 0 \
				or not member.stats.research_capabilities.has("shield"):
			shield_clocks.erase(member.entity_id)
			continue
		var clock: float = float(shield_clocks.get(member.entity_id, 0.0)) + delta
		var pulses := floori((clock + 0.000001) / PULSE_INTERVAL)
		if pulses > 0:
			clock = maxf(0, clock - pulses * PULSE_INTERVAL)
			if not sim.abilities.suppressed(member):
				var restored: float = minf(member.stats.shields - member.shields, member.stats.shields * PULSE_FRACTION * pulses)
				if restored > 0:
					member.shields += restored
					pulse_rings.append({"source": member.entity_id, "remaining": 0.6})
					sim._record_event("shield_pulse", {"source": member.entity_id, "restored": restored})
		shield_clocks[member.entity_id] = clock

func end_step(sim) -> void:
	for key: String in channels.keys():
		var channel: Dictionary = channels[key]
		if not channel.active or not channel.beam.target.is_alive() or not channel.beam.source.is_alive():
			sim.beams.erase(channel.beam)
			channels.erase(key)

static func ramp_integral(time: float) -> float:
	var ramp := minf(time, RAMP_SECONDS)
	return ramp + ramp * ramp / (2 * RAMP_SECONDS) + maxf(0, time - RAMP_SECONDS) * 2

func fire_laser(sim, source, index: int, weapon: ShipWeaponStats, origin: Vector2, delta: float) -> void:
	var key := "%s/%d" % [source.entity_id, index]
	var channel: Dictionary = channels.get(key, {})
	var target = null
	if not channel.is_empty():
		var previous = sim.entities.get(channel.target)
		if previous != null and (source.commanded_target == previous or (source.commanded_target == null \
				and sim._auto_candidate(source, previous))) and origin.distance_to(previous.position) <= weapon.range_units:
			target = previous
	if target == null:
		target = sim._choose_weapon_target(source, origin, weapon.range_units)
	if target == null or delta <= 0:
		return
	var obstruction = sim.asteroid_field.intercept(sim, origin, target.position)
	if obstruction != null:
		target = obstruction
	if channel.is_empty() or channel.target != target.entity_id:
		if not channel.is_empty():
			sim.beams.erase(channel.beam)
		var beam := BattleSimulation.Beam.new()
		beam.source = source
		beam.prismatic = true
		channel = {"target": target.entity_id, "held": 0.0, "active": true, "beam": beam}
		channels[key] = channel
		sim._record_event("beam_lock", {"source": source.entity_id, "weapon_index": index, "target": target.entity_id})
		sim.weapon_fired.emit()
	var before: float = channel.held
	channel.held += delta
	channel.active = true
	var fraction := (ramp_integral(channel.held) - ramp_integral(before)) \
		* weapon.projectiles_per_activation / weapon.fire_interval_seconds + float(bursts.get(key, 0))
	bursts.erase(key)
	source.target = target
	var beam: BattleSimulation.Beam = channel.beam
	beam.origin_position = origin
	beam.target = target
	beam.aim_position = target.position
	beam.lifetime = 0.16
	beam.intensity = 1 + minf(channel.held / RAMP_SECONDS, 1)
	if beam not in sim.beams:
		sim.beams.append(beam)
	sim._damage(target, weapon.damage_per_shot * fraction, origin, source, weapon.weapon_name, false, true, fraction)

func synchronize(source, index: int, weapon: ShipWeaponStats) -> void:
	if is_prismatic(source, weapon):
		bursts["%s/%d" % [source.entity_id, index]] = float(weapon.projectiles_per_activation)

func split(sim, parent) -> bool:
	if not parent.splinter or parent.guidance_lost or not parent.target.is_alive() \
		or parent.position.distance_to(parent.target.position) > SPLIT_DISTANCE \
		or (sim.visibility_enabled and not sim.team_can_see(BattleSimulation.Faction.PLAYER, parent.target)):
		return false
	var targets: Array = [parent.target]
	for candidate in sim._members:
		if candidate != parent.target and candidate.is_alive() and candidate.targetable and candidate.automatic_targetable \
			and candidate.faction == parent.target.faction and candidate.has_tag("combatant") \
			and candidate.position.distance_to(parent.target.position) <= SPLIT_RADIUS \
			and (not sim.visibility_enabled or sim.team_can_see(BattleSimulation.Faction.PLAYER, candidate)):
			targets.append(candidate)
			if targets.size() == 3:
				break
	sim._add_pending_damage(parent.target, -parent.damage)
	for index in range(3):
		var child := BattleSimulation.Projectile.new()
		child.source = parent.source
		child.origin = parent.position
		child.position = parent.position + Vector2(0, (index - 1) * 8).rotated(
			parent.position.angle_to_point(parent.target.position))
		child.previous_position = child.position
		child.weapon_name = parent.weapon_name
		child.target = targets[index % targets.size()]
		child.aim_position = child.target.position
		child.aim_radius = child.target.radius
		var multiplier := 1.0
		if parent.source != null and parent.source.owned_ship is HangarShip:
			multiplier = ResearchUpgrades.value(parent.source.owned_ship.research_modifiers, "fragment_damage_multiplier")
		child.damage = parent.damage * 0.5 * multiplier
		child.hull_damage_multiplier = parent.hull_damage_multiplier
		child.is_player = true
		child.interceptable = true
		child.speed = parent.speed * 1.5
		child.fragment = true
		sim.projectiles.append(child)
		sim._add_pending_damage(child.target, child.damage)
	sim._record_event("missile_split", {"source": parent.source.entity_id, "target": parent.target.entity_id, "fragments": 3})
	return true

func snapshot() -> Dictionary:
	var locks := {}
	for key: String in channels:
		locks[key] = {"target": channels[key].target, "held": channels[key].held}
	return {"enabled": enabled.duplicate(), "channels": locks, "bursts": bursts.duplicate(),
		"shield_clocks": shield_clocks.duplicate()}
