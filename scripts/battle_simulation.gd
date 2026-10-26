class_name BattleSimulation
extends RefCounted

const PROJECTILE_SPEED := 320.0
const TARGET_REFRESH_INTERVAL := 0.2
const SPATIAL_CELL_SIZE := 256.0
const WRECK_MOTION_SECONDS := 4.0

signal weapon_fired
signal shield_hit
signal ship_destroyed(is_player: bool)

enum Phase { COMBAT, VICTORY, DEFEAT, WITHDRAWN }
enum Faction { PLAYER, ALIEN, NEUTRAL }

const ARENA_RADIUS := 800.0
const DROP_CHANCE := 0.6
const SPEED_PER_THRUST := 4.0
const MIN_TURN_RATE := 0.75
const MAX_TURN_RATE := 1.5
const PASSIVE_DRAG_PER_SECOND := 0.06
const REVERSE_THRUST_FACTOR := 0.22
const REVERSE_THRUST_ALIGNMENT_START := 0.35
const FLYBY_MIN_CLEARANCE := 12.0
const FLYBY_RANGE_FACTOR := 0.70
const SOFT_BOUNDARY_MARGIN := 180.0
const PLAYER_FORMATION_CENTER := Vector2(-420.0, 0.0)
const PLAYER_FORMATION_COLUMNS := 3
const PLAYER_FORMATION_SPACING := Vector2(54.0, 54.0)
const ALIEN_FORMATION_CENTER := Vector2(420.0, 0.0)
const ALIEN_FORMATION_COLUMNS := 6
const ALIEN_FORMATION_SPACING := Vector2(65.0, 65.0)

class Combatant:
	var owned_ship: FleetShip
	var damage_dealt := 0.0
	var damage_taken := 0.0
	var permanent_damage_taken := 0.0
	var shield_damage_taken := 0.0
	var weapon_damage: Dictionary = {}
	var position := Vector2.ZERO
	var previous_position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var heading := 0.0
	var previous_heading := 0.0
	var entity_id := ""
	var faction := Faction.ALIEN
	var tags: Dictionary[String, bool] = {"combatant": true}
	var targetable := true
	var automatic_targetable := true
	var is_player: bool:
		get:
			return faction == Faction.PLAYER
		set(value):
			faction = Faction.PLAYER if value else Faction.ALIEN
	var stats: ShipStats
	var integrity := 0.0
	var shields := 0.0
	var alien: AlienShip
	var cooldowns: Array[float] = []
	var _target: WeakRef
	var _commanded_target: WeakRef
	var commanded_target: Combatant:
		get:
			return _commanded_target.get_ref() as Combatant if _commanded_target != null else null
		set(value):
			_commanded_target = weakref(value) if value != null else null
	var target: Combatant:
		get:
			return _target.get_ref() as Combatant if _target != null else null
		set(value):
			_target = weakref(value) if value != null else null
	var retreat_time := 0.0
	var retreat_cooldown := 0.0
	var since_damage := 0.0
	var shield_flash := 0.0
	var speed := 100.0
	var acceleration := 75.0
	var turn_rate := 1.2
	var radius := 18.0
	var wreck_angular_velocity := 0.0
	var wreck_motion_remaining := 0.0
	var target_refresh_remaining := 0.0
	var flyby_side := 1.0
	var thruster_activation_elapsed := 0.0

	func is_alive() -> bool:
		return integrity > 0.0

	func has_tag(tag: String) -> bool:
		return tags.get(tag, false)

	func damage_deflected() -> float:
		var result := shield_damage_taken
		if owned_ship == null:
			return result
		for unit in owned_ship.units:
			if unit.hp > 0.0:
				result += maxf(unit.max_hp - unit.hp, 0.0)
		return result

	func shortest_range() -> float:
		var result := INF
		for weapon in stats.weapons:
			if owned_ship != null and owned_ship.units[weapon.component_index].hp <= 0.0:
				continue
			result = minf(result, weapon.range_units)
		return result if result < INF else 220.0

class Projectile:
	var source: Combatant
	var origin := Vector2.ZERO
	var weapon_name := ""
	var position := Vector2.ZERO
	var previous_position := Vector2.ZERO
	var target: Combatant
	var damage := 0.0
	var is_player := false

class Beam:
	var source: Combatant
	var origin_position := Vector2.ZERO
	var target: Combatant
	var lifetime := 0.16

class Drop:
	var entity_id := ""
	var faction := Faction.NEUTRAL
	var tags: Dictionary[String, bool] = {"drop": true}
	var position := Vector2.ZERO
	var category := ShipPart.Category.DEFENSE
	var size := 8.0
	var collected := false

class Explosion:
	var position := Vector2.ZERO
	var lifetime := 0.6

var player: Combatant
var players: Array[Combatant] = []
var aliens: Array[Combatant] = []
var other_entities: Array[Combatant] = []
var entities: Dictionary[String, Combatant] = {}
var objective_target_ids: Array[String] = []
var destroy_all_neutral_targets := false
var projectiles: Array[Projectile] = []
var beams: Array[Beam] = []
var drops: Array[Drop] = []
var explosions: Array[Explosion] = []
var collected_categories: Array[int] = []
var victory_materials: Array[int] = []
var phase := Phase.COMBAT
var elapsed := 0.0
var random := RandomNumberGenerator.new()
var allied_drop_chance := 0.3
var laser_upgrade_level := 0
var withdrawing := false
var retreat_remaining := 10.0
var inactive_seconds := 0.0
var _damage_this_step := false
var _members: Array[Combatant] = []
var _previous_velocities: Array[Vector2] = []
var _pending_damage_by_target: Dictionary = {}
var _spatial_cells: Dictionary = {}
var battle_id := "battle"
var tick_index := 0
var _combat_elapsed := 0.0
var command_log: Array[Dictionary] = []
var event_log: Array[Dictionary] = []
var _command_receipts: Dictionary = {}
var _pending_commands: Array[Dictionary] = []
var _next_command_id := 0


