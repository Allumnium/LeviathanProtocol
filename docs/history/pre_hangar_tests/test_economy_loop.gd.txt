extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var state: Node
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	if not ok:
		failures += 1
		push_error(message)
	return ok

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://economy-loop/run.json"
	for mode in ["escort", "cargo", "passengers", "debt"]:
		play_route(mode)
	test_pool()
	print("Economy loop tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func blueprint(mode: String) -> Ship:
	if mode == "escort":
		return BUILTINS.escort()
	if mode == "cargo":
		return BUILTINS.hauler()
	var design := BUILTINS.scout()
	BUILTINS._add_part(design, ShipPart.Type.PASSENGER_CABIN, Vector2i(5, 3))
	return design

func play_route(mode: String) -> void:
	check(state.start_new_run(1, 42), "Start controlled economy comparison.")
	# Research timing is covered by opening-loop tests. Here all comparisons
	# have the same available knowledge and 124-credit discretionary capital.
	state.research_points = 20
	check(state.set_research_focus("civil_hospitality"), "Prepare accommodation for the controlled comparison.")
	state.credits = 124
	for field in ["red_tiles_available", "blue_tiles_available", "green_tiles_available", "core_tiles_available"]:
		state.set(field, 0)
	var design := blueprint(mode)
	var cost: int = state.get_construction_credit_cost(design)
	check(cost <= 124 and state.purchase_ship(design, mode), "Each alternative fits the same budget, paying full material prices.")
	var owned: FleetShip = state.fleet.back()
	var component_loss := false
	var debt_seen := false
	var repaired := false
	var refitted := false
	var arrival_count := 0
	var initial_id := owned.id
	for visit in range(7):
		var destination: int = state.get_reachable_nodes(state.current_node_id)[0]
		if not check(state.travel_to(destination), "Travel through a short route with multiple inhabited stops."):
			return
		if state.battle_pending:
			var sim := BattleSimulation.new()
			check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, state.allied_salvage_chance(), state.laser_upgrade_level,
				state.battle_simulation_seed(), state.battle_support_context()), "Use real Auto battles and physical components.")
			sim.victory_materials = state.battle_material_rewards()
			sim.set_objective_targets(state.battle_objective_ids())
			if visit == 4:
				for member in sim.players:
					if member.owned_ship.id != owned.id:
						continue
					var unit_index := 0
					for index in range(owned.units.size()):
						var part: ShipPart = owned.units[index].part
						if part != null and part.type == (ShipPart.Type.SINGLE_PLATE if mode == "cargo" else (ShipPart.Type.ARMOR_BLOCK if mode == "escort" else ShipPart.Type.PASSENGER_CABIN)):
							unit_index = index
							break
					owned.units[unit_index].hp = 0
					sim._refresh_owned_stats(member)
					component_loss = true
					if mode == "debt":
						state.credits = 0
						check(state.commit_field_pickup("loss-observation", [0, 0, 0, 0], {}), "Commit actual passenger casualties before the battle reward.")
						debt_seen = state.credits == -80
			for tick in range(60 * 180):
				sim.advance(1.0 / 60.0)
				if sim.phase != BattleSimulation.Phase.COMBAT:
					break
			if not check(sim.phase == BattleSimulation.Phase.VICTORY and state.settle_battle(sim), "The comparison route wins and settles on Auto, including the declared component loss."):
				return
		if state.is_shipyard_node(state.current_node_id):
			arrival_count += 1
			var balance: int = state.credits
			var ledger_size: int = state.transaction_ledger.size()
			check(state.dispatch_arrival() and state.dispatch_arrival() and state.credits == balance and state.transaction_ledger.size() == ledger_size,
				"Reopening each actual port cannot repeat sale, refill or ticket income.")
			if visit >= 4:
				for ship in state.get_deployed_fleet():
					if ship.needs_repair():
						check(state.repair_ship(ship), "Surviving trade/combat income funds normal component reconstruction.")
				repaired = owned.units.all(func(unit: Dictionary) -> bool: return unit.hp > 0)
			if visit >= 4 and mode != "debt":
				check(state.offload_cargo(owned.id) and state.disembark_passengers(owned.id), "Release physical loads before registering a revised hull.")
				var revised := blueprint(mode)
				var attachment := Vector2i.ZERO
				for cell: Vector2i in revised.tiles:
					for offset in FleetShip.NEIGHBORS:
						var candidate: Vector2i = cell + offset
						if candidate.x >= 0 and candidate.y >= 0 and not revised.tiles.has(candidate):
							attachment = candidate
							break
					if attachment != Vector2i.ZERO:
						break
				BUILTINS._add_part(revised, ShipPart.Type.SINGLE_PLATE, attachment)
				var slot: int = state.roster_state.active.find(owned.family_id)
				check(state.assign_fleet_design(slot, mode, revised, true) and state.purchase_ship(revised, mode), "Ordinary income affords a real paid revision after safe unloading.")
				owned = state.fleet.back()
				initial_id = owned.id
				refitted = true
		check(state.load_run_checkpoint(), "Reload every route row without changing settled income or loads.")
		var found: Array = state.fleet.filter(func(ship: FleetShip) -> bool: return ship.id == initial_id)
		if not check(found.size() == 1, "The tested physical hull survives the short route."):
			return
		owned = found[0]
	check(arrival_count >= 2 and component_loss and repaired, "The route includes multiple ports, losses and paid repair.")
	if mode == "debt":
		check(debt_seen and state.credits >= 0, "Surviving escorts recover the real 80-credit casualty debt without a grant or refund.")
	else:
		check(refitted, "The comparison includes a real researched family refit, not free healing.")
	var tickets := 0
	var sales := 0
	var fees := 0
	for entry: Dictionary in state.transaction_ledger.values():
		if entry.kind == "arrival":
			tickets += int(entry.details.get("passengers", {}).get("tickets", 0))
		elif entry.kind == "cargo_sale":
			sales += int(entry.credits_delta)
		elif entry.kind == "casualty":
			fees -= int(entry.credits_delta)
	if mode == "cargo":
		check(sales == 60, "Incoming cargo and the different destination load safely offloaded for refit each sell once at their frozen values.")
	print("Economy %s: budget 124, cost %d, end credits %d, tickets %d, sales %d, casualty fees %d, capacity %d" % [mode, cost, state.credits, tickets, sales, fees, state.used_deployment_capacity()])

