class_name CargoRules
extends RefCounted

const VERSION := 1
const CAPACITY := 10
const GRADES := ["basic", "uncommon", "rare"]
const FIELDS := ["ship_id", "unit_index", "capacity", "quantity", "origin", "grade", "unit_value"]

static func value(economy: Dictionary) -> int:
	var total := 0
	for record: Dictionary in economy.get("cargo", {}).get("holds", {}).values():
		total += int(record.quantity) * int(record.unit_value)
	return total

# Arrival and offload consume the same physical load through one ledger identity.
static func sell(checkpoint: Dictionary, fleet: Array[FleetShip], ship_id := 0) -> Dictionary:
	if not valid(checkpoint.economy, fleet):
		return {}
	var result := checkpoint.duplicate(true)
	var records: Dictionary = checkpoint.economy.get("cargo", {}).get("holds", {})
	var ids: Array = records.keys()
	ids.sort()
	for id: String in ids:
		var record: Dictionary = records[id]
		if int(record.quantity) == 0 or (ship_id != 0 and int(record.ship_id) != ship_id):
			continue
		var economy: Dictionary = result.economy.duplicate(true)
		economy.cargo.holds[id] = empty_record(record)
		var applied := TransactionLedger.apply(result, "cargo_sale", id + "/origin/" + record.origin,
			int(record.quantity) * int(record.unit_value), [0, 0, 0, 0], 0,
			{"hold_id": id, "quantity": int(record.quantity), "origin": record.origin,
				"grade": record.grade, "unit_value": int(record.unit_value)}, economy)
		if applied.is_empty() or applied.replayed:
			return {} # A loaded record cannot impersonate an already sold load.
		result = applied.checkpoint
	return result

static func refill(economy: Dictionary, fleet: Array[FleetShip], deployed: Array[int], node: Dictionary) -> Dictionary:
	var grade := str(node.get("goods_grade", "")).to_lower()
	if not valid(economy, fleet) or grade not in GRADES \
		or not RunProgressData._integer(node.get("goods_unit_value")) or node.goods_unit_value <= 0:
		return {}
	var result := register_components(economy, fleet)
	var loaded := 0
	var current := manifest(fleet)
	for id: String in current:
		var entry: Dictionary = current[id]
		if not entry.operational or int(entry.ship_id) not in deployed:
			continue
		var record: Dictionary = result.cargo.holds[id]
		if int(record.quantity) != 0:
			return {} # Sell before loading destination goods.
		record.quantity = int(entry.capacity)
		record.origin = "node/%d" % int(node.id)
		record.grade = grade
		record.unit_value = int(node.goods_unit_value)
		loaded += int(entry.capacity)
	return {"economy": result, "loaded": loaded} if valid(result, fleet) else {}

# Physical ship/unit identities survive renaming, revision selection and repair.
static func manifest(fleet: Array[FleetShip]) -> Dictionary:
	var result := {}
	for owned in fleet:
		for index in range(owned.units.size()):
			var unit := owned.units[index]
			if unit.part == null or unit.part.type != ShipPart.Type.CARGO_HOLD:
				continue
			var operational: bool = owned.is_alive() and unit.hp > 0
			result[PassengerRules.component_id(owned.id, index)] = {"ship_id": owned.id,
				"unit_index": index, "capacity": CAPACITY if operational else 0, "operational": operational, "load_lost": unit.get("load_lost", false)}
	return result

static func empty_record(entry: Dictionary) -> Dictionary:
	return {"ship_id": int(entry.ship_id), "unit_index": int(entry.unit_index), "capacity": CAPACITY,
		"quantity": 0, "origin": "", "grade": "", "unit_value": 0}

static func register_components(economy: Dictionary, fleet: Array[FleetShip]) -> Dictionary:
	var result := economy.duplicate(true)
	var current := manifest(fleet)
	if current.is_empty() and not result.has("cargo"):
		return result
	if not result.has("cargo"):
		result.cargo = {"version": VERSION, "holds": {}}
	for id: String in current:
		if not result.cargo.holds.has(id):
			result.cargo.holds[id] = empty_record(current[id])
	return result

