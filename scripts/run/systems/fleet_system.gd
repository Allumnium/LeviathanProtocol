class_name FleetSystem
extends RefCounted

const Loadouts = preload("res://scripts/ship_loadouts.gd")

static func _entry(tx: RunTransaction, id: int) -> Dictionary:
	for entry: Dictionary in tx.doc.fleet.ships:
		if int(entry.id) == id:
			return entry
	return {}

static func _manage(tx: RunTransaction, content: DefDatabase, message: String) -> bool:
	if not tx.error.is_empty():
		return false
	if not FactView.new(tx.doc, content).can_manage():
		tx.error = message
		return false
	return true

static func _shipyard(tx: RunTransaction, content: DefDatabase) -> bool:
	if not tx.error.is_empty():
		return false
	tx.error = FactView.new(tx.doc, content).service_error("shipyard")
	return tx.error.is_empty()

static func set_stance(tx: RunTransaction, content: DefDatabase, group_id: int, stance: String) -> bool:
	if not _manage(tx, content, "Squadron orders are unavailable."):
		return false
	if stance not in HangarSquadrons.STANCES:
		tx.error = "Squadron orders are unavailable."
		return false
	var group := HangarSquadrons.find(tx.doc.fleet.squadrons, group_id)
	if group.is_empty():
		tx.error = "Unknown squadron."
		return false
	group.stance = stance
	tx.record("fleet.orders_changed", {"squadron_id": group_id, "stance": stance})
	return true

static func assign(tx: RunTransaction, content: DefDatabase, ship_id: int, group_id: int) -> bool:
	if not _manage(tx, content, "Squadron assignments are unavailable."):
		return false
	var data: Dictionary = tx.doc.fleet
	var entry := _entry(tx, ship_id)
	var target := HangarSquadrons.find(data.squadrons, group_id)
	if entry.is_empty() or (group_id != 0 and (target.is_empty() or target.chassis != entry.chassis)):
		tx.error = "Choose a squadron of the same ship class."
		return false
	var previous := HangarSquadrons.for_ship(data.squadrons, ship_id)
	if previous.id == group_id or (group_id == 0 and previous.members.size() == 1):
		tx.error = "Already assigned."
		return false
	previous.members.erase(ship_id)
	previous.overrides.erase(ship_id)
	if group_id == 0:
		var id := 1
		for group: Dictionary in data.squadrons:
			id = maxi(id, int(group.id) + 1)
		target = previous.duplicate(true)
		target.id = id
		target.members = []
		target.overrides = []
		data.squadrons.append(target)
	HangarSquadrons.add_ship(data, entry, int(target.id), "", content)
	tx.record("fleet.assignment_changed", {"ship_id": ship_id, "squadron_id": target.id})
	return true

static func _stage_refit(tx: RunTransaction, content: DefDatabase, ship_id: int, target: Dictionary, allow_unchanged := false) -> bool:
	var data: Dictionary = tx.doc.fleet
	var entry := _entry(tx, ship_id)
	if entry.is_empty():
		tx.error = "Refits are unavailable right now."
		return false
	var chassis := SlotCatalog.find_chassis(entry.chassis, content)
	var current := Loadouts.current_keys(entry.mounts, data.equipment)
	for slot_id: String in target:
		var item := Loadouts.item_for(str(target[slot_id]), content)
		if not SlotCatalog.compatible(Loadouts.slot_by_id(chassis, slot_id), item) or not Loadouts.obtainable(item):
			tx.error = "That part does not fit this mount."
			return false
		if str(current.get(slot_id, "")) != str(target[slot_id]) and not Loadouts.equipment_available(item, data.research.research_ids, content):
			tx.error = "Research this equipment first."
			return false
	if SaveValidation.same(current, target):
		if allow_unchanged:
			return true
		tx.error = "Already fitted."
		return false
	var facts := FactView.new(tx.doc, content)
	var armor_before := facts.fitted_integrity(entry)
	var slots := current.keys()
	for slot_id: String in target:
		if slot_id not in slots:
			slots.append(slot_id)
	for slot_id: String in slots:
		if str(current.get(slot_id, "")) == str(target.get(slot_id, "")):
			continue
		if entry.mounts.has(slot_id):
			var old_uid: String = entry.mounts[slot_id]
			if HangarTrade.has_load(data.equipment[old_uid]):
				tx.error = "Deliver passengers/cargo first"
				return false
			data.equipment.erase(old_uid)
			entry.mounts.erase(slot_id)
		if target.has(slot_id):
			var parsed := Loadouts.parse_key(str(target[slot_id]))
			var uid := str(data.next_equipment_id)
			data.next_equipment_id += 1
			data.equipment[uid] = {"uid": uid, "equipment_id": parsed.id, "rank": int(parsed.rank)}
			entry.mounts[slot_id] = uid
	entry.hull_hp = clampf(float(entry.hull_hp) + facts.fitted_integrity(entry) - armor_before, 0.0, facts.hull_max(entry))
	return true

