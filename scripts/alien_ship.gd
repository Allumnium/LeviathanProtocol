class_name AlienShip
extends RefCounted

const CHRYSALIS_TEXTURE: Texture2D = preload("res://assets/drone_chrysalis.png")
const FIGHTER_TEXTURE: Texture2D = preload("res://assets/drone_fighter.png")
const SCOUT_TEXTURE: Texture2D = preload("res://assets/drone_scout.png")
const SENTINEL_TEXTURE: Texture2D = preload("res://assets/drone_sentinel.png")
const PYLON_TEXTURE: Texture2D = preload("res://assets/shield.png")
const SUPPORT_TEXTURE: Texture2D = preload("res://assets/drone_support.png")

var display_name: String
var texture: Texture2D
var base_stats: ShipStats
var stats: ShipStats
var definition_id := "legacy"
var role_id := ""
var tier := 0
var threat_cost := 0.0
var entity_id := ""
var entity_kind := "ship"
var wave_index := 0

const ROLE_COSTS := {"scout": 16.0, "fighter": 22.0, "sentinel": 30.0, "support": 26.0, "chrysalis": 32.0}
const TIER_COST := [1.0, 2.25, 3.75]
const TIER_HULL := [1.0, 1.8, 2.6]
const TIER_DAMAGE := [1.0, 1.6, 2.2]


func _init(
	p_display_name: String,
	p_texture: Texture2D,
	p_base_stats: ShipStats,
	difficulty_multiplier: float = 1.0
) -> void:
	if p_texture == null:
		push_error("An alien ship must have a texture.")
		return
	if p_base_stats == null:
		push_error("An alien ship must have base stats.")
		return
	if difficulty_multiplier <= 0.0:
		push_error("Alien difficulty scaling must be greater than zero.")
		return

	display_name = p_display_name
	role_id = p_display_name.to_snake_case()
	texture = p_texture
	base_stats = p_base_stats
	stats = _scale_stats(difficulty_multiplier)


func scaled_for_difficulty(difficulty_multiplier: float) -> AlienShip:
	return AlienShip.new(display_name, texture, base_stats, difficulty_multiplier)


static func warden_variant(pylon: bool, hull: float, shield: float, cost: float) -> AlienShip:
	var value := ShipStats.new()
	value.integrity = hull
	value.shields = shield
	value.weight = 20 if pylon else 60
	value.thrust = 0 if pylon else 2
	value.collision_radius = 12 if pylon else 26
	value.weapons.append(ShipWeaponStats.new("Pylon Pulse" if pylon else "Warden Pulse", 2.5 if pylon else 1.4, 0.2 if pylon else 0.8, 1, 210))
	var unit := AlienShip.new("Shield Pylon" if pylon else "Bastion Warden", PYLON_TEXTURE if pylon else SENTINEL_TEXTURE, value)
	unit.stats.collision_radius = value.collision_radius
	unit.role_id = "pylon" if pylon else "warden"
	unit.definition_id = "warden/pylon" if pylon else "warden/body"
	unit.entity_kind = "organ" if pylon else "ship"
	unit.threat_cost = cost
	return unit


static func threat_variant(role: String, rank: int) -> AlienShip:
	if not ROLE_COSTS.has(role) or rank < 0 or rank > 2:
		return null
	for definition in get_catalog():
		if definition.role_id != role:
			continue
		definition.definition_id = "%s/tier_%d" % [role, rank]
		definition.tier = rank
		definition.threat_cost = ROLE_COSTS[role] * TIER_COST[rank]
		definition.stats.integrity *= TIER_HULL[rank]
		definition.stats.shields *= TIER_HULL[rank]
		definition.stats.weight *= 1.0 + rank * 0.5
		definition.stats.thrust *= 1.0 + rank * 0.125
		for weapon in definition.stats.weapons:
			weapon.damage_per_shot *= TIER_DAMAGE[rank]
		return definition
	return null


func to_snapshot() -> Dictionary:
	var weapons: Array = []
	for weapon in stats.weapons:
		weapons.append([weapon.weapon_name, weapon.fire_interval_seconds, weapon.damage_per_shot,
			weapon.projectiles_per_activation, weapon.range_units, weapon.is_projectile_weapon, weapon.interceptable])
	return {"name": display_name, "stats": [stats.shields, stats.integrity, stats.weight, stats.thrust],
		"weapons": weapons, "definition_id": definition_id, "role": role_id, "tier": tier,
		"threat_cost": threat_cost, "entity_id": entity_id, "kind": entity_kind, "wave": wave_index}


