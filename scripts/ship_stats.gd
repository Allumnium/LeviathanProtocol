class_name ShipStats
extends RefCounted

const INTEGRITY_MULTIPLIER := 1.0 / 3.0

var shields := 0.0
var integrity := 0.0
var weight := 0.0
var thrust := 0.0
var weapons: Array[ShipWeaponStats] = []
var dps: float:
	get:
		var total_dps := 0.0
		for weapon in weapons:
			total_dps += weapon.get_dps()
		return total_dps


func add_equipment(
	equipment_stats: ShipPartStats,
	weapon_mount_offset: Vector2 = Vector2.ZERO
) -> void:
	if equipment_stats == null:
		push_error("Cannot add missing ship-part stats.")
		return

	shields += equipment_stats.shields
	integrity += equipment_stats.integrity * INTEGRITY_MULTIPLIER
	weight += equipment_stats.weight
	thrust += equipment_stats.thrust
	for weapon in equipment_stats.weapons:
		var copied_weapon := weapon.copy()
		copied_weapon.mount_offset += weapon_mount_offset
		weapons.append(copied_weapon)