func setup(
	player_stats: ShipStats,
	fleet: Array[RefCounted],
	seed_value: int = -1,
	player_ship_count: int = 1
) -> bool:
	if player_ship_count <= 0:
		push_error("Battle requires at least one player ship.")
		return false
	if not _validate_stats(player_stats) or fleet.is_empty():
		push_error("Battle requires an armed player ship and a nonempty alien fleet.")
		return false
	if seed_value >= 0:
		random.seed = seed_value
	else:
		random.randomize()
	withdrawing = false
	battle_id = "seed/%d" % random.seed
	tick_index = 0
	_combat_elapsed = 0.0
	command_log.clear()
	event_log.clear()
	_command_receipts.clear()
	_pending_commands.clear()
	_next_command_id = 0
	retreat_remaining = 10.0
	inactive_seconds = 0.0
	phase = Phase.COMBAT
	elapsed = 0.0
	players.clear()
	aliens.clear()
	other_entities.clear()
	_spatial_cells.clear()
	entities.clear()
	objective_target_ids.clear()
	destroy_all_neutral_targets = false
	projectiles.clear()
	beams.clear()
	drops.clear()
	explosions.clear()
	collected_categories.clear()
	victory_materials.clear()
	for index in range(player_ship_count):
		var player_ship := _create_combatant(player_stats)
		player_ship.is_player = true
		player_ship.entity_id = "player/%d" % index
		player_ship.position = _get_formation_position(
			index,
			player_ship_count,
			PLAYER_FORMATION_COLUMNS,
			PLAYER_FORMATION_CENTER,
			PLAYER_FORMATION_SPACING
		)
		player_ship.previous_position = player_ship.position
		players.append(player_ship)
	player = players[0]
	for index in range(fleet.size()):
		var definition := fleet[index] as AlienShip
		if definition == null:
			push_error("Battle fleet contains an invalid alien definition.")
			return false
		if not _validate_stats(definition.stats):
			return false
		var alien := _create_combatant(definition.stats)
		alien.alien = definition
		alien.entity_id = definition.entity_id if not definition.entity_id.is_empty() else "alien/%d" % index
		if definition.entity_kind == "craft":
			alien.tags["summon"] = true
		elif definition.entity_kind == "organ":
			alien.tags["organ"] = true
		alien.position = _get_formation_position(
			index,
			fleet.size(),
			ALIEN_FORMATION_COLUMNS,
			ALIEN_FORMATION_CENTER,
			ALIEN_FORMATION_SPACING
		)
		alien.heading = PI
		alien.previous_position = alien.position
		alien.previous_heading = alien.heading
		alien.radius = 7.0
		aliens.append(alien)
		if not alien.has_tag("summon"):
			objective_target_ids.append(alien.entity_id)
	_rebuild_member_cache()
	return entities.size() == _members.size()


func _rebuild_member_cache() -> void:
	_members.clear()
	_members.append_array(players)
	_members.append_array(aliens)
	_members.append_array(other_entities)
	entities.clear()
	for member in _members:
		entities[member.entity_id] = member
	_previous_velocities.resize(_members.size())


func setup_owned(ships: Array[FleetShip], fleet: Array[RefCounted], salvage_chance: float, upgrade_level: int, seed_value: int = -1) -> bool:
	if ships.is_empty():
		return false
	# Use an armed member for legacy setup validation; disabled weapons may remain
	# aboard other surviving ships in the deployment.
	var armed: FleetShip
	for owned in ships:
		if not owned.get_stats(upgrade_level).weapons.is_empty():
			armed = owned
	if armed == null or not setup(armed.get_stats(upgrade_level), fleet, seed_value, ships.size()):
		return false
	allied_drop_chance = salvage_chance
	laser_upgrade_level = upgrade_level
	var formation_center := Vector2.ZERO
	for owned in ships:
		formation_center += Vector2(owned.formation)
	formation_center /= float(ships.size())
	for index in range(ships.size()):
		var member := players[index]
		member.owned_ship = ships[index]
		member.entity_id = "player/ship/%d" % ships[index].id
		member.stats = ships[index].get_stats(upgrade_level)
		member.integrity = member.stats.integrity
		member.shields = member.stats.shields
		_refresh_mobility(member)
		member.cooldowns.clear()
		for weapon in member.stats.weapons:
			member.cooldowns.append(0.0)
			member.weapon_damage[weapon.weapon_name] = 0.0
		member.position = PLAYER_FORMATION_CENTER + (Vector2(ships[index].formation) - formation_center) * 65.0
		member.previous_position = member.position
	_rebuild_member_cache()
	return entities.size() == _members.size()


func register_entity(entity: Combatant) -> bool:
	if entity == null or entity.entity_id.is_empty() or entities.has(entity.entity_id):
		return false
	if entity.stats == null or not is_finite(entity.integrity) or entity.integrity <= 0.0:
		return false
	if not entity.position.is_finite() or not is_finite(entity.shields) or entity.shields < 0.0:
		return false
	if entity.faction not in [Faction.PLAYER, Faction.ALIEN, Faction.NEUTRAL]:
		return false
	entity.previous_position = entity.position
	_refresh_mobility(entity)
	if entity.cooldowns.size() != entity.stats.weapons.size():
		entity.cooldowns.clear()
		for weapon in entity.stats.weapons:
			entity.cooldowns.append(0.0)
	other_entities.append(entity)
	_rebuild_member_cache()
	_spatial_cells.clear()
	return true


func add_neutral_target(id: String, hp: float, position: Vector2) -> Combatant:
	if not is_finite(hp) or hp <= 0.0 or not position.is_finite():
		return null
	var stats := ShipStats.new()
	stats.integrity = hp
	stats.weight = 1.0
	var entity := _create_combatant(stats)
	entity.entity_id = id
	entity.faction = Faction.NEUTRAL
	entity.tags.assign({"neutral": true, "hazard": true})
	entity.position = position
	if not register_entity(entity):
		return null
	return entity


