class_name HangarShip
extends FleetShip

# Mount handles bridge the existing combat API; they are not construction cells.
const ART_SCALE := 0.18
const ESCORT_VIEW_SCALE := 0.25
var chassis_id := ""
var flagship := false
var squadron_id := 0
var stance := "seek"
var hull_hp := 0.0
var hull_max := 0.0
var mounts: Dictionary = {} # slot ID -> unique owned equipment instance
var chassis: Dictionary = {}
var art_texture: Texture2D
var equipment_art_mounts: Dictionary = {}
var equipment_art: Dictionary[String, Texture2D] = {}

func initialize_chassis(chassis_key: String, ship_id: int, is_lead := false) -> bool:
	chassis = SlotCatalog.find_chassis(chassis_key)
	if chassis.is_empty():
		return false
	chassis_id = chassis_key
	art_texture = SurfaceArt.texture(chassis.art)
	if art_texture == null:
		return false
	id = ship_id
	display_name = chassis.name + " %d" % id
	flagship = is_lead
	hull_max = float(chassis.get("integrity", 100))
	hull_hp = hull_max
	rebuild_units()
	return true

func is_slot_ship() -> bool:
	return true

func is_flagship() -> bool:
	return flagship

func fleet_view_scale() -> float:
	return 1.0 if flagship else ESCORT_VIEW_SCALE

func rebuild_units() -> void:
	equipment_art.clear()
	equipment_art_mounts.clear()
	var old_max := hull_max
	hull_max = float(chassis.integrity)
	for instance: Dictionary in mounts.values():
		var stats := SlotCatalog.stats_for(instance.equipment_id, int(instance.rank))
		hull_max += stats.integrity
	hull_hp += hull_max - old_max
	units.clear()
	cell_units.clear()
	var engine := ShipPart.new(0, 0, Vector2i.ZERO, [], ShipPartStats.new())
	engine.type = ShipPart.Type.THRUSTER
	engine.stats = ShipPartStats.new(0, 0, 0, float(chassis.get("thrust", 25)))
	_append_mount("engine", Vector2(256, 448), engine)
	if chassis.has("builtin_shield"):
		var item := SlotCatalog.find_equipment(chassis.builtin_shield)
		var shield := ShipPart.new(0, 0, Vector2i.ZERO, [], ShipPartStats.new())
		shield.type = ShipPart.Type.SHIELD
		shield.definition_id = item.id
		shield.rank = 1
		shield.stats = SlotCatalog.stats_for(item.id)
		var count := int(chassis.get("builtin_shield_count", 1))
		shield.stats.shields *= count
		shield.stats.weight *= count
		_append_mount("shield", Vector2(256, 320), shield)
	for slot: Dictionary in chassis.slots:
		if not mounts.has(slot.id):
			continue
		var instance: Dictionary = mounts[slot.id]
		var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
		var sprite := SlotCatalog.equipment_texture(item)
		if sprite != null:
			equipment_art[slot.id] = sprite
			equipment_art_mounts[slot.id] = item.get("art_mount", [])
		var part := ShipPart.new(0, 0, Vector2i.ZERO, [], ShipPartStats.new())
		part.type = int(item.part_type)
		part.definition_id = item.id
		part.rank = int(item.rank)
		part.stats = SlotCatalog.stats_for(item.id, int(item.rank))
		_append_mount(slot.id, Vector2(slot.rect[0] + slot.rect[2] / 2.0, slot.rect[1] + slot.rect[3] / 2.0), part)
	visual_revision += 1

func _append_mount(key: String, source_position: Vector2, part: ShipPart) -> void:
	var handle := Vector2i(units.size(), 0)
	cell_units[handle] = units.size()
	# Shared combat DTOs require an operational marker, not component integrity.
	units.append({"key": key, "position": (source_position - Vector2(256, 256)).rotated(PI / 2) * ART_SCALE,
		"cells": [handle], "part": part, "max_hp": 1.0, "hp": 1.0})

func draw_fitted_equipment(target: CanvasItem, chassis_rect: Rect2, tint := Color.WHITE) -> void:
	for slot: Dictionary in chassis.slots:
		if not equipment_art.has(slot.id):
			continue
		var texture: Texture2D = equipment_art[slot.id]
		var bounds := Rect2(chassis_rect.position + Vector2(slot.rect[0], slot.rect[1]) * chassis_rect.size / 512,
			Vector2(slot.rect[2], slot.rect[3]) * chassis_rect.size / 512)
		target.draw_texture_rect(texture, SlotCatalog.fitted_art_rect(texture, bounds, equipment_art_mounts.get(slot.id, [])), false, tint)

