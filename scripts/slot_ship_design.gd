class_name SlotShipDesign
extends RefCounted

const FORMAT := "chassis_slots_v1"
var chassis_id := ""
var equipment := {} # Stable slot ID -> equipment ID/rank. No cells or materials.

func initialize(id: String) -> bool:
	if SlotCatalog.find_chassis(id).is_empty():
		return false
	chassis_id = id
	equipment.clear()
	return true

func slot(id: String) -> Dictionary:
	for item in SlotCatalog.find_chassis(chassis_id).get("slots", []):
		if item.id == id:
			return item
	return {}

func equip(slot_id: String, equipment_id: String, rank: int, grants: Dictionary) -> bool:
	var mount := slot(slot_id)
	if mount.is_empty():
		return false
	if equipment_id.is_empty():
		equipment.erase(slot_id)
		return true
	var item := SlotCatalog.find_equipment(equipment_id, rank)
	if not SlotCatalog.compatible(mount, item) or not SlotCatalog.unlocked(item, grants):
		return false
	equipment[slot_id] = {"id": equipment_id, "rank": rank}
	return true

func to_data() -> Dictionary:
	return {"version": 3, "format": FORMAT, "chassis_id": chassis_id, "equipment": equipment.duplicate(true)}

func load_data(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 3 or data.get("format") != FORMAT or not data.get("chassis_id") is String or not data.get("equipment") is Dictionary:
		return false
	var next := SlotShipDesign.new()
	if not next.initialize(data.chassis_id):
		return false
	for id: Variant in data.equipment:
		var value: Variant = data.equipment[id]
		if not id is String or not value is Dictionary or not value.get("id") is String or not (value.get("rank") is float or value.get("rank") is int) or value.rank != floor(value.rank):
			return false
		var item := SlotCatalog.find_equipment(value.id, int(value.rank))
		if next.slot(id).is_empty() or not SlotCatalog.compatible(next.slot(id), item):
			return false
		next.equipment[id] = {"id": value.id, "rank": int(value.rank)}
	chassis_id = next.chassis_id
	equipment = next.equipment
	return true

func authorization_error(grants: Dictionary) -> String:
	for value: Dictionary in equipment.values():
		if SlotCatalog.find_equipment(value.id, value.rank).get("retired", false):
			return "Equipment retired."
		if not SlotCatalog.unlocked(SlotCatalog.find_equipment(value.id, value.rank), grants):
			return "Research required."
	return grants.get("error", "")
