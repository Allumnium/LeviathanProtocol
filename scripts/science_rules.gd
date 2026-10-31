class_name ScienceRules
extends RefCounted

# Planned journey time is fixed at departure; battle delays cannot farm research.
const BASELINE_LABS := 0.5

static func format_rp(value: float) -> String:
	return str(int(value)) if value == floor(value) else str(value)

static func production_rate(science: Dictionary) -> float:
	var rate := BASELINE_LABS
	for lab: Dictionary in science.labs:
		# Older grid-era snapshots retain their original one-RP-per-lab rate.
		rate += float(lab.rank) if science.get("production_version", 1) == 2 else 1.0
	return rate

static func journey_rp(science: Dictionary, travel_days: float) -> float:
	return production_rate(science) * maxf(0, travel_days)

static func production_label(science: Dictionary) -> String:
	if science.get("production_version", 1) != 2:
		return "%d labs" % science.labs.size()
	var counts := [0, 0, 0]
	for lab: Dictionary in science.labs:
		counts[int(lab.rank) - 1] += 1
	var lines: Array[String] = []
	for index in range(3):
		if counts[index] > 0:
			lines.append("%d x Lab %s" % [counts[index], ["I", "II", "III"][index]])
	return "\n".join(lines) if not lines.is_empty() else "0 labs"

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

static func snapshot(deployed: Array[FleetShip], legacy := false) -> Dictionary:
	var result := {"version": 1 if legacy else 2, "labs": [], "total_rp": 0}
	if not legacy and deployed.any(func(owned: FleetShip) -> bool: return owned.is_slot_ship()):
		result["production_version"] = 2
	for owned in deployed:
		if not owned.is_alive():
			continue
		for index in range(owned.units.size()):
			var lab: ShipPart = owned.units[index].part
			if lab == null or lab.type != ShipPart.Type.RESEARCH_LAB or owned.units[index].hp <= 0 or (legacy and index != active_lab(owned)):
				continue
			var analysis := false
			var observatory := false
			for unit in owned.units:
				var source: ShipPart = unit.part
				if unit.hp <= 0 or source == null or not _adjacent(source, lab):
					continue
				analysis = analysis or source.type == ShipPart.Type.ANALYSIS_ARRAY
				observatory = observatory or source.type == ShipPart.Type.QUANTUM_OBSERVATORY
			# Retain historical physical metadata for old checkpoint validation.
			var rp := 20 * lab.rank + (5 * lab.rank if analysis else 0) + (5 * lab.rank if observatory else 0)
			result.labs.append({"ship_id": owned.id, "unit_index": index, "rank": lab.rank,
				"analysis": analysis, "observatory": observatory, "rp": rp})
			result.total_rp += rp
	return result

static func valid(value: Variant, ship_ids: Array) -> bool:
	if not value is Dictionary or (value.get("version") != 1 and value.get("version") != 2) or not value.get("labs") is Array \
		or not SaveValidation.integer(value.get("total_rp")) or value.total_rp < 0:
		return false
	var ids: Array[int] = []
	for id in ship_ids:
		if not SaveValidation.integer(id):
			return false
		ids.append(int(id))
	var seen: Array[String] = []
	var total := 0
	for lab in value.labs:
		if not lab is Dictionary or not SaveValidation.integer(lab.get("ship_id")) or not SaveValidation.integer(lab.get("unit_index")) \
			or not SaveValidation.integer(lab.get("rank")) or not SaveValidation.integer(lab.get("rp")):
			return false
		var key := str(int(lab.ship_id)) if value.version == 1 else "%d/%d" % [int(lab.ship_id), int(lab.unit_index)]
		if int(lab.ship_id) not in ids or seen.has(key) or lab.unit_index < 0 or lab.rank < 1 or lab.rank > 3 \
			or not lab.get("analysis") is bool or not lab.get("observatory") is bool:
			return false
		var expected := 20 * int(lab.rank) + (5 * int(lab.rank) if lab.analysis else 0) + (5 * int(lab.rank) if lab.observatory else 0)
		if int(lab.rp) != expected:
			return false
		total += expected
		seen.append(key)
	return total == int(value.total_rp)

static func matches_deployment(value: Dictionary, deployment: Array) -> bool:
	var physical: Array[FleetShip] = []
	for entry in deployment:
		if not entry is Dictionary or not SaveValidation.integer(entry.get("id")) or not entry.get("hp") is Array:
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
	return JSON.parse_string(JSON.stringify(snapshot(physical, value.version == 1))) == JSON.parse_string(JSON.stringify(value))

static func deployment_has_lab(deployment: Array) -> bool:
	for entry in deployment:
		if not entry is Dictionary or not entry.get("design") is Dictionary or not entry.design.get("parts") is Array:
			continue
		for part in entry.design.parts:
			if part is Dictionary and part.get("type") == ShipPart.Type.RESEARCH_LAB:
				return true
	return false
