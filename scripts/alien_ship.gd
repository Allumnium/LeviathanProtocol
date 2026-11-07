class_name AlienShip
extends RefCounted

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
var copy_of := ""

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
	texture = SurfaceArt.texture(p_texture.resource_path) if p_texture.resource_path.ends_with("_d.png") else p_texture
	base_stats = p_base_stats
	stats = _scale_stats(difficulty_multiplier)


func scaled_for_difficulty(difficulty_multiplier: float) -> AlienShip:
	return AlienShip.new(display_name, texture, base_stats, difficulty_multiplier)


static func definition(id: String) -> Dictionary:
	return Content.get_def("enemy_unit", id)


static func tier_parameters(id: String, rank: int) -> Dictionary:
	for entry: Dictionary in definition(id).get("tiers", []):
		if int(entry.rank) == rank:
			return entry
	return {}


static func threat_cost_for(id: String, rank := 0) -> float:
	var parameters := tier_parameters(id, rank)
	return float(definition(id).cost) * float(parameters.cost) if not parameters.is_empty() else INF


static func from_def(id: String, rank := 0) -> AlienShip:
	var data := definition(id)
	var parameters := tier_parameters(id, rank)
	if data.is_empty() or parameters.is_empty():
		return null
	var value := ShipStats.new()
	value.integrity = float(data.stats.integrity) * float(parameters.hull)
	value.shields = float(data.stats.shields) * float(parameters.hull)
	value.weight = float(data.stats.weight) * float(parameters.weight)
	value.thrust = float(data.stats.thrust) * float(parameters.thrust)
	value.collision_radius = float(data.stats.collision_radius)
	for weapon: Dictionary in data.stats.weapons:
		var copy := ShipWeaponStats.new(weapon.name, weapon.interval, float(weapon.damage) * float(parameters.damage), int(weapon.count), weapon.range)
		copy.is_projectile_weapon = weapon.projectile
		copy.interceptable = weapon.interceptable
		value.weapons.append(copy)
	var unit := AlienShip.new(data.display_name, load(data.art), value)
	unit.stats.collision_radius = value.collision_radius
	unit.definition_id = Content.db().resolve_id("enemy_unit", id)
	unit.role_id = data.role
	unit.entity_kind = data.kind
	unit.tier = rank
	unit.threat_cost = threat_cost_for(id, rank)
	unit._apply_tier_art()
	return unit


static func warden_variant(pylon: bool, hull: float, shield: float, cost: float) -> AlienShip:
	var unit := from_def("core:warden/pylon" if pylon else "core:warden/body")
	unit.stats.integrity = hull
	unit.stats.shields = shield
	unit.threat_cost = cost
	return unit


static func threat_variant(role: String, rank: int) -> AlienShip:
	return from_def(role, rank)


func to_snapshot() -> Dictionary:
	var weapons: Array = []
	for weapon in stats.weapons:
		weapons.append([weapon.weapon_name, weapon.fire_interval_seconds, weapon.damage_per_shot,
			weapon.projectiles_per_activation, weapon.range_units, weapon.is_projectile_weapon, weapon.interceptable])
	var result := {"name": display_name, "stats": [stats.shields, stats.integrity, stats.weight, stats.thrust],
		"weapons": weapons, "definition_id": definition_id, "role": role_id, "tier": tier,
		"collision_radius": stats.collision_radius, "threat_cost": threat_cost, "entity_id": entity_id, "kind": entity_kind, "wave": wave_index}
	if not copy_of.is_empty():
		result.copy_of = copy_of
	return result


static func from_snapshot(entry: Variant) -> AlienShip:
	if not snapshot_valid(entry):
		return null
	var result := from_def(entry.get("definition_id", ""), int(entry.get("tier", 0)))
	if result == null:
		return null
	var restored := ShipStats.new()
	restored.collision_radius = float(entry.get("collision_radius", result.stats.collision_radius))
	restored.shields = entry.stats[0]
	restored.integrity = entry.stats[1]
	restored.weight = entry.stats[2]
	restored.thrust = entry.stats[3]
	for weapon in entry.weapons:
		var restored_weapon := ShipWeaponStats.new(weapon[0], weapon[1], weapon[2], int(weapon[3]), weapon[4])
		restored_weapon.is_projectile_weapon = weapon[5]
		restored_weapon.interceptable = weapon[6] if weapon.size() > 6 else false
		restored.weapons.append(restored_weapon)
	result.display_name = entry.name
	result.stats = restored
	result.definition_id = entry.get("definition_id", "legacy")
	result.role_id = entry.get("role", result.role_id)
	result.tier = int(entry.get("tier", 0))
	result.threat_cost = float(entry.get("threat_cost", 0.0))
	result.entity_id = entry.get("entity_id", "")
	result.entity_kind = entry.get("kind", "ship")
	result.wave_index = int(entry.get("wave", 0))
	result.copy_of = entry.get("copy_of", "")
	result._apply_tier_art()
	return result


func _apply_tier_art() -> void:
	var data := definition(definition_id)
	if tier > 0 and not data.is_empty():
		texture = SurfaceArt.texture(data.tier_art)


func art_scale() -> float:
	var data := definition(definition_id)
	return float(data.tier_art_scale) if tier > 0 and not data.is_empty() else 1.0


static func snapshot_valid(entry: Variant) -> bool:
	if not entry is Dictionary or not entry.get("name") is String or not entry.get("stats") is Array:
		return false
	if not entry.get("definition_id") is String or not SaveValidation.integer(entry.get("tier", 0)) or definition(entry.get("definition_id", "")).is_empty() or tier_parameters(entry.get("definition_id", ""), int(entry.get("tier", 0))).is_empty():
		return false
	if entry.stats.size() != 4 or not entry.get("weapons") is Array or entry.weapons.is_empty():
		return false
	for value in entry.stats:
		if not _finite_number(value) or value < 0:
			return false
	if entry.stats[1] <= 0:
		return false
	for key in ["definition_id", "role", "entity_id", "kind", "copy_of"]:
		if entry.has(key) and not entry[key] is String:
			return false
	for key in ["tier", "wave"]:
		if entry.has(key) and (not SaveValidation.integer(entry[key]) or entry[key] < 0):
			return false
	if entry.has("collision_radius") and (not SaveValidation.bounded_number(entry.collision_radius) or entry.collision_radius <= 0):
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
		if not SaveValidation.integer(weapon[3]) or weapon[3] < 1:
			return false
	return true


static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value)


static func get_catalog() -> Array[AlienShip]:
	var result: Array[AlienShip] = []
	for id: String in Content.get_def("encounter_tuning", "core:default").catalog:
		result.append(from_def(id))
	return result


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
