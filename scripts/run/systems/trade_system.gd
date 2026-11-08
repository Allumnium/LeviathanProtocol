class_name TradeSystem
extends RefCounted

const Loadouts = preload("res://scripts/ship_loadouts.gd")

static func _service(tx: RunTransaction, content: DefDatabase, service: String) -> bool:
	if not tx.error.is_empty():
		return false
	tx.error = FactView.new(tx.doc, content).service_error(service)
	return tx.error.is_empty()

static func ammunition_quote(content: DefDatabase) -> Dictionary:
	var economy := content.get_def("economy", "core:default")
	return {"count": int(economy.missile_pack_size), "price": int(economy.missile_pack_price)}

static func buy_ammunition(tx: RunTransaction, content: DefDatabase) -> bool:
	if not _service(tx, content, "ammunition"):
		return false
	var quote := ammunition_quote(content)
	if tx.doc.fleet.credits < quote.price:
		tx.error = "Not enough credits. Cost: %d." % quote.price
		return false
	if tx.doc.fleet.missiles > 2147483647 - quote.count:
		tx.error = "Missile storage limit reached."
		return false
	tx.doc.fleet.credits -= quote.price
	tx.doc.fleet.missiles += quote.count
	tx.record("trade.completed", {"kind": "ammunition", "count": quote.count, "credits": quote.price})
	return true

static func refuel(tx: RunTransaction, content: DefDatabase) -> bool:
	if not _service(tx, content, "refuel"):
		return false
	var travel: Dictionary = tx.doc.travel
	var missing := float(travel.fuel_capacity) - float(travel.fuel)
	if missing <= 0.000001:
		tx.error = "The expedition fuel tanks are already full."
		return false
	var price := ceili(missing * float(content.get_def("economy", "core:default").fuel_unit_price))
	if tx.doc.fleet.credits < price:
		tx.error = "Not enough credits to refuel. Cost: %d." % price
		return false
	tx.doc.fleet.credits -= price
	travel.fuel = travel.fuel_capacity
	tx.record("trade.completed", {"kind": "fuel", "quantity": missing, "credits": price})
	return true

static func buy_ships(tx: RunTransaction, content: DefDatabase, key: String, count: Variant, group_id: int, loadout_id: String) -> bool:
	if not _service(tx, content, "shipyard"):
		return false
	if not SaveValidation.integer(count) or count <= 0:
		tx.error = "Choose a positive whole number of ships."
		return false
	var data: Dictionary = tx.doc.fleet
	var group := HangarSquadrons.find(data.squadrons, group_id)
	var chassis := SlotCatalog.find_chassis(key, content)
	if group_id != 0:
		if group.is_empty() or group.chassis != chassis.get("id", ""):
			tx.error = "Choose a squadron of the same ship class."
			return false
		loadout_id = group.loadout
	var loadout := Loadouts.purchase_for(key, data.research.research_ids, content) if loadout_id.is_empty() else Loadouts.find(key, loadout_id, content)
	if chassis.is_empty() or chassis.flagship or loadout.is_empty():
		tx.error = "Ships are unavailable."
		return false
	if not Loadouts.available(loadout, data.research.research_ids, content):
		tx.error = "Research this loadout's equipment first."
		return false
	var price := Loadouts.ship_price(key, loadout, content)
	# Bound before multiplication/allocation, including zero-price authored ships.
	if int(count) > int(data.credits) / maxi(1, price):
		tx.error = "Not enough credits."
		return false
	price *= int(count)
	if data.credits < price:
		tx.error = "Not enough credits. Cost: %d." % price
		return false
	var ids := []
	for index in range(int(count)):
		Loadouts.append_ship(data, key, loadout, content)
		ids.append(int(data.ships.back().id))
		HangarSquadrons.add_ship(data, data.ships.back(), group_id, loadout.id, content)
	data.credits -= price
	tx.record("trade.completed", {"kind": "ships", "ship_ids": ids, "chassis": chassis.id, "loadout": loadout.id, "credits": price})
	return true

static func salvage_ship(tx: RunTransaction, content: DefDatabase, ship_id: int) -> bool:
	var facts := FactView.new(tx.doc, content)
	if not _service(tx, content, "shipyard"):
		return false
	var target := facts.ship(ship_id)
	if target.is_empty() or target.flagship:
		tx.error = "Choose an escort to salvage."
		return false
	var data: Dictionary = tx.doc.fleet
	var before := int(data.credits)
	HangarTrade.settle_losses(data, [ship_id], content)
	var fee := before - int(data.credits)
	data.ships = data.ships.filter(func(entry: Dictionary) -> bool: return int(entry.id) != ship_id)
	HangarSquadrons.sync(data)
	var chassis := SlotCatalog.find_chassis(target.chassis, content)
	var refund := floori(float(chassis.price) * 0.5 * maxf(0, target.hull_hp) / facts.hull_max(target))
	data.credits += refund
	if not tx.doc.stats.is_empty():
		tx.doc.stats.credits_earned += refund
	# Unmounted equipment retains its physical identity, matching current salvage rules.
	tx.record("trade.completed", {"kind": "salvage", "ship_id": ship_id, "credits": refund, "loss_fee": fee})
	return true