func set_objective_targets(ids: Array[String]) -> bool:
	if phase != Phase.COMBAT:
		return false
	var next_ids: Array[String] = []
	for id in ids:
		var target: Combatant = entities.get(id)
		if target == null or not target.targetable or target.has_tag("drop") or target.faction == Faction.PLAYER or next_ids.has(id):
			return false
		next_ids.append(id)
	objective_target_ids = next_ids
	return true


func _neutral_cleanup_target(entity: Combatant) -> bool:
	return entity.faction == Faction.NEUTRAL and entity.has_tag("neutral") and entity.targetable \
		and not entity.has_tag("drop") and not entity.has_tag("decoy") and not entity.has_tag("summon")


func remaining_victory_targets() -> Array[Combatant]:
	var result: Array[Combatant] = []
	for id in objective_target_ids:
		var target: Combatant = entities.get(id)
		if target != null and target.is_alive():
			result.append(target)
	if destroy_all_neutral_targets:
		for entity in other_entities:
			if entity.is_alive() and _neutral_cleanup_target(entity) and not result.has(entity):
				result.append(entity)
	return result


func objective_complete() -> bool:
	# Unknown objective identities fail closed, rather than becoming free victories.
	for id in objective_target_ids:
		if not entities.has(id):
			return false
	return remaining_victory_targets().is_empty()


func set_destroy_all_neutral_targets(enabled: bool) -> bool:
	if phase != Phase.COMBAT:
		return false
	destroy_all_neutral_targets = enabled
	for member in players:
		if member.commanded_target == null:
			member.target = null
			member.target_refresh_remaining = 0.0
	return true


func can_attack(source: Combatant, target: Combatant) -> bool:
	if source == null or target == null or source == target:
		return false
	if entities.get(source.entity_id) != source or entities.get(target.entity_id) != target:
		return false
	return source.is_alive() and target.is_alive() and target.targetable and not target.has_tag("drop") \
		and source.faction != target.faction


func _hostile(source: Combatant, target: Combatant) -> bool:
	return (source.faction == Faction.PLAYER and target.faction == Faction.ALIEN) \
		or (source.faction == Faction.ALIEN and target.faction == Faction.PLAYER)


func _auto_candidate(source: Combatant, target: Combatant) -> bool:
	if not can_attack(source, target) or not target.automatic_targetable:
		return false
	if _hostile(source, target):
		return true
	if not destroy_all_neutral_targets or source.faction != Faction.PLAYER or not _neutral_cleanup_target(target):
		return false
	# Cleanup is player intent, not a change to faction hostility. Threats take priority.
	for member in _members:
		if _hostile(source, member) and can_attack(source, member) and member.automatic_targetable:
			return false
	return true


func request_attack(source_id: String, target_id: String) -> bool:
	var source: Combatant = entities.get(source_id)
	var target: Combatant = entities.get(target_id)
	if phase != Phase.COMBAT or not can_attack(source, target) or not source.has_tag("combatant"):
		return false
	source.commanded_target = target
	source.target = target
	source.target_refresh_remaining = 0.0
	return true


func clear_attack_order(source_id: String) -> bool:
	var source: Combatant = entities.get(source_id)
	if phase != Phase.COMBAT or source == null:
		return false
	source.commanded_target = null
	source.target = null
	source.target_refresh_remaining = 0.0
	return true


func damage_entity(id: String, amount: float, source_id := "") -> bool:
	var target: Combatant = entities.get(id)
	if phase != Phase.COMBAT or target == null or not target.is_alive() or not target.targetable or target.has_tag("drop"):
		return false
	if not is_finite(amount) or amount <= 0.0:
		return false
	var source: Combatant = entities.get(source_id)
	if not source_id.is_empty() and not can_attack(source, target):
		return false
	_damage(target, amount, Vector2.ZERO if source == null else source.position, source, "Direct damage")
	return true


func issue_command(type: String, payload: Dictionary = {}) -> bool:
	# UI calls this at the current simulation boundary. Replay queues the recorded tick.
	while _command_receipts.has("%s/command/%d" % [battle_id, _next_command_id]):
		_next_command_id += 1
	var command := {"id": "%s/command/%d" % [battle_id, _next_command_id],
		"tick": tick_index, "type": type, "payload": payload.duplicate(true)}
	_next_command_id += 1
	return execute_command(command)


func _valid_command(command: Dictionary) -> bool:
	if not command.get("id") is String or command.id.is_empty() or not RunProgressData._integer(command.get("tick")):
		return false
	if command.tick < 0 or not command.get("payload") is Dictionary or not RunCheckpoint._json_value(command.payload):
		return false
	var payload: Dictionary = command.payload
	match command.get("type"):
		"attack":
			return payload.get("source") is String and payload.get("target") is String
		"clear_attack":
			return payload.get("source") is String
		"neutral_cleanup":
			return payload.get("enabled") is bool
		"withdraw":
			return payload.is_empty()
	return false


func queue_command(command: Dictionary) -> bool:
	if not _valid_command(command):
		return false
	var fingerprint := _command_fingerprint(command)
	if _command_receipts.has(command.id):
		return _command_receipts[command.id].fingerprint == fingerprint and _command_receipts[command.id].status != "rejected"
	if phase != Phase.COMBAT or command.tick < tick_index:
		return false
	_command_receipts[command.id] = {"fingerprint": fingerprint, "status": "queued"}
	_pending_commands.append(command.duplicate(true))
	command_log.append(command.duplicate(true))
	return true


func execute_command(command: Dictionary) -> bool:
	if not _valid_command(command):
		return false
	var fingerprint := _command_fingerprint(command)
	if _command_receipts.has(command.id):
		return _command_receipts[command.id].fingerprint == fingerprint and _command_receipts[command.id].status == "accepted"
	if phase != Phase.COMBAT or command.tick != tick_index:
		return false
	command_log.append(command.duplicate(true))
	return _execute_recorded_command(command, fingerprint)


