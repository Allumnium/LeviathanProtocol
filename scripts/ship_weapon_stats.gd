class_name ShipWeaponStats
extends RefCounted

var weapon_name: String
var fire_interval_seconds: float
var damage_per_shot: float
var projectiles_per_activation: int


func _init(
	p_weapon_name: String,
	p_fire_interval_seconds: float,
	p_damage_per_shot: float,
	p_projectiles_per_activation: int
) -> void:
	weapon_name = p_weapon_name
	fire_interval_seconds = p_fire_interval_seconds
	damage_per_shot = p_damage_per_shot
	projectiles_per_activation = p_projectiles_per_activation


func get_fire_rate_per_second() -> float:
	if fire_interval_seconds <= 0.0:
		push_error("A weapon's fire interval must be greater than zero.")
		return 0.0
	return 1.0 / fire_interval_seconds


func get_dps() -> float:
	return (
		get_fire_rate_per_second()
		* damage_per_shot
		* float(projectiles_per_activation)
	)


func copy() -> ShipWeaponStats:
	return ShipWeaponStats.new(
		weapon_name,
		fire_interval_seconds,
		damage_per_shot,
		projectiles_per_activation
	)
