extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _science() -> Ship:
	var design := Ship.new()
	BUILTINS._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(design, ShipPart.Type.RESEARCH_LAB, Vector2i(2, 0))
	return design

func _run() -> void:
	var state := root.get_node("GameState")
	_test_purchases(state)
	_test_support(state, false)
	_test_support(state, true)
	_test_reserve_recovery(state)
	await _test_builder(state)
	print("Review regression tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _test_purchases(state: Node) -> void:
	state.run_save_path = "user://review/purchases.json"
	_check(state.start_new_run(1, 42), "Start durable preparation fixture.")
	state.credits = 10000
	var design := BUILTINS.drone()
	design.set_tile_at(Vector2i(9, 0), ShipPart.Category.DEFENSE)
	var price: int = state.get_construction_credit_cost(design)
	var materials: Array[int] = state.get_construction_material_costs(design)
	var before := RunCheckpoint.capture(state)
	_check(state.purchase_ship(design, "New family"), "Purchase a new family.")
	var purchased := RunCheckpoint.capture(state)
	_check(state.load_run_checkpoint(), "Reload immediately after purchase.")
	_check(JSON.parse_string(JSON.stringify(RunCheckpoint.capture(state))) == JSON.parse_string(JSON.stringify(purchased)), "Purchase preserves exact fleet, family, IDs and accounting on reload.")
	_check(state.credits == int(before.progress.credits) - price and state.fleet.size() == before.fleet.size() + 1, "Charge construction exactly once.")
	for category in range(4):
		_check(int(purchased.inventory[category]) == int(before.inventory[category]) - materials[category], "Use only the quoted stored material.")
	before = RunCheckpoint.capture(state)
	state.red_tiles_available = 10
	state.blue_tiles_available = 10
	state.green_tiles_available = 10
	state.core_tiles_available = 10
	_check(state.purchase_build_area_upgrade() and state.load_run_checkpoint() and state.build_area_level == 1, "Build-area upgrade is durable.")
	var blocker := FileAccess.open("user://review/blocker", FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	var path: String = state.run_save_path
	state.run_save_path = "user://review/blocker/run.json"
	before = RunCheckpoint.capture(state)
	design.set_tile_at(Vector2i(10, 0), ShipPart.Category.DEFENSE)
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	_check(not state.purchase_ship(design, "Failed family"), "Reject ship purchase on failed write.")
	_check(before == RunCheckpoint.capture(state), "Failed ship write preserves fleet, family IDs, next ID, resources and editor.")
	_check(not state.purchase_build_area_upgrade() and before == RunCheckpoint.capture(state), "Failed upgrade write changes nothing.")
	Engine.print_error_messages = printed
	state.run_save_path = path
	# Debt permits actions paid entirely with already-owned material.
	state.credits = -100
	for category in range(4):
		match category:
			0: state.red_tiles_available = 100
			1: state.blue_tiles_available = 100
			2: state.green_tiles_available = 100
			3: state.core_tiles_available = 100
	_check(state.purchase_ship(BUILTINS.drone(), "Debt copy") and state.credits == -100, "Owned-material construction remains available in debt.")
	var owned: FleetShip = state.fleet.back()
	for unit in owned.units:
		if unit.part != null and unit.part.type == ShipPart.Type.MINI_TURRET:
			unit.hp = 0
	_check(int(state.repair_quote(owned).credits) == 0 and state.repair_ship(owned) and state.credits == -100, "Zero-credit reconstruction remains available in debt.")

func _test_support(state: Node, withdraw: bool) -> void:
	state.run_save_path = "user://review/support_%s.json" % withdraw
	_check(state.start_new_run(1, 42), "Start dedicated support fixture.")
	state.credits = 10000
	_check(state.purchase_ship(_science(), "Science", "science"), "Construct a legal dedicated Science ship.")
	var support: FleetShip = state.fleet.back()
	var id := support.id
	_check(state.set_destination(state.get_reachable_nodes(0)[0]), "Deploy dedicated support.")
	if withdraw:
		_check(state.complete_battle(), "Reach a non-port battle node.")
		# Seed 42 has a salvage route followed by another battle.
		for _step in range(10):
			var next: int = state.get_reachable_nodes(state.current_node_id)[0]
			_check(state.travel_to(next), "Advance toward a non-port withdrawal fixture.")
			if state.battle_pending:
				break
	_check(not state.is_shipyard_node(state.current_node_id) or not withdraw, "Withdrawal originates outside a port.")
	for unit in support.units:
		if unit.part != null and unit.part.type == ShipPart.Type.RESEARCH_LAB:
			unit.hp = 0
	_check(state.cancel_battle() if withdraw else state.complete_battle(), "Settle with a destroyed lab and surviving escorts.")
	_check(state.load_run_checkpoint(), "Reload the damaged support checkpoint.")
	for owned in state.fleet:
		if owned.id == id:
			support = owned
	_check(support.is_alive() and ScienceRules.active_lab(support) == -1 and state.can_deploy(), "Damaged legal support can depart without granting lab benefits.")
	var visited_noncombat := false
	for _step in range(25):
		if state.is_shipyard_node(state.current_node_id):
			break
		var next: int = state.get_reachable_nodes(state.current_node_id)[0]
		_check(state.travel_to(next), "Limp onward through the campaign.")
		if state.battle_pending:
			_check(state.complete_battle(), "Healthy escorts can continue fighting.")
		else:
			visited_noncombat = true
	_check(visited_noncombat and state.is_shipyard_node(state.current_node_id), "Continue through a noncombat node to a secured port.")
	_check(state.repair_ship(support) and ScienceRules.active_lab(support) >= 0, "Repair the lab normally at a port.")

func _test_reserve_recovery(state: Node) -> void:
	state.run_save_path = "user://review/reserves.json"
	_check(state.start_new_run(1, 42), "Start reserve recovery fixture.")
	state.credits = 10000
	var alternative := BUILTINS.drone()
	alternative.set_tile_at(Vector2i(9, 0), ShipPart.Category.DEFENSE)
	_check(state.assign_fleet_design(0, "Revision", alternative, true) and state.purchase_ship(alternative, "Revision"), "Construct a distinct active revision.")
	var reserve: FleetShip = state.fleet[0]
	for owned in state.fleet:
		if owned != state.fleet.back():
			_check(state.set_ship_reserve(owned, true), "Keep older physical revisions in reserve.")
	_check(state.set_destination(state.get_reachable_nodes(0)[0]) and state.complete_battle(), "Reach a non-port node.")
	var next: int = state.get_reachable_nodes(state.current_node_id)[0]
	_check(state.travel_to(next), "Move beyond the initial port.")
	if not state.battle_pending:
		next = state.get_reachable_nodes(state.current_node_id)[0]
		_check(state.travel_to(next), "Reach another battle.")
	_check(state.battle_pending and not state.is_shipyard_node(state.current_node_id), "Reserve recovery begins away from a port.")
	var sim := BattleSimulation.new()
	_check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0.0, 0, 42), "Create actual deployed-force loss fixture.")
	for member in sim.players:
		member.owned_ship.units[member.owned_ship.core_index].hp = 0
		member.integrity = 0
	sim.advance(1.0 / 30.0)
	_check(state.settle_battle(sim) and not state.run_ended and not state.can_deploy(), "A defeated force leaves living reserves.")
	_check(state.load_run_checkpoint() and state.emergency_roster_available(), "Emergency reserve access survives reload.")
	_check(state.assign_fleet_design(0, "Drone", BUILTINS.drone()), "Select an already-owned historical revision in an emergency.")
	reserve = state.fleet[0]
	_check(state.set_ship_reserve(reserve, false) and state.can_deploy(), "Activate a surviving combat reserve outside a port.")
	_check(not state.purchase_ship(BUILTINS.drone()) and not state.set_ship_reserve(reserve, true), "Emergency recovery grants neither construction nor arbitrary reserve swaps.")
	_check(state.load_run_checkpoint() and state.can_deploy(), "Recovered deployment is durable.")