func _execute_recorded_command(command: Dictionary, fingerprint: String) -> bool:
	var payload: Dictionary = command.payload
	var accepted := false
	match command.type:
		"attack":
			accepted = request_attack(payload.source, payload.target)
		"clear_attack":
			accepted = clear_attack_order(payload.source)
		"neutral_cleanup":
			accepted = set_destroy_all_neutral_targets(payload.enabled)
		"withdraw":
			accepted = phase == Phase.COMBAT and not withdrawing
			if accepted:
				request_withdrawal()
	_command_receipts[command.id] = {"fingerprint": fingerprint, "status": "accepted" if accepted else "rejected"}
	_record_event("command", {"command_id": command.id, "accepted": accepted})
	return accepted


func _apply_pending_commands() -> void:
	# Insertion order breaks ties at a shared tick; callers persist/replay that order.
	for index in range(_pending_commands.size() - 1, -1, -1):
		if _pending_commands[index].tick < tick_index:
			_pending_commands.remove_at(index)
	var due: Array[Dictionary] = []
	for command in _pending_commands:
		if command.tick == tick_index:
			due.append(command)
	for command in due:
		_pending_commands.erase(command)
		_execute_recorded_command(command, _command_fingerprint(command))


func _command_fingerprint(command: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify([command.id, int(command.tick), command.type, command.payload])))


func _record_event(type: String, details: Dictionary) -> void:
	event_log.append({"id": "%s/event/%d" % [battle_id, event_log.size()], "tick": tick_index,
		"type": type, "details": details.duplicate(true)})


func authoritative_snapshot() -> Dictionary:
	# Detached diagnostic state, not a mid-battle restore format. Visual interpolation,
	# camera, effects and audio are deliberately absent from replay comparisons.
	var actors: Array = []
	for member in _members:
		var hp: Array = []
		if member.owned_ship != null:
			for unit in member.owned_ship.units:
				hp.append(unit.hp)
		actors.append({"id": member.entity_id, "faction": member.faction, "tags": member.tags.duplicate(),
			"position": [member.position.x, member.position.y] if member.is_alive() else null,
			"velocity": [member.velocity.x, member.velocity.y] if member.is_alive() else null,
			"heading": member.heading if member.is_alive() else null, "integrity": member.integrity, "shields": member.shields,
			"cooldowns": member.cooldowns.duplicate(), "component_hp": hp,
			"target": member.target.entity_id if member.target != null else "",
			"order": member.commanded_target.entity_id if member.commanded_target != null else "",
			"damage": member.damage_dealt, "taken": member.damage_taken,
			"retreat": member.retreat_time, "retreat_cooldown": member.retreat_cooldown,
			"since_damage": member.since_damage, "target_refresh": member.target_refresh_remaining})
	var shots: Array = []
	for shot in projectiles:
		shots.append({"source": shot.source.entity_id if shot.source != null else "",
			"target": shot.target.entity_id if shot.target != null else "", "damage": shot.damage,
			"position": [shot.position.x, shot.position.y], "origin": [shot.origin.x, shot.origin.y], "weapon": shot.weapon_name})
	var salvage: Array = []
	for drop in drops:
		salvage.append({"id": drop.entity_id, "category": drop.category, "collected": drop.collected,
			"position": [drop.position.x, drop.position.y]})
	return {"battle_id": battle_id, "tick": tick_index, "phase": phase, "elapsed": _combat_elapsed,
		"rng_state": str(random.state), "actors": actors, "projectiles": shots, "drops": salvage,
		"objectives": objective_target_ids.duplicate(), "neutral_cleanup": destroy_all_neutral_targets,
		"remaining_targets": _remaining_target_ids(), "withdrawing": withdrawing,
		"retreat_remaining": retreat_remaining, "inactive": inactive_seconds,
		"materials": collected_categories.duplicate(), "pending_commands": _pending_commands.duplicate(true)}


func _remaining_target_ids() -> Array[String]:
	var ids: Array[String] = []
	for target in remaining_victory_targets():
		ids.append(target.entity_id)
	return ids


func _get_formation_position(
	index: int,
	count: int,
	max_columns: int,
	center: Vector2,
	spacing: Vector2
) -> Vector2:
	var columns := mini(count, max_columns)
	var rows := ceili(float(count) / float(columns))
	var column := index % columns
	var row := floori(float(index) / float(columns))
	return center + Vector2(
		(float(column) - float(columns - 1) * 0.5) * spacing.x,
		(float(row) - float(rows - 1) * 0.5) * spacing.y
	)


func _validate_stats(stats: ShipStats) -> bool:
	if stats == null or stats.integrity <= 0.0 or stats.weapons.is_empty():
		push_error("A combat ship requires positive integrity and working weapons.")
		return false
	for weapon in stats.weapons:
		if (
			weapon.fire_interval_seconds <= 0.0 or weapon.range_units <= 0.0
			or weapon.damage_per_shot <= 0.0 or weapon.projectiles_per_activation <= 0
		):
			push_error("Battle weapons require positive intervals, ranges, damage and projectile counts.")
			return false
	return true


func _create_combatant(stats: ShipStats) -> Combatant:
	var ship := Combatant.new()
	ship.stats = stats
	ship.integrity = stats.integrity
	ship.shields = stats.shields
	_refresh_mobility(ship)
	ship.target_refresh_remaining = 0.0
	ship.flyby_side = -1.0 if random.randf() < 0.5 else 1.0
	for weapon in stats.weapons:
		ship.cooldowns.append(0.0)
	return ship


func _refresh_mobility(ship: Combatant) -> void:
	ship.speed = maxf(ship.stats.thrust, 0.0) * SPEED_PER_THRUST
	if ship.speed <= 0.0:
		ship.acceleration = 0.0
		ship.turn_rate = MIN_TURN_RATE
		return
	var thrust_to_weight := ship.stats.thrust / maxf(ship.stats.weight, 1.0)
	var acceleration_factor := clampf(0.75 + thrust_to_weight * 0.06, 0.8, 1.8)
	ship.acceleration = ship.speed * acceleration_factor
	ship.turn_rate = clampf(
		MIN_TURN_RATE + thrust_to_weight * 0.1,
		MIN_TURN_RATE,
		MAX_TURN_RATE
	)


