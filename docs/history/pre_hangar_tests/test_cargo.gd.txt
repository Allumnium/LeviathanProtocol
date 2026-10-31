extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0
var state: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func hull(id := 100) -> FleetShip:
	var design := Ship.new()
	BUILTINS._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	# Detached authoritative-recipe fixture for physical capacity/loss tests.
	for origin in [Vector2i(2, 0), Vector2i(5, 0)]:
		var cells := MaterialRecipe.parse(GameDefinitions.equipment(ShipPart.Type.CARGO_HOLD).recipe)
		var offsets: Array[Vector2i] = []
		for cell: Vector2i in cells:
			offsets.append(cell)
		var part := ShipPart.new(ShipPart.Type.CARGO_HOLD, ShipPart.Category.CORE, origin, offsets, ShipPartStats.new(0, 0, 6, 0))
		design.parts.append(part)
		for cell: Vector2i in cells:
			design.tiles[origin + cell] = cells[cell]
	var owned := FleetShip.new()
	owned.initialize(design, id, "Cargo fixture")
	return owned

func load_hold(economy: Dictionary, owned: FleetShip, index: int, amount := 10) -> String:
	var id := PassengerRules.component_id(owned.id, index)
	var record: Dictionary = economy.cargo.holds[id]
	record.quantity = amount
	record.origin = "node/starting-anchorage"
	record.grade = "basic"
	record.unit_value = 3
	return id

func run() -> void:
	state = root.get_node("GameState")
	_test_state()
	_test_validation()
	_test_checkpoint_losses()
	print("Cargo state tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _test_state() -> void:
	var owned := hull()
	var fleet: Array[FleetShip] = [owned]
	var economy := CargoRules.register_components({"unrelated": {"quantity": 7}}, fleet)
	check(CargoRules.valid(economy, fleet) and economy.unrelated.quantity == 7, "Cargo has an independent additive namespace.")
	var rows := CargoRules.snapshot(fleet, economy)
	check(rows.size() == 2 and rows[0].capacity == 10 and rows[0].quantity == 0, "Each hold starts with ten empty places.")
	var id := load_hold(economy, owned, 1, 7)
	load_hold(economy, owned, 2)
	check(CargoRules.valid(economy, fleet) and CargoRules.snapshot(fleet, economy)[0].value == 21, "Seven Basic Goods retain origin value 21 without becoming credits.")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(economy))
	owned.display_name = "Renamed"
	owned.in_reserve = true
	owned.formation = Vector2(40, -10)
	check(CargoRules.valid(saved, fleet) and CargoRules.quantity(saved, owned.id) == 17, "JSON and formation/label changes preserve per-hold identity.")
	var before := saved.duplicate(true)
	rows = CargoRules.snapshot(fleet, saved)
	rows[0].quantity = 0
	check(saved == before and CargoRules.register_components(saved, fleet) == saved, "Reading or registering holds cannot load, sell or mutate cargo.")
	owned.units[1].hp = 0.1
	check(CargoRules.valid(saved, fleet) and CargoRules.snapshot(fleet, saved)[0].quantity == 7, "Partial damage loses no cargo or capacity.")
	owned.units[1].hp = 0
	check(not CargoRules.valid(saved, fleet), "A destroyed loaded hold must settle its loss before saving.")
	saved.cargo.holds[id] = CargoRules.empty_record(saved.cargo.holds[id])
	owned.repair()
	check(CargoRules.valid(saved, fleet) and CargoRules.snapshot(fleet, saved)[0].quantity == 0 and CargoRules.snapshot(fleet, saved)[0].capacity == 10, "Repair restores empty space, never the lost load.")
	var copy := hull(101)
	fleet.append(copy)
	check(CargoRules.quantity(CargoRules.register_components(saved, fleet), copy.id) == 0, "An identical physical copy starts empty.")

func _test_validation() -> void:
	var owned := hull()
	var fleet: Array[FleetShip] = [owned]
	var economy := CargoRules.register_components({}, fleet)
	var id := load_hold(economy, owned, 1)
	for change in [{"quantity": -1}, {"quantity": 11}, {"quantity": 0.5}, {"capacity": 15}, {"origin": ""}, {"origin": 5},
		{"grade": "offense"}, {"unit_value": -1}, {"unit_value": 0}, {"unit_value": 1.5}, {"unit_value": 1e18}, {"ship_id": 999}, {"unit_index": 0}, {"extra": 1}]:
		var forged := economy.duplicate(true)
		for key in change:
			forged.cargo.holds[id][key] = change[key]
		check(not CargoRules.valid(forged, fleet), "Reject malformed cargo: %s" % change)
	var forged := economy.duplicate(true)
	forged.cargo.version = 99
	check(not CargoRules.valid(forged, fleet), "Reject unknown cargo versions.")
	forged = economy.duplicate(true)
	forged.cargo.holds[PassengerRules.component_id(owned.id, 0)] = CargoRules.empty_record({"ship_id": owned.id, "unit_index": 0})
	check(not CargoRules.valid(forged, fleet), "A command center cannot impersonate a hold.")
	var empty := CargoRules.register_components({}, fleet)
	var no_ships: Array[FleetShip] = []
	check(CargoRules.valid(empty, no_ships) and not CargoRules.valid(economy, no_ships), "Only empty historical records may outlive removed hosts.")