static func refit(tx: RunTransaction, content: DefDatabase, ship_id: int, target: Dictionary) -> bool:
	if not _shipyard(tx, content) or not _stage_refit(tx, content, ship_id, target):
		return false
	HangarSquadrons.update_override(tx.doc.fleet, ship_id, content)
	tx.record("fleet.refitted", {"ship_id": ship_id, "mounts": target})
	return true

static func refit_ship(tx: RunTransaction, content: DefDatabase, ship_id: int, loadout_id: String) -> bool:
	var entry := _entry(tx, ship_id)
	var loadout := {} if entry.is_empty() else Loadouts.find(entry.chassis, loadout_id, content)
	if loadout.is_empty():
		tx.error = "Unknown loadout."
		return false
	if not Loadouts.available(loadout, tx.doc.fleet.research.research_ids, content):
		tx.error = "Research this loadout's equipment first."
		return false
	return refit(tx, content, ship_id, loadout.mounts)

static func swap_part(tx: RunTransaction, content: DefDatabase, ship_id: int, slot_id: String, key: String) -> bool:
	var entry := _entry(tx, ship_id)
	if entry.is_empty():
		tx.error = "Unknown ship."
		return false
	var target := Loadouts.current_keys(entry.mounts, tx.doc.fleet.equipment)
	if key.is_empty():
		target.erase(slot_id)
	else:
		target[slot_id] = key
	return refit(tx, content, ship_id, target)

static func refit_squadron(tx: RunTransaction, content: DefDatabase, group_id: int, loadout_id: String, reset_overrides: bool) -> bool:
	if not _shipyard(tx, content):
		return false
	var data: Dictionary = tx.doc.fleet
	var group := HangarSquadrons.find(data.squadrons, group_id)
	var loadout := Loadouts.find(str(group.get("chassis", "")), loadout_id, content)
	if group.is_empty() or loadout.is_empty():
		tx.error = "Unknown squadron loadout."
		return false
	if not Loadouts.available(loadout, data.research.research_ids, content):
		tx.error = "Research this loadout's equipment first."
		return false
	var overrides: Array = group.overrides.duplicate()
	group.loadout = loadout_id
	for id: int in group.members:
		if reset_overrides or id not in overrides:
			if not _stage_refit(tx, content, id, loadout.mounts, true):
				return false
		HangarSquadrons.update_override(data, id, content)
	tx.record("fleet.refitted", {"squadron_id": group_id, "loadout": loadout_id, "reset_overrides": reset_overrides})
	return true

