class_name BattleSimulation
extends RefCounted

const PROJECTILE_SPEED := 640.0
const Collision = preload("res://scripts/sprite_collision.gd")
const TARGET_REFRESH_INTERVAL := 0.2
const SPATIAL_CELL_SIZE := 256.0
const SEPARATION_CELL_SIZE := 64.0
const EMPTY_CELL := []
const WRECK_MOTION_SECONDS := 4.0
const MAX_LIVE_COMBATANTS := 192

signal weapon_fired
signal shield_hit
signal ship_destroyed(is_player: bool)
signal projectile_impacted(position: Vector2)

enum Phase { COMBAT, VICTORY, DEFEAT, WITHDRAWN }
enum Faction { PLAYER, ALIEN, NEUTRAL }

const ARENA_RADIUS := 2400.0
const DROP_CHANCE := 0.6
const MIN_TURN_RATE := ShipStats.MIN_TURN_RATE
const MAX_TURN_RATE := ShipStats.MAX_TURN_RATE
const PASSIVE_DRAG_PER_SECOND := 0.06
const REVERSE_THRUST_FACTOR := 0.22
const REVERSE_THRUST_ALIGNMENT_START := 0.35
const FLYBY_MIN_CLEARANCE := 12.0
const FLYBY_RANGE_FACTOR := 0.70
const SOFT_BOUNDARY_MARGIN := 540.0
const PLAYER_FORMATION_CENTER := Vector2(-1260.0, 0.0)
const PLAYER_FORMATION_COLUMNS := 3
const PLAYER_FORMATION_SPACING := Vector2(78.0, 78.0)
const ALIEN_FORMATION_CENTER := Vector2(1260.0, 0.0)
const ALIEN_FORMATION_SPACING := 36.0
const DEPLOYMENT_SCALE := 130.0
const WAVE_ENTRY_X := 1860.0
const CORRIDOR_HALF_WIDTH := 720.0
const CORRIDOR_INNER_WIDTH := 420.0

static func deployment_area(plan: Dictionary) -> Rect2:
	return Rect2(Vector2(-1910, -420), Vector2(1300, 840)) if plan.get("arena_layout", "open") == "corridor" \
		else Rect2(Vector2(-1910, -520), Vector2(1300, 1040))

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
	var weapon_search_remaining: Dictionary = {}
	var indexed_cell := Vector2i.ZERO
	var member_order := 0
	var squadron_id := ""
	var support_parts: Dictionary = {}
	var support_parts_ready := false
	var cached_lab_index := -1
	var support_active := false
	var flyby_side := 1.0
	var thruster_activation_elapsed := 0.0
	var analysis_target_id := ""
	var analysis_remaining := 0.0
	var repaired_hp := 0.0
	var resource_contents: Dictionary = {}
	var sortie_ammo := -1 # -1: ordinary weapons; finite carrier-craft activations.
	var carrier_source_id := ""

	func is_alive() -> bool:
		return owned_ship.is_alive() if owned_ship != null and owned_ship.is_slot_ship() else integrity > 0.0

	func has_tag(tag: String) -> bool:
		return tags.get(tag, false)

	func damage_deflected() -> float:
		var result := shield_damage_taken
		if owned_ship == null or owned_ship is HangarShip:
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
	var interceptable := false
	var speed := PROJECTILE_SPEED
	var aim_position := Vector2.ZERO
	var aim_radius := 18.0
	var guidance_lost := false
	var rotation_phase := 0.0
	var splinter := false
	var fragment := false
	var hull_damage_multiplier := 1.0

class Beam:
	var source: Combatant
	var weapon_name := ""
	var origin_position := Vector2.ZERO
	var target: Combatant
	var aim_position := Vector2.ZERO
	var lifetime := 0.16
	var prismatic := false
	var intensity := 1.0

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
var visibility_enabled := false
var visibility = preload("res://scripts/battle_visibility.gd").new()
var abilities = preload("res://scripts/battle_abilities.gd").new()
var asteroid_field = preload("res://scripts/asteroid_field.gd").new()
var environment: Dictionary = {}
var mining_enabled := false
var credits_only := false
var initial_missiles := -1
var missile_supply := -1
var mining_materials: Array[int] = []
var encounter = preload("res://scripts/battle_encounter.gd").new()
var enemy_roles = preload("res://scripts/enemy_roles.gd").new()
var ability_commit := Callable()
var energy_efficiency := 0.0
var research_combat := ResearchCombat.new()
var doctrines := CombatDoctrines.new()
var repair_reserves: Dictionary = {}
var repair_capacity := 0
var repair_spent := 0.0
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
var swarm_damage_dealt := 0.0
var random := RandomNumberGenerator.new()
var allied_drop_chance := 0.3
var laser_upgrade_level := 0
var withdrawing := false
var retreat_remaining := 10.0
var inactive_seconds := 0.0
var undamaged_seconds := 0.0
const STALEMATE_SECONDS := 30.0
# Long grinds disengage so a demo fight never outlasts a few minutes.
const MAX_ENGAGEMENT_SECONDS := 180.0
var _damage_this_step := false
var _members: Array[Combatant] = []
var _previous_velocities: Array[Vector2] = []
var _pending_damage_by_target: Dictionary = {}
var _spatial_cells: Dictionary = {}
var _separation_cells: Dictionary = {}
var _separation_radius := 0.0
var _separation_motion := 0.0
var _flocks: Dictionary = {}
var battle_id := "battle"
var tick_index := 0
var _combat_elapsed := 0.0
var command_log: Array[Dictionary] = []
var event_log: Array[Dictionary] = []
var _command_receipts: Dictionary = {}
var _pending_commands: Array[Dictionary] = []
var _next_command_id := 0
var _next_projectile_id := 0


func setup(
	player_stats: ShipStats,
	fleet: Array[RefCounted],
	seed_value: int = -1,
	player_ship_count: int = 1,
	allow_unarmed_player := false
) -> bool:
	if player_ship_count <= 0:
		push_error("Battle requires at least one player ship.")
		return false
	if player_ship_count + fleet.size() > MAX_LIVE_COMBATANTS:
		return false
	if not _validate_stats(player_stats, allow_unarmed_player) or fleet.is_empty():
		push_error("Battle requires an armed player ship and a nonempty alien fleet.")
		return false
	if seed_value >= 0:
		random.seed = seed_value
	else:
		random.randomize()
	withdrawing = false
	initial_missiles = -1
	missile_supply = -1
	energy_efficiency = 0.0
	research_combat.configure({})
	doctrines = CombatDoctrines.new()
	repair_reserves.clear()
	repair_capacity = 0
	repair_spent = 0.0
	battle_id = "seed/%d" % random.seed
	tick_index = 0
	_combat_elapsed = 0.0
	command_log.clear()
	event_log.clear()
	_command_receipts.clear()
	_pending_commands.clear()
	_next_command_id = 0
	_next_projectile_id = 0
	retreat_remaining = 10.0
	inactive_seconds = 0.0
	undamaged_seconds = 0.0
	phase = Phase.COMBAT
	elapsed = 0.0
	swarm_damage_dealt = 0.0
	visibility_enabled = false
	visibility.reset()
	abilities.configure({})
	asteroid_field = preload("res://scripts/asteroid_field.gd").new()
	environment = {}
	mining_enabled = false
	mining_materials.clear()
	encounter.configure(self, {})
	enemy_roles.configure(self, false)
	ability_commit = Callable()
	players.clear()
	aliens.clear()
	other_entities.clear()
	_spatial_cells.clear()
	_separation_cells.clear()
	_flocks.clear()
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
	var alien_positions := alien_formation_positions(fleet, ALIEN_FORMATION_CENTER)
	if alien_positions.size() != fleet.size():
		return false
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
		alien.position = alien_positions[index]
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
		member.squadron_id = ""
		if member.owned_ship is HangarShip and member.owned_ship.squadron_id > 0:
			member.squadron_id = "player/squadron/%d" % member.owned_ship.squadron_id
		elif member.alien != null and member.alien.entity_kind == "ship" \
				and member.alien.role_id not in ["warden", "pylon"]:
			member.squadron_id = "alien/squadron/%s/%d/%d" % [member.alien.role_id, member.alien.tier, member.alien.wave_index]
	_previous_velocities.resize(_members.size())

