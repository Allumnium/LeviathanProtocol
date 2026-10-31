class_name PassengerRules
extends RefCounted

const VERSION := 1
const PLACES := 4
const ACCOMMODATION_IDS := ["passenger_cabin", "luxury_suites"]
const RECORD_FIELDS := ["ship_id", "unit_index", "equipment_id", "capacity", "occupied", "boarded_luxury"]
const TICKET_PRICES := [8, 12, 16]
const DEATH_FEE := 20

# A destroyed component and its later host destruction consume the same load.
# Proposal only: fees, empty occupancy and physical damage commit together.
static func settle_losses(checkpoint: Dictionary, fleet: Array[FleetShip], scope: String, lost_ships: Array[int] = []) -> Dictionary:
	if scope.is_empty() or not valid(checkpoint.economy, fleet, true):
		return {}
	var result := checkpoint.duplicate(true)
	var current := manifest(fleet)
	var records: Dictionary = result.economy.get("passengers", {}).get("components", {})
	var ids: Array = records.keys()
	ids.sort()
	for id: String in ids:
		var record: Dictionary = records[id]
		if int(record.occupied) == 0 or (current.get(id, {}).get("operational", false) and not current.get(id, {}).get("load_lost", false) and int(record.ship_id) not in lost_ships):
			continue
		var deaths := int(record.occupied)
		var economy: Dictionary = result.economy.duplicate(true)
		economy.passengers.components[id].occupied = 0
		var applied := TransactionLedger.apply(result, "casualty", scope + "/" + id,
			-deaths * DEATH_FEE, [0, 0, 0, 0], 0,
			{"component_id": id, "deaths": deaths, "fee_per_person": DEATH_FEE}, economy)
		if applied.is_empty():
			return {}
		result = applied.checkpoint
	return result if valid(result.economy, fleet) else {}

static func occupied(economy: Dictionary, ship_id := 0) -> int:
	var total := 0
	for record: Dictionary in economy.get("passengers", {}).get("components", {}).values():
		if ship_id == 0 or int(record.ship_id) == ship_id:
			total += int(record.occupied)
	return total

static func casualty_summary(ledger: Dictionary, scope: String, ship_id := 0) -> Dictionary:
	var deaths := 0
	var fee := 0
	for entry: Dictionary in ledger.values():
		if entry.kind != "casualty" or not str(entry.source_id).begins_with(scope + "/"):
			continue
		var id: String = entry.details.get("component_id", "")
		if ship_id != 0 and not id.begins_with("ship/%d/unit/" % ship_id):
			continue
		deaths += int(entry.details.get("deaths", 0))
		fee -= int(entry.credits_delta)
	return {"deaths": deaths, "fee": fee}

static func ticket_price(luxury: int) -> int:
	return TICKET_PRICES[clampi(luxury, 1, 3) - 1]

static func boarding(economy: Dictionary, fleet: Array[FleetShip], deployed_ids: Array[int]) -> Dictionary:
	if not valid(economy, fleet):
		return {}
	var known := {}
	for owned in fleet:
		known[owned.id] = true
	var seen := {}
	for id in deployed_ids:
		if not known.has(id) or seen.has(id):
			return {}
		seen[id] = true
	var result := register_components(economy, fleet)
	var disembarked := 0
	var boarded := 0
	var tickets := 0
	var components: Array[Dictionary] = []
	if result.has("passengers"):
		for record: Dictionary in result.passengers.components.values():
			disembarked += int(record.occupied)
			record.occupied = 0
		var current := manifest(fleet)
		for id: String in current:
			var entry: Dictionary = current[id]
			if not seen.has(int(entry.ship_id)) or not entry.operational:
				continue
			var record: Dictionary = result.passengers.components[id]
			record.occupied = int(entry.capacity)
			record.boarded_luxury = int(entry.luxury)
			var amount := int(entry.capacity) * ticket_price(int(entry.luxury))
			boarded += int(entry.capacity)
			tickets += amount
			components.append({"id": id, "boarded": int(entry.capacity), "luxury": int(entry.luxury), "tickets": amount})
	return {"economy": result, "disembarked": disembarked, "boarded": boarded, "tickets": tickets, "components": components}