func advance(delta: float) -> void:
	for member in _members:
		member.previous_position = member.position
		member.previous_heading = member.heading
	for projectile in projectiles:
		projectile.previous_position = projectile.position
	elapsed += delta
	_update_shield_flashes(delta)
	_update_wrecks(delta)
	for index in range(beams.size() - 1, -1, -1):
		beams[index].lifetime -= delta
		if beams[index].lifetime <= 0.0:
			beams.remove_at(index)
	for index in range(explosions.size() - 1, -1, -1):
		explosions[index].lifetime -= delta
		if explosions[index].lifetime <= 0.0:
			explosions.remove_at(index)
	if phase == Phase.COMBAT:
		_combat_elapsed += delta
		_apply_pending_commands()
		var previous_phase := phase
		_damage_this_step = false
		_rebuild_pending_projectile_damage()
		_rebuild_spatial_index()
		for index in range(_members.size()):
			_previous_velocities[index] = _members[index].velocity
		var resolving_victory := objective_complete()
		for player_ship in players:
			if player_ship.is_alive():
				_update_ship(player_ship, delta, not resolving_victory)
		for alien in aliens:
			if alien.is_alive():
				_update_ship(alien, delta, not resolving_victory)
		for entity in other_entities:
			if entity.is_alive() and entity.has_tag("combatant"):
				_update_ship(entity, delta, not resolving_victory)
		_update_projectiles(delta)
		var accelerating := false
		for index in range(_members.size()):
			if _members[index].is_alive() and _members[index].velocity.distance_to(_previous_velocities[index]) > 0.01 * delta:
				accelerating = true
		inactive_seconds = 0.0 if _damage_this_step or accelerating else inactive_seconds + delta
		if withdrawing:
			retreat_remaining -= delta
		if living_player_count() == 0:
			phase = Phase.DEFEAT
		elif withdrawing and retreat_remaining <= 0.0:
			phase = Phase.WITHDRAWN
		elif objective_complete() and not _victory_projectiles_pending():
			_collect_all_salvage()
			phase = Phase.VICTORY
		elif inactive_seconds >= 10.0:
			phase = Phase.WITHDRAWN
		if phase != previous_phase:
			_record_event("objective", {"phase": phase, "remaining": _remaining_target_ids(),
				"materials": collected_categories.duplicate()})
		tick_index += 1


func _victory_projectiles_pending() -> bool:
	for projectile in projectiles:
		if projectile.target == null or not projectile.target.is_alive():
			continue
		if projectile.target.faction == Faction.PLAYER or objective_target_ids.has(projectile.target.entity_id):
			return true
		if destroy_all_neutral_targets and _neutral_cleanup_target(projectile.target):
			return true
	return false


func _update_wrecks(delta: float) -> void:
	for member in _members:
		if member.is_alive() or member.wreck_motion_remaining <= 0.0:
			continue
		member.wreck_motion_remaining = maxf(member.wreck_motion_remaining - delta, 0.0)
		member.position += member.velocity * delta
		member.heading = wrapf(
			member.heading + member.wreck_angular_velocity * delta,
			-PI,
			PI
		)
		if member.wreck_motion_remaining <= 0.0:
			member.velocity = Vector2.ZERO
			member.wreck_angular_velocity = 0.0


func _update_shield_flashes(delta: float) -> void:
	for member in _members:
		member.shield_flash = maxf(0.0, member.shield_flash - delta)


func living_alien_count() -> int:
	var count := 0
	for alien in _members:
		if alien.faction == Faction.ALIEN and alien.has_tag("combatant") and alien.is_alive():
			count += 1
	return count


func living_player_count() -> int:
	var count := 0
	for player_ship in players:
		if player_ship.is_alive() and not player_ship.has_tag("summon") and not player_ship.has_tag("decoy"):
			count += 1
	return count


func _choose_target(ship: Combatant) -> Combatant:
	if _spatial_cells.is_empty():
		return _choose_target_linear(ship)
	var best: Combatant
	var best_score := INF
	var fallback: Combatant
	var fallback_score := INF
	var center_cell := _spatial_cell(ship.position)
	var maximum_ring := ceili(ARENA_RADIUS * 2.0 / SPATIAL_CELL_SIZE) + 1
	for ring in range(maximum_ring + 1):
		best = null
		fallback = null
		best_score = INF
		fallback_score = INF
		for cell_x in range(center_cell.x - ring, center_cell.x + ring + 1):
			for cell_y in range(center_cell.y - ring, center_cell.y + ring + 1):
				if ring > 0 and abs(cell_x - center_cell.x) != ring and abs(cell_y - center_cell.y) != ring:
					continue
				var occupants: Array = _spatial_cells.get(Vector2i(cell_x, cell_y), [])
				for enemy: Combatant in occupants:
					if not _auto_candidate(ship, enemy):
						continue
					var score := enemy.integrity + enemy.shields
					if score < fallback_score:
						fallback = enemy
						fallback_score = score
					if _pending_projectile_damage(enemy) >= score:
						continue
					if score < best_score:
						best = enemy
						best_score = score
		if best != null or fallback != null:
			return best if best != null else fallback
	return null


func _choose_target_linear(ship: Combatant) -> Combatant:
	var enemies: Array[Combatant] = _members
	var best: Combatant
	var best_score := INF
	var fallback: Combatant
	var fallback_score := INF
	for enemy in enemies:
		if not _auto_candidate(ship, enemy):
			continue
		var score := enemy.integrity + enemy.shields
		if score < fallback_score:
			fallback = enemy
			fallback_score = score
		if _pending_projectile_damage(enemy) < score and score < best_score:
			best = enemy
			best_score = score
	return best if best != null else fallback


