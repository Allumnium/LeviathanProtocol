extends RefCounted

static func _state() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("GameState")

static func payload(uid: String) -> Dictionary:
	return {"kind": "hangar_equipment", "uid": uid, "run_id": _state().run_id}

static func valid(data: Variant) -> bool:
	return data is Dictionary and data.get("kind") == "hangar_equipment" and data.get("run_id") == _state().run_id \
		and data.get("uid") is String and _state().equipment_inventory.has(data.uid) \
		and _state().can_use_shipyard()

static func can_fit(ship_id: int, slot_id: String, data: Variant, grants: Dictionary = {}) -> bool:
	if not valid(data):
		return false
	var owned: HangarShip = _state().owned_ship(ship_id)
	if owned == null or not owned.is_alive() or owned.mounts.get(slot_id, {}).get("uid") == data.uid:
		return false
	var instance: Dictionary = _state().equipment_inventory[data.uid]
	if HangarTrade.has_load(instance) or instance.equipment_id in HangarResearch.DEFERRED_PURCHASES:
		return false
	var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
	if grants.is_empty():
		grants = _state().research_grants()
	for slot: Dictionary in owned.chassis.slots:
		if slot.id == slot_id:
			return not HangarTrade.has_load(owned.mounts.get(slot_id, {})) and SlotCatalog.compatible(slot, item) and SlotCatalog.unlocked(item, grants)
	return false

static func can_store(data: Variant) -> bool:
	return valid(data) and not _state().equipment_location(data.uid).is_empty() \
		and not HangarTrade.has_load(_state().equipment_inventory[data.uid])

static func store(data: Variant) -> bool:
	if not can_store(data):
		return false
	var source: Dictionary = _state().equipment_location(data.uid)
	return _state().fit_equipment(int(source.ship_id), source.slot, "")