func is_alive() -> bool:
	return not chassis.is_empty() and hull_hp >= 0

func has_cell(cell: Vector2i) -> bool:
	return is_alive() and cell_units.has(cell)

func local_cell_position(cell: Vector2i) -> Vector2:
	return units[cell_units[cell]].position if cell_units.has(cell) else Vector2.ZERO

func get_stats(_laser_level := 0, energy_efficiency := 0.0) -> ShipStats:
	var result := ShipStats.new()
	result.integrity = hull_hp
	result.weight = float(chassis.get("mass", 35))
	result.collision_radius = float(chassis.get("radius", 36))
	result.footprint_size = Vector2.ONE * 512 * ART_SCALE
	for index in range(units.size()):
		var unit: Dictionary = units[index]
		var part: ShipPart = unit.part
		result.weight += part.stats.weight
		result.thrust += part.stats.thrust
		result.shields += part.stats.shields
		result.shield_recharge += part.stats.shields * (1 + energy_efficiency)
		for weapon in part.stats.weapons:
			var copy := weapon.copy()
			copy.damage_per_shot *= float(chassis.get("weapon_damage_multiplier", 1.0))
			copy.fire_interval_seconds /= weapon_cycle_rate()
			if part.type in [ShipPart.Type.LASER, ShipPart.Type.DOUBLE_LASER, ShipPart.Type.BEAM_LANCE, ShipPart.Type.ION_EMITTER]:
				copy.fire_interval_seconds /= 1 + energy_efficiency
			copy.mount_offset = unit.position
			copy.component_index = index
			result.weapons.append(copy)
	return result

func weapon_cycle_rate() -> float:
	var count := 0
	for unit: Dictionary in units:
		if unit.part != null and unit.part.type == ShipPart.Type.AMMUNITION_MAGAZINE:
			count += 1
	return 1.0 + float(chassis.get("weapon_cycle_bonus", 0.0)) + 0.2 * count

func hangar_summary() -> Dictionary:
	var stats := get_stats()
	var result := {"integrity": hull_hp, "integrity_max": hull_max, "shields": stats.shields,
		"dps": stats.dps, "cargo": 0, "passengers": 0}
	if is_alive():
		for unit: Dictionary in units:
			if unit.part != null:
				if unit.part.definition_id == "cargo_hold":
					result.cargo += HangarTrade.CARGO_CAPACITY
				if unit.part.definition_id == "passenger_cabin":
					result.passengers += HangarTrade.PASSENGER_CAPACITY
	return result

func hit_cell(_origin: Vector2, _random: RandomNumberGenerator) -> Vector2i:
	return Vector2i(-1, 0)

func damage_cell(_cell: Vector2i, amount: float) -> Dictionary:
	return damage_hull(amount)

func damage_hull(amount: float, hit_fraction := 1.0) -> Dictionary:
	var removed: Array[Vector2i] = []
	if not is_alive() or not is_finite(amount) or amount <= 0 or not is_finite(hit_fraction) or hit_fraction <= 0:
		return {"damage": 0.0, "removed": removed}
	var damage := maxf(0, amount - float(chassis.get("flat_damage_reduction", 0.0)) * hit_fraction)
	hull_hp -= damage
	visual_revision += 1
	return {"damage": damage, "removed": removed}

func needs_repair() -> bool:
	return hull_hp < hull_max

func repair_cost() -> int:
	return ceili(maxf(0, hull_max - hull_hp))

func repair_hull(amount: float) -> float:
	if not is_alive() or not is_finite(amount) or amount <= 0:
		return 0.0
	var healed := minf(amount, hull_max - hull_hp)
	hull_hp += healed
	return healed

func repair() -> void:
	if not is_alive():
		return
	hull_hp = hull_max
	visual_revision += 1

func to_hangar_data() -> Dictionary:
	var fitted := {}
	for key in mounts:
		fitted[key] = mounts[key].uid
	return {"id": id, "chassis": chassis_id, "flagship": flagship, "hull_hp": hull_hp,
		"mounts": fitted,
		"formation": [formation.x, formation.y]}
