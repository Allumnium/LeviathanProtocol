extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func design(type: int) -> Ship:
	var result := Ship.new()
	BUILTINS._add_part(result, ShipPart.Type.COMMAND_CENTER, Vector2i(0, 1))
	BUILTINS._add_part(result, type, Vector2i(2, 1))
	BUILTINS._add_part(result, ShipPart.Type.MINI_TURRET, Vector2i(0, 3))
	return result
func physical(blueprint: Ship, id := 100) -> FleetShip:
	var result := FleetShip.new()
	check(result.initialize(blueprint, id, "Shared fixture"), "Functional shared recipe constructs and reloads.")
	return result
func simulation(owned: FleetShip, context: Dictionary = {}) -> BattleSimulation:
	var sim := BattleSimulation.new()
	var ships: Array[FleetShip] = [owned]
	var aliens: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(1, 1.0, 42):
		aliens.append(alien)
	check(sim.setup_owned(ships, aliens, 0, 0, 42, context), "Shared combat initializes.")
	sim.player.position = Vector2.ZERO
	sim.aliens[0].position = Vector2(100, 0)
	return sim
func repair_design() -> Ship:
	var result := design(ShipPart.Type.REPAIR_STATION)
	BUILTINS._add_part(result, ShipPart.Type.ARMOR_BLOCK, Vector2i(2, -1))
	BUILTINS._add_part(result, ShipPart.Type.CREW_QUARTERS, Vector2i(2, 3))
	return result