static func fit_equipment(tx: RunTransaction, content: DefDatabase, ship_id: int, slot_id: String, uid: String) -> bool:
	if not _shipyard(tx, content):
		return false
	var data: Dictionary = tx.doc.fleet
	var target := _entry(tx, ship_id)
	var chassis := {} if target.is_empty() else SlotCatalog.find_chassis(target.chassis, content)
	var slot := Loadouts.slot_by_id(chassis, slot_id)
	if slot.is_empty() or (not uid.is_empty() and not data.equipment.has(uid)):
		tx.error = "Unknown ship, mount or equipment."
		return false
	if not uid.is_empty():
		var instance: Dictionary = data.equipment[uid]
		var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank), content)
		if not SlotCatalog.compatible(slot, item) or not Loadouts.obtainable(item):
			tx.error = "That part does not fit this mount."
			return false
		if not Loadouts.equipment_available(item, data.research.research_ids, content):
			tx.error = "Research this equipment first."
			return false
	var facts := FactView.new(tx.doc, content)
	for entry: Dictionary in data.ships:
		var armor_before := facts.fitted_integrity(entry)
		for key: String in entry.mounts.keys():
			if entry.mounts[key] == uid or (int(entry.id) == ship_id and key == slot_id):
				if HangarTrade.has_load(data.equipment[entry.mounts[key]]):
					tx.error = "Deliver passengers/cargo first"
					return false
				if entry.mounts[key] != uid:
					data.equipment.erase(entry.mounts[key])
				entry.mounts.erase(key)
		if int(entry.id) == ship_id and not uid.is_empty():
			entry.mounts[slot_id] = uid
		entry.hull_hp += facts.fitted_integrity(entry) - armor_before
		if entry.hull_hp < 0:
			tx.error = "Removing this equipment would destroy a ship."
			return false
		HangarSquadrons.update_override(data, int(entry.id), content)
	tx.record("fleet.equipment_moved", {"ship_id": ship_id, "slot": slot_id, "uid": uid})
	return true

static func repair(tx: RunTransaction, content: DefDatabase, ids: Array) -> bool:
	if not _shipyard(tx, content):
		return false
	var facts := FactView.new(tx.doc, content)
	var cost := facts.repair_cost(ids)
	if cost <= 0 or tx.doc.fleet.credits < cost:
		tx.error = "No repairs needed." if cost <= 0 else "Not enough credits. Cost: %d." % cost
		return false
	for entry: Dictionary in tx.doc.fleet.ships:
		if int(entry.id) in ids and float(entry.hull_hp) >= 0:
			entry.hull_hp = facts.hull_max(entry)
	tx.doc.fleet.credits -= cost
	tx.record("fleet.repaired", {"ship_ids": ids, "credits": cost})
	return true

static func move(tx: RunTransaction, content: DefDatabase, positions: Dictionary, battle := false) -> bool:
	var data: Dictionary = tx.doc.fleet
	var living: Array = data.ships.filter(func(entry: Dictionary) -> bool: return float(entry.hull_hp) >= 0)
	if (battle and (not data.pending or data.ended or data.completed or positions.size() != living.size())) \
			or (not battle and not FactView.new(tx.doc, content).can_manage()) or positions.is_empty():
		tx.error = "Battle deployment is unavailable." if battle else "Formation changes are unavailable."
		return false
	var area := BattleSimulation.deployment_area(data.pending_encounter) if battle else BattleSimulation.formation_area()
	for id: int in positions:
		var entry := _entry(tx, id)
		var position: Variant = positions[id]
		if entry.is_empty() or (battle and float(entry.hull_hp) < 0) or not position is Vector2 or not position.is_finite():
			tx.error = "Place every ship inside the deployment area."
			return false
		var radius := Vector2.ONE * float(SlotCatalog.find_chassis(entry.chassis, content).radius)
		if not battle:
			radius /= BattleSimulation.DEPLOYMENT_SCALE
		if position != position.clamp(area.position + radius, area.end - radius):
			tx.error = "Place every ship inside the deployment area."
			return false
		var formation: Vector2 = (position - BattleSimulation.PLAYER_FORMATION_CENTER) / BattleSimulation.DEPLOYMENT_SCALE if battle else position
		entry.formation = [formation.x, formation.y]
	HangarSquadrons.sync(data)
	# Formation may be adjusted repeatedly; keep the durable hook without flooding the journal.
	tx.emit_hook("fleet.formation_changed", {"battle": battle, "ship_ids": positions.keys()})
	return true
