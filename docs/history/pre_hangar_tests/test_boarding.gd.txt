extends SceneTree

var failures := 0
var policy: SceneTree
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func hull(id := 100, type := ShipPart.Type.PASSENGER_CABIN) -> FleetShip:
	var owned: FleetShip = policy.hull(id)
	owned.family_id = "family/1"
	policy.add(owned, type, Vector2i.ZERO)
	return owned
func checkpoint() -> Dictionary:
	return {"run_id": "boarding-fixture", "progress": {"credits": 100, "research_points": 0},
		"inventory": [0, 0, 0, 0], "ledger": {}, "economy": {}, "campaign_active": true,
		"fleet_roster": {"active": ["family/1", "", ""], "support_ids": {"science": 0, "civic": 0}}}
func node(id := 0, inhabited := true) -> Dictionary:
	return {"id": id, "inhabited": inhabited, "goods_grade": "basic", "goods_unit_value": 3}
func run() -> void:
	# Future cabins use detached authoritative-recipe policy fixtures. Live
	# readiness remains gated until the passenger-loss milestone also works.
	policy = load("res://tests/test_passengers.gd").new()
	_test_once_and_new_capacity()
	_test_deployment()
	_test_luxury_prices()
	_test_atomic_store()
	_test_live_arrival_boundary()
	policy.free()
	print("Passenger boarding tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
func _test_once_and_new_capacity() -> void:
	var owned := hull()
	var fleet: Array[FleetShip] = [owned]
	var before := checkpoint()
	var arrived := ArrivalRules.apply(before, node(), fleet)
	var id := PassengerRules.component_id(100, 1)
	check(arrived.progress.credits == 132 and arrived.economy.passengers.components[id].occupied == 4, "The first inhabited arrival, including the start, boards four for +32.")
	check(before.progress.credits == 100 and before.economy.is_empty() and before.ledger.is_empty(), "An arrival proposal never mutates live input before commit.")
	var entry: Dictionary = arrived.ledger["boarding-fixture/arrival/node/0"]
	check(entry.details.passengers.boarded == 4 and entry.details.passengers.disembarked == 0 and entry.credits_delta == 32, "The arrival journal records its actual boarding and ticket amounts.")
	for repetition in range(3):
		arrived = ArrivalRules.apply(arrived, node(), fleet)
		check(arrived.progress.credits == 132 and arrived.ledger.size() == 1, "Reopening a settled port never pays again.")
	owned.units[1].hp = 1
	owned.repair()
	check(ArrivalRules.apply(arrived, node(), fleet).progress.credits == 132, "Repair at the same arrival cannot sell new tickets.")
	policy.add(owned, ShipPart.Type.PASSENGER_CABIN, Vector2i(10, 0))
	var unchanged := ArrivalRules.apply(arrived, node(), fleet)
	check(unchanged.progress.credits == 132 and PassengerRules.snapshot(fleet, unchanged.economy)[1].occupied == 0, "New accommodation waits empty until the next actual inhabited arrival.")
	for kind in ["combat", "scenic", "salvage"]:
		var empty_stop := node(2, false)
		empty_stop["kind"] = kind
		check(ArrivalRules.apply(unchanged, empty_stop, fleet) == unchanged, "Uninhabited %s nodes neither board nor disembark nor pay." % kind)
	var next := ArrivalRules.apply(unchanged, node(4), fleet)
	check(next.progress.credits == 196 and next.economy.passengers.components[PassengerRules.component_id(100, 2)].occupied == 4, "A later genuine arrival fills old and new accommodation exactly once.")
	check(next.ledger["boarding-fixture/arrival/node/4"].details.passengers.disembarked == 4, "Survivors safely disembark before new tickets are sold.")
	check(ArrivalRules.apply(next, node(4), fleet).progress.credits == 196, "The new arrival is also idempotent.")
func _test_deployment() -> void:
	var active := hull()
	var reserve := hull(101)
	reserve.in_reserve = true
	var inactive := hull(102)
	inactive.family_id = "family/2"
	var destroyed := hull(103)
	destroyed.units[1].hp = 0
	var dead_host := hull(104)
	dead_host.units[0].hp = 0
	var fleet: Array[FleetShip] = [active, reserve, inactive, destroyed, dead_host]
	var state := checkpoint()
	state.economy = PassengerRules.register_components({}, fleet)
	state.economy.passengers.components[PassengerRules.component_id(101, 1)].occupied = 2
	state.economy.passengers.components[PassengerRules.component_id(102, 1)].occupied = 3
	var arrived := ArrivalRules.apply(state, node(), fleet)
	var summary: Dictionary = arrived.ledger["boarding-fixture/arrival/node/0"].details.passengers
	check(summary.boarded == 4 and summary.disembarked == 5 and summary.tickets == 32, "Only active operational ships board; all surviving existing occupants disembark safely.")
	for id in [101, 102, 103, 104]:
		check(arrived.economy.passengers.components[PassengerRules.component_id(id, 1)].occupied == 0, "Reserve, inactive and destroyed accommodation cannot receive passengers.")
	active.in_reserve = true
	check(ArrivalRules.apply(arrived, node(4), fleet).progress.credits == 132, "No deployed accommodation means no ticket income.")
	var civic := hull(105)
	civic.slot_role = "civic"
	var extra := hull(106)
	extra.slot_role = "civic"
	var supports: Array[FleetShip] = [civic, extra]
	state = checkpoint()
	state.fleet_roster.support_ids.civic = 105
	arrived = ArrivalRules.apply(state, node(), supports)
	check(arrived.progress.credits == 132 and arrived.economy.passengers.components[PassengerRules.component_id(106, 1)].occupied == 0, "The dedicated physical Civic selection boards; unselected copies do not.")
func _test_luxury_prices() -> void:
	var suites := hull(200, ShipPart.Type.LUXURY_SUITES)
	var suite_fleet: Array[FleetShip] = [suites]
	check(ArrivalRules.apply(checkpoint(), node(), suite_fleet).progress.credits == 148, "Four luxury-2 suite places pay 48.")
	var luxury: FleetShip = policy.hull(201)
	luxury.family_id = "family/1"
	policy.add(luxury, ShipPart.Type.PASSENGER_CABIN, Vector2i(-2, 0))
	var deck: int = policy.add(luxury, ShipPart.Type.OBSERVATION_DECK, Vector2i.ZERO)
	policy.add(luxury, ShipPart.Type.GRAND_PROMENADE, Vector2i(10, 0))
	var fleet: Array[FleetShip] = [luxury]
	var arrived := ArrivalRules.apply(checkpoint(), node(), fleet)
	var id := PassengerRules.component_id(201, 1)
	check(arrived.progress.credits == 164 and arrived.economy.passengers.components[id].boarded_luxury == 3, "Four luxury-3 places pay 64 at boarding.")
	luxury.units[deck].hp = 0
	check(ArrivalRules.apply(arrived, node(), fleet).progress.credits == 164 and arrived.economy.passengers.components[id].boarded_luxury == 3, "Later luxury changes cannot reprice settled tickets.")
	var later := ArrivalRules.apply(arrived, node(4), fleet)
	check(later.progress.credits == 212 and later.economy.passengers.components[id].boarded_luxury == 2, "A genuine later arrival evaluates luxury again for its new load.")
func _test_atomic_store() -> void:
	var fleet: Array[FleetShip] = [hull()]
	var validate := func(value: Variant) -> bool:
		return value is Dictionary and value.get("economy") is Dictionary \
			and PassengerRules.valid(value.economy, fleet) and TransactionLedger.valid(value.get("ledger"), value.get("run_id", ""))
	var store := AtomicRunStore.new()
	var path := "user://boarding/fixture-%d.json" % Time.get_ticks_usec()
	var original := checkpoint()
	var first := store.commit(path, original, validate)
	check(first.ok, "Save the pre-arrival aggregate fixture.")
	var proposal := ArrivalRules.apply(original, node(), fleet)
	var blocker := FileAccess.open("user://boarding/blocker", FileAccess.WRITE)
	blocker.store_string("file")
	blocker.close()
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	var failed := store.commit("user://boarding/blocker/arrival.json", proposal, validate)
	Engine.print_error_messages = printed
	check(not failed.ok and original.progress.credits == 100 and original.economy.is_empty(), "Failed writes cannot grant tickets or board passengers in live state.")
	check(not store.commit(path, proposal, validate, first.generation, "before_stage").ok and store.load_latest(path, validate).payload.progress.credits == 100, "An interruption before staging leaves the old complete arrival state.")
	check(store.commit(path, proposal, validate, first.generation, "after_stage").ok, "Stage ticket payment, occupancy and deduplication together.")
	var recovered: Dictionary = store.load_latest(path, validate).payload
	check(recovered.progress.credits == 132 and recovered.economy.passengers.components[PassengerRules.component_id(100, 1)].occupied == 4, "Interrupted promotion recovers money and occupancy from one generation.")
	check(ArrivalRules.apply(recovered, node(), fleet).progress.credits == 132 and recovered.ledger.size() == 1, "Recovered/reloaded arrivals cannot pay twice.")
func _test_live_arrival_boundary() -> void:
	var state = root.get_node("GameState")
	state.run_save_path = "user://boarding/game.json"
	check(state.start_new_run(1, 42), "Start real campaign arrival integration.")
	var credits: int = state.credits
	var count: int = state.transaction_ledger.size()
	check(state.dispatch_arrival() and state.dispatch_arrival() and state.credits == credits and state.transaction_ledger.size() == count, "Existing start-port arrival stays settled without changing its old no-cabin fingerprint.")
	var staged := RunCheckpoint.capture(state)
	staged.economy["example_hold"] = {"quantity": 7}
	check(state._commit_campaign_checkpoint(staged) and state.economy_state.example_hold.quantity == 7, "Campaign commits apply their staged economic state to live state.")
	check(state.load_run_checkpoint() and state.dispatch_arrival() and state.economy_state.example_hold.quantity == 7, "Arrival reload/reopening preserves unrelated economic domains.")
	var destination: int = state.get_reachable_nodes(0)[0]
	check(state.set_destination(destination) and not state.dispatch_arrival(), "An unsecured battle approach cannot board or pay.")
	state.cancel_battle()
	check(not state.is_equipment_available(ShipPart.Type.PASSENGER_CABIN), "Cabins still require current-run Civil Hospitality research.")