func run() -> void:
	await _test_purchases_and_ui()
	_test_energy()
	_test_repairs()
	_test_interception()
	_test_reserve_persistence()
	_test_earned_research()
	_test_shared_replay()
	print("Shared research tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
func _test_purchases_and_ui() -> void:
	var state = root.get_node("GameState")
	state.run_save_path = "user://shared/run.json"
	check(state.start_new_run(1, 42), "Start shared research campaign.")
	check(not state.purchase_research("applied_energy") and not state.is_equipment_available(ShipPart.Type.LASER), "Insufficient RP cannot unlock hardware.")
	state.research_points = 200
	check(not state.purchase_research("energy_manipulation") and not state.purchase_research("optics_i"), "Prerequisites and future content remain gated.")
	var blocker := FileAccess.open("user://shared/blocker", FileAccess.WRITE)
	blocker.store_string("file")
	blocker.close()
	var path: String = state.run_save_path
	state.run_save_path = "user://shared/blocker/run.json"
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	check(not state.purchase_research("applied_energy") and state.research_points == 200 and not state.current_research_ids.has("applied_energy"), "Failed save cannot debit RP or grant research.")
	Engine.print_error_messages = printed
	state.run_save_path = path
	var map: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(map)
	await process_frame
	var view: Control = map.panel_tabs.get_node("Upgrades").grouped_view
	view.selected_id = "applied_energy"
	view.open_details()
	check(view.review_action != null, "Ready research has a reviewed purchase action in the real grouped UI.")
	view.review_action.pressed.emit()
	check(state.research_points == 180 and state.is_equipment_available(ShipPart.Type.LASER) and state.is_equipment_available(ShipPart.Type.DOUBLE_LASER), "One reviewed purchase unlocks both beams for 20 RP.")
	check(not state.purchase_research("applied_energy") and state.research_points == 180, "Duplicate purchase cannot charge or unlock twice.")
	check(state.purchase_research("field_engineering") and state.purchase_research("guided_munitions") and state.purchase_research("energy_manipulation"), "All useful shared research is purchasable with satisfied prerequisites.")
	check(state.load_run_checkpoint() and state.research_points == 100 and is_equal_approx(state.energy_efficiency(), 0.1), "RP, purchases, ledger and concept grants reload together.")
	state.credits = 10000
	check(state.purchase_ship(design(ShipPart.Type.MISSILE_RACK), "Missile fixture"), "Newly researched hardware can be physically constructed.")
	check(state.purchase_research("laboratory_ii") and state.is_equipment_available(ShipPart.Type.RESEARCH_LAB, 2), "Physical lab II activates through its actual research grant.")
	check(not state.purchase_research("laboratory_iii"), "Lab III still requires the first boss.")
	state.research_points = 80
	state.story_flags["boss_i_defeated"] = true
	var destination: int = state.get_reachable_nodes(0)[0]
	check(state.set_destination(destination) and not state.purchase_research("laboratory_iii"), "Research cannot change a deployed battle.")
	check(is_equal_approx(state.battle_support_context().energy_efficiency, 0.1), "Departure freezes the concept modifier for replay.")
	state.cancel_battle()
	check(state.purchase_research("laboratory_iii") and state.is_equipment_available(ShipPart.Type.RESEARCH_LAB, 3), "Lab III purchases after its actual story and RP requirements are satisfied.")
	map.queue_free()
	await process_frame
func _test_energy() -> void:
	var blueprint := design(ShipPart.Type.LASER)
	BUILTINS._add_part(blueprint, ShipPart.Type.CREW_QUARTERS, Vector2i(2, 2))
	var owned := physical(blueprint)
	var base := owned.get_stats()
	var boosted := owned.get_stats(0, 0.1)
	check(is_equal_approx(base.weapons[0].get_dps(), 3 * 1.12) and is_equal_approx(boosted.weapons[0].get_dps(), 3 * 1.22), "Crew and Energy add to beam firing rate rather than multiplying.")
	check(boosted.weapons[0].damage_per_shot == 12 and boosted.weapons[1].get_dps() == 1, "Energy changes firing rate only and excludes projectile weapons.")
	check(is_equal_approx(owned.get_stats(0, 0.3).weapons[0].get_dps(), 3 * 1.3), "The shared stat path enforces the ordinary 30% ceiling.")
	var sim := simulation(owned, {"energy_efficiency": 0.1})
	check(is_equal_approx(sim.player.stats.dps, blueprint.get_stats(0, 0.1).dps), "Builder, physical hull and battle use the same researched stats.")
	owned.units[2].hp *= 0.5
	sim._refresh_owned_stats(sim.player)
	check(is_equal_approx(sim.player.stats.weapons[0].get_dps(), 3 * 1.22), "Damage refresh retains the concept modifier.")
	var shield := physical(design(ShipPart.Type.SHIELD))
	check(is_equal_approx(shield.get_stats(0, 0.1).shield_recharge, 44) and shield.get_stats(0, 0.1).shields == 40, "Energy boosts shield recharge without capacity.")
func _test_repairs() -> void:
	var owned := physical(repair_design())
	var sim := simulation(owned)
	owned.units[0].hp = 1
	owned.units[3].hp = 1
	SharedSupport.repair(sim, 0.1)
	check(is_equal_approx(owned.units[0].hp, 1.112) and is_equal_approx(owned.units[3].hp, 1.112), "Crew boosts finite throughput shared between two adjacent survivors.")
	check(is_equal_approx(sim.repair_reserves["100/1"], 19.776), "Reserve falls by actual repaired HP.")
	for tick in range(1000):
		SharedSupport.repair(sim, 0.1)
	check(is_equal_approx(sim.player.repaired_hp, 20) and is_zero_approx(sim.repair_reserves["100/1"]), "A station cannot create more than its finite 20 HP reserve.")
	var hp: float = owned.units[3].hp
	SharedSupport.repair(sim, 100)
	check(owned.units[3].hp == hp, "An exhausted reserve never regenerates itself.")
	sim.repair_reserves["100/1"] = 20
	owned.units[1].hp = 0
	SharedSupport.repair(sim, 1)
	check(owned.units[3].hp == hp, "Destroyed repair sources stop immediately.")
	owned.units[1].hp = owned.units[1].max_hp
	owned.units[3].hp = 0
	SharedSupport.repair(sim, 10)
	check(owned.units[3].hp == 0, "Field repair cannot reconstruct a destroyed component.")
	var replacement := physical(repair_design(), 101)
	replacement.units[3].hp = 1
	var retry := simulation(replacement, {"repair_reserves": sim.repair_reserves,
		"repair_pool": {"capacity": sim.repair_capacity, "spent": sim.repair_spent}})
	SharedSupport.repair(retry, 100)
	check(replacement.units[3].hp == 1 and retry.repair_capacity == 20, "Replacing or recycling a source cannot refill the finite node allowance.")
func _test_interception() -> void:
	var owned := physical(design(ShipPart.Type.POINT_DEFENSE_TURRET))
	var sim := simulation(owned)
	var weapon := sim.player.stats.weapons[0]
	var shot := BattleSimulation.Projectile.new()
	shot.source = sim.aliens[0]
	shot.target = sim.player
	shot.position = Vector2(50, 0)
	shot.damage = 100
	shot.interceptable = true
	sim.projectiles.append(shot)
	sim._add_pending_damage(sim.player, shot.damage)
	check(SharedSupport.intercept(sim, sim.player, weapon, Vector2.ZERO) and sim.projectiles.is_empty(), "Point defense removes an incoming missile before impact.")
	check(is_zero_approx(sim._pending_projectile_damage(sim.player)), "Interception releases the pending-damage reservation.")
	shot.interceptable = false
	sim.projectiles.append(shot)
	check(not SharedSupport.intercept(sim, sim.player, weapon, Vector2.ZERO), "Point defense cannot erase ordinary bullets.")
	shot.interceptable = true
	shot.position = Vector2(1000, 0)
	check(not SharedSupport.intercept(sim, sim.player, weapon, Vector2.ZERO), "Interception respects local weapon range.")
	shot.position = Vector2(50, 0)
	var craft := BattleSimulation.Combatant.new()
	craft.entity_id = "fixture/craft"
	craft.faction = BattleSimulation.Faction.ALIEN
	craft.tags["craft"] = true
	craft.stats = ShipStats.new()
	craft.integrity = 50
	craft.position = Vector2(100, 0)
	check(sim.register_entity(craft) and SharedSupport.weapon_target(sim, sim.player, weapon, Vector2.ZERO) == craft, "Point defense prioritizes hostile strike craft over hull fire.")
	owned.units[1].hp = 0
	sim._refresh_owned_stats(sim.player)
	check(sim.player.stats.weapons.size() == 1 and not SharedSupport.intercept(sim, sim.player, weapon, Vector2.ZERO), "Destroyed point defense cannot intercept.")
	var missile := simulation(physical(design(ShipPart.Type.MISSILE_RACK)))
	missile._update_ship(missile.player, 0.01)
	check(missile.projectiles.size() >= 3 and missile.projectiles[0].interceptable and missile.projectiles[0].speed == 200, "Missile Rack fires a long-range interceptable burst.")
	var alien := AlienShip.threat_variant("chrysalis", 0)
	check(AlienShip.from_snapshot(alien.to_snapshot()).stats.weapons[0].interceptable, "Alien missile identity survives frozen roster reload.")
	var legacy := alien.to_snapshot()
	legacy.weapons[0].resize(6)
	check(AlienShip.from_snapshot(legacy) != null and not AlienShip.from_snapshot(legacy).stats.weapons[0].interceptable, "Old frozen rosters load without reinterpreting their weapons.")
func _test_reserve_persistence() -> void:
	var state = root.get_node("GameState")
	check(state.start_new_run(1, 42), "Start reserve persistence fixture.")
	state.research_points = 20
	check(state.purchase_research("field_engineering"), "Research real repair stations.")
	state.credits = 10000
	check(state.purchase_ship(repair_design(), "Repair fixture"), "Construct repair fixture.")
	var owned: FleetShip = state.fleet.back()
	var node: int = state.get_reachable_nodes(0)[0]
	check(state.set_destination(node), "Freeze repair deployment.")
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, 42, state.battle_support_context()), "Initialize durable reserves.")
	owned.units[3].hp = 1
	SharedSupport.repair(sim, 1)
	var key := SharedSupport.reserve_key(owned, 1)
	var remaining: float = sim.repair_reserves[key]
	state.update_battle_support(sim)
	check(state.commit_field_pickup("repair-test", [1, 0, 0, 0], {"ore": 0}), "A midbattle pickup commits expended repair reserves with repaired HP.")
	SharedSupport.repair(sim, 1)
	remaining = sim.repair_reserves[key]
	state.update_battle_support(sim)
	check(state.commit_field_pickup("repair-test", [1, 0, 0, 0], {"ore": 0}), "Changing repair reserves cannot invalidate ore pickup idempotence.")
	sim.phase = BattleSimulation.Phase.WITHDRAWN
	check(state.settle_battle(sim) and state.load_run_checkpoint(), "Withdrawal saves repaired HP and expended reserves.")
	check(state.set_destination(node), "Retry the same frozen node.")
	var retry := BattleSimulation.new()
	check(retry.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, 42, state.battle_support_context()) and is_equal_approx(retry.repair_reserves[key], remaining), "A retry cannot refill the station reserve.")
	check(is_equal_approx(retry.repair_spent, sim.repair_spent) and retry.repair_capacity == sim.repair_capacity, "Node-wide expenditure also persists across retries.")
	var forged := RunCheckpoint.capture(state)
	forged.encounter_progress[str(node)].field.repair_reserves[key] = 999
	check(not RunCheckpoint.valid(forged), "Saved finite reserves reject impossible values.")
	state.cancel_battle()

