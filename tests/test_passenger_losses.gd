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

func design(cabins := 1, deck := false) -> Ship:
	var blueprint := Ship.new()
	BUILTINS._add_part(blueprint, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	for index in range(cabins):
		BUILTINS._add_part(blueprint, ShipPart.Type.PASSENGER_CABIN, Vector2i(2 + index * 2, 0))
	if deck:
		BUILTINS._add_part(blueprint, ShipPart.Type.OBSERVATION_DECK, Vector2i(2, 2))
	return blueprint

func fixture(cabins := 1, deck := false, role := "civic") -> FleetShip:
	state.run_save_path = "user://passenger_losses/run.json"
	check(state.start_new_run(1, 42), "Start isolated live passenger campaign.")
	state.research_points = 20
	check(state.purchase_research("civil_hospitality"), "Purchase actual Civil Hospitality research.")
	state.credits = 10000
	var blueprint := design(cabins, deck)
	if role == "regular":
		BUILTINS._add_part(blueprint, ShipPart.Type.MINI_TURRET, Vector2i(0, 2))
	check(state.purchase_ship(blueprint, "Passenger ship", role), "Construct real passenger equipment at normal cost.")
	var owned: FleetShip = state.fleet.back()
	check(PassengerRules.occupied(state.economy_state) == 0 and state.dispatch_arrival()
		and PassengerRules.occupied(state.economy_state) == 0, "New cabins remain empty at the already-settled start.")
	for _step in range(12):
		var next: int = state.get_reachable_nodes(state.current_node_id)[0]
		if state.campaign_node(next).inhabited:
			state.credits = 0
		check(state.travel_to(next), "Advance through actual campaign arrival handling.")
		if state.battle_pending:
			check(state.complete_battle(), "Placeholder objective reaches the next actual port.")
		if state.is_shipyard_node(state.current_node_id):
			break
	check(PassengerRules.occupied(state.economy_state) == cabins * 4, "The next genuine inhabited arrival fills deployed cabins.")
	check(state.credits == cabins * (48 if deck else 32), "Actual boarding pays the quoted luxury price once.")
	return owned

func deploy() -> BattleSimulation:
	for _step in range(12):
		var next: int = state.get_reachable_nodes(state.current_node_id)[0]
		check(state.travel_to(next), "Deploy occupied accommodation.")
		if state.battle_pending:
			break
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0.0, 0, 42), "Real deployed fleet initializes.")
	sim.battle_id = state.battle_identity()
	return sim

func destroy_cabin(owned: FleetShip, unit_index := 1) -> void:
	var unit: Dictionary = owned.units[unit_index]
	owned.damage_cell(unit.cells[0], unit.hp)
	check(unit.hp == 0, "Damage destroys the atomic cabin footprint.")

func blocker() -> String:
	var good: String = state.run_save_path
	var file := FileAccess.open("user://passenger_losses/blocker", FileAccess.WRITE)
	file.store_string("not a directory")
	file.close()
	state.run_save_path = "user://passenger_losses/blocker/run.json"
	return good

