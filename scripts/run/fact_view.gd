class_name FactView
extends RefCounted

## Read-only queries over a transaction/document and its owning definitions.
## Returned ship rows are copies; systems mutate their private transaction.
var _doc: Dictionary
var _content: DefDatabase
var _items := {}

func _init(doc: Dictionary, content: DefDatabase) -> void:
	_doc = doc
	_content = content

func ship(id: int) -> Dictionary:
	for entry: Dictionary in _doc.fleet.ships:
		if int(entry.id) == id:
			return entry.duplicate(true)
	return {}

func can_manage() -> bool:
	return not _doc.meta.id.is_empty() and not _doc.fleet.pending and not _doc.fleet.ended and not _doc.fleet.completed

func fitted_integrity(entry: Dictionary) -> float:
	var total := 0.0
	for uid: String in entry.mounts.values():
		var instance: Dictionary = _doc.fleet.equipment[uid]
		total += float(SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank), _content).stats.integrity)
	return total

func hull_max(entry: Dictionary) -> float:
	return float(SlotCatalog.find_chassis(entry.chassis, _content).integrity) + fitted_integrity(entry)

func repair_cost(ids: Array) -> int:
	var cost := 0
	for entry: Dictionary in _doc.fleet.ships:
		if int(entry.id) in ids and float(entry.hull_hp) >= 0:
			cost += ceili(maxf(0, hull_max(entry) - float(entry.hull_hp)))
	return cost

func _equipment(instance: Dictionary) -> Dictionary:
	var key := SlotCatalog.equipment_key(instance.equipment_id, int(instance.rank))
	if not _items.has(key):
		_items[key] = SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank), _content)
	return _items[key]

func research_grants() -> Dictionary:
	return ResearchRules.resolve(_doc.fleet.research.research_ids, HangarResearch.catalog(_content), _content)

func research_capabilities() -> Dictionary:
	var result := {}
	for entry: Dictionary in _doc.fleet.ships:
		if float(entry.hull_hp) < 0:
			continue
		var chassis := SlotCatalog.find_chassis(entry.chassis, _content)
		if float(chassis.get("self_repair_hp_per_second", 0)) > 0:
			result["passive_repair"] = true
		for uid: String in entry.mounts.values():
			for capability: String in _equipment(_doc.fleet.equipment[uid]).get("research_capabilities", []):
				result[capability] = true
		if chassis.has("builtin_shield"):
			for capability: String in SlotCatalog.find_equipment(chassis.builtin_shield, 1, _content).get("research_capabilities", []):
				result[capability] = true
	return result

func matches_research(id: String) -> bool:
	var targets: Array = Content.get_def("research", id, "", _content).get("equipment_capabilities_any", [])
	if targets.is_empty():
		return true
	var capabilities := research_capabilities()
	return targets.any(func(capability: String) -> bool: return capabilities.has(capability))

func research_option_count() -> int:
	var base := int(_content.get_def("research_tuning", "core:default").base_options)
	for entry: Dictionary in _doc.fleet.ships:
		if entry.flagship and float(entry.hull_hp) >= 0:
			return base + int(SlotCatalog.find_chassis(entry.chassis, _content).get("research_option_bonus", 0))
	return base

func research_production_rate() -> float:
	var rate := 0.0
	var modifiers: Dictionary = research_grants().modifiers
	for entry: Dictionary in _doc.fleet.ships:
		if float(entry.hull_hp) < 0:
			continue
		var chassis := SlotCatalog.find_chassis(entry.chassis, _content)
		for uid: String in entry.mounts.values():
			var item := _equipment(_doc.fleet.equipment[uid])
			if int(item.part_type) != ShipPart.Type.RESEARCH_LAB:
				continue
			var multiplier := float(chassis.get("research_rate_multiplier", 1.0))
			if "research" in item.get("research_capabilities", []):
				multiplier *= ResearchUpgrades.value(modifiers, "research_output_multiplier")
			rate += int(item.rank) * multiplier
	return rate

func service_error(service: String) -> String:
	return station_service_error(can_manage(), _doc.travel, _doc.sites, service)

static func station_service_error(available: bool, travel: Dictionary, sites: Dictionary, service: String) -> String:
	if not available:
		return "Station services are unavailable during combat or after the run ends."
	if travel.is_empty():
		return "No active expedition state."
	if ExpeditionState.PauseReason.SAVE_ERROR in travel.pause_reasons:
		return "Retry the failed save before using station services."
	if travel.travel_state != ExpeditionState.TravelState.DOCKED:
		if service == "ammunition":
			return "Dock at a station to buy missiles."
		return "Dock at a shipyard to refit, sell, salvage or repair." if service == "shipyard" \
			else "Dock at a refueling station to refuel."
	var location: Dictionary = sites.get(travel.docked_location_id, {})
	if location.is_empty() or location.get("kind") != "station" \
			or Vector2(travel.position_nu[0], travel.position_nu[1]).distance_to(Vector2(location.position[0], location.position[1])) > 0.000001:
		return "The fleet is not docked at a valid station."
	var services := ExpeditionSimulation.available_services(location, travel.flags)
	if services.is_empty():
		return "This port is abandoned; use another station."
	if service != "ammunition" and service not in services:
		return "This station has no shipyard." if service == "shipyard" else "This station does not offer refueling."
	return ""
