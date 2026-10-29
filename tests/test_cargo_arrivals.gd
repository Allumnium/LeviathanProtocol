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

func design(passengers := false) -> Ship:
	var result := Ship.new()
	BUILTINS._add_part(result, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(result, ShipPart.Type.CARGO_HOLD, Vector2i(2, 0))
	if passengers:
		BUILTINS._add_part(result, ShipPart.Type.PASSENGER_CABIN, Vector2i(2, 2))
	return result

func node(id: int, grade := "basic", unit_value := 3, inhabited := true) -> Dictionary:
	return {"id": id, "inhabited": inhabited, "goods_grade": grade, "goods_unit_value": unit_value}

func base() -> Dictionary:
	return {"run_id": "cargo-arrival", "progress": {"credits": 100, "research_points": 0},
		"inventory": [1, 2, 3, 4], "ledger": {}, "economy": {}, "campaign_active": false}

func run() -> void:
	state = root.get_node("GameState")
	_test_order_and_identity()
	_test_deployment_and_repairs()
	_test_live_atomic_arrival()
	print("Cargo arrival tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _test_order_and_identity() -> void:
	var owned := FleetShip.new()
	owned.initialize(design(), 100, "Trader")
	var fleet: Array[FleetShip] = [owned]
	var before := base()
	var first := ArrivalRules.apply(before, node(0), fleet)
	var id := PassengerRules.component_id(100, 1)
	check(first.progress.credits == 100 and CargoRules.quantity(first.economy) == 10 and CargoRules.value(first.economy) == 30,
		"The first empty arrival loads ten Basic Goods without a sale.")
	check(before == base(), "Arrival proposals leave their input unchanged.")
	first.economy = first.economy.duplicate(true)
	first.economy.cargo.holds[id].quantity = 7
	var arrived := ArrivalRules.apply(first, node(4, "rare", 10), fleet)
	check(arrived.progress.credits == 121 and CargoRules.value(arrived.economy) == 100 and CargoRules.quantity(arrived.economy) == 10,
		"Seven Basic Goods sell for 21 before refilling ten Rare Goods.")
	check(arrived.economy.cargo.holds[id].origin == "node/4" and arrived.economy.cargo.holds[id].unit_value == 10,
		"Destination properties are frozen on the new load.")
	check(arrived.inventory == [1, 2, 3, 4] and arrived.progress.research_points == 0,
		"Trade changes neither construction materials nor research.")
	check(ArrivalRules.apply(arrived, node(4), fleet) == arrived, "Reopening a settled arrival cannot resell or reprice its load.")
	var offloaded := CargoRules.sell(arrived, fleet)
	check(offloaded.progress.credits == 221 and CargoRules.quantity(offloaded.economy) == 0,
		"Safe offload sells the frozen Rare load exactly once.")
	check(CargoRules.sell(offloaded, fleet) == offloaded and ArrivalRules.apply(offloaded, node(4), fleet) == offloaded,
		"Offload and reopening cannot refill or repay an already settled arrival.")
	var forged := offloaded.duplicate(true)
	forged.economy = arrived.economy.duplicate(true)
	check(CargoRules.sell(forged, fleet).is_empty(), "The sale ledger rejects restoring an already sold load.")
	check(ArrivalRules.apply(arrived, node(5, "basic", 3, false), fleet) == arrived,
		"Uninhabited arrivals neither sell nor refill.")

func _test_deployment_and_repairs() -> void:
	var active := FleetShip.new()
	active.initialize(design(), 100, "Active")
	var reserve := FleetShip.new()
	reserve.initialize(design(), 101, "Reserve")
	reserve.in_reserve = true
	var destroyed := FleetShip.new()
	destroyed.initialize(design(), 102, "Destroyed hold")
	destroyed.units[1].hp = 0
	var fleet: Array[FleetShip] = [active, reserve, destroyed]
	var arrived := ArrivalRules.apply(base(), node(0), fleet)
	check(CargoRules.quantity(arrived.economy, 100) == 10 and CargoRules.quantity(arrived.economy, 101) == 0
		and CargoRules.quantity(arrived.economy, 102) == 0, "Only operational deployed holds load goods.")
	destroyed.repair()
	check(ArrivalRules.apply(arrived, node(0), fleet) == arrived, "Repairing empty capacity at a settled port cannot manufacture cargo.")
	var next := ArrivalRules.apply(arrived, node(4, "uncommon", 6), fleet)
	check(next.progress.credits == 130 and CargoRules.quantity(next.economy, 102) == 10 and CargoRules.quantity(next.economy, 101) == 0,
		"The next genuine arrival fills reconstructed holds while reserves stay empty.")

func _test_live_atomic_arrival() -> void:
	state.run_save_path = "user://cargo_arrivals/run.json"
	check(state.start_new_run(1, 42), "Start isolated trade campaign.")
	state.credits = 10000
	state.research_points = 20
	check(state.purchase_research("civil_hospitality") and state.purchase_ship(design(true), "Civic trader", "civic"),
		"Construct functioning Foundation cargo with researched passenger accommodation.")
	var owned: FleetShip = state.fleet.back()
	check(CargoRules.quantity(state.economy_state) == 0 and state.dispatch_arrival() and CargoRules.quantity(state.economy_state) == 0,
		"Construction at the already settled start leaves new holds empty.")
	var destination := -1
	for _step in range(20):
		var next: int = state.get_reachable_nodes(state.current_node_id)[0]
		if state.campaign_node(next).inhabited:
			destination = next
			break
		check(state.travel_to(next), "Trade fleet travels through actual campaign routes.")
		if state.battle_pending:
			check(state.complete_battle(), "Secure hostile routes before trade settlement.")
	check(destination >= 0, "Reach a real inhabited destination.")
	if destination < 0:
		return
	var before := RunCheckpoint.capture(state)
	var good: String = state.run_save_path
	var blocker := FileAccess.open("user://cargo_arrivals/blocker", FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	state.run_save_path = "user://cargo_arrivals/blocker/run.json"
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	check(not state.travel_to(destination), "Failed inhabited-arrival save rejects the entire transaction.")
	Engine.print_error_messages = printed
	check(RunCheckpoint.capture(state) == before, "Failed arrival preserves funds, passengers, cargo, ledger and location.")
	state.run_save_path = good
	check(state.travel_to(destination), "Retry reaches the inhabited destination.")
	check(CargoRules.quantity(state.economy_state) == 10 and PassengerRules.occupied(state.economy_state) == 4
		and state.credits == before.progress.credits + 32, "First live arrival loads cargo and pays passenger tickets together.")
	var settled := RunCheckpoint.capture(state)
	check(state.load_run_checkpoint() and state.dispatch_arrival()
		and JSON.parse_string(JSON.stringify(RunCheckpoint.capture(state))) == JSON.parse_string(JSON.stringify(settled)),
		"Reload and redispatch preserve the settled combined arrival.")
	owned = state.fleet.back()
	var loaded_value := CargoRules.value(state.economy_state)
	before = RunCheckpoint.capture(state)
	state.run_save_path = "user://cargo_arrivals/blocker/run.json"
	Engine.print_error_messages = false
	check(not state.offload_cargo(owned.id), "Failed safe-offload save rejects the sale.")
	Engine.print_error_messages = printed
	check(RunCheckpoint.capture(state) == before, "Failed offload preserves cargo, funds, passengers and ledger.")
	state.run_save_path = good
	check(state.offload_cargo(owned.id) and state.credits == settled.progress.credits + loaded_value
		and CargoRules.quantity(state.economy_state) == 0 and PassengerRules.occupied(state.economy_state) == 4,
		"Live safe offload pays once without boarding, disembarking or refilling.")
	var balance: int = state.credits
	check(state.offload_cargo(owned.id) and state.load_run_checkpoint() and state.dispatch_arrival()
		and state.credits == balance and CargoRules.quantity(state.economy_state) == 0,
		"Reload, offload and reopening cannot create repeated sale/refill income.")
