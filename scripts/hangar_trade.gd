class_name HangarTrade
extends RefCounted

static func economy() -> Dictionary:
	return Content.get_def("economy", "core:default")

static func load_spec(instance: Dictionary) -> Dictionary:
	var item := SlotCatalog.find_equipment(str(instance.equipment_id), int(instance.get("rank", 1)))
	return {"kind": item.get("load_kind", ""), "capacity": int(item.get("load_capacity", 0))}

static func summary(data: Dictionary) -> Dictionary:
	var totals := {"cargo": 0, "cargo_capacity": 0, "passengers": 0, "passenger_capacity": 0}
	for ship: Dictionary in data.ships:
		if ship.hull_hp < 0:
			continue
		for uid: String in ship.mounts.values():
			var instance: Dictionary = data.equipment[uid]
			var spec := load_spec(instance)
			if spec.kind == "cargo":
				totals.cargo_capacity += spec.capacity
				totals.cargo += int(instance.get("load", {}).get("quantity", 0))
			elif spec.kind == "passengers":
				totals.passenger_capacity += spec.capacity
				totals.passengers += int(instance.get("load", {}).get("quantity", 0))
	return totals

# Loads belong to physical equipment IDs, never slot indices or blueprints.
static func depart(data: Dictionary, source: Dictionary, target: Dictionary) -> void:
	if not source.inhabited:
		return
	for ship: Dictionary in data.ships:
		for uid: String in ship.mounts.values():
			var instance: Dictionary = data.equipment[uid]
			if ship.hull_hp < 0 or not instance.get("load", {}).is_empty():
				continue
			var spec := load_spec(instance)
			if spec.kind == "passengers" and target.inhabited:
				instance["load"] = {"kind": "passengers", "quantity": spec.capacity, "unit_value": int(economy().passenger_fare), "origin": int(source.id)}
			elif spec.kind == "cargo":
				instance["load"] = {"kind": "cargo", "quantity": spec.capacity, "unit_value": int(source.goods_unit_value), "origin": int(source.id)}

static func arrive(data: Dictionary, node: Dictionary, skip_origin := -1) -> void:
	if not node.inhabited:
		return
	for ship: Dictionary in data.ships:
		for uid: String in ship.mounts.values():
			var instance: Dictionary = data.equipment[uid]
			var contents: Dictionary = instance.get("load", {})
			if contents.is_empty() or ship.hull_hp < 0:
				continue
			# Loads returning to their origin stay aboard for a different port.
			if skip_origin >= 0 and int(contents.get("origin", -1)) == skip_origin:
				continue
			var chassis := SlotCatalog.find_chassis(ship.chassis)
			RunScore.earn_credits(data, roundi(int(contents.quantity) * int(contents.unit_value)
				* float(chassis.get("delivery_income_multiplier", 1.0))))
			instance["load"] = {}

static func settle_losses(data: Dictionary, lost_ships: Array[int]) -> void:
	for ship: Dictionary in data.ships:
		for uid: String in ship.mounts.values():
			var instance: Dictionary = data.equipment[uid]
			if int(ship.id) not in lost_ships:
				continue
			var contents: Dictionary = instance.get("load", {})
			if contents.get("kind") == "passengers":
				data.credits -= int(contents.quantity) * int(economy().passenger_death_fee)
			instance["load"] = {}

static func has_load(instance: Dictionary) -> bool:
	return not instance.get("load", {}).is_empty()

static func valid(instance: Dictionary) -> bool:
	var contents: Variant = instance.get("load", {})
	if not contents is Dictionary:
		return false
	if contents.is_empty():
		return true
	var spec := load_spec(instance)
	var kind: String = spec.kind
	if kind.is_empty() or contents.get("kind") != kind or not HangarCheckpoint._integer(contents.get("quantity"), 1) or contents.quantity > spec.capacity or not HangarCheckpoint._integer(contents.get("origin"), 0):
		return false
	if not HangarCheckpoint._integer(contents.get("unit_value"), 1):
		return false
	# A load freezes its departure fare. Later price changes never rewrite it.
	return int(contents.unit_value) <= 1000000
