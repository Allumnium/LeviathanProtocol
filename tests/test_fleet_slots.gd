extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _policy_design(types: Array[int]) -> Ship:
	# Eligibility fixtures only. Unimplemented equipment stays unavailable to
	# blueprint loading/construction; these do not invent gameplay effects.
	var design := Ship.new()
	preload("res://scripts/builtin_ships.gd")._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	for index in range(types.size()):
		var cell := Vector2i(6 + index * 2, 0)
		design.set_tile_at(cell, ShipPart.Category.CORE)
		design.add_part(ShipPart.new(types[index], ShipPart.Category.CORE, cell, [Vector2i.ZERO], ShipPartStats.new()))
	return design

func _variant(index: int) -> Ship:
	var design := preload("res://scripts/builtin_ships.gd").drone()
	if index > 0:
		design.set_tile_at(Vector2i(8 + index, 0), ShipPart.Category.DEFENSE)
	return design

func _run() -> void:
	var science := _policy_design([ShipPart.Type.RESEARCH_LAB])
	var civic := _policy_design([ShipPart.Type.CARGO_HOLD])
	_check(FleetRules.design_error(science, "science").is_empty(), "Science accepts one lab without requiring weapons.")
	_check(FleetRules.design_error(civic, "civic").is_empty(), "Civic accepts a Cargo Hold.")
	_check(FleetRules.design_error(_policy_design([ShipPart.Type.PASSENGER_CABIN]), "civic").is_empty(), "Passenger accommodation qualifies Civic.")
	_check(not FleetRules.design_error(_policy_design([ShipPart.Type.OBSERVATION_DECK]), "civic").is_empty(), "A luxury modifier without berths does not qualify Civic.")
	_check(not FleetRules.design_error(_policy_design([ShipPart.Type.RESEARCH_LAB, ShipPart.Type.CARGO_HOLD]), "science").is_empty(), "Science forbids cargo.")
	_check(not FleetRules.design_error(_policy_design([ShipPart.Type.RESEARCH_LAB, ShipPart.Type.PASSENGER_CABIN]), "science").is_empty(), "Science forbids berths.")
	_check(not FleetRules.design_error(_policy_design([ShipPart.Type.RESEARCH_LAB, ShipPart.Type.CARGO_HOLD]), "civic").is_empty(), "Civic forbids labs.")
	for type in [ShipPart.Type.MINING_LASER, ShipPart.Type.EXTRACTION_DRILL, ShipPart.Type.ORE_PROCESSOR, ShipPart.Type.SEISMIC_CUTTER, ShipPart.Type.PLANETCRACKER_CORE]:
		for role in ["science", "civic"]:
			var required := ShipPart.Type.RESEARCH_LAB if role == "science" else ShipPart.Type.CARGO_HOLD
			var design := _policy_design([required, type])
			_check(not FleetRules.design_error(design, role).is_empty(), "Every mining component is regular-slot-only.")
			_check(FleetRules.design_error(design, "regular").is_empty(), "Regular hulls retain legal support/mining options.")
	for type in [ShipPart.Type.FLIGHT_DECK, ShipPart.Type.TORPEDO_BOMBER_BAY, ShipPart.Type.STELLAR_LANCE, ShipPart.Type.SINGULARITY_PROJECTOR, ShipPart.Type.SIEGE_MASS_DRIVER, ShipPart.Type.HIVE_CARRIER_CORE]:
		_check(not FleetRules.design_error(_policy_design([ShipPart.Type.RESEARCH_LAB, type]), "science").is_empty(), "Offensive capstones and strike craft cannot use Science.")
		_check(not FleetRules.design_error(_policy_design([ShipPart.Type.CARGO_HOLD, type]), "civic").is_empty(), "Offensive capstones and strike craft cannot use Civic.")
	for index in range(7):
		science.set_tile_at(Vector2i(20 + index, 0), ShipPart.Category.OFFENSE)
	_check(not FleetRules.design_error(science, "science").is_empty(), "Loose Offense tiles count toward the six-tile limit.")
	science.remove_tile_at(Vector2i(26, 0))
	_check(FleetRules.design_error(science, "science").is_empty(), "Exactly six Offense tiles are permitted.")
	var physical := FleetShip.new()
	physical.design = science
	physical.slot_role = "science"
	physical.units = [{"part": science.parts[1], "hp": 1.0}]
	_check(FleetRules.operational_error(physical).is_empty(), "A living lab satisfies deployed Science.")
	physical.units[0].hp = 0
	_check(not FleetRules.operational_error(physical).is_empty(), "A destroyed lab cannot grant the dedicated Science designation.")

	var state := root.get_node("GameState")
	state.run_save_path = "user://fleet_slots/run.json"
	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 42), "Start fleet policy fixture.")
	var support_a := FleetShip.new()
	var support_b := FleetShip.new()
	for support in [support_a, support_b]:
		support.id = 100 if support == support_a else 101
		support.design = science
		support.slot_role = "science"
		support.core_index = 0
		support.units.assign([{"part": science.parts[0], "hp": 1.0}, {"part": science.parts[1], "hp": 1.0}])
		state.fleet.append(support)
	state.roster_state.support_ids.science = support_a.id
	_check(state.get_deployed_fleet().size() == 4 and not state.is_ship_deployed(support_b), "Exactly one physical Science ship can occupy the dedicated slot.")
	state.roster_state.support_ids.civic = support_a.id
	_check(not FleetRules.valid(state.roster_state, state.fleet), "A physical ship cannot occupy both dedicated slots.")
	state.roster_state.support_ids.science = 0
	state.roster_state.support_ids.civic = 0
	state.fleet.erase(support_a)
	state.fleet.erase(support_b)
	state.credits = 100000
	var originals: Array[Dictionary] = state.get_saved_ship_designs()
	var fixtures: Array[Dictionary] = [{"name": "Science Vessel", "ship": _variant(0).to_design_data()}, {"name": "Fourth", "ship": _variant(3).to_design_data()}]
	state.saved_ship_designs = fixtures
	var before_credits: int = state.credits
	_check(not state.purchase_saved_ship("Science Vessel", "science") and state.credits == before_credits,
		"Renaming/importing a combat design cannot manufacture a Science ship.")
	_check(state.purchase_ship(_variant(1), "Escort") and state.purchase_ship(_variant(2), "Frigate"), "Three regular families can construct physical copies.")
	var family_count: int = state.roster_state.families.size()
	_check(not state.purchase_saved_ship("Fourth") and state.roster_state.families.size() == family_count, "A fourth family cannot deploy through library construction.")
	_check(not state.purchase_ship(_variant(3), "Renamed"), "Direct/editor construction cannot bypass the three-family limit.")
	var alias := Ship.new()
	var data := _variant(0).to_design_data()
	data.tiles.reverse()
	data.parts.reverse()
	for tile in data.tiles:
		tile[0] += 2
		tile[1] += 2
	for part in data.parts:
		part.origin[0] += 2
		part.origin[1] += 2
	_check(alias.load_design_data(data) and FleetRules.fingerprint(alias) == FleetRules.fingerprint(_variant(0)), "Translation/order changes preserve family identity.")
	_check(state.purchase_ship(alias, "Another Alias") and state.roster_state.families.size() == family_count, "Renamed copies consume the existing family.")
	var starter: FleetShip = state.fleet[0]
	starter.units[starter.core_index].hp *= 0.8
	var hp: float = starter.units[starter.core_index].hp
	var id := starter.id
	_check(state.assign_fleet_design(0, "Fourth", _variant(3)), "A secured port can swap an active family.")
	_check(not state.is_ship_deployed(starter) and state.fleet.has(starter) and starter.units[starter.core_index].hp == hp,
		"Swapping families retains old physical ships/damage as reserves.")
	_check(state.purchase_ship(_variant(3), "Fourth"), "The newly assigned family constructs at normal cost.")
	var replacement: FleetShip = state.fleet.back()
	_check(state.assign_fleet_design(0, "Fourth revision", _variant(4), true), "An explicit revision stays in the selected family.")
	_check(state.family_for_design(_variant(4)) == replacement.family_id and state.is_ship_deployed(replacement), "Earlier revisions remain in their stable family.")
	_check(state.set_ship_reserve(replacement, true) and not state.is_ship_deployed(replacement), "Individual owned copies can be reserved.")
	_check(state.load_run_checkpoint(), "Reload stable families and reserves.")
	for owned in state.fleet:
		if owned.id == id:
			starter = owned
	_check(not state.is_ship_deployed(starter) and is_equal_approx(starter.units[starter.core_index].hp, hp), "Reserve HP/identity survives reload.")
	var deployed: Array[FleetShip] = state.get_deployed_fleet()
	_check(deployed.size() < state.fleet.size() and state.can_deploy(), "Owned reserves are separate from the deployed fleet.")
	_check(state.set_destination(state.get_reachable_nodes(0)[0]), "Deployment validates only active eligible assignments.")
	var progress: Dictionary = state.encounter_progress[str(state.destination_node_id)]
	_check(progress.ship_ids.size() == deployed.size() and progress.deployment.fleet.size() == deployed.size(), "Battle/research replay snapshots exclude reserves.")
	var sim := BattleSimulation.new()
	_check(sim.setup_owned(deployed, state.battle_aliens, 0.3, 0, 42), "Simulation receives deployed physical ships only.")
	for member in sim.players:
		member.owned_ship.units[member.owned_ship.core_index].hp = 0
		member.integrity = 0
	sim.advance(1.0 / 30.0)
	_check(state.settle_battle(sim) and not state.run_ended and state.fleet.has(starter), "A lost deployment cannot destroy ships held in reserve.")
	_check(state.assign_fleet_design(0, "Drone", _variant(0)) and state.can_deploy(), "A surviving reserve family can be redeployed after losses.")
	var checkpoint := RunCheckpoint.capture(state)
	checkpoint.fleet[0].slot_role = "science"
	_check(not RunCheckpoint.valid(checkpoint), "Loading cannot relabel a combat ship into an invalid dedicated slot.")
	# Migrate a pre-policy pending campaign checkpoint durably, preserving HP,
	# frozen enemies and the ledger while deriving identities from actual designs.
	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 99), "Start pending migration fixture.")
	_check(state.set_destination(state.get_reachable_nodes(0)[0]), "Freeze a pending deployment before migration.")
	var historical := RunCheckpoint.capture(state)
	historical.erase("fleet_roster")
	historical.progress.erase("family_identity_version")
	for entry in historical.fleet:
		entry.erase("family_id")
		entry.erase("slot_role")
		entry.erase("reserve")
		entry.erase("escort_target_id")
	var migration_path := "user://fleet_slots/historical.json"
	var store := AtomicRunStore.new()
	_check(store.commit(migration_path, historical, RunCheckpoint.valid).ok, "Store a valid historical campaign.")
	state.run_save_path = migration_path
	_check(state.load_run_checkpoint() and state.battle_pending and state.get_deployed_fleet().size() == 3, "Pending migration retains its playable fleet.")
	var migrated := store.load_latest(migration_path, RunCheckpoint.valid)
	_check(migrated.payload.has("fleet_roster") and int(migrated.generation) > 1, "Migration is durable before exposing loaded state.")
	var pending: Dictionary = state.encounter_progress[str(state.destination_node_id)]
	_check(pending.ship_ids.size() == 3 and state.cancel_battle(), "Migrated attempt identities remain settleable.")
	state.saved_ship_designs = originals
	_test_escort()
	await _test_ui(state)
	print("Fleet slot tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _test_escort() -> void:
	# Existing weaponed hulls isolate the movement policy from future lab effects.
	var host := FleetShip.new()
	var escort := FleetShip.new()
	host.initialize(_variant(0), 1, "Host")
	escort.initialize(_variant(0), 2, "Escort")
	escort.slot_role = "civic"
	escort.escort_target_id = host.id
	var owned: Array[FleetShip] = [host, escort]
	var aliens: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(1, 1.0, 42):
		aliens.append(alien)
	var simulation := BattleSimulation.new()
	_check(simulation.setup_owned(owned, aliens, 0.0, 0, 42), "Escort fixture initializes.")
	simulation.players[0].position = Vector2.ZERO
	simulation.players[0].heading = 0
	var member := simulation.players[1]
	member.position = Vector2(-90, 0)
	simulation.aliens[0].position = Vector2(400, 0)
	simulation._update_ship(member, 0.25)
	_check(member.position == Vector2(-90, 0) and member.velocity.is_zero_approx(), "Default support behavior holds behind its host instead of pursuing a distant enemy.")
	simulation.players[0].position = Vector2(80, 0)
	simulation._update_ship(member, 0.25)
	_check(member.position.x > -90, "Escort follows the chosen regular hull as it advances.")

func _test_ui(state: Node) -> void:
	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 42), "Start five-slot UI fixture.")
	var map: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await process_frame
	await process_frame
	var panel: Control = map.panel_tabs.get_node("Fleet")
	_check(panel.slots.size() == 5 and panel.slot_widgets.size() == 5, "Fleet UI exposes three regular plus Science/Civic slots.")
	_check(panel.slot_widgets[3].label.text.begins_with("SCIENCE") and panel.slot_widgets[4].label.text.begins_with("CIVIC"), "Dedicated slots are labeled distinctly.")
	_check(panel.slot_widgets[3].construct.visible == false and panel.slot_widgets[4].construct.visible == false, "Unimplemented support equipment is not exposed as a purchasable stub.")
	map.queue_free()
	current_scene = null
	await process_frame