func test_pool() -> void:
	check(state.start_new_run(1, 1357), "Start frozen salvage validation.")
	var destination: int = state.get_reachable_nodes(0)[0]
	check(state.travel_to(destination), "Freeze the first salvage encounter.")
	var encounter: Dictionary = state.get_frozen_encounter(destination)
	for category in range(4):
		check(encounter.rewards.material_pool[category] == encounter.rewards.materials[category] * 2, "The starting 50% payout cannot exceed the frozen material pool.")
	var bad := encounter.duplicate(true)
	bad.rewards.material_pool[0] += 1
	check(not EncounterGenerator.valid(bad), "Reject a forged frozen salvage pool.")
	bad = encounter.duplicate(true)
	bad.rewards.initial_recovery_rate = 1.5
	check(not EncounterGenerator.valid(bad), "Reject a forged recovery multiplier.")
	var before := RunCheckpoint.capture(state)
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, state.battle_simulation_seed()), "Initialize salvage retry fixture.")
	for index in range(4):
		var summon := BattleSimulation.Combatant.new()
		summon.entity_id = "test/summon/%d" % index
		summon.tags["summon"] = true
		summon.stats = ShipStats.new()
		summon.integrity = 1
		check(sim.register_entity(summon), "Register a finite test summon.")
		sim.damage_entity(summon.entity_id, 100)
	check(sim.drops.is_empty(), "Summons generate no enemy salvage.")
	var wreck := BattleSimulation.Drop.new()
	wreck.entity_id = "player/ship/1/wreck/0/0"
	wreck.category = ShipPart.Category.CORE
	sim.drops.append(wreck)
	sim.victory_materials = state.battle_material_rewards()
	sim._collect_all_salvage()
	sim._collect_all_salvage()
	check(sim.collected_categories == state.battle_material_rewards(), "Repeated collection and player wrecks cannot enlarge frozen enemy salvage.")
	sim.collected_categories.assign([0, 0, 0, 0])
	sim.phase = BattleSimulation.Phase.WITHDRAWN
	check(state.settle_battle(sim) and state.credits == before.progress.credits, "Withdrawal grants no enemy salvage or victory credits.")
	check(state.load_run_checkpoint() and state.travel_to(destination), "Retry the same frozen pool after reload.")
	var inventory: Array = [state.red_tiles_available, state.blue_tiles_available, state.green_tiles_available, state.core_tiles_available]
	var spoofed: Array = []
	spoofed.resize(1000)
	spoofed.fill(0)
	check(state.complete_battle(-1, spoofed), "Only authoritative frozen materials are accepted at victory.")
	for category in range(4):
		check(state.get_available_tile_count(category) == inventory[category] + int(encounter.rewards.materials[category]), "Caller-supplied drops cannot enlarge frozen victory rewards.")