func _test_builder(state: Node) -> void:
	state.run_save_path = "user://review/builder.json"
	_check(state.start_new_run(1, 42), "Start builder performance fixture.")
	var map: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await process_frame
	await process_frame
	var builder: Control = map.build_area
	state.ship.clear()
	var start := Time.get_ticks_usec()
	for index in range(5):
		state.ship.set_tile_at(Vector2i(index, 0), ShipPart.Category.DEFENSE)
		builder._evaluate_part_patterns()
	var milliseconds := (Time.get_ticks_usec() - start) / 5000.0
	print("Builder average evaluation: %.2f ms" % milliseconds)
	_check(milliseconds < 500.0, "Block evaluation must stay below a multi-second stall (generous headless budget).")
	for pattern in builder._part_patterns:
		for turns in range(4 if pattern.can_rotate else 1):
			for flip in range(2):
				state.ship.clear()
				var offsets: Array[Vector2i] = pattern.get_offsets_for_transform(turns, flip == 1)
				for index in range(offsets.size()):
					state.ship.set_tile_at(offsets[index], pattern.tile_categories[index])
				_check(builder._candidate_origins(pattern).has(Vector2i.ZERO), "Sparse scan retains every legal transformed recipe origin, including holes.")
	map.queue_free()
	current_scene = null
	await process_frame
