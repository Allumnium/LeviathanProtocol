class_name ShipStats
extends RefCounted

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


func add_equipment(equipment_stats: ShipPartStats) -> void:
	if equipment_stats == null:
		push_error("Cannot add missing ship-part stats.")
		return

	shields += equipment_stats.shields
	integrity += equipment_stats.integrity
	weight += equipment_stats.weight
	thrust += equipment_stats.thrust
	for weapon in equipment_stats.weapons:
		weapons.append(weapon.copy())
