class_name ScienceRules
extends RefCounted

static func active_lab(owned: FleetShip) -> int:
	if not owned.is_alive():
		return -1
	var chosen := -1
	var level := 0
	for index in range(owned.units.size()):
		var unit := owned.units[index]
		var part: ShipPart = unit.part
		if unit.hp > 0 and part != null and part.type == ShipPart.Type.RESEARCH_LAB and part.rank > level:
			chosen = index
			level = part.rank
	return chosen

static func _adjacent(a: ShipPart, b: ShipPart) -> bool:
	return AdjacencyRules.touches(a, b)

static func snapshot(deployed: Array[FleetShip]) -> Dictionary:
	var result := {"version": 1, "labs": [], "total_rp": 0}
	for owned in deployed:
		var index := active_lab(owned)
		if index < 0:
			continue
		var lab: ShipPart = owned.units[index].part
		var analysis := false
		var observatory := false
		for unit in owned.units:
			var source: ShipPart = unit.part
			if unit.hp <= 0 or source == null or not _adjacent(source, lab):
				continue
			analysis = analysis or source.type == ShipPart.Type.ANALYSIS_ARRAY
			observatory = observatory or source.type == ShipPart.Type.QUANTUM_OBSERVATORY
		var rp := 20 * lab.rank + (5 * lab.rank if analysis else 0) + (5 * lab.rank if observatory else 0)
		result.labs.append({"ship_id": owned.id, "unit_index": index, "rank": lab.rank,
			"analysis": analysis, "observatory": observatory, "rp": rp})
		result.total_rp += rp
	return result

static func valid(value: Variant, ship_ids: Array) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not value.get("labs") is Array \
		or not RunProgressData._integer(value.get("total_rp")) or value.total_rp < 0:
		return false
	var ids: Array[int] = []
	for id in ship_ids:
		if not RunProgressData._integer(id):
			return false
		ids.append(int(id))
	var seen: Array[int] = []
	var total := 0
	for lab in value.labs:
		if not lab is Dictionary or not RunProgressData._integer(lab.get("ship_id")) or not RunProgressData._integer(lab.get("unit_index")) \
			or not RunProgressData._integer(lab.get("rank")) or not RunProgressData._integer(lab.get("rp")):
			return false
		if int(lab.ship_id) not in ids or seen.has(int(lab.ship_id)) or lab.unit_index < 0 or lab.rank < 1 or lab.rank > 3 \
			or not lab.get("analysis") is bool or not lab.get("observatory") is bool:
			return false
		var expected := 20 * int(lab.rank) + (5 * int(lab.rank) if lab.analysis else 0) + (5 * int(lab.rank) if lab.observatory else 0)
		if int(lab.rp) != expected:
			return false
		total += expected
		seen.append(int(lab.ship_id))
	return total == int(value.total_rp)

static func matches_deployment(value: Dictionary, deployment: Array) -> bool:
	var physical: Array[FleetShip] = []
	for entry in deployment:
		if not entry is Dictionary or not RunProgressData._integer(entry.get("id")) or not entry.get("hp") is Array:
			return false
		var design := Ship.new()
		if not design.load_design_data(entry.get("design")):
			return false
		var owned := FleetShip.new()
		if not owned.initialize(design, int(entry.id), "Snapshot") or entry.hp.size() != owned.units.size():
			return false
		for index in range(owned.units.size()):
			if not (entry.hp[index] is int or entry.hp[index] is float) or not is_finite(entry.hp[index]) \
				or entry.hp[index] < 0 or entry.hp[index] > owned.units[index].max_hp + 0.00000001:
				return false
			owned.units[index].hp = minf(float(entry.hp[index]), owned.units[index].max_hp)
		physical.append(owned)
	return JSON.parse_string(JSON.stringify(snapshot(physical))) == JSON.parse_string(JSON.stringify(value))

static func deployment_has_lab(deployment: Array) -> bool:
	for entry in deployment:
		if not entry is Dictionary or not entry.get("design") is Dictionary or not entry.design.get("parts") is Array:
			continue
		for part in entry.design.parts:
			if part is Dictionary and part.get("type") == ShipPart.Type.RESEARCH_LAB:
				return true
	return false
