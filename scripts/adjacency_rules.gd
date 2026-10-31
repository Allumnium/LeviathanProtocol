class_name AdjacencyRules
extends RefCounted

static func touches(a: ShipPart, b: ShipPart) -> bool:
	if a == b:
		return false
	for cell in a.get_occupied_cells():
		for offset in FleetShip.NEIGHBORS:
			if b.occupies_cell(cell + offset):
				return true
	return false

static func eligible(part: ShipPart) -> bool:
	return part != null and (not part.stats.weapons.is_empty() or part.stats.thrust > 0 or part.stats.shields > 0 \
		or part.type in [ShipPart.Type.RESEARCH_LAB, ShipPart.Type.REPAIR_STATION,
		ShipPart.Type.REPAIR_DRONE_BAY])

static func recipients(units: Array[Dictionary], source_index: int) -> Array[int]:
	var result: Array[int] = []
	if source_index < 0 or source_index >= units.size() or units[source_index].hp <= 0:
		return result
	var source: ShipPart = units[source_index].part
	if source == null or source.type != ShipPart.Type.CREW_QUARTERS:
		return result
	# Physical component order is stable across damage, reconstruction and reload.
	for index in range(units.size()):
		var target: ShipPart = units[index].part
		if units[index].hp <= 0 or not eligible(target) or not touches(source, target):
			continue
		if source.crew_manual and not source.crew_recipients.has(target.origin - source.origin):
			continue
		result.append(index)
		if result.size() == 3:
			break
	return result

static func ordinary_rate(named_bonuses: Dictionary) -> float:
	var total := 0.0
	for amount in named_bonuses.values():
		if (amount is float or amount is int) and is_finite(amount):
			total += maxf(0, amount)
	return 1.0 + minf(total, 0.30)

static func rates(units: Array[Dictionary]) -> Dictionary:
	var result := {}
	for source_index in range(units.size()):
		for target_index in recipients(units, source_index):
			# Identical Crew sources never stack or recursively amplify each other.
			result[target_index] = ordinary_rate({"crew": 0.12})
	return result
