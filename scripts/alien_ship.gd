class_name AlienShip
extends RefCounted

const CHRYSALIS_TEXTURE: Texture2D = preload("res://assets/drone_chrysalis.png")
const FIGHTER_TEXTURE: Texture2D = preload("res://assets/drone_fighter.png")
const SCOUT_TEXTURE: Texture2D = preload("res://assets/drone_scout.png")
const SENTINEL_TEXTURE: Texture2D = preload("res://assets/drone_sentinel.png")
const SUPPORT_TEXTURE: Texture2D = preload("res://assets/drone_support.png")

var display_name: String
var texture: Texture2D
var base_stats: ShipStats
var stats: ShipStats


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
	texture = p_texture
	base_stats = p_base_stats
	stats = _scale_stats(difficulty_multiplier)


func scaled_for_difficulty(difficulty_multiplier: float) -> AlienShip:
	return AlienShip.new(display_name, texture, base_stats, difficulty_multiplier)


static func get_catalog() -> Array[AlienShip]:
	return [
		AlienShip.new(
			"Chrysalis",
			CHRYSALIS_TEXTURE,
			_create_base_stats(24.0, 44.0, 28.0, 9.0, "Spore Launcher", 1.5, 5.0)
		),
		AlienShip.new(
			"Fighter",
			FIGHTER_TEXTURE,
			_create_base_stats(8.0, 28.0, 14.0, 18.0, "Plasma Cannon", 0.8, 4.0)
		),
		AlienShip.new(
			"Scout",
			SCOUT_TEXTURE,
			_create_base_stats(4.0, 20.0, 8.0, 24.0, "Scout Pulse", 1.2, 2.4)
		),
		AlienShip.new(
			"Sentinel",
			SENTINEL_TEXTURE,
			_create_base_stats(30.0, 70.0, 36.0, 6.0, "Sentinel Beam", 2.0, 8.0)
		),
		AlienShip.new(
			"Support",
			SUPPORT_TEXTURE,
			_create_base_stats(18.0, 26.0, 18.0, 12.0, "Support Pulse", 2.5, 3.0)
		),
	]


static func create_random_fleet(
	ship_count: int,
	difficulty_multiplier: float
) -> Array[AlienShip]:
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
	random.randomize()
	var randomized_catalog: Array[AlienShip] = []
	for definition in catalog:
		randomized_catalog.append(definition)
	randomized_catalog.shuffle()

	var fleet: Array[AlienShip] = []
	for definition in randomized_catalog:
		if fleet.size() >= ship_count:
			break
		fleet.append(definition.scaled_for_difficulty(difficulty_multiplier))
	while fleet.size() < ship_count:
		var definition := catalog[random.randi_range(0, catalog.size() - 1)]
		fleet.append(definition.scaled_for_difficulty(difficulty_multiplier))
	fleet.shuffle()
	return fleet


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
	damage_per_shot: float
) -> ShipStats:
	var new_stats := ShipStats.new()
	new_stats.shields = shields
	new_stats.integrity = integrity
	new_stats.weight = weight
	new_stats.thrust = thrust
	new_stats.weapons.append(
		ShipWeaponStats.new(weapon_name, fire_interval_seconds, damage_per_shot, 1)
	)
	return new_stats