func _test_earned_research() -> void:
	var state = root.get_node("GameState")
	check(state.start_new_run(1, 42), "Start actual earn-and-research scenario.")
	check(state.purchase_ship(design(ShipPart.Type.RESEARCH_LAB), "Starting scientist"), "Starting resources can build a functional lab hull.")
	var battles := 0
	while battles < 8:
		var node: int = state.get_reachable_nodes(state.current_node_id)[0]
		check(state.travel_to(node), "Follow a legal route toward a shipyard.")
		if state.battle_pending:
			var sim := BattleSimulation.new()
			check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, state.battle_simulation_seed(), state.battle_support_context()), "Initialize real starting combat.")
			for tick in range(60 * 120):
				sim.advance(1.0 / 60.0)
				if sim.phase != BattleSimulation.Phase.COMBAT:
					break
			check(sim.phase == BattleSimulation.Phase.VICTORY and state.settle_battle(sim), "Win and settle real victory RP from a deployed lab.")
			battles += 1
		if not state.current_research_ids.has("applied_energy"):
			check(state.purchase_research("applied_energy"), "Earned victory RP buys Applied Energy without injected research points.")
		if state.is_shipyard_node(state.current_node_id):
			var blueprint := design(ShipPart.Type.LASER)
			check(state.purchase_ship(blueprint, "Researched beam"), "Earned research leads to a paid working beam hull at the next shipyard.")
			var owned: FleetShip = state.fleet.back()
			check(is_equal_approx(owned.get_stats().weapons[0].get_dps(), 3), "The purchased refit has a real next-battle weapon benefit.")
			return
		if state.run_ended:
			break
	check(false, "The starting route must reach a shipyard with useful research.")

func _test_shared_replay() -> void:
	var blueprint := repair_design()
	BUILTINS._add_part(blueprint, ShipPart.Type.POINT_DEFENSE_TURRET, Vector2i(4, 0))
	BUILTINS._add_part(blueprint, ShipPart.Type.MISSILE_RACK, Vector2i(4, 2))
	var snapshots: Array[Dictionary] = []
	for run_index in range(2):
		var owned := physical(blueprint)
		owned.units[3].hp -= 5
		var sim := BattleSimulation.new()
		var ships: Array[FleetShip] = [owned]
		var aliens: Array[RefCounted] = [AlienShip.threat_variant("chrysalis", 0)]
		check(sim.setup_owned(ships, aliens, 0, 0, 123, {"energy_efficiency": 0.1}), "Shared replay initializes from the same physical inputs.")
		sim.player.position = Vector2.ZERO
		sim.aliens[0].position = Vector2(120, 0)
		for tick in range(300):
			sim.advance(1.0 / 30.0)
		snapshots.append(JSON.parse_string(JSON.stringify(sim.authoritative_snapshot())))
	check(snapshots[0] == snapshots[1], "Repairs, missiles, interception and concept modifiers replay deterministically.")