static func component_id(ship_id: int, unit_index: int) -> String:
	return "ship/%d/unit/%d" % [ship_id, unit_index]

static func accommodation(part: ShipPart) -> bool:
	return part != null and part.type in [ShipPart.Type.PASSENGER_CABIN, ShipPart.Type.LUXURY_SUITES]

static func base_luxury(part: ShipPart) -> int:
	return 2 if part.type == ShipPart.Type.LUXURY_SUITES else 1

static func exterior_edge(owned: FleetShip, part: ShipPart) -> bool:
	# Empty enclosed courtyards are not the hull exterior. Row/column bounds
	# let the flood stop as soon as an empty cell has a clear ray to open space,
	# without walking the full bounding box of a sparse or translated design.
	var occupied := {}
	var rows := {}
	var columns := {}
	for unit in owned.units:
		if unit.hp <= 0:
			continue
		for cell: Vector2i in unit.cells:
			occupied[cell] = true
			var row: Vector2i = rows.get(cell.y, Vector2i(cell.x, cell.x))
			rows[cell.y] = Vector2i(mini(row.x, cell.x), maxi(row.y, cell.x))
			var column: Vector2i = columns.get(cell.x, Vector2i(cell.y, cell.y))
			columns[cell.x] = Vector2i(mini(column.x, cell.y), maxi(column.y, cell.y))
	var pending: Array[Vector2i] = []
	for cell in part.get_occupied_cells():
		for offset in FleetShip.NEIGHBORS:
			if not occupied.has(cell + offset):
				pending.append(cell + offset)
	var visited := {}
	var cursor := 0
	while cursor < pending.size():
		var cell := pending[cursor]
		cursor += 1
		if visited.has(cell) or occupied.has(cell):
			continue
		visited[cell] = true
		if not rows.has(cell.y) or not columns.has(cell.x):
			return true
		var row: Vector2i = rows[cell.y]
		var column: Vector2i = columns[cell.x]
		if cell.x < row.x or cell.x > row.y or cell.y < column.x or cell.y > column.y:
			return true
		for offset in FleetShip.NEIGHBORS:
			if not visited.has(cell + offset) and not occupied.has(cell + offset):
				pending.append(cell + offset)
	return false

static func observation_recipients(owned: FleetShip, source_index: int) -> Array[int]:
	var result: Array[int] = []
	if not owned.is_alive() or source_index < 0 or source_index >= owned.units.size():
		return result
	var unit := owned.units[source_index]
	var source: ShipPart = unit.part
	if unit.hp <= 0 or source == null or source.type != ShipPart.Type.OBSERVATION_DECK or not exterior_edge(owned, source):
		return result
	for index in range(owned.units.size()):
		var target := owned.units[index]
		if target.hp > 0 and accommodation(target.part) and AdjacencyRules.touches(source, target.part):
			result.append(index)
			if result.size() == 2:
				break
	return result

static func luxury_levels(owned: FleetShip) -> Dictionary:
	var result := {}
	if not owned.is_alive():
		return result
	var observation := {}
	var promenade := false
	for index in range(owned.units.size()):
		var unit := owned.units[index]
		var part: ShipPart = unit.part
		if unit.hp <= 0 or part == null:
			continue
		if part.type == ShipPart.Type.GRAND_PROMENADE:
			promenade = true
		if part.type == ShipPart.Type.OBSERVATION_DECK:
			for recipient in observation_recipients(owned, index):
				observation[recipient] = true
	for index in range(owned.units.size()):
		var unit := owned.units[index]
		if unit.hp > 0 and accommodation(unit.part):
			result[index] = clampi(base_luxury(unit.part) + (1 if observation.has(index) else 0) + (1 if promenade else 0), 1, 3)
	return result