func run() -> void:
	state = root.get_node("GameState")
	_test_fee_and_reconstruction()
	_test_host_loss_retry()
	_test_simulated_host_loss()
	_test_victory()
	await _test_loaded_guards_and_ui()
	_test_regular_loaded_revision()
	_test_interrupted_casualty()
	_test_midbattle_reload()
	print("Passenger loss/debt tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _test_fee_and_reconstruction() -> void:
	var owned := fixture()
	var sim := deploy()
	owned.units[1].hp -= 0.5
	check(state.save_run_checkpoint() and state.credits == 32 and PassengerRules.occupied(state.economy_state) == 4, "Partial cabin damage preserves occupants without a fee.")
	destroy_cabin(owned)
	var before: Dictionary = state.transaction_ledger.duplicate(true)
	var good := blocker()
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	check(not state.commit_field_pickup("loss-pickup", [0, 0, 0, 0], {}), "Failed midbattle checkpoint remains retryable.")
	Engine.print_error_messages = printed
	check(state.credits == 32 and PassengerRules.occupied(state.economy_state) == 4 and state.transaction_ledger == before, "Failed write applies neither casualty fee nor occupancy change.")
	state.run_save_path = good
	check(state.commit_field_pickup("loss-pickup", [0, 0, 0, 0], {}) and state.credits == -48
		and PassengerRules.occupied(state.economy_state) == 0, "+32 boarding and four deaths produce -48, atomically with a field checkpoint.")
	check(state.save_run_checkpoint() and state.credits == -48, "Repeated checkpoint cannot charge the same lost load again.")
	sim.phase = BattleSimulation.Phase.WITHDRAWN
	check(state.settle_battle(sim) and state.credits == -48, "Withdrawal retains fees and grants no victory income.")
	check(state.load_run_checkpoint() and state.credits == -48 and PassengerRules.occupied(state.economy_state) == 0, "Debt and empty capacity survive reload.")
	owned = state.fleet.back()
	state.red_tiles_available = 100
	state.blue_tiles_available = 100
	state.green_tiles_available = 100
	state.core_tiles_available = 100
	check(state.repair_quote(owned).credits == 0 and state.repair_ship(owned), "Owned material reconstructs a cabin while in debt.")
	check(state.credits == -48 and PassengerRules.occupied(state.economy_state) == 0, "Reconstruction restores empty space, never passengers or credits.")
	check(state.dispatch_arrival() and state.credits == -48 and PassengerRules.occupied(state.economy_state) == 0, "Reopening the same port cannot refill a repaired cabin.")
	check(state.load_run_checkpoint() and state.passenger_manifest()[0].capacity == 4, "Empty reconstructed capacity is durable.")

func _test_host_loss_retry() -> void:
	var owned := fixture(2)
	var id := owned.id
	var sim := deploy()
	var scope: String = state.passenger_loss_scope()
	destroy_cabin(owned)
	check(state.save_run_checkpoint() and state.credits == -16, "First cabin death charges only its four occupants.")
	owned.damage_cell(owned.units[owned.core_index].cells[0], 10000)
	for member in sim.players:
		if member.owned_ship == owned:
			sim._refresh_owned_stats(member)
	sim.phase = BattleSimulation.Phase.WITHDRAWN
	var before: Dictionary = state.transaction_ledger.duplicate(true)
	var good := blocker()
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	check(not state.settle_battle(sim), "Failed host-loss settlement can retry.")
	Engine.print_error_messages = printed
	check(state.fleet.has(owned) and state.credits == -16 and PassengerRules.occupied(state.economy_state) == 4
		and state.transaction_ledger == before, "Failed settlement keeps the dead host and remaining occupied load until commit.")
	state.run_save_path = good
	check(state.settle_battle(sim) and not state.fleet.has(owned) and state.credits == -96, "Host loss charges only the remaining four passengers before removing the hull.")
	var summary := PassengerRules.casualty_summary(state.transaction_ledger, scope)
	check(summary.deaths == 8 and summary.fee == 160, "Cabin-then-host loss records eight deaths exactly once.")
	check(state.roster_state.support_ids.civic == 0 and state.load_run_checkpoint(), "Host removal, support slot and economic records reload consistently.")
	check(state.credits == -96 and PassengerRules.occupied(state.economy_state, id) == 0 and RunCheckpoint.valid(RunCheckpoint.capture(state)), "Historical empty records remain valid after host loss.")

func _test_victory() -> void:
	var owned := fixture()
	var sim := deploy()
	var reward: int = state.get_frozen_encounter(state.destination_node_id).rewards.credits
	destroy_cabin(owned)
	sim.phase = BattleSimulation.Phase.VICTORY
	check(state.settle_battle(sim) and state.credits == 32 - 80 + reward, "Victory saves casualty fees and the frozen reward together.")
	check(state.last_battle_report.back().get("is_alien", false), "Battle report remains populated after successful settlement.")
	var deaths := 0
	for entry in state.last_battle_report:
		deaths += int(entry.get("passenger_deaths", 0))
	check(deaths == 4 and state.load_run_checkpoint(), "Battle report exposes four deaths; the settled outcome reloads.")

func _test_simulated_host_loss() -> void:
	var owned := fixture()
	var sim := deploy()
	for member in sim.players:
		if member.owned_ship == owned:
			member.integrity = 0
	sim.phase = BattleSimulation.Phase.WITHDRAWN
	check(state.settle_battle(sim) and not state.fleet.has(owned) and state.credits == -48, "A simulation-declared host loss settles fees before hull removal even before component HP refresh.")
	check(state.load_run_checkpoint() and PassengerRules.occupied(state.economy_state) == 0, "Simulation-declared losses cannot resurrect on reload.")

func _test_loaded_guards_and_ui() -> void:
	var owned := fixture(1, true)
	var original := RunCheckpoint.capture(state)
	check(not state.set_ship_reserve(owned, true) and not state.dismantle_ship(owned), "Occupied hulls cannot be reserved or dismantled.")
	check(not state.assign_fleet_design(4, "Different Civic", design(2)), "Replacing the occupied dedicated slot requires safe disembarkation.")
	check(RunCheckpoint.capture(state) == original, "Rejected loaded operations preserve fleet, slots, occupancy and funds.")
	var map: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await process_frame
	await process_frame
	var panel: Control = map.panel_tabs.get_node("Fleet")
	var button: Button = panel.summary_host.get_node_or_null("DisembarkPassengers")
	check(button != null and not button.disabled, "Fleet UI exposes free safe disembarkation at a port.")
	if button != null:
		button.pressed.emit()
	check(PassengerRules.occupied(state.economy_state) == 0 and state.credits == 48, "Disembarking releases occupancy without a fee, refund or ticket payout.")
	check(state.set_ship_reserve(owned, true) and state.load_run_checkpoint(), "An emptied ship can be reserved durably.")
	check(state.dispatch_arrival() and PassengerRules.occupied(state.economy_state) == 0 and state.credits == 48, "Safe release cannot trigger same-arrival reboarding.")
	map.queue_free()
	current_scene = null
	await process_frame

func _test_midbattle_reload() -> void:
	var owned := fixture()
	deploy()
	destroy_cabin(owned)
	owned.damage_cell(owned.units[owned.core_index].cells[0], 10000)
	check(state.save_run_checkpoint() and state.load_run_checkpoint() and state.credits == -48, "A midbattle checkpoint persists dead-host fees and loads before validation.")
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0.0, 0, 42), "Reloaded battle can restart with surviving escorts.")
	sim.phase = BattleSimulation.Phase.WITHDRAWN
	check(state.settle_battle(sim) and state.credits == -48 and state.fleet.size() == 3, "Reloaded settlement omits the already-lost host without repeating its fee.")
	var deaths := 0
	for entry in state.last_battle_report:
		deaths += int(entry.get("passenger_deaths", 0))
	check(deaths == 4, "A reloaded battle report still explains previously committed host casualties.")

