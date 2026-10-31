class_name HangarTrade
extends RefCounted

const PASSENGER_DEATH_FEE := 20

# Loads belong to physical equipment IDs, never slot indices or blueprints.
static func depart(data: Dictionary, source: Dictionary, target: Dictionary) -> void:
	for ship: Dictionary in data.ships:
		for uid: String in ship.mounts.values():
			var instance: Dictionary = data.equipment[uid]
			if instance.hp <= 0 or not instance.get("load", {}).is_empty():
				continue
			if instance.equipment_id == "passenger_cabin" and target.inhabited:
				instance["load"] = {"kind": "passengers", "quantity": 4, "unit_value": 8, "origin": int(source.id)}
			elif instance.equipment_id == "cargo_hold" and source.inhabited:
				instance["load"] = {"kind": "cargo", "quantity": 10, "unit_value": int(source.goods_unit_value), "origin": int(source.id)}

static func arrive(data: Dictionary, node: Dictionary) -> void:
	if not node.inhabited:
		return
	for ship: Dictionary in data.ships:
		for uid: String in ship.mounts.values():
			var instance: Dictionary = data.equipment[uid]
			var contents: Dictionary = instance.get("load", {})
			if contents.is_empty() or instance.hp <= 0:
				continue
			data.credits += int(contents.quantity) * int(contents.unit_value)
			instance["load"] = {}

static func settle_losses(data: Dictionary, lost_ships: Array[int]) -> void:
	for ship: Dictionary in data.ships:
		for uid: String in ship.mounts.values():
			var instance: Dictionary = data.equipment[uid]
			if instance.hp > 0 and int(ship.id) not in lost_ships:
				continue
			var contents: Dictionary = instance.get("load", {})
			if contents.get("kind") == "passengers":
				data.credits -= int(contents.quantity) * PASSENGER_DEATH_FEE
			instance["load"] = {}

static func has_load(instance: Dictionary) -> bool:
	return not instance.get("load", {}).is_empty()

static func valid(instance: Dictionary) -> bool:
	var contents: Variant = instance.get("load", {})
	if not contents is Dictionary:
		return false
	if contents.is_empty():
		return true
	var kind: String = "cargo" if instance.equipment_id == "cargo_hold" else ("passengers" if instance.equipment_id == "passenger_cabin" else "")
	if kind.is_empty() or contents.get("kind") != kind or not HangarCheckpoint._integer(contents.get("quantity"), 1) or contents.quantity > (10 if kind == "cargo" else 4) or not HangarCheckpoint._integer(contents.get("origin"), 0):
		return false
	if not HangarCheckpoint._integer(contents.get("unit_value"), 1):
		return false
	return int(contents.unit_value) in [3, 6, 10] if kind == "cargo" else int(contents.unit_value) == 8