func living_combatant_count() -> int:
	var count := 0
	for member in _members:
		if member.is_alive() and member.has_tag("combatant"):
			count += 1
	return count


func setup_owned(ships: Array[FleetShip], fleet: Array[RefCounted], salvage_chance: float, upgrade_level: int, seed_value: int = -1, shared_context: Dictionary = {}) -> bool:
	if not ResearchCombat.valid(shared_context.get("research_effects", {})):
		push_error("Cannot configure battle with invalid research effects.")
		return false
	if shared_context.has("missiles") and (not SaveValidation.integer(shared_context.missiles) \
			or shared_context.missiles < 0 or shared_context.missiles > 2147483647):
		push_error("Cannot configure battle with invalid missile supply.")
		return false
	if shared_context.has("environment") and not NodeEnvironment.valid(shared_context.environment):
		push_error("Cannot configure battle with invalid node conditions.")
		return false
	if not abilities.configure(shared_context):
		return false
	if not shared_context.get("visibility_enabled", false) is bool:
		return false
	if not SharedSupport.valid_reserves(shared_context.get("repair_reserves", {})):
		return false
	if not SharedSupport.valid_pool(shared_context.get("repair_pool", {"capacity": 0, "spent": 0.0})):
		return false
	var requested: Variant = shared_context.get("energy_efficiency", 0.0)
	if not (requested is float or requested is int) or not is_finite(requested) or requested < 0 or requested > 0.3:
		return false
	var requested_energy := float(requested)
	if ships.is_empty():
		return false
	for owned in ships:
		if owned == null:
			return false
	# Use an armed member for legacy setup validation; disabled weapons may remain
	# aboard other surviving ships in the deployment.
	var armed: FleetShip
	for owned in ships:
		if not owned.get_stats(upgrade_level, requested_energy).weapons.is_empty() or HangarCarriers.has_bay(owned):
			armed = owned
	if armed == null:
		return false
	var bootstrap_stats := armed.get_stats(upgrade_level, requested_energy)
	if armed.is_slot_ship() and armed.is_alive():
		bootstrap_stats.integrity = maxf(bootstrap_stats.integrity, 0.00001)
	if not setup(bootstrap_stats, fleet, seed_value, ships.size(), HangarCarriers.has_bay(armed)):
		return false
	energy_efficiency = requested_energy
	research_combat.configure(shared_context.get("research_effects", {}))
	credits_only = shared_context.get("credits_only", false)
	initial_missiles = int(shared_context.get("missiles", -1))
	missile_supply = initial_missiles
	environment = shared_context.get("environment", {}).duplicate(true)
	repair_reserves = shared_context.get("repair_reserves", {}).duplicate(true)
	var pool: Dictionary = shared_context.get("repair_pool", {"capacity": 0, "spent": 0.0})
	repair_capacity = int(pool.capacity)
	repair_spent = float(pool.spent)
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
		member.stats = ships[index].get_stats(upgrade_level, energy_efficiency)
		member.integrity = member.stats.integrity
		member.shields = member.stats.shields
		member.radius = member.stats.collision_radius
		_refresh_mobility(member)
		member.cooldowns.clear()
		for weapon in member.stats.weapons:
			member.cooldowns.append(0.0)
			member.weapon_damage[weapon.weapon_name] = 0.0
		member.position = PLAYER_FORMATION_CENTER + (Vector2(ships[index].formation) - formation_center) * DEPLOYMENT_SCALE
		member.previous_position = member.position
	_rebuild_member_cache()
	SharedSupport.initialize(self)
	if not doctrines.configure(self, shared_context.get("doctrine_pool", {})):
		return false
	if not abilities.configure(shared_context):
		return false
	visibility_enabled = shared_context.get("visibility_enabled", false)
	mining_enabled = shared_context.has("mining_materials")
	if mining_enabled:
		if not AsteroidField.valid_policy({"rate": 0, "materials": shared_context.mining_materials}):
			return false
		for category in shared_context.mining_materials:
			mining_materials.append(int(category))
	if shared_context.has("asteroids"):
		if not shared_context.asteroids is Dictionary or not asteroid_field.configure(shared_context.asteroids, shared_context.get("extraction", {})):
			return false
		asteroid_field.attach(self)
	if not shared_context.get("enemy_roles", false) is bool:
		return false
	enemy_roles.configure(self, shared_context.get("enemy_roles", false))
	if not shared_context.get("encounter_plan", {}) is Dictionary or not encounter.configure(self, shared_context.get("encounter_plan", {})):
		return false
	refresh_visibility()
	return entities.size() == _members.size()


func register_entity(entity: Combatant) -> bool:
	if entity == null or entity.entity_id.is_empty() or entities.has(entity.entity_id):
		return false
	if entity.stats == null or not is_finite(entity.integrity) or entity.integrity <= 0.0:
		return false
	if entity.has_tag("combatant") and living_combatant_count() >= MAX_LIVE_COMBATANTS:
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
	_separation_cells.clear()
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
		if target == null and encounter.knows(id) and not next_ids.has(id):
			next_ids.append(id)
			continue
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
	if not encounter.pending.is_empty():
		return false
	if destroy_all_neutral_targets:
		for record: Dictionary in asteroid_field.records.values():
			if record.status == "pending":
				return false
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
		and source.faction != target.faction and (not visibility_enabled or team_can_see(source.faction, target))


func _hostile(source: Combatant, target: Combatant) -> bool:
	return (source.faction == Faction.PLAYER and target.faction == Faction.ALIEN) \
		or (source.faction == Faction.ALIEN and target.faction == Faction.PLAYER)


func _auto_candidate(source: Combatant, target: Combatant) -> bool:
	if source == null or target == null or source.faction == target.faction:
		return false
	if not can_attack(source, target) or not target.automatic_targetable:
		return false
	var ordered_source: Combatant = entities.get(source.carrier_source_id, source)
	if ordered_source.owned_ship is HangarShip and ordered_source.commanded_target == null:
		if ordered_source.owned_ship.stance == "evade":
			return false
		if ordered_source.owned_ship.stance == "defend" and target.position.distance_to(_flagship_position()) > 260.0:
			return false
	if mining_enabled and MiningRules.operational(source, MiningRules.TOOLS) and MiningRules.known_eligible(self, source, target):
		return true
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


func record_pickup_rejection(pickup: String) -> void:
	# External IO failure is replay input. Its command event is emitted at the
	# collection point, after movement/collisions, rather than before the tick.
	while _command_receipts.has("%s/command/%d" % [battle_id, _next_command_id]):
		_next_command_id += 1
	var command := {"id": "%s/command/%d" % [battle_id, _next_command_id], "tick": tick_index,
		"type": "pickup_rejection", "payload": {"pickup": pickup}}
	_next_command_id += 1
	command_log.append(command)
	_command_receipts[command.id] = {"fingerprint": _command_fingerprint(command), "status": "accepted"}
	_record_event("command", {"command_id": command.id, "accepted": true})


