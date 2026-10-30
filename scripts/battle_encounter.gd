extends RefCounted

# The whole priced roster is frozen at departure; waiting never creates enemies
# or rewards. Legacy contexts without a plan keep their original rules.
var warden = preload("res://scripts/warden_battle.gd").new()
const WAVE_INTERVAL := 6.0
var plan: Dictionary = {}
var clock := 0.0
var pending: Array[Dictionary] = []
var wave := 1

func configure(sim, value: Dictionary) -> bool:
	plan = value.duplicate(true)
	clock = 0.0
	wave = 1
	pending.clear()
	if plan.is_empty():
		return warden.configure(sim, {})
	if not EncounterGenerator.valid(plan) or not plan.has("arena_layout") or plan.legacy:
		return false
	var initial: Array[String] = []
	for entry: Dictionary in plan.roster:
		if entry.kind != "ship" and not (plan.has("warden") and entry.kind == "organ"):
			return false
		if int(entry.wave) > 0:
			pending.append(entry.duplicate(true))
		else:
			initial.append(entry.entity_id)
	for member in sim.aliens:
		if not initial.has(member.entity_id):
			return false
		for entry: Dictionary in plan.roster:
			if entry.entity_id == member.entity_id and JSON.parse_string(JSON.stringify(member.alien.to_snapshot())) != JSON.parse_string(JSON.stringify(entry)):
				return false
	if initial.size() != sim.aliens.size():
		return false
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.wave) < int(b.wave) if int(a.wave) != int(b.wave) else str(a.entity_id) < str(b.entity_id))
	sim.objective_target_ids = EncounterGenerator.objective_ids(plan)
	return warden.configure(sim, plan)

func knows(id: String) -> bool:
	for entry in pending:
		if entry.entity_id == id:
			return true
	return false

func advance(sim, delta: float) -> void:
	clock += delta
	while not pending.is_empty():
		var entry: Dictionary = pending[0]
		if clock + 0.000001 < int(entry.wave) * WAVE_INTERVAL:
			break
		var living := 0
		for member in sim._members:
			if member.is_alive() and member.has_tag("combatant"):
				living += 1
		if living >= 64:
			break
		var definition := AlienShip.from_snapshot(entry)
		var member = sim._create_combatant(definition.stats)
		member.alien = definition
		member.entity_id = definition.entity_id
		member.position = Vector2(620, (int(entry.entity_id.get_slice("/", 3)) % 5 - 2) * 45)
		member.previous_position = member.position
		member.heading = PI
		member.previous_heading = PI
		member.radius = 7.0
		sim.aliens.append(member)
		sim._rebuild_member_cache()
		sim.enemy_roles.register_source(member)
		wave = maxi(wave, int(entry.wave) + 1)
		sim._record_event("wave_spawn", {"entity": member.entity_id, "wave": int(entry.wave) + 1})
		pending.pop_front()

func steer(position: Vector2, desired: Vector2, speed: float) -> Vector2:
	if plan.get("arena_layout", "open") == "corridor" and absf(position.y) > 140:
		var strength := clampf((absf(position.y) - 140) / 100, 0, 1)
		return desired.lerp(Vector2(desired.x, -signf(position.y) * speed), strength)
	return desired

func label(sim) -> String:
	if not warden.rules.is_empty():
		return warden.label(sim)
	if plan.is_empty():
		return "OBJECTIVE: %d targets" % sim.remaining_victory_targets().size()
	if int(plan.wave_count) == 1:
		var kind := "PATROL" if plan.encounter_type == "standard" else str(plan.encounter_type).to_upper()
		return "%s: %d targets" % [kind, sim.remaining_victory_targets().size()]
	var text := "DEFENSE: %d/%d" % [wave, int(plan.wave_count)]
	if not pending.is_empty():
		var next := INF
		for entry in pending:
			next = minf(next, int(entry.wave) * WAVE_INTERVAL)
		text += " | Next %ds" % ceili(maxf(0, next - clock))
	else:
		text += " | %d targets" % sim.remaining_victory_targets().size()
	return text

func snapshot() -> Dictionary:
	var ids: Array[String] = []
	for entry in pending:
		ids.append(entry.entity_id)
	return {"clock": clock, "wave": wave, "pending": ids, "warden": warden.snapshot()}
