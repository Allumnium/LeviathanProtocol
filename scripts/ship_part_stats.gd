class_name ShipPartStats
extends RefCounted

var shields: float
var integrity: float
var weight: float
var thrust: float
var weapons: Array[ShipWeaponStats] = []


func _init(
	p_shields: float = 0.0,
	p_integrity: float = 0.0,
	p_weight: float = 0.0,
	p_thrust: float = 0.0
) -> void:
	shields = p_shields
	integrity = p_integrity
	weight = p_weight
	thrust = p_thrust


func copy() -> ShipPartStats:
	var copied_stats := ShipPartStats.new(shields, integrity, weight, thrust)
	for weapon in weapons:
		copied_stats.weapons.append(weapon.copy())
	return copied_stats


static func with_weapon(
	p_weight: float,
	fire_interval_seconds: float,
	damage_per_shot: float,
	projectiles_per_activation: int
) -> ShipPartStats:
	var stats := ShipPartStats.new(0.0, 0.0, p_weight, 0.0)
	stats.weapons.append(
		ShipWeaponStats.new(
			fire_interval_seconds,
			damage_per_shot,
			projectiles_per_activation
		)
	)
	return stats