func _valid_command(command: Dictionary) -> bool:
	if command.has("persistence_rejected") and (not command.persistence_rejected is bool or command.get("type") not in ["ability_cast", "ability_auto", "ability_pause_aim"]):
		return false
	if not command.get("id") is String or command.id.is_empty() or not SaveValidation.integer(command.get("tick")):
		return false
	if command.tick < 0 or not command.get("payload") is Dictionary or not SaveValidation.json_value(command.payload):
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
		"ability_cast":
			return payload.get("ability") is String and payload.get("source", "") is String and SaveValidation.integer(payload.get("faction", 0)) and int(payload.get("faction", 0)) in [0, 1] \
				and payload.get("position") is Array and payload.position.size() == 2 \
				and SaveValidation.bounded_number(payload.position[0]) and SaveValidation.bounded_number(payload.position[1])
		"ability_auto":
			return payload.get("ability") is String and payload.get("enabled") is bool
		"ability_pause_aim":
			return payload.get("enabled") is bool
		"pickup_rejection":
			return payload.get("pickup") is String and not payload.pickup.is_empty()
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
	abilities.last_commit_failed = false
	if command.get("persistence_rejected", false):
		abilities.retry_delay = 1.0
		_command_receipts[command.id] = {"fingerprint": fingerprint, "status": "rejected"}
		_record_event("command", {"command_id": command.id, "accepted": false})
		return false
	match command.type:
		"pickup_rejection":
			asteroid_field.replayed_rejections[payload.pickup] = command.id
			_command_receipts[command.id] = {"fingerprint": fingerprint, "status": "accepted"}
			return true
		"attack":
			accepted = request_attack(payload.source, payload.target)
		"clear_attack":
			accepted = clear_attack_order(payload.source)
		"ability_cast":
			accepted = abilities.cast(self, payload.ability, Vector2(payload.position[0], payload.position[1]), payload.get("source", ""), int(payload.get("faction", 0)))
		"ability_auto":
			accepted = abilities.set_auto(self, payload.ability, payload.enabled)
		"ability_pause_aim":
			accepted = abilities.set_pause_aim(self, payload.enabled)
		"neutral_cleanup":
			accepted = set_destroy_all_neutral_targets(payload.enabled)
		"withdraw":
			accepted = phase == Phase.COMBAT and not withdrawing
			if accepted:
				request_withdrawal()
	if abilities.last_commit_failed:
		for recorded in command_log:
			if recorded.id == command.id:
				recorded["persistence_rejected"] = true
				break
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
		if member.owned_ship != null and not member.owned_ship is HangarShip:
			for unit in member.owned_ship.units:
				hp.append(unit.hp)
		actors.append({"id": member.entity_id, "faction": member.faction, "tags": member.tags.duplicate(),
			"slot_role": member.owned_ship.slot_role if member.owned_ship != null else "",
			"stance": member.owned_ship.stance if member.owned_ship is HangarShip else "seek",
			"squadron": member.owned_ship.squadron_id if member.owned_ship is HangarShip else 0,
			"analysis_target": member.analysis_target_id, "analysis_remaining": member.analysis_remaining, "repaired_hp": member.repaired_hp,
			"escort_target_id": member.owned_ship.escort_target_id if member.owned_ship != null else 0,
			"position": [member.position.x, member.position.y] if member.is_alive() else null,
			"velocity": [member.velocity.x, member.velocity.y] if member.is_alive() else null,
			"heading": member.heading if member.is_alive() else null, "integrity": member.integrity, "shields": member.shields,
			"cooldowns": member.cooldowns.duplicate(), "component_hp": hp,
			"weapon_search": member.weapon_search_remaining.duplicate(),
			"sortie_ammo": member.sortie_ammo, "carrier_source": member.carrier_source_id,
			"target": member.target.entity_id if member.target != null else "",
			"order": member.commanded_target.entity_id if member.commanded_target != null else "",
			"damage": member.damage_dealt, "taken": member.damage_taken,
			"retreat": member.retreat_time, "retreat_cooldown": member.retreat_cooldown,
			"since_damage": member.since_damage, "target_refresh": member.target_refresh_remaining})
	var shots: Array = []
	for shot in projectiles:
		shots.append({"source": shot.source.entity_id if shot.source != null else "",
			"target": shot.target.entity_id if shot.target != null else "", "damage": shot.damage,
			"position": [shot.position.x, shot.position.y], "origin": [shot.origin.x, shot.origin.y], "weapon": shot.weapon_name,
			"interceptable": shot.interceptable, "speed": shot.speed, "splinter": shot.splinter, "fragment": shot.fragment,
			"hull_damage_multiplier": shot.hull_damage_multiplier})
		if visibility_enabled:
			shots[-1]["aim"] = [shot.aim_position.x, shot.aim_position.y]
			shots[-1]["guidance_lost"] = shot.guidance_lost
	var salvage: Array = []
	for drop in drops:
		salvage.append({"id": drop.entity_id, "category": drop.category, "collected": drop.collected,
			"position": [drop.position.x, drop.position.y]})
	var result := {"battle_id": battle_id, "tick": tick_index, "phase": phase, "elapsed": _combat_elapsed,
		"swarm_damage": swarm_damage_dealt,
		"missiles": missile_supply,
		"research": research_combat.snapshot(),
		"repair_reserves": repair_reserves.duplicate(true), "energy_efficiency": energy_efficiency,
		"repair_pool": {"capacity": repair_capacity, "spent": repair_spent},
		"doctrines": doctrines.snapshot(),
		"rng_state": str(random.state), "actors": actors, "projectiles": shots, "drops": salvage,
		"objectives": objective_target_ids.duplicate(), "neutral_cleanup": destroy_all_neutral_targets,
		"remaining_targets": _remaining_target_ids(), "withdrawing": withdrawing,
		"retreat_remaining": retreat_remaining, "inactive": inactive_seconds,
		"materials": collected_categories.duplicate(), "pending_commands": _pending_commands.duplicate(true)}
	if visibility_enabled:
		result["visibility"] = visibility.diagnostic_snapshot()
	if visibility_enabled or not abilities.available.is_empty():
		result["ability_state"] = abilities.snapshot()
		result["enemy_cooldowns"] = abilities.enemy_cooldowns.duplicate()
		result["ability_retry_delay"] = abilities.retry_delay
		var effects: Array = []
		for effect: Dictionary in abilities.effects:
			var detached := effect.duplicate(true)
			detached.position = [effect.position.x, effect.position.y]
			effects.append(detached)
		result["ability_effects"] = effects
		result["resource_knowledge"] = {"0": abilities.resource_knowledge[0].duplicate(true), "1": abilities.resource_knowledge[1].duplicate(true)}
	if not asteroid_field.records.is_empty():
		asteroid_field.remember(self)
		result["asteroids"] = asteroid_field.snapshot()
		result["ore_retry"] = asteroid_field.retry_remaining
		result["ore_rejections"] = asteroid_field.replayed_rejections.duplicate()
	if not environment.is_empty():
		result["environment"] = environment.duplicate(true)
	if not encounter.plan.is_empty():
		result["encounter"] = encounter.snapshot()
	if enemy_roles.enabled:
		result["enemy_roles"] = enemy_roles.snapshot()
	return result


func _remaining_target_ids() -> Array[String]:
	var ids: Array[String] = []
	for target in remaining_victory_targets():
		ids.append(target.entity_id)
	return ids


static func alien_formation_positions(fleet: Array[RefCounted], center: Vector2) -> Array[Vector2]:
	var groups: Dictionary = {}
	for index in range(fleet.size()):
		var definition := fleet[index] as AlienShip
		if definition == null or definition.stats == null:
			push_error("Cannot arrange an invalid alien definition.")
			return []
		var key := "%s/%d/%d" % [definition.role_id, definition.tier, definition.wave_index] \
			if definition.entity_kind == "ship" and definition.role_id not in ["warden", "pylon"] else "entity/%d" % index
		if not groups.has(key):
			groups[key] = {"indices": [], "spacing": ALIEN_FORMATION_SPACING}
		groups[key].indices.append(index)
		groups[key].spacing = maxf(groups[key].spacing, definition.stats.collision_radius * 2 + 12)
	var height := 0.0
	for group: Dictionary in groups.values():
		var count: int = group.indices.size()
		group.height = ceili(float(count) / ceili(sqrt(count))) * group.spacing
		height += group.height + 48
	var y := -(height - 48) * 0.5
	var positions: Array[Vector2] = []
	positions.resize(fleet.size())
	for group: Dictionary in groups.values():
		for slot in range(group.indices.size()):
			positions[group.indices[slot]] = center + Vector2(0, y + group.height * 0.5) \
				+ HangarSquadrons.box_offset(slot, group.indices.size(), group.spacing)
		y += group.height + 48
	return positions

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