static func manifest(fleet: Array[FleetShip]) -> Dictionary:
	var result := {}
	for owned in fleet:
		var levels := luxury_levels(owned)
		for index in range(owned.units.size()):
			var unit := owned.units[index]
			if not accommodation(unit.part):
				continue
			var operational: bool = owned.is_alive() and unit.hp > 0
			result[component_id(owned.id, index)] = {"ship_id": owned.id, "unit_index": index,
				"equipment_id": GameDefinitions.equipment(unit.part.type).id, "capacity": PLACES if operational else 0,
				"luxury": int(levels.get(index, base_luxury(unit.part))), "operational": operational, "load_lost": unit.get("load_lost", false)}
	return result

static func empty_record(entry: Dictionary) -> Dictionary:
	return {"ship_id": int(entry.ship_id), "unit_index": int(entry.unit_index), "equipment_id": entry.equipment_id,
		"capacity": PLACES, "occupied": 0, "boarded_luxury": int(entry.luxury)}

static func register_components(economy: Dictionary, fleet: Array[FleetShip]) -> Dictionary:
	var result := economy.duplicate(true)
	var current := manifest(fleet)
	if current.is_empty() and not result.has("passengers"):
		return result
	if not result.has("passengers"):
		result["passengers"] = {"version": VERSION, "components": {}}
	for id: String in current:
		if not result.passengers.components.has(id):
			result.passengers.components[id] = empty_record(current[id])
	return result

static func valid(economy: Dictionary, fleet: Array[FleetShip], allow_losses := false) -> bool:
	if not economy.has("passengers"):
		return true # Existing checkpoints have no passenger namespace.
	var state: Variant = economy.passengers
	if not state is Dictionary or state.size() != 2 or state.get("version") != VERSION or not state.get("components") is Dictionary:
		return false
	var current := manifest(fleet)
	var ships := {}
	for owned in fleet:
		ships[owned.id] = owned
	for id in state.components:
		var record: Variant = state.components[id]
		if not id is String or not record is Dictionary or record.size() != RECORD_FIELDS.size():
			return false
		for key in RECORD_FIELDS:
			if not record.has(key):
				return false
		for key in ["ship_id", "unit_index", "capacity", "occupied", "boarded_luxury"]:
			if not RunProgressData._integer(record[key]):
				return false
		if record.ship_id < 1 or record.unit_index < 0 or id != component_id(int(record.ship_id), int(record.unit_index)) \
			or record.equipment_id not in ACCOMMODATION_IDS or record.capacity != PLACES \
			or record.occupied < 0 or record.occupied > PLACES or record.boarded_luxury < 1 or record.boarded_luxury > 3:
			return false
		if record.equipment_id == "luxury_suites" and record.boarded_luxury < 2:
			return false
		if current.has(id):
			if record.equipment_id != current[id].equipment_id or (record.occupied > 0 and not current[id].operational and not allow_losses):
				return false
		else:
			# Empty historical records preserve stable identities after a loss.
			# A live hull's non-accommodation unit cannot impersonate a cabin.
			if (record.occupied > 0 and not allow_losses) or ships.has(int(record.ship_id)):
				return false
	return true

static func snapshot(fleet: Array[FleetShip], economy: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current := manifest(fleet)
	var stored: Dictionary = economy.get("passengers", {}).get("components", {})
	for id: String in current:
		var entry: Dictionary = current[id].duplicate(true)
		var record: Dictionary = stored.get(id, empty_record(entry))
		entry["id"] = id
		entry["occupied"] = int(record.occupied)
		entry["available"] = maxi(0, int(entry.capacity) - int(record.occupied))
		entry["boarded_luxury"] = int(record.boarded_luxury)
		result.append(entry)
	return result