func _test_regular_loaded_revision() -> void:
	var owned := fixture(1, false, "regular")
	var slot: int = state.roster_state.active.find(owned.family_id)
	var revised := Ship.new()
	check(revised.load_design_data(owned.design.to_design_data()), "Clone a physical regular passenger design.")
	revised.set_tile_at(Vector2i(8, 0), ShipPart.Category.DEFENSE)
	var before := RunCheckpoint.capture(state)
	check(not state.assign_fleet_design(slot, "Revision", revised, true) and not state.set_ship_reserve(owned, true), "A regular revision cannot hide an occupied historical copy.")
	check(RunCheckpoint.capture(state) == before, "Rejected loaded revision leaves family history and accounting intact.")
	var good := blocker()
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	check(not state.disembark_passengers() and PassengerRules.occupied(state.economy_state) == 4 and state.credits == 32, "Failed safe release preserves passengers and funds.")
	Engine.print_error_messages = printed
	state.run_save_path = good
	check(state.disembark_passengers() and state.assign_fleet_design(slot, "Revision", revised, true), "Safe disembarkation permits a later revision selection.")
	check(not state.is_ship_deployed(owned) and owned.design.tiles.size() < revised.tiles.size(), "Selection preserves the historical physical blueprint without a free refit.")
	var ids := ArrivalRules.deployed_ids(RunCheckpoint.capture(state), state.fleet)
	check(not ids.has(owned.id), "Arrival rules also exclude historical revisions from boarding.")

func _test_interrupted_casualty() -> void:
	var owned := fixture()
	deploy()
	var before := RunCheckpoint.capture(state)
	var store := AtomicRunStore.new()
	var path := "user://passenger_losses/interrupted-%d.json" % Time.get_ticks_usec()
	var initial := store.commit(path, before, RunCheckpoint.valid)
	check(initial.ok, "Save the original occupied deployment for interruption checks.")
	destroy_cabin(owned)
	var proposal: Dictionary = state._capture_checkpoint()
	check(state.credits == 32 and PassengerRules.occupied(state.economy_state) == 4, "Building a casualty proposal is read-only.")
	check(not store.commit(path, proposal, RunCheckpoint.valid, initial.generation, "before_stage").ok
		and store.load_latest(path, RunCheckpoint.valid).payload.progress.credits == 32, "Interruption before staging retains the whole occupied pre-loss checkpoint.")
	check(store.commit(path, proposal, RunCheckpoint.valid, initial.generation, "after_stage").ok, "A verified casualty stage is a complete commit.")
	var recovered: Dictionary = store.load_latest(path, RunCheckpoint.valid).payload
	check(recovered.progress.credits == -48 and PassengerRules.occupied(recovered.economy) == 0
		and RunCheckpoint.valid(recovered), "Interrupted promotion recovers fee, empty occupancy, physical damage and ledger together.")