func _choose_weapon_target(
	ship: Combatant,
	weapon_origin: Vector2,
	weapon_range: float
) -> Combatant:
	var ordered := ship.commanded_target
	if ordered != null and can_attack(ship, ordered):
		if weapon_origin.distance_squared_to(ordered.position) <= weapon_range * weapon_range \
			and _pending_projectile_damage(ordered) < ordered.integrity + ordered.shields:
			return ordered
		return null
	var current := ship.target
	var range_squared := weapon_range * weapon_range
	if (
		current != null
		and _auto_candidate(ship, current)
		and weapon_origin.distance_squared_to(current.position) <= range_squared
		and _pending_projectile_damage(current) < current.integrity + current.shields
	):
		return current
	if _spatial_cells.is_empty():
		var enemies: Array[Combatant] = _members
		var fallback_best: Combatant
		var fallback_score := INF
		for enemy in enemies:
			if (
				not _auto_candidate(ship, enemy)
				or weapon_origin.distance_squared_to(enemy.position) > range_squared
			):
				continue
			var score := enemy.integrity + enemy.shields
			if _pending_projectile_damage(enemy) < score and score < fallback_score:
				fallback_best = enemy
				fallback_score = score
		return fallback_best
	var best: Combatant
	var best_score := INF
	var cell_radius := ceili(weapon_range / SPATIAL_CELL_SIZE)
	var center_cell := _spatial_cell(weapon_origin)
	for cell_x in range(center_cell.x - cell_radius, center_cell.x + cell_radius + 1):
		for cell_y in range(center_cell.y - cell_radius, center_cell.y + cell_radius + 1):
			var occupants: Array = _spatial_cells.get(Vector2i(cell_x, cell_y), [])
			for enemy: Combatant in occupants:
				if (
					not _auto_candidate(ship, enemy)
					or weapon_origin.distance_squared_to(enemy.position) > range_squared
				):
					continue
				var score := enemy.integrity + enemy.shields
				if _pending_projectile_damage(enemy) >= score:
					continue
				if score < best_score:
					best = enemy
					best_score = score
	return best


func _spatial_cell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / SPATIAL_CELL_SIZE), floori(position.y / SPATIAL_CELL_SIZE))


func _rebuild_spatial_index() -> void:
	_spatial_cells.clear()
	for member in _members:
		if not member.is_alive():
			continue
		var cell := _spatial_cell(member.position)
		if not _spatial_cells.has(cell):
			_spatial_cells[cell] = []
		(_spatial_cells[cell] as Array).append(member)


func _pending_projectile_damage(target: Combatant) -> float:
	return float(_pending_damage_by_target.get(target, 0.0))


func _rebuild_pending_projectile_damage() -> void:
	_pending_damage_by_target.clear()
	for projectile in projectiles:
		_add_pending_damage(projectile.target, projectile.damage)


func _add_pending_damage(target: Combatant, amount: float) -> void:
	if target == null:
		return
	_pending_damage_by_target[target] = maxf(
		float(_pending_damage_by_target.get(target, 0.0)) + amount,
		0.0
	)