static func from_snapshot(entry: Variant) -> AlienShip:
	if not snapshot_valid(entry):
		return null
	var result: AlienShip
	for definition in get_catalog():
		if definition.display_name == entry.name:
			result = definition
			break
	if entry.name in ["Shield Pylon", "Bastion Warden"]:
		result = warden_variant(entry.name == "Shield Pylon", 1, 0, 1)
	if result == null:
		return null
	var restored := ShipStats.new()
	if entry.name in ["Shield Pylon", "Bastion Warden"]:
		restored.collision_radius = 12 if entry.name == "Shield Pylon" else 26
	restored.shields = entry.stats[0]
	restored.integrity = entry.stats[1]
	restored.weight = entry.stats[2]
	restored.thrust = entry.stats[3]
	for weapon in entry.weapons:
		var restored_weapon := ShipWeaponStats.new(weapon[0], weapon[1], weapon[2], int(weapon[3]), weapon[4])
		restored_weapon.is_projectile_weapon = weapon[5]
		restored_weapon.interceptable = weapon[6] if weapon.size() > 6 else false
		restored.weapons.append(restored_weapon)
	result.stats = restored
	result.definition_id = entry.get("definition_id", "legacy")
	result.role_id = entry.get("role", result.role_id)
	result.tier = int(entry.get("tier", 0))
	result.threat_cost = float(entry.get("threat_cost", 0.0))
	result.entity_id = entry.get("entity_id", "")
	result.entity_kind = entry.get("kind", "ship")
	result.wave_index = int(entry.get("wave", 0))
	return result


static func snapshot_valid(entry: Variant) -> bool:
	if not entry is Dictionary or not entry.get("name") is String or not entry.get("stats") is Array:
		return false
	if entry.name not in ["Scout", "Fighter", "Sentinel", "Support", "Chrysalis", "Shield Pylon", "Bastion Warden"]:
		return false
	if entry.stats.size() != 4 or not entry.get("weapons") is Array or entry.weapons.is_empty():
		return false
	for value in entry.stats:
		if not _finite_number(value) or value < 0:
			return false
	if entry.stats[1] <= 0:
		return false
	for key in ["definition_id", "role", "entity_id", "kind"]:
		if entry.has(key) and not entry[key] is String:
			return false
	for key in ["tier", "wave"]:
		if entry.has(key) and (not RunProgressData._integer(entry[key]) or entry[key] < 0):
			return false
	if entry.has("threat_cost") and (not _finite_number(entry.threat_cost) or entry.threat_cost < 0):
		return false
	for weapon in entry.weapons:
		if not weapon is Array or weapon.size() not in [6, 7] or not weapon[0] is String or not weapon[5] is bool:
			return false
		if weapon.size() == 7 and not weapon[6] is bool:
			return false
		for index in [1, 2, 4]:
			if not _finite_number(weapon[index]) or weapon[index] <= 0:
				return false
		if not RunProgressData._integer(weapon[3]) or weapon[3] < 1:
			return false
	return true


static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value)


static func get_catalog() -> Array[AlienShip]:
	return [
		AlienShip.new(
			"Chrysalis",
			CHRYSALIS_TEXTURE,
			_create_base_stats(2.0, 12.0, 28.0, 9.0, "Spore Launcher", 1.5, 1.0, 200.0, true)
		),
		AlienShip.new(
			"Fighter",
			FIGHTER_TEXTURE,
			_create_base_stats(1.0, 8.0, 14.0, 18.0, "Plasma Cannon", 0.8, 0.7, 180.0)
		),
		AlienShip.new(
			"Scout",
			SCOUT_TEXTURE,
			_create_base_stats(0.0, 6.0, 8.0, 24.0, "Scout Pulse", 1.2, 0.6, 190.0)
		),
		AlienShip.new(
			"Sentinel",
			SENTINEL_TEXTURE,
			_create_base_stats(3.0, 14.0, 36.0, 6.0, "Sentinel Beam", 2.0, 1.4, 230.0)
		),
		AlienShip.new(
			"Support",
			SUPPORT_TEXTURE,
			_create_base_stats(2.0, 8.0, 18.0, 12.0, "Support Pulse", 2.5, 1.0, 210.0)
		),
	]


