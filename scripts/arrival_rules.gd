class_name ArrivalRules
extends RefCounted

static func has_accommodation(checkpoint: Dictionary) -> bool:
	for entry: Dictionary in checkpoint.fleet:
		for part: Dictionary in entry.design.parts:
			if int(part.type) in [ShipPart.Type.PASSENGER_CABIN, ShipPart.Type.LUXURY_SUITES]:
				return true
	return false

static func deployed_ids(checkpoint: Dictionary, fleet: Array[FleetShip]) -> Array[int]:
	var result: Array[int] = []
	var campaign: bool = checkpoint.get("campaign_active", false)
	var roster: Dictionary = checkpoint.get("fleet_roster", {})
	for owned in fleet:
		if not owned.is_alive() or owned.in_reserve:
			continue
		if campaign:
			if owned.slot_role == "regular":
				if not roster.get("active", []).has(owned.family_id):
					continue
				var family: Dictionary = roster.get("families", {}).get(owned.family_id, {})
				if family.has("design"):
					var selected := Ship.new()
					if not selected.load_design_data(family.design) or FleetRules.fingerprint(selected) != FleetRules.fingerprint(owned.design):
						continue
			elif int(roster.get("support_ids", {}).get(owned.slot_role, 0)) != owned.id:
				continue
		result.append(owned.id)
	return result

static func apply(checkpoint: Dictionary, node: Dictionary, fleet: Array[FleetShip]) -> Dictionary:
	if not node.get("inhabited", false):
		return checkpoint.duplicate(true)
	if not RunProgressData._integer(node.get("id")) or node.id < 0:
		return {}
	var source := "node/%d" % int(node.id)
	var event_id: String = checkpoint.run_id + "/arrival/" + source
	# Arrival identity precedes today's loadout. A repaired/new cabin at an old
	# port cannot turn a settled arrival into a different, freshly paid event.
	if checkpoint.ledger.has(event_id):
		return checkpoint.duplicate(true) if TransactionLedger.valid(checkpoint.ledger, checkpoint.run_id) else {}
	var proposal := PassengerRules.boarding(checkpoint.economy, fleet, deployed_ids(checkpoint, fleet))
	if proposal.is_empty():
		return {}
	var details := {"goods_grade": node.goods_grade, "goods_unit_value": node.goods_unit_value}
	var economy_after: Variant = null
	if proposal.economy.has("passengers"):
		details["passengers"] = {"disembarked": proposal.disembarked, "boarded": proposal.boarded,
			"tickets": proposal.tickets, "components": proposal.components}
		economy_after = proposal.economy
	var result := TransactionLedger.apply(checkpoint, "arrival", source, int(proposal.tickets), [0, 0, 0, 0], 0, details, economy_after)
	return result.checkpoint if not result.is_empty() else {}