func _validate_stats(stats: ShipStats, allow_unarmed := false) -> bool:
	if stats == null or not is_finite(stats.integrity) or stats.integrity <= 0.0 or (stats.weapons.is_empty() and not allow_unarmed):
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
	ship.radius = stats.collision_radius
	_refresh_mobility(ship)
	ship.target_refresh_remaining = 0.0
	ship.flyby_side = -1.0 if random.randf() < 0.5 else 1.0
	for weapon in stats.weapons:
		ship.cooldowns.append(0.0)
	return ship


func _refresh_mobility(ship: Combatant) -> void:
	ship.speed = ship.stats.top_speed
	ship.acceleration = ship.stats.acceleration
	ship.turn_rate = ship.stats.turn_rate


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
		_damage_this_step = false
		encounter.advance(self, delta)
		doctrines.advance(self, delta)
		SharedSupport.repair(self, delta)
		enemy_roles.advance(self, delta)
		refresh_visibility()
		_apply_pending_commands()
		if visibility_enabled or not abilities.available.is_empty():
			abilities.auto_cast(self)
		abilities.advance(self, delta)
		refresh_visibility()
		_update_analysis(delta)
		_combat_elapsed += delta
		var previous_phase := phase
		encounter.warden.advance(self, delta)
		_rebuild_pending_projectile_damage()
		_rebuild_spatial_index(delta)
		research_combat.begin_step(self, delta)
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
		research_combat.end_step(self)
		asteroid_field.advance(self, delta)
		refresh_visibility()
		_update_projectiles(delta)
		asteroid_field._flush_fractures(self)
		refresh_visibility()
		if visibility_enabled:
			for member in _members:
				if member.target != null and not team_can_see(member.faction, member.target):
					member.target = null
				if member.commanded_target != null and not team_can_see(member.faction, member.commanded_target):
					member.commanded_target = null
		var accelerating := false
		for index in range(_members.size()):
			if _members[index].is_alive() and _members[index].velocity.distance_to(_previous_velocities[index]) > 0.01 * delta:
				accelerating = true
		inactive_seconds = 0.0 if _damage_this_step or accelerating else inactive_seconds + delta
		# Kiting with no hits at all is a stalemate even while ships keep moving.
		undamaged_seconds = 0.0 if _damage_this_step else undamaged_seconds + delta
		if withdrawing:
			retreat_remaining -= delta
		if living_player_count() == 0 or players.any(func(member: Combatant) -> bool: return member.owned_ship != null and member.owned_ship.is_flagship() and not member.is_alive()):
			phase = Phase.DEFEAT
		elif withdrawing and retreat_remaining <= 0.0:
			phase = Phase.WITHDRAWN
		elif objective_complete() and not _victory_projectiles_pending():
			_collect_all_salvage()
			phase = Phase.VICTORY
		elif (inactive_seconds >= 10.0 or undamaged_seconds >= STALEMATE_SECONDS or elapsed >= MAX_ENGAGEMENT_SECONDS) \
				and encounter.pending.is_empty():
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
				var occupants: Array = _spatial_cells.get(Vector2i(cell_x, cell_y), EMPTY_CELL)
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
	var first_cell := _spatial_cell(weapon_origin - Vector2.ONE * weapon_range)
	var last_cell := _spatial_cell(weapon_origin + Vector2.ONE * weapon_range)
	for cell_x in range(first_cell.x, last_cell.x + 1):
		for cell_y in range(first_cell.y, last_cell.y + 1):
			var occupants: Array = _spatial_cells.get(Vector2i(cell_x, cell_y), EMPTY_CELL)
			for enemy: Combatant in occupants:
				if (
					weapon_origin.distance_squared_to(enemy.position) > range_squared
					or not _auto_candidate(ship, enemy)
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


func _rebuild_spatial_index(delta := 1.0 / 30.0) -> void:
	_spatial_cells.clear()
	_separation_cells.clear()
	_flocks.clear()
	_separation_radius = 0.0
	_separation_motion = 0.0
	for member in _members:
		if not member.is_alive():
			continue
		var cell := _spatial_cell(member.position)
		member.indexed_cell = cell
		_separation_radius = maxf(_separation_radius, member.radius)
		_separation_motion = maxf(_separation_motion, maxf(member.speed, member.velocity.length()) * delta)
		if not _spatial_cells.has(cell):
			_spatial_cells[cell] = []
		(_spatial_cells[cell] as Array).append(member)
		var near_cell := Vector2i((member.position / SEPARATION_CELL_SIZE).floor())
		if not _separation_cells.has(near_cell):
			_separation_cells[near_cell] = []
		(_separation_cells[near_cell] as Array).append(member)
		var flock_key := _flock_key(member)
		if not flock_key.is_empty():
			if not _flocks.has(flock_key):
				_flocks[flock_key] = {"count": 0, "position": Vector2.ZERO, "velocity": Vector2.ZERO}
			var flock: Dictionary = _flocks[flock_key]
			flock.count += 1
			flock.position += member.position
			flock.velocity += member.velocity
	for index in range(_members.size()):
		_members[index].member_order = index

func _flock_key(ship: Combatant) -> String:
	if ship.squadron_id.is_empty() or not ship.is_alive() or ship.speed <= 0 \
			or ship.retreat_time > 0 or (withdrawing and ship.is_player) or encounter.warden.braced(ship):
		return ""
	var stance: String = ship.owned_ship.stance if ship.owned_ship is HangarShip else "seek"
	var order := ship.commanded_target.entity_id if ship.commanded_target != null else ""
	return "%d/%s/%s/%s" % [ship.faction, ship.squadron_id, stance, order]

func _flock_velocity(ship: Combatant, desired: Vector2) -> Vector2:
	var flock: Dictionary = _flocks.get(_flock_key(ship), {})
	if flock.is_empty() or flock.count < 2:
		return desired
	# Per-step aggregates avoid order-dependent steering and quadratic group scans.
	var center: Vector2 = flock.position / float(flock.count)
	var alignment: Vector2 = flock.velocity / float(flock.count)
	var cohesion := (center - ship.position).limit_length(ship.speed * 0.45)
	if not alignment.is_zero_approx():
		desired = desired.lerp(alignment.normalized() * desired.length(), 0.65)
	return (desired + cohesion).limit_length(ship.speed)

func _separation_velocity(ship: Combatant, desired: Vector2) -> Vector2:
	var extent := Vector2.ONE * (ship.radius + _separation_radius + 12 + _separation_motion)
	var first := Vector2i(((ship.position - extent) / SEPARATION_CELL_SIZE).floor())
	var last := Vector2i(((ship.position + extent) / SEPARATION_CELL_SIZE).floor())
	var original_cell := _spatial_cell(ship.position)
	var neighbors: Array[Combatant] = []
	for cell_x in range(first.x, last.x + 1):
		for cell_y in range(first.y, last.y + 1):
			for other: Combatant in _separation_cells.get(Vector2i(cell_x, cell_y), EMPTY_CELL):
				if other == ship or absi(other.indexed_cell.x - original_cell.x) > 1 or absi(other.indexed_cell.y - original_cell.y) > 1:
					continue
				var clearance := ship.radius + other.radius + 12.0
				if ship.position.distance_squared_to(other.position) < clearance * clearance and other.is_alive():
					neighbors.append(other)
	# Keep the original coarse-cell/insertion order, including floating-point sums.
	if neighbors.is_empty():
		return desired
	if neighbors.size() > 1:
		neighbors.sort_custom(_separation_less)
	for other in neighbors:
		var separation := ship.position - other.position
		var separation_distance := sqrt(separation.length_squared())
		if separation.is_zero_approx():
			separation = Vector2.UP
			separation_distance = 1.0
		var clearance := ship.radius + other.radius + 12.0
		desired += separation / separation_distance * ship.speed * (1.0 - separation_distance / clearance)
	return desired

static func _separation_less(a: Combatant, b: Combatant) -> bool:
	if a.indexed_cell.x != b.indexed_cell.x:
		return a.indexed_cell.x < b.indexed_cell.x
	if a.indexed_cell.y != b.indexed_cell.y:
		return a.indexed_cell.y < b.indexed_cell.y
	return a.member_order < b.member_order

func nearby_players(position: Vector2, radius: float) -> Array[Combatant]:
	if _separation_cells.is_empty():
		return players
	var result: Array[Combatant] = []
	var extent := Vector2.ONE * (radius + _separation_motion)
	var first := Vector2i(((position - extent) / SEPARATION_CELL_SIZE).floor())
	var last := Vector2i(((position + extent) / SEPARATION_CELL_SIZE).floor())
	for cell_x in range(first.x, last.x + 1):
		for cell_y in range(first.y, last.y + 1):
			for member: Combatant in _separation_cells.get(Vector2i(cell_x, cell_y), EMPTY_CELL):
				if member.faction == Faction.PLAYER and position.distance_squared_to(member.position) < radius * radius and players.has(member):
					result.append(member)
	return result


func _pending_projectile_damage(target: Combatant) -> float:
	return float(_pending_damage_by_target.get(target, 0.0))


func _rebuild_pending_projectile_damage() -> void:
	_pending_damage_by_target.clear()
	for projectile in projectiles:
		if not projectile.guidance_lost:
			_add_pending_damage(projectile.target, projectile.damage)


func _add_pending_damage(target: Combatant, amount: float) -> void:
	if target == null:
		return
	_pending_damage_by_target[target] = maxf(
		float(_pending_damage_by_target.get(target, 0.0)) + amount,
		0.0
	)


func _update_ship(ship: Combatant, delta: float, allow_weapons := true) -> void:
	if not ship.is_alive() or ship.has_tag("repair_drone"):
		return
	ship.since_damage += delta
	ship.retreat_time = maxf(0.0, ship.retreat_time - delta)
	ship.retreat_cooldown = maxf(0.0, ship.retreat_cooldown - delta)
	if ship.since_damage >= 4.0 and not abilities.suppressed(ship):
		var recharge := ship.stats.shield_recharge if ship.owned_ship != null else ship.stats.shields
		var recharge_delta := minf(delta, maxf(0.0, ship.since_damage - 4.0))
		ship.shields = minf(ship.stats.shields, ship.shields + recharge * 0.04 * recharge_delta)
	if ship.stats.shields > 0.0 and ship.shields <= ship.stats.shields * 0.2:
		if ship.retreat_cooldown <= 0.0:
			ship.retreat_time = 2.5
			ship.retreat_cooldown = 9.0
	if encounter.warden.braced(ship):
		ship.velocity = Vector2.ZERO
		ship.thruster_activation_elapsed = 0
		return
	if ship.commanded_target != null and not can_attack(ship, ship.commanded_target):
		ship.commanded_target = null
	var stance: String = ship.owned_ship.stance if ship.is_player and ship.owned_ship is HangarShip else "seek"
	if stance == "evade" and ship.commanded_target == null and not withdrawing:
		ship.target = null
		var escape := Vector2.ZERO
		for enemy: Combatant in aliens:
			if not enemy.is_alive() or not can_attack(ship, enemy):
				continue
			var offset := ship.position - enemy.position
			if offset.length_squared() < 360.0 * 360.0:
				escape += offset.normalized() * (360.0 - offset.length())
		var destination := ship.position + escape if not escape.is_zero_approx() else _flagship_position() - Vector2(180, 0)
		_stance_move(ship, destination, delta)
		return
	ship.target_refresh_remaining -= delta
	if ship.commanded_target != null:
		ship.target = ship.commanded_target
	elif ship.target != null and not _auto_candidate(ship, ship.target):
		ship.target = null
		ship.target_refresh_remaining = random.randf_range(0.0, TARGET_REFRESH_INTERVAL)
	if mining_enabled and stance == "seek" and ship.commanded_target == null and ship.target_refresh_remaining <= 0:
		var mining_target: Combatant = MiningRules.target(self, ship)
		if mining_target != null:
			ship.target = mining_target
			ship.target_refresh_remaining = TARGET_REFRESH_INTERVAL
	if enemy_roles.enabled and ship.commanded_target == null and ship.target_refresh_remaining <= 0:
		var role_target: Combatant = enemy_roles.choose_target(self, ship)
		if role_target != null:
			ship.target = role_target
			ship.target_refresh_remaining = TARGET_REFRESH_INTERVAL
	if ship.target == null and ship.target_refresh_remaining <= 0.0:
		ship.target = MiningRules.target(self, ship) if mining_enabled and stance == "seek" else null
		if ship.target == null:
			ship.target = _choose_target(ship)
		ship.target_refresh_remaining = TARGET_REFRESH_INTERVAL
	if ship.target == null:
		if stance == "defend" and not withdrawing:
			_stance_move(ship, _flagship_position() + _guard_offset(ship), delta)
			return
		if visibility_enabled:
			_investigate_contacts(ship, delta)
			return
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
	steering_direction = enemy_roles.steering(self, ship, steering_direction)
	var mining_in_range := false
	var pickup_approach_speed := INF
	if ship.target.has_tag("asteroid") and MiningRules.operational(ship, MiningRules.TOOLS):
		steering_direction = MiningRules.steering(self, ship, ship.target)
		for weapon in ship.stats.weapons:
			if weapon.weapon_name in MiningRules.WEAPONS and MiningRules.in_range(_get_weapon_origin(ship, weapon), ship.target, weapon.range_units * 0.8):
				mining_in_range = true
		if mining_in_range:
			ship.velocity = ship.velocity.move_toward(ship.target.velocity, ship.acceleration * delta)
	elif mining_enabled and not withdrawing:
		var pickup: Variant = MiningRules.pickup_destination(self, ship)
		if pickup != null:
			steering_direction = ship.position.direction_to(pickup)
			pickup_approach_speed = minf(ship.speed, maxf(8, ship.position.distance_to(pickup) * 0.6))
	var escort_distance := INF
	if ship.owned_ship != null and (ship.owned_ship.escort_target_id > 0 or ship.stats.weapons.is_empty()) and ship.commanded_target == null:
		var anchor := _escort_anchor(ship)
		escort_distance = ship.position.distance_to(anchor)
		steering_direction = ship.position.direction_to(anchor)
	if ship.retreat_time > 0.0:
		steering_direction = -direction
	var desired := steering_direction * ship.speed
	desired = _flock_velocity(ship, desired)
	desired = _separation_velocity(ship, desired)
	desired = encounter.steer(ship.position, desired, ship.speed)
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
	desired = MiningRules.avoidance(self, ship, desired)
	desired = encounter.warden.avoidance(self, ship, desired)
	var slow := abilities.movement_rate(ship)
	var desired_velocity := desired.limit_length(ship.speed * slow)
	var desired_heading := direction.angle()
	if desired_velocity.length_squared() > 0.01:
		desired_heading = desired_velocity.angle()
	ship.heading = rotate_toward(ship.heading, desired_heading, delta * ship.turn_rate * slow)
	# Ships have forward thrust only. They shed speed through passive drag rather
	# than braking, so reversals and course corrections form broad flight arcs.
	var forward := Vector2.from_angle(ship.heading)
	_apply_passive_drag(ship, delta)
	if ship.retreat_time <= 0.0 and not (withdrawing and ship.is_player):
		_apply_limited_reverse_thrust(ship, desired_velocity, delta)
	if ((escort_distance > 20.0 and not mining_in_range) or ship.retreat_time > 0.0 or withdrawing) \
		and ship.velocity.length() < pickup_approach_speed:
		ship.velocity += forward * ship.acceleration * delta * slow
	ship.velocity = ship.velocity.limit_length(ship.speed * slow)
	ship.position += ship.velocity * delta
	if not allow_weapons:
		return
	for index in range(ship.stats.weapons.size()):
		if ship.sortie_ammo == 0:
			break
		var weapon := ship.stats.weapons[index]
		if ship.owned_ship != null and ship.owned_ship.units[weapon.component_index].hp <= 0.0:
			continue
		if research_combat.is_prismatic(ship, weapon):
			research_combat.fire_laser(self, ship, index, weapon, _get_weapon_origin(ship, weapon), delta)
			continue
		ship.cooldowns[index] = maxf(0.0, ship.cooldowns[index] - delta)
		if ship.cooldowns[index] > 0.0:
			continue
		var missile_cost := weapon.missiles_per_projectile if ship.is_player and missile_supply >= 0 else 0
		if missile_cost > 0 and missile_supply < missile_cost:
			continue
		var weapon_origin := _get_weapon_origin(ship, weapon)
		if SharedSupport.intercept(self, ship, weapon, weapon_origin):
			if ship.sortie_ammo > 0:
				ship.sortie_ammo -= 1
			ship.cooldowns[index] = weapon.fire_interval_seconds
			continue
		ship.weapon_search_remaining[index] = maxf(0, float(ship.weapon_search_remaining.get(index, 0)) - delta)
		if ship.commanded_target == null and ship.weapon_search_remaining[index] > 0 and ship.target != null \
			and weapon_origin.distance_squared_to(ship.target.position) > pow(weapon.range_units + 64, 2):
			continue
		var weapon_target: Combatant = SharedSupport.weapon_target(self, ship, weapon, weapon_origin)
		if weapon_target == null:
			# Distant idle guns retry at the existing AI cadence. Interception and
			# explicit attack orders remain immediate; nearby guns search every tick.
			if ship.target != null and weapon_origin.distance_to(ship.target.position) > weapon.range_units + 64:
				ship.weapon_search_remaining[index] = TARGET_REFRESH_INTERVAL
			continue
		ship.weapon_search_remaining[index] = 0.0
		ship.target = weapon_target
		if ship.sortie_ammo > 0:
			ship.sortie_ammo -= 1
		ship.cooldowns[index] = weapon.fire_interval_seconds
		_record_event("expenditure", {"source": ship.entity_id, "weapon_index": index,
			"weapon": weapon.weapon_name, "cooldown": ship.cooldowns[index], "target": weapon_target.entity_id})
		if weapon.charge_seconds > 0:
			doctrines.begin_charge(self, ship, weapon, weapon_target, weapon_origin)
			continue
		for shot_index in range(weapon.projectiles_per_activation):
			if missile_cost > 0 and missile_supply < missile_cost:
				break
			ship.target = SharedSupport.weapon_target(self, ship, weapon, weapon_origin)
			if ship.target == null:
				break
			if missile_cost > 0:
				missile_supply -= missile_cost
				_record_event("missile_spent", {"source": ship.entity_id, "cost": missile_cost, "remaining": missile_supply})
			if shot_index == 0:
				weapon_fired.emit()
			if ship.is_player and not weapon.is_projectile_weapon:
				var hit_target := ship.target
				var obstruction = asteroid_field.intercept(self, weapon_origin, hit_target.position)
				if obstruction != null:
					hit_target = obstruction
				var beam := Beam.new()
				beam.source = ship
				beam.weapon_name = weapon.weapon_name
				beam.origin_position = weapon_origin
				beam.target = hit_target
				beam.aim_position = hit_target.position
				beams.append(beam)
				_damage(hit_target, weapon.damage_per_shot, weapon_origin, ship, weapon.weapon_name, false, true, 1.0, weapon.hull_damage_multiplier)
			else:
				var projectile := Projectile.new()
				projectile.rotation_phase = float(_next_projectile_id % 16) / 16.0 * TAU
				_next_projectile_id += 1
				projectile.source = ship
				projectile.origin = weapon_origin
				projectile.weapon_name = weapon.weapon_name
				projectile.position = weapon_origin
				projectile.previous_position = weapon_origin
				projectile.target = ship.target
				projectile.aim_position = ship.target.position
				projectile.aim_radius = ship.target.radius
				projectile.damage = weapon.damage_per_shot
				projectile.hull_damage_multiplier = weapon.hull_damage_multiplier
				projectile.is_player = ship.is_player
				projectile.interceptable = weapon.interceptable
				projectile.speed = 200.0 if weapon.interceptable else PROJECTILE_SPEED
				projectile.splinter = research_combat.enabled.get("splinter_missiles", false) \
					and ship.owned_ship is HangarShip and ship.is_player and "splitting_missile" in weapon.research_capabilities
				projectiles.append(projectile)
				_add_pending_damage(projectile.target, projectile.damage)


func _investigate_contacts(ship: Combatant, delta: float) -> void:
	# Search a deterministic patrol or anonymous sensor position. Hidden actor
	# references and hit points must never steer pursuit or choose a lock.
	var phase_offset := 0.0 if ship.faction == Faction.PLAYER else PI
	var angle := elapsed * 0.08 + phase_offset
	var destination := Vector2(cos(angle), sin(angle)) * ARENA_RADIUS * 0.6
	var nearest := INF
	for contact: Dictionary in visibility.contacts(ship.faction):
		var distance := ship.position.distance_squared_to(contact.position)
		if distance < nearest:
			nearest = distance
			destination = contact.position
	if ship.owned_ship != null and (ship.owned_ship.escort_target_id > 0 or ship.stats.weapons.is_empty()):
		destination = _escort_anchor(ship)
	if withdrawing and ship.faction == Faction.PLAYER:
		destination = ship.position + Vector2.LEFT * ARENA_RADIUS
	var slow := abilities.movement_rate(ship)
	var direction := ship.position.direction_to(destination)
	var role_direction: Vector2 = enemy_roles.steering(self, ship, direction)
	if role_direction != direction:
		destination = ship.position + role_direction * 100
	var pickup: Variant = MiningRules.pickup_destination(self, ship) if mining_enabled and not withdrawing else null
	if pickup != null:
		destination = pickup
	var desired := MiningRules.avoidance(self, ship, ship.position.direction_to(destination) * ship.speed)
	desired = _separation_velocity(ship, _flock_velocity(ship, desired))
	desired = encounter.steer(ship.position, desired, ship.speed)
	desired = encounter.warden.avoidance(self, ship, desired)
	direction = desired.normalized()
	if direction.is_zero_approx():
		_apply_passive_drag(ship, delta)
	else:
		ship.heading = rotate_toward(ship.heading, direction.angle(), ship.turn_rate * delta * slow)
		_apply_passive_drag(ship, delta)
		var approach_speed := ship.speed if pickup == null else minf(ship.speed, maxf(8, ship.position.distance_to(pickup) * 0.6))
		if pickup != null:
			_apply_limited_reverse_thrust(ship, direction * approach_speed, delta)
		var forward := Vector2.from_angle(ship.heading)
		if ship.velocity.length() < approach_speed and (pickup == null or forward.dot(direction) > 0.5):
			ship.velocity += forward * ship.acceleration * delta * slow
		ship.velocity = ship.velocity.limit_length(ship.speed * slow)
	ship.position += ship.velocity * delta
	ship.thruster_activation_elapsed += delta
	for index in range(ship.cooldowns.size()):
		ship.cooldowns[index] = maxf(0, ship.cooldowns[index] - delta)


func _escort_anchor(ship: Combatant) -> Vector2:
	var host: Combatant
	for candidate in players:
		if candidate == ship or not candidate.is_alive() or candidate.owned_ship == null:
			continue
		if candidate.owned_ship.id == ship.owned_ship.escort_target_id:
			host = candidate
			break
		if candidate.stats.weapons.is_empty():
			continue
		if host == null or candidate.position.distance_squared_to(ship.position) < host.position.distance_squared_to(ship.position):
			host = candidate
	if host == null:
		return PLAYER_FORMATION_CENTER + ship.owned_ship.formation * DEPLOYMENT_SCALE
	return host.position - Vector2.from_angle(host.heading) * 90.0

func _flagship_position() -> Vector2:
	for member: Combatant in players:
		if member.owned_ship != null and member.owned_ship.is_flagship() and member.is_alive():
			return member.position
	return PLAYER_FORMATION_CENTER

func _guard_offset(ship: Combatant) -> Vector2:
	for member: Combatant in players:
		if member.owned_ship != null and member.owned_ship.is_flagship():
			return (ship.owned_ship.formation - member.owned_ship.formation) * DEPLOYMENT_SCALE
	return Vector2.ZERO

func _stance_move(ship: Combatant, destination: Vector2, delta: float) -> void:
	var offset := destination - ship.position
	var desired := offset.limit_length(ship.speed)
	desired = _separation_velocity(ship, _flock_velocity(ship, desired))
	desired = encounter.steer(ship.position, desired, ship.speed)
	desired = MiningRules.avoidance(self, ship, desired)
	desired = encounter.warden.avoidance(self, ship, desired)
	if ship.position.length() > ARENA_RADIUS - SOFT_BOUNDARY_MARGIN:
		desired -= ship.position.normalized() * ship.speed
	var slow := abilities.movement_rate(ship)
	desired = desired.limit_length(ship.speed * slow)
	if desired.length_squared() > 1:
		ship.heading = rotate_toward(ship.heading, desired.angle(), delta * ship.turn_rate * slow)
	_apply_passive_drag(ship, delta)
	_apply_limited_reverse_thrust(ship, desired, delta)
	if offset.length() > 20.0:
		ship.velocity += Vector2.from_angle(ship.heading) * ship.acceleration * delta * slow
	ship.velocity = ship.velocity.limit_length(ship.speed * slow)
	ship.position += ship.velocity * delta
	ship.thruster_activation_elapsed = ship.thruster_activation_elapsed + delta if desired.length_squared() > 1 else 0
	for index in range(ship.cooldowns.size()):
		ship.cooldowns[index] = maxf(0, ship.cooldowns[index] - delta)


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
	if ship.owned_ship is HangarShip:
		return ship.position + (weapon.mount_offset * ship.owned_ship.fleet_view_scale()).rotated(ship.heading)
	return ship.position + weapon.mount_offset.rotated(ship.heading)


func _update_projectiles(delta: float) -> void:
	var rock_shapes: Dictionary = {}
	var actor_shapes: Dictionary = {}
	for actor: Combatant in other_entities:
		if actor.has_tag("asteroid") and actor.is_alive():
			rock_shapes[actor] = Collision.actor_polygons(actor)
	for index in range(projectiles.size() - 1, -1, -1):
		var projectile := projectiles[index]
		if projectile.target == null:
			projectiles.remove_at(index)
			continue
		if research_combat.split(self, projectile):
			projectiles.remove_at(index)
			continue
		if visibility_enabled:
			if not projectile.guidance_lost and not team_can_see(projectile.source.faction if projectile.source != null else (Faction.PLAYER if projectile.is_player else Faction.ALIEN), projectile.target):
				projectile.guidance_lost = true
				_add_pending_damage(projectile.target, -projectile.damage)
			if not projectile.guidance_lost:
				projectile.aim_position = projectile.target.position
				projectile.aim_radius = projectile.target.radius
		var destination := projectile.aim_position if visibility_enabled else projectile.target.position
		var start := projectile.position
		projectile.position = projectile.position.move_toward(destination, projectile.speed * delta)
		var finish := projectile.position
		projectile.position = start
		var shape: Array[PackedVector2Array] = []
		var bullet_radius := Collision.BULLET_TEXTURE.get_size().length() * Collision.BULLET_SCALE * 0.5 \
			if projectile.is_player and projectile.weapon_name == "Mini Turret" else 2.5
		var contact := INF
		var struck: Combatant
		if projectile.target.is_alive() and Collision.sweep_near_actor(start, finish, bullet_radius, projectile.target):
			shape = Collision.bullet_polygons(projectile, elapsed)
			if not actor_shapes.has(projectile.target):
				actor_shapes[projectile.target] = Collision.actor_polygons(projectile.target)
			contact = Collision.sweep(shape, finish - start, actor_shapes[projectile.target])
			if contact < INF:
				struck = projectile.target
		for candidate: Combatant in rock_shapes:
			if not candidate.is_alive() or not Collision.sweep_near_actor(start, finish, bullet_radius, candidate):
				continue
			if shape.is_empty():
				shape = Collision.bullet_polygons(projectile, elapsed)
			var fraction := Collision.sweep(shape, finish - start, rock_shapes[candidate])
			if fraction < contact:
				contact = fraction
				struck = candidate
		projectile.position = finish
		if struck != null:
			_add_pending_damage(projectile.target, -projectile.damage)
			projectile.position = start.lerp(finish, contact)
			_damage(struck, projectile.damage, projectile.origin, projectile.source, projectile.weapon_name, true, false, 1.0, projectile.hull_damage_multiplier)
			projectile_impacted.emit(projectile.position)
			projectiles.remove_at(index)
		elif projectile.position.is_equal_approx(destination):
			_add_pending_damage(projectile.target, -projectile.damage)
			projectiles.remove_at(index)


func get_finishing_projectile(maximum_time_to_impact := INF) -> Projectile:
	var target: Combatant
	var attacking_players := false
	var required := remaining_victory_targets()
	if required.size() == 1 and encounter.pending.is_empty():
		target = required[0]
		attacking_players = true
	elif living_player_count() == 1:
		for player_ship in players:
			if player_ship.is_alive():
				target = player_ship
				break
	else:
		return null
	if visibility_enabled and not team_can_see(Faction.PLAYER, target):
		return null
	var incoming: Array[Projectile] = []
	for projectile in projectiles:
		if (
			projectile.target == target
			and not projectile.guidance_lost
			and projectile.is_player == attacking_players
		):
			var obstruction = asteroid_field.intercept(self, projectile.position, target.position)
			if obstruction != null and obstruction != target:
				continue
			incoming.append(projectile)
	incoming.sort_custom(func(left: Projectile, right: Projectile) -> bool:
		return left.position.distance_squared_to(target.position) < right.position.distance_squared_to(target.position))
	var committed_damage := 0.0
	for projectile in incoming:
		committed_damage += projectile.damage * enemy_roles.protection(self, target) * encounter.warden.protection(self, target)
		if committed_damage < target.integrity + target.shields:
			continue
		var time_to_impact := maxf(
			projectile.position.distance_to(target.position) - target.radius,
			0.0
		) / projectile.speed
		return projectile if time_to_impact <= maximum_time_to_impact else null
	return null


func _refresh_owned_stats(target: Combatant) -> void:
	target.weapon_search_remaining.clear()
	target.support_parts_ready = false
	target.support_parts.clear()
	var was_alive := target.is_alive()
	# Match cooldowns by physical source rather than by the changing weapon index.
	var cooldowns_by_source: Dictionary = {}
	for index in range(target.stats.weapons.size()):
		var weapon := target.stats.weapons[index]
		var key := "%d/%s" % [weapon.component_index, weapon.weapon_name]
		if not cooldowns_by_source.has(key):
			cooldowns_by_source[key] = []
		cooldowns_by_source[key].append({"remaining": target.cooldowns[index], "interval": weapon.fire_interval_seconds})
	target.stats = target.owned_ship.get_stats(laser_upgrade_level, energy_efficiency)
	target.integrity = target.stats.integrity if target.owned_ship.is_alive() else 0.0
	target.shields = minf(target.shields, target.stats.shields)
	target.radius = target.stats.collision_radius
	target.cooldowns.clear()
	for weapon in target.stats.weapons:
		var key := "%d/%s" % [weapon.component_index, weapon.weapon_name]
		var old: Array = cooldowns_by_source.get(key, [])
		var remaining := 0.0
		if not old.is_empty():
			var previous: Dictionary = old.pop_front()
			remaining = float(previous.remaining)
			if not is_equal_approx(previous.interval, weapon.fire_interval_seconds):
				remaining *= weapon.fire_interval_seconds / float(previous.interval)
		target.cooldowns.append(remaining)
	_refresh_mobility(target)
	doctrines.carriers.prune(self)
	if was_alive != target.is_alive():
		refresh_visibility()


func team_can_see(faction: int, target: Combatant) -> bool:
	if target == null:
		return false
	if visibility_enabled:
		return visibility.can_see(faction, target.entity_id)
	# Conservative Command Center sight until the shared fog/sensor milestone.
	if not target.is_alive() or not target.targetable:
		return false
	for observer in _members:
		if observer.faction == faction and observer.is_alive() and observer.has_tag("combatant") \
			and observer.position.distance_to(target.position) <= 260.0:
			return true
	return false


func refresh_visibility() -> void:
	if visibility_enabled:
		visibility.refresh(self)


func point_visible(faction: int, point: Vector2) -> bool:
	return not visibility_enabled or visibility.point_visible(faction, point)


func _update_analysis(delta: float) -> void:
	for member in _members:
		var lab_index := _active_lab(member)
		if lab_index < 0:
			member.analysis_target_id = ""
			continue
		var marked: Combatant = entities.get(member.analysis_target_id)
		if marked == null or not team_can_see(member.faction, marked):
			member.analysis_target_id = ""
		var lab_rate: float = AdjacencyRules.rates(member.owned_ship.units).get(lab_index, 1.0)
		member.analysis_remaining = maxf(0, member.analysis_remaining - delta * lab_rate)
		if member.analysis_remaining > 0:
			continue
		member.analysis_remaining = 8.0
		var closest := INF
		member.analysis_target_id = ""
		for target in _members:
			if target.faction == member.faction or target.faction == Faction.NEUTRAL or not target.has_tag("combatant") \
				or not team_can_see(member.faction, target):
				continue
			var distance := member.position.distance_squared_to(target.position)
			if distance < closest:
				closest = distance
				member.analysis_target_id = target.entity_id


func _active_lab(member: Combatant) -> int:
	if not member.is_alive() or member.owned_ship == null:
		return -1
	if member.owned_ship is HangarShip:
		if not member.support_parts_ready:
			CombatDoctrines.operational(member, ShipPart.Type.RESEARCH_LAB)
		return member.cached_lab_index
	return ScienceRules.active_lab(member.owned_ship)

func _analysis_multiplier(source: Combatant, target: Combatant) -> float:
	if source == null or not team_can_see(source.faction, target):
		return 1.0
	var mark := doctrines.mark_multiplier(self, source, target)
	if mark > 1:
		return mark
	for member in _members:
		if member.faction == source.faction and member.is_alive() and member.owned_ship != null \
			and _active_lab(member) >= 0 and member.analysis_target_id == target.entity_id:
			return 1.05
	return 1.0


func _damage(target: Combatant, damage: float, origin: Vector2 = Vector2.ZERO, source: Combatant = null, weapon_name: String = "", projectile_hit := false, weapon_hit := false, hit_fraction: float = 1.0, hull_multiplier: float = 1.0) -> void:
	if not target.is_alive() or not target.targetable or target.has_tag("drop") or not is_finite(damage) or damage <= 0.0:
		return
	if target.owned_ship is HangarShip and (weapon_hit or projectile_hit):
		var chance: float = target.owned_ship.chassis.get("dodge_chance", 0.0)
		if chance > 0.0 and random.randf() < chance:
			_record_event("dodge", {"source": "" if source == null else source.entity_id, "target": target.entity_id, "weapon": weapon_name})
			return
	damage *= _analysis_multiplier(source, target)
	# Railgun penetrates Sentinel hull cover; shields and boss protection still work.
	if weapon_name != "Railgun" or target.shields > 0:
		damage *= enemy_roles.protection(self, target)
	damage *= encounter.warden.protection(self, target)
	if target.has_tag("asteroid") and weapon_name in MiningRules.WEAPONS:
		damage *= 4.0
	var ion_shield := weapon_name == "Ion Emitter" and target.shields > 0
	if weapon_name == "Ion Emitter":
		damage *= 2.0 if target.shields > 0 else 0.5
	var absorbed := minf(target.shields, damage)
	if ion_shield:
		damage = absorbed + (damage - absorbed) * 0.25
	target.shields -= absorbed
	target.shield_damage_taken += absorbed
	var actual := absorbed
	if target.owned_ship != null and damage > absorbed:
		var owned := target.owned_ship
		var local_origin := (origin - target.position).rotated(-target.heading)
		var remaining := (damage - absorbed) * hull_multiplier
		for penetration in range(2 if weapon_name == "Beam Lance" else 1):
			var cell := owned.hit_cell(local_origin, random)
			if projectile_hit and owned.cell_units.has(cell) and CombatDoctrines.protected_unit(owned, owned.cell_units[cell]):
				remaining *= 0.7
			var result: Dictionary = owned.damage_hull(remaining, hit_fraction) if owned is HangarShip else owned.damage_cell(cell, remaining)
			actual += result.damage
			remaining -= result.damage
			target.permanent_damage_taken += result.damage if owned is HangarShip else result.removed.size()
			for removed_cell in result.removed:
				if not credits_only and random.randf() < allied_drop_chance:
					var drop := Drop.new()
					drop.entity_id = "%s/wreck/%d/%d" % [target.entity_id, removed_cell.x, removed_cell.y]
					drop.category = owned.design.tiles[removed_cell]
					drop.position = target.position + owned.local_cell_position(removed_cell).rotated(target.heading)
					drop.size = owned.cell_size
					drops.append(drop)
			if remaining <= 0 or result.removed.is_empty() or not owned.is_alive():
				break
		_refresh_owned_stats(target)
	else:
		var hull_damage := minf(target.integrity, (damage - absorbed) * hull_multiplier)
		target.integrity -= hull_damage
		actual += hull_damage
	if actual > 0.0:
		_damage_this_step = true
	target.damage_taken += actual
	if source != null:
		if source.faction == Faction.PLAYER and target.faction == Faction.ALIEN:
			swarm_damage_dealt += actual
		source.damage_dealt += actual
		source.weapon_damage[weapon_name] = source.weapon_damage.get(weapon_name, 0.0) + actual
		if not source.carrier_source_id.is_empty() and entities.has(source.carrier_source_id):
			var carrier: Combatant = entities[source.carrier_source_id]
			carrier.damage_dealt += actual
			carrier.weapon_damage[weapon_name] = carrier.weapon_damage.get(weapon_name, 0.0) + actual
	target.since_damage = 0.0
	if absorbed > 0.0:
		target.shield_flash = 0.2
		shield_hit.emit()
	encounter.warden.on_damage(self, target, actual)
	if target.has_tag("asteroid"):
		asteroid_field.on_damage(self, target, source, weapon_name)
	if target.is_alive():
		return
	var component_hp: Array = []
	if target.owned_ship != null and not target.owned_ship is HangarShip:
		for unit in target.owned_ship.units:
			component_hp.append(unit.hp)
	_record_event("destruction", {"target": target.entity_id, "source": source.entity_id if source != null else "",
		"integrity": target.integrity, "shields": target.shields, "component_hp": component_hp,
		"remaining_objectives": _remaining_target_ids()})
	if target.velocity.length_squared() < 1.0:
		target.velocity = Vector2.from_angle(random.randf_range(0.0, TAU)) * random.randf_range(8.0, 20.0)
	target.wreck_angular_velocity = random.randf_range(-0.45, 0.45)
	target.wreck_motion_remaining = WRECK_MOTION_SECONDS
	if target.has_tag("asteroid"):
		target.wreck_motion_remaining = 0.0
	if absf(target.wreck_angular_velocity) < 0.12:
		target.wreck_angular_velocity = 0.12 if target.wreck_angular_velocity >= 0.0 else -0.12
	var explosion := Explosion.new()
	explosion.position = target.position
	explosions.append(explosion)
	if target.has_tag("combatant"):
		ship_destroyed.emit(target.is_player)
	if not credits_only and target.faction == Faction.ALIEN and target.has_tag("combatant") and not target.has_tag("summon") \
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
