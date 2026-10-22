class_name ShipWeaponStats
extends RefCounted

var weapon_name: String
var fire_interval_seconds: float
var damage_per_shot: float
var projectiles_per_activation: int
var range_units: float
var mount_offset := Vector2.ZERO
var is_projectile_weapon := false
var component_index := -1


func _init(
	p_weapon_name: String,
	p_fire_interval_seconds: float,
	p_damage_per_shot: float,
	p_projectiles_per_activation: int,
	p_range_units: float = 220.0,
	p_mount_offset: Vector2 = Vector2.ZERO
) -> void:
	weapon_name = p_weapon_name
	fire_interval_seconds = p_fire_interval_seconds
	damage_per_shot = p_damage_per_shot
	projectiles_per_activation = p_projectiles_per_activation
	range_units = p_range_units
	mount_offset = p_mount_offset


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
	var copied_weapon := ShipWeaponStats.new(
		weapon_name,
		fire_interval_seconds,
		damage_per_shot,
		projectiles_per_activation,
		range_units,
		mount_offset
	)
	copied_weapon.is_projectile_weapon = is_projectile_weapon
	copied_weapon.component_index = component_index
	return copied_weapon
