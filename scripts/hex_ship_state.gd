class_name HexShipState
extends RefCounted

# Chassis structure is one pool, never a collection of breakable hull tiles.
var design: HexShipDesign
var chassis_integrity := 0.0
var max_chassis_integrity := 0.0
var units: Array[Dictionary] = []
var _cell_units := {}
var _hull := {}
var _core_index := -1

func initialize(blueprint: HexShipDesign) -> bool:
	var copy := HexShipDesign.new()
	if not copy.load_data(blueprint.to_data()):
		return false
	design = copy
	var chassis := design.chassis()
	chassis_integrity = chassis.integrity
	max_chassis_integrity = chassis.integrity
	units.clear()
	_cell_units.clear()
	_hull.clear()
	_core_index = -1
	for cell in chassis.hull:
		_hull[cell] = true
	for builtin in chassis.builtins:
		_add_unit("builtin/" + builtin.id, builtin.equipment_id, int(builtin.rank), builtin.cells, true, {})
	for index in range(design.components.size()):
		var component := design.components[index]
		var footprint: Array[Vector2i] = []
		footprint.assign(HexShipDesign.component_cells(component).keys())
		_add_unit("fitted/%d" % index, component.equipment_id, component.rank, footprint, false, chassis.modifiers_at(footprint[0]))
	# Unassembled material is still physical equipment, but never changes the hull.
	for cell: Vector2i in design.tiles:
		if not _cell_units.has(cell):
			_add_unit("tile/%d/%d" % [cell.x, cell.y], "", 1, [cell], false, {})
	return _core_index >= 0

func _add_unit(id: String, equipment_id: String, rank: int, cells: Array[Vector2i], builtin: bool, modifiers: Dictionary) -> void:
	var hp := float(cells.size())
	for pattern in ShipPartPattern.get_catalog():
		if pattern.definition_id == equipment_id and pattern.rank == rank:
			hp += pattern.stats.integrity / 3.0
			break
	if equipment_id in ["hull_plate", "armor_block", "reactive_bulkhead", "aegis_citadel"]:
		hp *= 1.0 + modifiers.get("armor_integrity", 0.0)
	for cell in cells:
		_cell_units[cell] = units.size()
	if equipment_id == "command_center":
		_core_index = units.size()
	units.append({"id": id, "equipment_id": equipment_id, "rank": rank, "cells": cells.duplicate(),
		"builtin": builtin, "modifiers": modifiers.duplicate(true), "hp": hp, "max_hp": hp})

func is_alive() -> bool:
	return _core_index >= 0 and chassis_integrity >= 0 and units[_core_index].hp > 0

func has_cell(cell: Vector2i) -> bool:
	return is_alive() and _hull.has(cell)

func component_at(cell: Vector2i) -> int:
	var index: int = _cell_units.get(cell, -1)
	return index if index >= 0 and units[index].hp > 0 else -1

func damage_cell(cell: Vector2i, amount: float) -> float:
	if not has_cell(cell) or not is_finite(amount) or amount <= 0:
		return 0
	var index := component_at(cell)
	if index < 0:
		chassis_integrity -= amount
		return amount
	chassis_integrity -= amount * 0.5
	var component_damage := minf(units[index].hp, amount * 0.5)
	units[index].hp -= component_damage
	if units[index].hp <= 0:
		units[index]["load_lost"] = true
	return amount * 0.5 + component_damage

# Ordinary repairs cannot resurrect a destroyed chassis/command center.
func repair_chassis(amount: float) -> float:
	if not is_alive() or not is_finite(amount) or amount <= 0:
		return 0
	var repaired := minf(amount, max_chassis_integrity - chassis_integrity)
	chassis_integrity += repaired
	return repaired

func to_data() -> Dictionary:
	var health: Array = []
	for unit in units:
		health.append({"id": unit.id, "hp": unit.hp, "load_lost": unit.get("load_lost", false)})
	return {"version": 1, "design": design.to_data(), "chassis_integrity": chassis_integrity, "health": health}

func load_data(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not data.get("health") is Array:
		return false
	var blueprint := HexShipDesign.new()
	if not blueprint.load_data(data.get("design")):
		return false
	var next := HexShipState.new()
	if not next.initialize(blueprint) or data.health.size() != next.units.size():
		return false
	var hull_hp: Variant = data.get("chassis_integrity")
	if not (hull_hp is float or hull_hp is int) or not is_finite(float(hull_hp)) or hull_hp > next.max_chassis_integrity:
		return false
	var health := {}
	var lost := {}
	for item: Variant in data.health:
		if not item is Dictionary or not item.get("id") is String or health.has(item.id):
			return false
		var hp: Variant = item.get("hp")
		if not (hp is int or hp is float) or not is_finite(float(hp)) or hp < 0:
			return false
		health[item.id] = hp
		if not item.get("load_lost", false) is bool:
			return false
		lost[item.id] = item.get("load_lost", false) or hp == 0
	for unit in next.units:
		if not health.has(unit.id) or health[unit.id] > unit.max_hp + 0.000001:
			return false
		unit.hp = minf(float(health[unit.id]), unit.max_hp)
		if lost[unit.id]:
			unit["load_lost"] = true
	design = next.design
	chassis_integrity = float(hull_hp)
	max_chassis_integrity = next.max_chassis_integrity
	units = next.units
	_cell_units = next._cell_units
	_hull = next._hull
	_core_index = next._core_index
	return true