func _update_ship(ship: Combatant, delta: float, allow_weapons := true) -> void:
	if not ship.is_alive():
		return
	ship.since_damage += delta
	ship.retreat_time = maxf(0.0, ship.retreat_time - delta)
	ship.retreat_cooldown = maxf(0.0, ship.retreat_cooldown - delta)
	if ship.since_damage > 2.5:
		ship.shields = minf(ship.stats.shields, ship.shields + ship.stats.shields * 0.12 * delta)
	if ship.stats.shields > 0.0 and ship.shields <= ship.stats.shields * 0.2:
		if ship.retreat_cooldown <= 0.0:
			ship.retreat_time = 2.5
			ship.retreat_cooldown = 9.0
	ship.target_refresh_remaining -= delta
	if ship.commanded_target != null and not can_attack(ship, ship.commanded_target):
		ship.commanded_target = null
	if ship.commanded_target != null:
		ship.target = ship.commanded_target
	elif ship.target != null and not _auto_candidate(ship, ship.target):
		ship.target = null
		ship.target_refresh_remaining = random.randf_range(0.0, TARGET_REFRESH_INTERVAL)
	if ship.target == null and ship.target_refresh_remaining <= 0.0:
		ship.target = _choose_target(ship)
		ship.target_refresh_remaining = TARGET_REFRESH_INTERVAL
	if ship.target == null:
		ship.thruster_activation_elapsed = 0.0
		_apply_passive_drag(ship, delta)
		ship.position += ship.velocity * delta
		return
	ship.thruster_activation_elapsed += delta
	var offset := ship.target.position - ship.position
	var distance := offset.length()
	var direction := (
		offset / distance if distance > 0.001 else Vector2.from_angle(ship.heading)
	)
	var steering_direction := _flyby_direction(ship, ship.target)
	if ship.retreat_time > 0.0:
		steering_direction = -direction
	var desired := steering_direction * ship.speed
	var ship_cell := _spatial_cell(ship.position)
	for cell_x in range(ship_cell.x - 1, ship_cell.x + 2):
		for cell_y in range(ship_cell.y - 1, ship_cell.y + 2):
			var occupants: Array = _spatial_cells.get(Vector2i(cell_x, cell_y), [])
			for other: Combatant in occupants:
				if other == ship or not other.is_alive():
					continue
				var separation := ship.position - other.position
				var clearance := ship.radius + other.radius + 12.0
				var distance_squared := separation.length_squared()
				if distance_squared >= clearance * clearance:
					continue
				var separation_distance := sqrt(distance_squared)
				if separation.is_zero_approx():
					separation = Vector2.UP
					separation_distance = 1.0
				desired += separation / separation_distance * ship.speed * (1.0 - separation_distance / clearance)
	var distance_from_center := ship.position.length()
	if distance_from_center > ARENA_RADIUS - SOFT_BOUNDARY_MARGIN:
		var boundary_progress := clampf(
			(distance_from_center - (ARENA_RADIUS - SOFT_BOUNDARY_MARGIN))
			/ SOFT_BOUNDARY_MARGIN,
			0.0,
			1.5
		)
		desired -= (
			ship.position.normalized() * ship.speed * (0.5 + boundary_progress * 2.0)
		)
	if withdrawing and ship.is_player:
		direction = -direction
		desired = direction * ship.speed
	var desired_velocity := desired.limit_length(ship.speed)
	var desired_heading := direction.angle()
	if desired_velocity.length_squared() > 0.01:
		desired_heading = desired_velocity.angle()
	ship.heading = rotate_toward(ship.heading, desired_heading, delta * ship.turn_rate)
	# Ships have forward thrust only. They shed speed through passive drag rather
	# than braking, so reversals and course corrections form broad flight arcs.
	var forward := Vector2.from_angle(ship.heading)
	_apply_passive_drag(ship, delta)
	if ship.retreat_time <= 0.0 and not (withdrawing and ship.is_player):
		_apply_limited_reverse_thrust(ship, desired_velocity, delta)
	ship.velocity += forward * ship.acceleration * delta
	ship.velocity = ship.velocity.limit_length(ship.speed)
	ship.position += ship.velocity * delta
	if not allow_weapons:
		return
	for index in range(ship.stats.weapons.size()):
		var weapon := ship.stats.weapons[index]
		if ship.owned_ship != null and ship.owned_ship.units[weapon.component_index].hp <= 0.0:
			continue
		ship.cooldowns[index] = maxf(0.0, ship.cooldowns[index] - delta)
		if ship.cooldowns[index] > 0.0:
			continue
		var weapon_origin := _get_weapon_origin(ship, weapon)
		var weapon_target := _choose_weapon_target(ship, weapon_origin, weapon.range_units)
		if weapon_target == null:
			continue
		ship.target = weapon_target
		ship.cooldowns[index] = weapon.fire_interval_seconds
		_record_event("expenditure", {"source": ship.entity_id, "weapon_index": index,
			"weapon": weapon.weapon_name, "cooldown": ship.cooldowns[index], "target": weapon_target.entity_id})
		for shot_index in range(weapon.projectiles_per_activation):
			ship.target = _choose_weapon_target(ship, weapon_origin, weapon.range_units)
			if ship.target == null:
				break
			if shot_index == 0:
				weapon_fired.emit()
			if ship.is_player and not weapon.is_projectile_weapon:
				var beam := Beam.new()
				beam.source = ship
				beam.origin_position = weapon_origin
				beam.target = ship.target
				beams.append(beam)
				_damage(ship.target, weapon.damage_per_shot, weapon_origin, ship, weapon.weapon_name)
			else:
				var projectile := Projectile.new()
				projectile.source = ship
				projectile.origin = weapon_origin
				projectile.weapon_name = weapon.weapon_name
				projectile.position = weapon_origin
				projectile.previous_position = weapon_origin
				projectile.target = ship.target
				projectile.damage = weapon.damage_per_shot
				projectile.is_player = ship.is_player
				projectiles.append(projectile)
				_add_pending_damage(projectile.target, projectile.damage)


func _apply_passive_drag(ship: Combatant, delta: float) -> void:
	ship.velocity *= exp(-PASSIVE_DRAG_PER_SECOND * delta)


func _flyby_direction(ship: Combatant, target: Combatant) -> Vector2:
	var relative_target := target.position - ship.position
	var distance := relative_target.length()
	if distance <= 0.001:
		return Vector2.from_angle(ship.heading)
	var radial_direction := relative_target / distance
	var pass_distance := maxf(
		ship.shortest_range() * FLYBY_RANGE_FACTOR,
		ship.radius + target.radius + FLYBY_MIN_CLEARANCE
	)
	var tangent := radial_direction.orthogonal() * ship.flyby_side
	if distance > pass_distance:
		# Aim along a tangent to the minimum-range circle. This approaches the
		# enemy without using its center as a collision-course waypoint.
		var lateral_ratio := clampf(pass_distance / distance, 0.0, 1.0)
		var forward_ratio := sqrt(maxf(1.0 - lateral_ratio * lateral_ratio, 0.0))
		return (radial_direction * forward_ratio + tangent * lateral_ratio).normalized()
	# Once inside the intended pass radius, keep crossing the target's flank and
	# add a gradual outward correction instead of stopping in weapon range.
	var outward_strength := clampf((pass_distance - distance) / pass_distance, 0.0, 1.0)
	return (tangent - radial_direction * outward_strength).normalized()


func _apply_limited_reverse_thrust(
	ship: Combatant,
	desired_velocity: Vector2,
	delta: float
) -> void:
	var current_speed := ship.velocity.length()
	if current_speed <= 0.001 or desired_velocity.length_squared() <= 0.001:
		return
	var alignment := ship.velocity.normalized().dot(desired_velocity.normalized())
	if alignment >= REVERSE_THRUST_ALIGNMENT_START:
		return
	var braking_ratio := clampf(
		(REVERSE_THRUST_ALIGNMENT_START - alignment)
		/ (REVERSE_THRUST_ALIGNMENT_START + 1.0),
		0.0,
		1.0
	)
	var braking_speed := ship.acceleration * REVERSE_THRUST_FACTOR * braking_ratio * delta
	ship.velocity = ship.velocity.normalized() * maxf(current_speed - braking_speed, 0.0)


func _get_weapon_origin(ship: Combatant, weapon: ShipWeaponStats) -> Vector2:
	return ship.position + weapon.mount_offset.rotated(ship.heading)