static func quantity(economy: Dictionary, ship_id := 0) -> int:
	var total := 0
	for record: Dictionary in economy.get("cargo", {}).get("holds", {}).values():
		if ship_id == 0 or int(record.ship_id) == ship_id:
			total += int(record.quantity)
	return total

static func snapshot(fleet: Array[FleetShip], economy: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var stored: Dictionary = economy.get("cargo", {}).get("holds", {})
	var current := manifest(fleet)
	for id: String in current:
		var entry: Dictionary = current[id].duplicate(true)
		var record: Dictionary = stored.get(id, empty_record(entry))
		entry.merge(record, false)
		entry["id"] = id
		entry["value"] = int(record.quantity) * int(record.unit_value)
		result.append(entry)
	return result

static func valid(economy: Dictionary, fleet: Array[FleetShip], allow_losses := false) -> bool:
	if not economy.has("cargo"):
		return true # Older checkpoints have no cargo namespace.
	var state: Variant = economy.cargo
	if not state is Dictionary or state.size() != 2 or state.get("version") != VERSION or not state.get("holds") is Dictionary:
		return false
	var current := manifest(fleet)
	var ships := {}
	for owned in fleet:
		ships[owned.id] = true
	for id in state.holds:
		var record: Variant = state.holds[id]
		if not id is String or not record is Dictionary or record.size() != FIELDS.size():
			return false
		for key in FIELDS:
			if not record.has(key):
				return false
		for key in ["ship_id", "unit_index", "capacity", "quantity", "unit_value"]:
			if not RunProgressData._integer(record[key]):
				return false
		if record.ship_id < 1 or record.unit_index < 0 or id != PassengerRules.component_id(int(record.ship_id), int(record.unit_index)) \
			or record.capacity != CAPACITY or record.quantity < 0 or record.quantity > record.capacity \
			or not record.origin is String or not record.grade is String or record.unit_value < 0 or record.unit_value > 9007199254740991.0 / CAPACITY:
			return false
		if record.quantity > 0 and (record.origin.is_empty() or record.grade not in GRADES or record.unit_value <= 0):
			return false
		if record.quantity == 0 and (record.origin != "" or record.grade != "" or record.unit_value != 0):
			return false
		if current.has(id):
			if record.quantity > 0 and not current[id].operational and not allow_losses:
				return false
		elif ships.has(int(record.ship_id)) or (record.quantity > 0 and not allow_losses):
			return false
	return true

# Propose cargo clearing and a zero-fee ledger entry alongside physical damage.
# Replaying a loss sees the same empty hold, including later host destruction.
static func settle_losses(checkpoint: Dictionary, fleet: Array[FleetShip], scope: String, lost_ships: Array[int] = []) -> Dictionary:
	if scope.is_empty() or not valid(checkpoint.economy, fleet, true):
		return {}
	var result := checkpoint.duplicate(true)
	var current := manifest(fleet)
	var records: Dictionary = result.economy.get("cargo", {}).get("holds", {})
	var ids: Array = records.keys()
	ids.sort()
	for id: String in ids:
		var record: Dictionary = records[id]
		if int(record.quantity) == 0 or (current.get(id, {}).get("operational", false) and not current.get(id, {}).get("load_lost", false) and int(record.ship_id) not in lost_ships):
			continue
		var economy: Dictionary = result.economy.duplicate(true)
		economy.cargo.holds[id] = empty_record(record)
		var applied := TransactionLedger.apply(result, "cargo_loss", scope + "/" + id, 0, [0, 0, 0, 0], 0,
			{"hold_id": id, "quantity": int(record.quantity), "origin": record.origin,
				"grade": record.grade, "unit_value": int(record.unit_value)}, economy)
		if applied.is_empty():
			return {}
		result = applied.checkpoint
	return result if valid(result.economy, fleet) else {}
