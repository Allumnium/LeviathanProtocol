class_name HexFleet
extends RefCounted

# No slots, act capacities, historical-active revisions, or reserve state.
# Economy/content accounting remains the caller's transactional responsibility.
var ships: Dictionary[int, HexShipState] = {}
var next_id := 1

# A battle shares these physical health pools; it cannot create a reserve copy
# or silently serialize hex coordinates as a legacy square design.
func battle_ships() -> Array[FleetShip]:
	var result: Array[FleetShip] = []
	if defeated():
		return result
	for id: int in ships:
		if not ships[id].is_alive():
			continue
		var ship := HexBattleShip.new()
		if not ship.bind_state(ships[id], id, ships[id].design.chassis().display_name):
			return []
		ship.formation = Vector2(result.size() % 3, result.size() / 3)
		result.append(ship)
	return result

func flagship_id() -> int:
	for id: int in ships:
		if ships[id].design.chassis().flagship:
			return id
	return 0

func command_points() -> int:
	var id := flagship_id()
	return ships[id].design.chassis().command_points if id else 0

func command_used() -> int:
	var used := 0
	for ship: HexShipState in ships.values():
		used += ship.design.chassis().command_cost
	return used

func defeated() -> bool:
	var id := flagship_id()
	return id == 0 or not ships[id].is_alive()

func construction_error(blueprint: HexShipDesign) -> String:
	var verified := HexShipDesign.new()
	if not verified.load_data(blueprint.to_data()):
		return "Invalid design."
	var chassis := verified.chassis()
	var flagship := flagship_id()
	if chassis.flagship:
		return "Replace the flagship." if flagship else ""
	if flagship == 0 or defeated():
		return "Requires a flagship."
	if command_used() + chassis.command_cost > command_points():
		return "Insufficient command points."
	return ""

func construct(blueprint: HexShipDesign) -> int:
	if not construction_error(blueprint).is_empty():
		return 0
	var state := HexShipState.new()
	if not state.initialize(blueprint):
		return 0
	var id := next_id
	ships[id] = state
	next_id += 1
	return id

func salvage(id: int) -> bool:
	if defeated() or not ships.has(id) or id == flagship_id():
		return false
	ships.erase(id)
	return true

func replace_flagship(blueprint: HexShipDesign) -> bool:
	if defeated():
		return false
	var replacement := HexShipState.new()
	if not replacement.initialize(blueprint):
		return false
	var chassis := replacement.design.chassis()
	if not chassis.flagship or command_used() > chassis.command_points:
		return false
	# A single assignment: no intermediate missing/duplicate flagship state.
	ships[flagship_id()] = replacement
	return true

func to_data() -> Dictionary:
	var owned: Array = []
	for id: int in ships:
		owned.append({"id": id, "ship": ships[id].to_data()})
	return {"version": 1, "next_id": next_id, "ships": owned}

func load_data(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not HexRecipe.integer(data.get("next_id"), 1, 2147483647) or not data.get("ships") is Array:
		return false
	var next := HexFleet.new()
	var flagships := 0
	for item: Variant in data.ships:
		if not item is Dictionary or not HexRecipe.integer(item.get("id"), 1, 2147483646) or item.id >= data.next_id or next.ships.has(int(item.id)):
			return false
		var state := HexShipState.new()
		if not state.load_data(item.get("ship")):
			return false
		next.ships[int(item.id)] = state
		if state.design.chassis().flagship:
			flagships += 1
	if flagships != 1 or next.command_used() > next.command_points():
		return false
	ships = next.ships
	next_id = int(data.next_id)
	return true