static func create_random_fleet(
	ship_count: int,
	difficulty_multiplier: float,
	seed_value: int = -1
) -> Array[AlienShip]:
	# Legacy/ad-hoc simulation helper. Campaign nodes use EncounterGenerator's
	# frozen priced definitions, never this health/damage normalization.
	if ship_count <= 0:
		push_error("An alien fleet must contain at least one ship.")
		return []
	if difficulty_multiplier <= 0.0:
		push_error("Alien difficulty scaling must be greater than zero.")
		return []

	var catalog := get_catalog()
	if catalog.is_empty():
		push_error("The alien ship catalog is empty.")
		return []

	var random := RandomNumberGenerator.new()
	if seed_value >= 0:
		random.seed = seed_value
	else:
		random.randomize()
	var randomized_catalog: Array[AlienShip] = []
	for definition in catalog:
		randomized_catalog.append(definition)
	_shuffle_fleet(randomized_catalog, random)

	var fleet: Array[AlienShip] = []
	for definition in randomized_catalog:
		if fleet.size() >= ship_count:
			break
		fleet.append(definition.scaled_for_difficulty(difficulty_multiplier))
	while fleet.size() < ship_count:
		var definition := catalog[random.randi_range(0, catalog.size() - 1)]
		fleet.append(definition.scaled_for_difficulty(difficulty_multiplier))
	_shuffle_fleet(fleet, random)
	# Preserve the legacy fixture budget independently of campaign allocation.
	var total_health := 0.0
	for alien in fleet:
		total_health += alien.stats.integrity + alien.stats.shields
	var health_scale := 21.25 * difficulty_multiplier / total_health
	for alien in fleet:
		alien.stats.integrity *= health_scale
		alien.stats.shields *= health_scale
	var focus_order := fleet.duplicate()
	focus_order.sort_custom(func(a: AlienShip, b: AlienShip) -> bool:
		return a.stats.integrity + a.stats.shields < b.stats.integrity + b.stats.shields)
	var cumulative_health := 0.0
	var expected_damage := 0.0
	for alien in focus_order:
		cumulative_health += alien.stats.integrity + alien.stats.shields
		expected_damage += alien.stats.dps * cumulative_health / 10.0
	# Account for how long each enemy survives focused fire, not just starting fleet DPS.
	var damage_scale := 7.5 * difficulty_multiplier * difficulty_multiplier / expected_damage
	for alien in fleet:
		for weapon in alien.stats.weapons:
			weapon.damage_per_shot *= damage_scale
	return fleet


static func _shuffle_fleet(fleet: Array[AlienShip], random: RandomNumberGenerator) -> void:
	for index in range(fleet.size() - 1, 0, -1):
		var other_index := random.randi_range(0, index)
		var temporary := fleet[index]
		fleet[index] = fleet[other_index]
		fleet[other_index] = temporary


func _scale_stats(difficulty_multiplier: float) -> ShipStats:
	var scaled_stats := ShipStats.new()
	scaled_stats.shields = base_stats.shields * difficulty_multiplier
	scaled_stats.integrity = base_stats.integrity * difficulty_multiplier
	scaled_stats.weight = base_stats.weight * difficulty_multiplier
	scaled_stats.thrust = base_stats.thrust * difficulty_multiplier
	for weapon in base_stats.weapons:
		var scaled_weapon := weapon.copy()
		scaled_weapon.damage_per_shot *= difficulty_multiplier
		scaled_stats.weapons.append(scaled_weapon)
	return scaled_stats


static func _create_base_stats(
	shields: float,
	integrity: float,
	weight: float,
	thrust: float,
	weapon_name: String,
	fire_interval_seconds: float,
	damage_per_shot: float,
	range_units: float,
	interceptable := false
) -> ShipStats:
	var new_stats := ShipStats.new()
	new_stats.shields = shields
	new_stats.integrity = integrity
	new_stats.weight = weight
	new_stats.thrust = thrust
	new_stats.weapons.append(
		ShipWeaponStats.new(weapon_name, fire_interval_seconds, damage_per_shot, 1, range_units)
	)
	new_stats.weapons[0].interceptable = interceptable
	return new_stats
