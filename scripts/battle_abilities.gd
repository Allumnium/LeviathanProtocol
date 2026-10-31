class_name BattleAbilities
extends RefCounted

var state := initial_state()
var available: Array[String] = []
var enemy_cooldowns: Dictionary = {}
var effects: Array[Dictionary] = []
var resource_knowledge: Dictionary = {0: {}, 1: {}}
var last_commit_failed := false
var retry_delay := 0.0

static func initial_state() -> Dictionary:
	return {"version": 1, "cooldowns": {}, "auto": {"scan": true}, "pins": ["scan"], "pause_aim": false}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not value.get("cooldowns") is Dictionary \
		or not value.get("auto") is Dictionary or not value.get("pins") is Array or value.pins.size() > 6 \
		or not value.get("pause_aim", false) is bool:
		return false
	for id in value.cooldowns:
		var definition := GameDefinitions.find("abilities", str(id))
		var remaining: Variant = value.cooldowns[id]
		if not id is String or definition.is_empty() or not SaveValidation.bounded_number(remaining) or remaining < 0 or remaining > float(definition.cooldown_seconds):
			return false
	for id in value.auto:
		if not id is String or GameDefinitions.find("abilities", id).is_empty() or not value.auto[id] is bool:
			return false
	var seen := {}
	for id in value.pins:
		if not id is String or seen.has(id) or GameDefinitions.find("abilities", id).is_empty():
			return false
		seen[id] = true
	return true

func configure(context: Dictionary) -> bool:
	var requested: Variant = context.get("ability_state", initial_state())
	if not valid(requested) or not context.get("ability_ids", []) is Array:
		return false
	state = requested.duplicate(true)
	state["pause_aim"] = state.get("pause_aim", false)
	available.clear()
	enemy_cooldowns.clear()
	effects.clear()
	resource_knowledge = {0: {}, 1: {}}
	last_commit_failed = false
	retry_delay = 0.0
	for id in context.get("ability_ids", []):
		var definition := GameDefinitions.find("abilities", str(id))
		if not id is String or definition.is_empty() or not definition.implemented or available.has(id):
			return false
		available.append(id)
	return true

func sources(sim, faction: int, id: String) -> Array:
	var result: Array = []
	var definition := GameDefinitions.find("abilities", id)
	if definition.is_empty():
		return result
	for member in sim._members:
		if member.faction != faction or not member.is_alive() or not member.has_tag("combatant"):
			continue
		if member.owned_ship != null:
			for unit in member.owned_ship.units:
				if unit.hp > 0 and unit.part != null and unit.part.definition_id == definition.source_equipment_id:
					result.append(member)
					break
		elif faction == 1 and id == "scan" and not member.has_tag("summon") and not member.has_tag("craft") and not member.has_tag("organ"):
			result.append(member)
	return result

func choose_source(sim, faction: int, id: String, point: Vector2, source_id := ""):
	var definition := GameDefinitions.find("abilities", id)
	if definition.is_empty() or not point.is_finite():
		return null
	var best = null
	var nearest := INF
	for source in sources(sim, faction, id):
		if not source_id.is_empty() and source.entity_id != source_id:
			continue
		var distance: float = origin(source, id).distance_squared_to(point)
		if distance <= float(definition.range_units) * float(definition.range_units) and distance < nearest:
			best = source
			nearest = distance
	return best

func origin(source, id: String) -> Vector2:
	if source.owned_ship == null:
		return source.position
	var definition := GameDefinitions.find("abilities", id)
	for unit in source.owned_ship.units:
		if unit.hp <= 0 or unit.part == null or unit.part.definition_id != definition.get("source_equipment_id", ""):
			continue
		var local := Vector2.ZERO
		for cell: Vector2i in unit.cells:
			local += source.owned_ship.local_cell_position(cell)
		return source.position + (local / maxf(1, unit.cells.size())).rotated(source.heading)
	return source.position

func remaining(id: String, faction := 0) -> float:
	return float((state.cooldowns if faction == 0 else enemy_cooldowns).get(id, 0.0))

func can_cast(sim, id: String, point: Vector2, source_id := "", faction := 0) -> bool:
	if sim.phase != 0 or not sim.visibility_enabled or id not in ["scan", "seismic_cut", "ion_pulse", "gravity_well"] or not available.has(id) \
		or faction not in [0, 1] or remaining(id, faction) > 0 or choose_source(sim, faction, id, point, source_id) == null:
		return false
	if id == "ion_pulse":
		var target = visible_target(sim, faction, point)
		return target != null and choose_source(sim, faction, id, target.position, source_id) != null
	if id == "gravity_well":
		return sim.point_visible(faction, point)
	if id == "seismic_cut":
		for member in sim.other_entities:
			if member.has_tag("asteroid") and member.is_alive() and sim.team_can_see(faction, member) and member.position.distance_to(point) <= 100:
				return true
		return false
	return true