func _test_checkpoint_losses() -> void:
	state.run_save_path = "user://cargo/run.json"
	check(state.start_new_run(1, 42), "Start an isolated campaign.")
	check(state.is_equipment_available(ShipPart.Type.CARGO_HOLD), "Foundation grants functioning Cargo Holds.")
	var owned := hull(state.next_ship_id)
	state.next_ship_id += 1
	# Install the physical policy fixture in a general design family.
	owned.family_id = state._register_family(owned.design, "Cargo fixture")
	state.roster_state.active[1] = owned.family_id
	state.fleet_design_slots[1] = "Cargo fixture"
	state.fleet.append(owned)
	state.economy_state = CargoRules.register_components(state.economy_state, state.fleet)
	var first := load_hold(state.economy_state, owned, 1, 7)
	load_hold(state.economy_state, owned, 2)
	check(state.save_run_checkpoint() and state.load_run_checkpoint(), "Loaded cargo persists through real checkpoint encoding and decoding.")
	owned = state.fleet.back()
	var credits: int = state.credits
	var inventory: Array = RunCheckpoint.capture(state).inventory.duplicate()
	check(not state.dismantle_ship(owned) and not state.set_ship_reserve(owned, true), "Loaded ships cannot be dismantled or reserved before safe offloading is implemented.")
	for _step in range(12):
		var next: int = state.get_reachable_nodes(state.current_node_id)[0]
		check(state.travel_to(next), "Travel into a real frozen encounter for cargo damage.")
		if state.battle_pending:
			break
	check(state.battle_pending, "Cargo fixture reaches an active encounter.")
	credits = state.credits
	inventory = RunCheckpoint.capture(state).inventory.duplicate()
	owned.units[1].hp = 0
	var before: Dictionary = state.economy_state.duplicate(true)
	var ledger: Dictionary = state.transaction_ledger.duplicate(true)
	var checkpoint: Dictionary = state._capture_checkpoint()
	check(CargoRules.quantity(checkpoint.economy) == 10 and checkpoint.progress.credits == credits and checkpoint.inventory == inventory, "Hold destruction clears only its cargo, with no credit/material fee.")
	check(state.economy_state == before and state.transaction_ledger == ledger, "Loss proposals never mutate live state ahead of a successful write.")
	var good: String = state.run_save_path
	var blocker := FileAccess.open("user://cargo/blocker", FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	state.run_save_path = "user://cargo/blocker/run.json"
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	check(not state.save_run_checkpoint(), "A failed cargo-loss write is rejected.")
	Engine.print_error_messages = printed
	check(state.economy_state == before and state.transaction_ledger == ledger, "Failed writes preserve live cargo and ledger for retry.")
	state.run_save_path = good
	check(state.save_run_checkpoint() and state.load_run_checkpoint(), "Retry commits cargo loss and physical damage together.")
	owned = state.fleet.back()
	check(state.economy_state.cargo.holds[first].quantity == 0 and CargoRules.quantity(state.economy_state) == 10, "Reload retains only the surviving hold's goods.")
	var loss_count: int = state.transaction_ledger.size()
	check(state.save_run_checkpoint() and state.transaction_ledger.size() == loss_count, "Repeated checkpoints cannot count a hold loss twice.")
	owned.units[owned.core_index].hp = 0
	checkpoint = state._capture_checkpoint()
	check(CargoRules.quantity(checkpoint.economy) == 0 and checkpoint.ledger.size() == loss_count + 1 and checkpoint.progress.credits == credits, "Later host loss clears the remaining hold once, without a fee.")
	check(not RunCheckpoint.valid(RunCheckpoint.capture(state)) and CargoRules.valid(checkpoint.economy, state.fleet), "Unsettled physical loss fails closed at the checkpoint boundary.")
	owned.repair()
	state.economy_state = checkpoint.economy
	check(CargoRules.quantity(state.economy_state) == 0 and CargoRules.snapshot(state.fleet, state.economy_state).back().capacity == 10, "Host reconstruction restores empty holds.")