func _update_projectiles(delta: float) -> void:
	for index in range(projectiles.size() - 1, -1, -1):
		var projectile := projectiles[index]
		var destination := projectile.target.position
		projectile.position = projectile.position.move_toward(destination, PROJECTILE_SPEED * delta)
		if projectile.position.distance_to(destination) <= projectile.target.radius:
			_add_pending_damage(projectile.target, -projectile.damage)
			_damage(projectile.target, projectile.damage, projectile.origin, projectile.source, projectile.weapon_name)
			projectiles.remove_at(index)


func get_finishing_projectile(maximum_time_to_impact := INF) -> Projectile:
	var target: Combatant
	var attacking_players := false
	var required := remaining_victory_targets()
	if required.size() == 1:
		target = required[0]
		attacking_players = true
	elif living_player_count() == 1:
		for player_ship in players:
			if player_ship.is_alive():
				target = player_ship
				break
	else:
		return null
	var incoming: Array[Projectile] = []
	for projectile in projectiles:
		if (
			projectile.target == target
			and projectile.is_player == attacking_players
		):
			incoming.append(projectile)
	incoming.sort_custom(func(left: Projectile, right: Projectile) -> bool:
		return left.position.distance_squared_to(target.position) < right.position.distance_squared_to(target.position))
	var committed_damage := 0.0
	for projectile in incoming:
		committed_damage += projectile.damage
		if committed_damage < target.integrity + target.shields:
			continue
		var time_to_impact := maxf(
			projectile.position.distance_to(target.position) - target.radius,
			0.0
		) / PROJECTILE_SPEED
		return projectile if time_to_impact <= maximum_time_to_impact else null
	return null


func _damage(target: Combatant, damage: float, origin: Vector2 = Vector2.ZERO, source: Combatant = null, weapon_name: String = "") -> void:
	if not target.is_alive() or not target.targetable or target.has_tag("drop") or not is_finite(damage) or damage <= 0.0:
		return
	var absorbed := minf(target.shields, damage)
	target.shields -= absorbed
	target.shield_damage_taken += absorbed
	var actual := absorbed
	if target.owned_ship != null and damage > absorbed:
		var owned := target.owned_ship
		var local_origin := (origin - target.position).rotated(-target.heading)
		var cell := owned.hit_cell(local_origin, random)
		var result := owned.damage_cell(cell, damage - absorbed)
		actual += result.damage
		target.permanent_damage_taken += result.removed.size()
		for removed_cell in result.removed:
			if random.randf() < allied_drop_chance:
				var drop := Drop.new()
				drop.entity_id = "%s/wreck/%d/%d" % [target.entity_id, removed_cell.x, removed_cell.y]
				drop.category = owned.design.tiles[removed_cell]
				drop.position = target.position + owned.local_cell_position(removed_cell).rotated(target.heading)
				drop.size = owned.cell_size
				drops.append(drop)
		var remaining := owned.get_stats(laser_upgrade_level)
		target.integrity = remaining.integrity if owned.is_alive() else 0.0
		target.stats.shields = remaining.shields
		target.stats.thrust = remaining.thrust
		target.shields = minf(target.shields, remaining.shields)
		_refresh_mobility(target)
	else:
		var hull_damage := minf(target.integrity, damage - absorbed)
		target.integrity -= hull_damage
		actual += hull_damage
	if actual > 0.0:
		_damage_this_step = true
	target.damage_taken += actual
	if source != null:
		source.damage_dealt += actual
		source.weapon_damage[weapon_name] = source.weapon_damage.get(weapon_name, 0.0) + actual
	target.since_damage = 0.0
	if absorbed > 0.0:
		target.shield_flash = 0.2
		shield_hit.emit()
	if target.is_alive():
		return
	var component_hp: Array = []
	if target.owned_ship != null:
		for unit in target.owned_ship.units:
			component_hp.append(unit.hp)
	_record_event("destruction", {"target": target.entity_id, "source": source.entity_id if source != null else "",
		"integrity": target.integrity, "shields": target.shields, "component_hp": component_hp,
		"remaining_objectives": _remaining_target_ids()})
	if target.velocity.length_squared() < 1.0:
		target.velocity = Vector2.from_angle(random.randf_range(0.0, TAU)) * random.randf_range(8.0, 20.0)
	target.wreck_angular_velocity = random.randf_range(-0.45, 0.45)
	target.wreck_motion_remaining = WRECK_MOTION_SECONDS
	if absf(target.wreck_angular_velocity) < 0.12:
		target.wreck_angular_velocity = 0.12 if target.wreck_angular_velocity >= 0.0 else -0.12
	var explosion := Explosion.new()
	explosion.position = target.position
	explosions.append(explosion)
	if target.has_tag("combatant"):
		ship_destroyed.emit(target.is_player)
	if target.faction == Faction.ALIEN and target.has_tag("combatant") and not target.has_tag("summon") \
		and not target.has_tag("decoy") and not target.has_tag("hazard") and random.randf() < DROP_CHANCE:
		var drop := Drop.new()
		drop.entity_id = target.entity_id + "/salvage"
		drop.position = target.position
		var roll := random.randf()
		if roll < 0.60:
			drop.category = ShipPart.Category.DEFENSE
		elif roll < 0.84:
			drop.category = ShipPart.Category.OFFENSE
		elif roll < 0.96:
			drop.category = ShipPart.Category.SPECIAL
		else:
			drop.category = ShipPart.Category.CORE
		drops.append(drop)


func _collect_all_salvage() -> void:
	# A frozen encounter pays its declared material bundle, independent of kill
	# order/RNG. Ad-hoc simulation fixtures retain their existing drop behavior.
	if not victory_materials.is_empty():
		collected_categories.assign(victory_materials)
		for drop in drops:
			drop.collected = true
		return
	for drop in drops:
		if drop.collected:
			continue
		drop.collected = true
		collected_categories.append(drop.category)


func get_living_player() -> Combatant:
	if player != null and player.is_alive():
		return player
	for player_ship in players:
		if player_ship.is_alive():
			return player_ship
	return null


func request_withdrawal() -> void:
	if phase == Phase.COMBAT and not withdrawing:
		withdrawing = true
		retreat_remaining = 10.0