func cast(sim, id: String, point: Vector2, source_id := "", faction := 0) -> bool:
	if not can_cast(sim, id, point, source_id, faction):
		return false
	var source = choose_source(sim, faction, id, point, source_id)
	var definition := GameDefinitions.find("abilities", id)
	if faction == 0:
		var proposal := state.duplicate(true)
		proposal.cooldowns[id] = float(definition.cooldown_seconds)
		if sim.ability_commit.is_valid() and not sim.ability_commit.call(proposal):
			last_commit_failed = true
			retry_delay = 1.0
			return false
		state = proposal
		retry_delay = 0.0
	else:
		enemy_cooldowns[id] = float(definition.cooldown_seconds)
	if id == "ion_pulse":
		var target = visible_target(sim, faction, point)
		sim.doctrines.interrupt(sim, target)
		effects.append({"id": id, "faction": faction, "source": source.entity_id, "target": target.entity_id,
			"position": target.position, "radius": 12.0, "remaining": float(definition.duration_seconds)})
	elif id == "gravity_well":
		effects.append({"id": id, "faction": faction, "source": source.entity_id, "position": point,
			"radius": float(definition.radius_units), "remaining": float(definition.duration_seconds)})
	elif id == "scan":
		effects.append({"id": id, "faction": faction, "source": source.entity_id, "position": point,
			"radius": float(definition.radius_units), "remaining": float(definition.duration_seconds)})
		for member in sim._members:
			if member.has_tag("asteroid") and member.position.distance_squared_to(point) <= float(definition.radius_units) * float(definition.radius_units):
				resource_knowledge[faction][member.entity_id] = member.resource_contents.duplicate(true)
	elif id == "seismic_cut":
		for member in sim._members:
			if member == source or member.faction == faction or not member.is_alive() or member.position.distance_to(point) > float(definition.radius_units):
				continue
			sim._damage(member, 60.0 if member.has_tag("asteroid") else 15.0, origin(source, id), source, "Seismic Cut")
	sim._record_event("ability", {"ability": id, "source": source.entity_id, "faction": faction, "position": [point.x, point.y]})
	sim.refresh_visibility()
	return true

func set_auto(sim, id: String, enabled: bool) -> bool:
	if not available.has(id) or sim.phase != 0:
		return false
	var proposal := state.duplicate(true)
	proposal.auto[id] = enabled
	if sim.ability_commit.is_valid() and not sim.ability_commit.call(proposal):
		last_commit_failed = true
		retry_delay = 1.0
		return false
	state = proposal
	retry_delay = 0.0
	return true

func set_pause_aim(sim, enabled: bool) -> bool:
	if sim.phase != 0:
		return false
	var proposal := state.duplicate(true)
	proposal.pause_aim = enabled
	if sim.ability_commit.is_valid() and not sim.ability_commit.call(proposal):
		last_commit_failed = true
		retry_delay = 1.0
		return false
	state = proposal
	retry_delay = 0.0
	return true

func advance(sim, delta: float) -> void:
	retry_delay = maxf(0, retry_delay - delta)
	for id in state.cooldowns:
		state.cooldowns[id] = maxf(0, float(state.cooldowns[id]) - delta)
	for id in enemy_cooldowns:
		enemy_cooldowns[id] = maxf(0, float(enemy_cooldowns[id]) - delta)
	for index in range(effects.size() - 1, -1, -1):
		var effect := effects[index]
		effect.remaining = float(effect.remaining) - delta
		var source = sim.entities.get(effect.source)
		if effect.remaining <= 0 or source == null or not sources(sim, int(effect.faction), effect.id).has(source):
			effects.remove_at(index)

func visible_target(sim, faction: int, point: Vector2):
	var chosen = null
	var nearest := INF
	for target in sim._members:
		if target.faction == faction or target.faction == 2 or not target.is_alive() or not target.has_tag("combatant") or not sim.team_can_see(faction, target):
			continue
		var distance: float = target.position.distance_to(point)
		if distance <= target.radius and distance < nearest:
			chosen = target
			nearest = distance
	return chosen

func suppressed(member) -> bool:
	for effect in effects:
		if effect.id == "ion_pulse" and effect.get("target", "") == member.entity_id:
			return true
	return false

func movement_rate(member) -> float:
	for effect in effects:
		if effect.id == "gravity_well" and int(effect.faction) != member.faction and member.position.distance_to(effect.position) <= effect.radius:
			return 0.65
	return 1.0

func auto_cast(sim) -> void:
	for id in ["ion_pulse", "gravity_well"]:
		if not available.has(id) or not state.auto.get(id, true) or remaining(id) > 0 or retry_delay > 0:
			continue
		for target in sim._members:
			if target.faction != 1 or not target.is_alive() or not sim.team_can_see(0, target) or not target.has_tag("combatant"):
				continue
			if can_cast(sim, id, target.position):
				sim.issue_command("ability_cast", {"ability": id, "position": [target.position.x, target.position.y], "source": "", "faction": 0})
				break
	if available.has("seismic_cut") and state.auto.get("seismic_cut", true) and retry_delay <= 0 and remaining("seismic_cut") <= 0:
		for member in sim.other_entities:
			if member.has_tag("asteroid") and member.is_alive() and sim.team_can_see(0, member) and MiningRules.known_eligible(sim, sim.get_living_player(), member) \
				and can_cast(sim, "seismic_cut", member.position):
				sim.issue_command("ability_cast", {"ability": "seismic_cut", "position": [member.position.x, member.position.y], "source": "", "faction": 0})
				break
	if not available.has("scan") or retry_delay > 0:
		return
	for faction in [0, 1]:
		if (faction == 0 and not state.auto.get("scan", false)) or remaining("scan", faction) > 0:
			continue
		var points: Array[Vector2] = []
		for contact: Dictionary in sim.visibility.contacts(faction):
			if contact.kind == "radar":
				points.append(contact.position)
		for member in sim._members:
			if member.has_tag("asteroid") and sim.team_can_see(faction, member) and not resource_knowledge[faction].has(member.entity_id):
				points.append(member.position)
		for point in points:
			if can_cast(sim, "scan", point, "", faction):
				sim.issue_command("ability_cast", {"ability": "scan", "position": [point.x, point.y], "source": "", "faction": faction})
				break

func snapshot() -> Dictionary:
	return state.duplicate(true)

func known_resources(faction: int, id: String) -> Dictionary:
	return resource_knowledge.get(faction, {}).get(id, {}).duplicate(true)
