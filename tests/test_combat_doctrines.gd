extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func blueprint(types: Array) -> Ship:
	var design := Ship.new()
	BUILTINS._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	for index in range(types.size()):
		BUILTINS._add_part(design, types[index], Vector2i(3 + index * 4, 0))
	if design.get_stats().weapons.is_empty():
		BUILTINS._add_part(design, ShipPart.Type.MINI_TURRET, Vector2i(3 + types.size() * 4, 0))
	return design

func physical(design: Ship, id := 100) -> FleetShip:
	var owned := FleetShip.new()
	check(owned.initialize(design, id, "Test"), "Initialize researched physical components.")
	return owned

func fixture(design: Ship, extras: Array[FleetShip] = [], pool: Dictionary = {}) -> BattleSimulation:
	var ships: Array[FleetShip] = [physical(design)]
	ships.append_array(extras)
	var stats := ShipStats.new()
	stats.integrity = 500
	stats.shields = 20
	stats.weight = 10
	stats.weapons.append(ShipWeaponStats.new("Fixture", 1000, 0.1, 1, 100))
	var aliens: Array[RefCounted] = [AlienShip.new("Target", preload("res://assets/drone_scout.png"), stats)]
	var sim := BattleSimulation.new()
	var ability := BattleAbilities.initial_state()
	ability.auto = {"scan": false, "ion_pulse": false, "gravity_well": false}
	check(sim.setup_owned(ships, aliens, 0, 0, 42, {"visibility_enabled": true,
		"doctrine_pool": pool, "ability_state": ability, "ability_ids": ["scan", "ion_pulse", "gravity_well"]}), "Initialize doctrine fixture.")
	for index in range(sim.players.size()):
		sim.players[index].position = Vector2(0, index * 60)
		sim.players[index].speed = 0
		sim.players[index].acceleration = 0
	sim.aliens[0].position = Vector2(160, 0)
	sim.aliens[0].speed = 0
	sim.aliens[0].acceleration = 0
	sim.refresh_visibility()
	return sim

func run() -> void:
	test_lens()
	test_charge()
	test_disruption()
	test_bastion()
	test_renewal()
	test_replay()
	test_pool_validation()
	test_authorization()
	test_persistence()
	await test_native()
	print("Combat doctrine tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func test_lens() -> void:
	var design := Ship.new()
	BUILTINS._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(design, ShipPart.Type.FOCUSING_LENS, Vector2i(2, 0))
	BUILTINS._add_part(design, ShipPart.Type.LASER, Vector2i(2, 2))
	BUILTINS._add_part(design, ShipPart.Type.DOUBLE_LASER, Vector2i(4, 0))
	BUILTINS._add_part(design, ShipPart.Type.FOCUSING_LENS, Vector2i(2, 3))
	var owned := physical(design)
	var base: ShipWeaponStats = design.parts[2].stats.weapons[0]
	var weapon: ShipWeaponStats = owned.get_stats().weapons[0]
	check(is_equal_approx(weapon.damage_per_shot, base.damage_per_shot * 1.2) and is_equal_approx(weapon.range_units, base.range_units * 1.2), "Lens improves real adjacent beam damage and range.")
	check(is_equal_approx(weapon.fire_interval_seconds, base.fire_interval_seconds * 1.25) and weapon.charge_seconds == 0.25,
		"Duplicate lenses do not stack; specialization pays an interval and windup cost.")
	check(CombatDoctrines.adjacency_targets(owned.units, ShipPart.Type.FOCUSING_LENS, [ShipPart.Type.LASER, ShipPart.Type.DOUBLE_LASER]).size() == 2,
		"Only two distinct adjacent beam recipients are selected.")
	owned.units[1].hp = 0
	owned.units[4].hp = 0
	check(owned.get_stats().weapons[0].damage_per_shot == base.damage_per_shot and owned.get_stats().weapons[0].charge_seconds == 0,
		"Destroyed lenses stop contributing immediately.")
	var sim := fixture(design)
	var target := sim.aliens[0]
	target.shields = 0
	var double: ShipWeaponStats = sim.player.stats.weapons[1]
	var before := target.integrity
	sim.doctrines.begin_charge(sim, sim.player, double, target, Vector2.ZERO)
	sim.doctrines.advance(sim, double.charge_seconds + 0.01)
	check(is_equal_approx(before - target.integrity, double.damage_per_shot * 2), "Lens-assisted Double Laser retains both shots after its charge.")
	var energy := physical(blueprint([ShipPart.Type.BEAM_LANCE, ShipPart.Type.ION_EMITTER]))
	var ordinary := energy.get_stats()
	var efficient := energy.get_stats(0, 0.1)
	for index in range(ordinary.weapons.size()):
		check(is_equal_approx(efficient.weapons[index].fire_interval_seconds, ordinary.weapons[index].fire_interval_seconds / 1.1),
			"Energy Manipulation applies to the new energy weapons under the existing efficiency cap.")

func test_charge() -> void:
	var sim := fixture(blueprint([ShipPart.Type.BEAM_LANCE]))
	var weapon: ShipWeaponStats = sim.player.stats.weapons[0]
	var target := sim.aliens[0]
	var before := target.integrity + target.shields
	sim._update_ship(sim.player, 0.01)
	check(sim.doctrines.charges.size() == 1 and target.integrity + target.shields == before, "Lance announces its charge before dealing damage.")
	sim.doctrines.advance(sim, 1.19)
	check(target.integrity + target.shields == before, "Charge cannot deal early damage.")
	sim.doctrines.advance(sim, 0.02)
	check(is_equal_approx(before - target.integrity - target.shields, 12), "Lance commits the actual charged shot.")
	sim.doctrines.begin_charge(sim, sim.player, weapon, target, Vector2.ZERO)
	sim.player.owned_ship.units[1].hp = 0
	sim.doctrines.advance(sim, 2)
	check(sim.doctrines.charges.is_empty() and is_equal_approx(before - target.integrity - target.shields, 12), "Destroying the charging component cancels its unfinished shot.")
	sim.player.owned_ship.units[1].hp = sim.player.owned_ship.units[1].max_hp
	sim.doctrines.begin_charge(sim, sim.player, weapon, target, Vector2.ZERO)
	target.position += Vector2(0, 60)
	sim.refresh_visibility()
	sim.doctrines.advance(sim, 2)
	check(is_equal_approx(before - target.integrity - target.shields, 12), "Moving off the warned aim point avoids the charged beam.")
	var armor := Ship.new()
	BUILTINS._add_part(armor, ShipPart.Type.COMMAND_CENTER, Vector2i(-6, 0))
	BUILTINS._add_part(armor, ShipPart.Type.ARMOR_BLOCK, Vector2i.ZERO)
	BUILTINS._add_part(armor, ShipPart.Type.ARMOR_BLOCK, Vector2i(0, 2))
	var victim := physical(armor, 101)
	var fight := fixture(blueprint([ShipPart.Type.MINI_TURRET]), [victim])
	var member := fight.players[1]
	member.shields = 0
	fight._damage(member, 100, member.position + Vector2(200, 0), fight.player, "Beam Lance")
	var damaged := 0
	for unit in victim.units:
		if unit.hp < unit.max_hp:
			damaged += 1
	check(damaged == 2, "Lance penetration is bounded to two exposed physical components.")
	var stationary := fixture(blueprint([ShipPart.Type.BEAM_LANCE]))
	for tick in range(330):
		stationary.advance(1.0 / 30)
	check(stationary.phase == BattleSimulation.Phase.COMBAT and stationary.inactive_seconds < 4.1,
		"Repeated charged hits count as combat activity instead of causing an idle withdrawal.")

func test_disruption() -> void:
	var sim := fixture(blueprint([ShipPart.Type.ION_EMITTER, ShipPart.Type.GRAVITIC_SNARE]))
	var target := sim.aliens[0]
	sim._damage(target, 2, sim.player.position, sim.player, "Ion Emitter")
	check(target.shields == 16, "Ion basic fire pressures shields at twice its base damage.")
	target.shields = 0
	sim._damage(target, 2, sim.player.position, sim.player, "Ion Emitter")
	check(target.integrity == 499, "Ion basic fire has half hull damage.")
	check(sim.abilities.cast(sim, "ion_pulse", target.position), "Ion Pulse accepts a visible in-range enemy.")
	target.since_damage = 10
	sim._update_ship(target, 1)
	check(target.shields == 0 and sim.abilities.remaining("ion_pulse") == 24, "Ion suppresses recharge and consumes the shared cooldown.")
	check(not sim.abilities.cast(sim, "ion_pulse", target.position), "A second emitter cannot multiply activations.")
	check(sim.abilities.cast(sim, "gravity_well", target.position) and sim.abilities.movement_rate(target) == 0.65,
		"Gravity field slows enemy movement and turning by 35 percent.")
	check(sim.abilities.movement_rate(sim.player) == 1, "Gravity does not slow its allies.")
	target.speed = 100
	target.velocity = Vector2(100, 0)
	sim._investigate_contacts(target, 0.1)
	check(target.velocity.length() <= 65.00001, "Gravity also slows radar/search movement without a live weapon target.")
	target.position = Vector2(700, 0)
	sim.refresh_visibility()
	check(not sim.team_can_see(0, target) and not sim.point_visible(0, Vector2(260, 0)), "Control fields do not grant Scan coverage or track unseen enemies.")
	sim.abilities.advance(sim, 5.01)
	check(not sim.abilities.suppressed(target) and sim.abilities.movement_rate(target) == 1, "Control effects expire on the simulation clock.")
	var state := sim.abilities.snapshot()
	check(not sim.abilities.can_cast(sim, "gravity_well", Vector2(600, 0)) and sim.abilities.snapshot() == state, "Hidden or out-of-range field targets consume nothing.")
	var charge := fixture(blueprint([ShipPart.Type.BEAM_LANCE]))
	charge.doctrines.begin_charge(charge, charge.player, charge.player.stats.weapons[0], charge.aliens[0], Vector2.ZERO)
	check(charge.doctrines.interrupt(charge, charge.player) and charge.doctrines.charges.is_empty(), "Ion's shared interrupt path cancels ordinary weapon charges.")
	var plan := EncounterGenerator.generate(42, 20, 8, 1, "bastion_warden", 4)
	var boss := BattleSimulation.new()
	var ships: Array[FleetShip] = [physical(blueprint([ShipPart.Type.ION_EMITTER]))]
	check(boss.setup_owned(ships, EncounterGenerator.initial_fleet(plan), 0, 0, 42,
		{"visibility_enabled": true, "ability_ids": ["ion_pulse"], "encounter_plan": plan}), "Initialize researched Ion against actual Warden.")
	var body = boss.entities[plan.warden.body_id]
	boss.player.position = body.position + Vector2(-180, 0)
	boss.refresh_visibility()
	boss.encounter.warden.advance(boss, 9)
	check(boss.encounter.warden.charging and boss.abilities.cast(boss, "ion_pulse", body.position)
		and not boss.encounter.warden.charging and boss.encounter.warden.finished_cycle == boss.encounter.warden.cycle,
		"A committed Ion Pulse interrupts one actual Warden charge within its boss limits.")

func test_bastion() -> void:
	var design := Ship.new()
	BUILTINS._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(design, ShipPart.Type.REACTIVE_BULKHEAD, Vector2i(2, 0))
	BUILTINS._add_part(design, ShipPart.Type.LASER, Vector2i(2, 2))
	var owned := physical(design)
	check(CombatDoctrines.protected_unit(owned, 0) and CombatDoctrines.protected_unit(owned, 2) and not CombatDoctrines.protected_unit(owned, 1),
		"Bulkhead protects two touching components, without protecting itself.")
	var sim := fixture(design)
	var member := sim.player
	var origin := member.position + Vector2(0, 200)
	for candidate in range(100):
		sim.random.seed = candidate
		var cell := member.owned_ship.hit_cell(origin - member.position, sim.random)
		if CombatDoctrines.protected_unit(member.owned_ship, member.owned_ship.cell_units[cell]):
			sim.random.seed = candidate
			break
	var before := member.integrity
	sim._damage(member, 1, origin, sim.aliens[0], "Bullet", true)
	check(is_equal_approx(before - member.integrity, 0.7), "Projectile hull damage applies the actual 30-percent bulkhead reduction.")
	var relay := fixture(blueprint([ShipPart.Type.SHIELD, ShipPart.Type.SHIELD_RELAY]), [physical(blueprint([ShipPart.Type.SHIELD]), 101)])
	relay.players[1].shields = 0
	var total := relay.player.shields
	relay.doctrines.advance(relay, 1)
	check(relay.players[1].shields == 2 and is_equal_approx(relay.player.shields + relay.players[1].shields, total), "Relay transfers two shields per second, debiting its host exactly.")
	relay.players[1].position = Vector2(400, 0)
	var before_transfer := relay.player.shields
	relay.doctrines.advance(relay, 10)
	check(relay.player.shields == before_transfer, "Relay cannot reach a distant ally.")

func test_renewal() -> void:
	var sim := fixture(blueprint([ShipPart.Type.REPAIR_DRONE_BAY]), [physical(blueprint([ShipPart.Type.ARMOR_BLOCK]), 101)])
	var target := sim.players[1]
	target.owned_ship.units[1].hp = 1
	sim._refresh_owned_stats(target)
	sim.doctrines.advance(sim, 0.01)
	check(sim.doctrines.drones.size() == 1 and sim.doctrines.pool.repair_spent == 4, "Launching an interceptable repair drone spends its payload immediately.")
	var drone = sim.doctrines.drones[0].actor
	check(drone.has_tag("craft") and drone.has_tag("summon") and drone.targetable, "Repair drones participate in normal interception and grant no salvage.")
	sim.damage_entity(drone.entity_id, 10)
	sim.doctrines.advance(sim, 0.5)
	check(target.owned_ship.units[1].hp == 1 and sim.doctrines.pool.repair_spent == 4, "An intercepted drone heals nothing and does not refund its reserve.")
	sim.doctrines.advance(sim, 2)
	sim.doctrines.advance(sim, 1)
	check(target.owned_ship.units[1].hp == 5, "A surviving drone delivers a bounded four-HP repair.")
	for tick in range(40):
		target.owned_ship.units[1].hp = 1
		sim.doctrines.advance(sim, 1)
	check(sim.doctrines.pool.repair_spent == 20, "Drone bays exhaust their finite reserve.")
	var retry := fixture(blueprint([ShipPart.Type.REPAIR_DRONE_BAY]), [], sim.doctrines.pool)
	retry.player.owned_ship.units[0].hp = 1
	retry.doctrines.advance(retry, 10)
	check(retry.doctrines.drones.is_empty(), "Retry cannot refill the spent drone reserve.")
	var nano := fixture(blueprint([ShipPart.Type.NANOFORGE, ShipPart.Type.ARMOR_BLOCK, ShipPart.Type.MINI_TURRET]))
	nano.player.owned_ship.units[2].hp = 0
	nano.player.owned_ship.units[3].hp = 0
	nano.doctrines.advance(nano, 0.01)
	check(nano.player.owned_ship.units[2].hp == nano.player.owned_ship.units[2].max_hp * 0.25 and nano.player.owned_ship.units[3].hp == 0,
		"Nanoforge reconstructs exactly one non-command component at 25-percent HP.")
	nano.player.owned_ship.units[2].hp = 0
	nano.doctrines.advance(nano, 10)
	check(nano.player.owned_ship.units[2].hp == 0, "Duplicate modules or time cannot reconstruct repeatedly.")
	var exhausted := fixture(blueprint([ShipPart.Type.NANOFORGE, ShipPart.Type.ARMOR_BLOCK]), [], nano.doctrines.pool)
	exhausted.player.owned_ship.units[1].hp = 0
	exhausted.player.owned_ship.units[2].hp = 0
	exhausted.doctrines.advance(exhausted, 10)
	check(exhausted.player.owned_ship.units[2].hp == 0, "A retry preserves reconstruction expenditure and destroyed sources.")
	var design := Ship.new()
	BUILTINS._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(design, ShipPart.Type.CREW_QUARTERS, Vector2i(2, 0))
	BUILTINS._add_part(design, ShipPart.Type.REPAIR_DRONE_BAY, Vector2i(2, 1))
	BUILTINS._add_part(design, ShipPart.Type.ARMOR_BLOCK, Vector2i(5, 0))
	BUILTINS._add_part(design, ShipPart.Type.MINI_TURRET, Vector2i(5, 2))
	for staffed in [false, true]:
		var crew := fixture(design)
		crew.player.owned_ship.units[3].hp = 1
		if not staffed:
			crew.player.owned_ship.units[1].hp = 0
		crew.doctrines.advance(crew, 0.01)
		crew.doctrines.advance(crew, 1.79)
		check(crew.doctrines.pool.repair_spent == (8 if staffed else 4) and crew.doctrines.pool.repair_capacity == 20,
			"Crew accelerates drone cadence without enlarging its finite reserve.")
	check(not AdjacencyRules.eligible(blueprint([ShipPart.Type.NANOFORGE]).parts[1]), "Instant reconstruction does not consume a Crew rate recipient slot.")

func test_replay() -> void:
	var design := blueprint([ShipPart.Type.BEAM_LANCE, ShipPart.Type.ION_EMITTER, ShipPart.Type.GRAVITIC_SNARE,
		ShipPart.Type.REPAIR_DRONE_BAY, ShipPart.Type.NANOFORGE, ShipPart.Type.ARMOR_BLOCK])
	var reference: Dictionary = {}
	var events: Array = []
	for batch in [1, 2, 5]:
		var sim := fixture(design)
		sim.player.owned_ship.damage_cell(Vector2i(23, 0), 100)
		sim._refresh_owned_stats(sim.player)
		check(sim.queue_command({"id": "ion", "tick": 2, "type": "ability_cast", "payload": {"ability": "ion_pulse", "position": [160, 0], "source": "", "faction": 0}}), "Queue recorded control input.")
		for group in range(150 / batch):
			for tick in range(batch):
				sim.advance(1.0 / 30)
		if reference.is_empty():
			reference = sim.authoritative_snapshot()
			events = sim.event_log.duplicate(true)
		else:
			check(reference == sim.authoritative_snapshot() and events == sim.event_log, "Charges, control, drones and reconstruction replay identically across tick batches.")

func test_pool_validation() -> void:
	for value in [null, [], {"version": 1}, {"version": 1, "repair_capacity": 20, "repair_spent": 21, "rebuild_capacity": 1, "rebuilt": []},
		{"version": 1, "repair_capacity": 20, "repair_spent": 0, "rebuild_capacity": 2, "rebuilt": ["1", "1"]}]:
		check(not CombatDoctrines.valid_pool(value), "Malformed or overdrawn support state is rejected.")
	check(CombatDoctrines.valid_pool({}), "Historical checkpoints default to uninitialized doctrine reserves.")
	var sim := BattleSimulation.new()
	var ships: Array[FleetShip] = [physical(blueprint([ShipPart.Type.MINI_TURRET]))]
	var aliens: Array[RefCounted] = [AlienShip.threat_variant("scout", 1)]
	check(not sim.setup_owned(ships, aliens, 0, 0, 42, {"doctrine_pool": []}), "Malformed deployment support is rejected without a type error.")

func test_authorization() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://doctrines/authorization.json"
	for paths in [["optics_i", "optics_ii", "bastion_i", "bastion_ii"], ["disruption_i", "disruption_ii", "renewal_i", "renewal_ii"]]:
		check(state.start_new_run(1, 42), "Start actual branch authorization run.")
		state.research_points = 1000
		check(state.purchase_research("applied_energy") and state.purchase_research("field_engineering"), "Purchase shared branch prerequisites.")
		for id in paths:
			check(state.purchase_research(id), "Functional branch research can be completed through real accounting.")
		check(state.load_run_checkpoint(), "Exclusive branch choices and grants survive reload.")
		var opposite: String = "disruption_i" if paths[0] == "optics_i" else "optics_i"
		check(not state.set_research_focus(opposite) and not state.purchase_research(opposite), "A committed branch cannot research its exact-recipe opposite.")
		check(not state.purchase_research("optics_iii") and not state.purchase_research("renewal_iii"), "Endpoints stay unavailable.")
		var types: Array = [ShipPart.Type.FOCUSING_LENS, ShipPart.Type.BEAM_LANCE, ShipPart.Type.REACTIVE_BULKHEAD, ShipPart.Type.SHIELD_RELAY] \
			if paths[0] == "optics_i" else [ShipPart.Type.ION_EMITTER, ShipPart.Type.GRAVITIC_SNARE, ShipPart.Type.REPAIR_DRONE_BAY, ShipPart.Type.NANOFORGE]
		var design := blueprint(types + [ShipPart.Type.MINI_TURRET])
		state.credits = 10000
		check(state.design_research_error(design).is_empty() and state.purchase_ship(design, "Branch ship"), "Players construct researched mixed ships through normal family and price rules.")
		var recipe := MaterialRecipe.signature(MaterialRecipe.parse("OT/TT"))
		var candidates: Array[String] = []
		for pattern in ShipPartPattern.get_catalog():
			if MaterialRecipe.signature(MaterialRecipe.parse(GameDefinitions.equipment(pattern.part_type).recipe)) == recipe and state.is_equipment_available(pattern.part_type):
				candidates.append(pattern.definition_id)
		check(candidates.size() == 1 and candidates[0] == ("focusing_lens" if paths[0] == "optics_i" else "ion_emitter"), "An exact shared recipe resolves to one legal branch component.")

func test_persistence() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://doctrines/persistence.json"
	check(state.start_new_run(1, 1357), "Start actual support persistence run.")
	state.research_points = 1000
	for id in ["field_engineering", "renewal_i", "renewal_ii", "civil_hospitality"]:
		check(state.purchase_research(id), "Unlock required real support recipes.")
	state.credits = 10000
	var design := blueprint([ShipPart.Type.NANOFORGE, ShipPart.Type.REPAIR_DRONE_BAY, ShipPart.Type.PASSENGER_CABIN, ShipPart.Type.CARGO_HOLD, ShipPart.Type.MINI_TURRET])
	check(state.purchase_ship(design, "Recovery"), "Construct a mixed recovery and economic ship.")
	check(state.purchase_ship(design, "Recovery"), "A second ordinary hull shares the family and has its own single reconstruction.")
	var next: int = state.get_reachable_nodes(state.current_node_id)[0]
	check(state.travel_to(next), "Freeze actual support departure.")
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, state.allied_salvage_chance(), 0, state.battle_simulation_seed(), state.battle_support_context()), "Initialize actual saved support context.")
	sim.battle_id = state.battle_identity()
	var member = sim.players[sim.players.size() - 2]
	var owned: FleetShip = member.owned_ship
	var cargo_member = sim.players.back()
	var cargo_owned: FleetShip = cargo_member.owned_ship
	state.economy_state = PassengerRules.register_components(state.economy_state, state.fleet)
	state.economy_state = CargoRules.register_components(state.economy_state, state.fleet)
	# Stage genuine occupied loads to test destruction and same-tick reconstruction.
	var passenger_id := PassengerRules.component_id(owned.id, 3)
	var cargo_id := PassengerRules.component_id(cargo_owned.id, 4)
	state.economy_state.passengers.components[passenger_id].occupied = 4
	state.economy_state.cargo.holds[cargo_id].quantity = 10
	state.economy_state.cargo.holds[cargo_id].origin = "node/0"
	state.economy_state.cargo.holds[cargo_id].grade = "basic"
	state.economy_state.cargo.holds[cargo_id].unit_value = 3
	owned.damage_cell(Vector2i(11, 0), 100)
	sim._refresh_owned_stats(member)
	sim.doctrines.advance(sim, 0.1)
	check(owned.units[3].hp > 0 and owned.units[3].get("load_lost", false), "Rebuilt cabin remembers that its former occupants died.")
	cargo_owned.damage_cell(Vector2i(15, 0), 100)
	sim._refresh_owned_stats(cargo_member)
	sim.doctrines.advance(sim, 0.1)
	check(cargo_owned.units[4].hp > 0 and sim.doctrines.pool.rebuilt.size() == 2, "Each hull rebuilds once; a rebuilt hold remembers its destroyed goods.")
	state.update_battle_support(sim)
	var proposal: Dictionary = state._capture_checkpoint()
	check(proposal.economy.passengers.components[passenger_id].occupied == 0 and proposal.economy.cargo.holds[cargo_id].quantity == 0,
		"Reconstruction cannot resurrect passengers or cargo before settlement.")
	var path: String = state.run_save_path
	var blocker := FileAccess.open("user://doctrines/blocker", FileAccess.WRITE)
	blocker.store_string("file")
	blocker.close()
	state.run_save_path = "user://doctrines/blocker/run.json"
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	check(not state.save_run_checkpoint() and owned.units[3].get("load_lost", false), "Failed checkpoint keeps the pending economic loss latched.")
	Engine.print_error_messages = printed
	state.run_save_path = path
	var before: int = state.credits
	check(state.save_run_checkpoint() and state.load_run_checkpoint() and state.credits == before - 80, "A successful reload charges cabin casualties exactly once.")
	check(state.save_run_checkpoint() and state.load_run_checkpoint() and state.credits == before - 80, "Repeated persistence cannot repeat casualty fees.")
	var retry := BattleSimulation.new()
	check(retry.setup_owned(state.get_deployed_fleet(), state.battle_aliens, state.allied_salvage_chance(), 0, state.battle_simulation_seed(), state.battle_support_context()), "Reload actual support battle.")
	print("Support pools: %s -> %s" % [sim.doctrines.pool, retry.doctrines.pool])
	check(JSON.parse_string(JSON.stringify(retry.doctrines.pool)) == JSON.parse_string(JSON.stringify(sim.doctrines.pool)), "Reload retains spent drone and reconstruction allowances.")
	var forged: Dictionary = state._capture_checkpoint()
	forged.encounter_progress[str(next)].field.doctrine_pool.repair_spent = 1000
	check(not RunCheckpoint.valid(forged), "Saved support pool cannot exceed its frozen allowance.")
	retry.battle_id = state.battle_identity()
	for target in retry.aliens:
		retry.damage_entity(target.entity_id, 100000)
	retry.advance(1.0 / 30)
	check(retry.phase == BattleSimulation.Phase.VICTORY and state.settle_battle(retry) and state.load_run_checkpoint(),
		"A real battle containing reconstructed hulls settles and reloads successfully.")
	check(PassengerRules.occupied(state.economy_state) == 0 and CargoRules.quantity(state.economy_state) == 0,
		"Battle settlement keeps reconstructed accommodation and holds empty.")

func test_native() -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	root.size = Vector2i(640, 360)
	var sim := fixture(blueprint([ShipPart.Type.BEAM_LANCE, ShipPart.Type.ION_EMITTER, ShipPart.Type.GRAVITIC_SNARE]))
	sim.player.position = Vector2(-100, 0)
	sim.aliens[0].position = Vector2(80, 0)
	sim.refresh_visibility()
	var view = load("res://scripts/battle_visuals.gd").new()
	view.simulation = sim
	view.size = Vector2(640, 360)
	view.camera_zoom = 0.8
	root.add_child(view)
	var bar = load("res://scripts/battle_ability_bar.gd").new()
	bar.theme = load("res://themes/ui_theme.tres")
	bar.simulation = sim
	bar.visuals = view
	view.add_child(bar)
	bar.position = Vector2(8, 286)
	await process_frame
	bar.begin_targeting("gravity_well")
	bar.set_preview(sim.aliens[0].position)
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(bar.get_global_rect()), "Three-action doctrine bar fits the minimum viewport.")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/doctrines/control-preview-640.png")
	check(bar.cast_at(sim.aliens[0].position), "Native control preview commits through the same cast command.")
	sim._update_ship(sim.player, 0.01)
	sim.doctrines.begin_charge(sim, sim.player, sim.player.stats.weapons[0], sim.aliens[0], sim._get_weapon_origin(sim.player, sim.player.stats.weapons[0]))
	check(not sim.doctrines.charges.is_empty(), "Native charge capture contains a real pending beam.")
	check(sim.team_can_see(0, sim.player) and sim.team_can_see(0, sim.aliens[0]), "Native charge warning has legitimately visible endpoints.")
	sim.beams.clear() # Isolate the charge warning from the fixture's simultaneous Ion beam.
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var pending: Dictionary = sim.doctrines.charges.values()[0]
	var warning_point: Vector2 = view.world_transform() * pending.origin.lerp(pending.aim, 0.7)
	var warning_color := root.get_texture().get_image().get_pixelv(Vector2i(warning_point.round()))
	check(warning_color.r > 0.5 and warning_color.g > 0.35, "Charge warning remains visible at minimum-size zoom.")
	root.get_texture().get_image().save_png("res://.local/doctrines/charge-640.png")
	sim.aliens[0].position = Vector2(1500, 0)
	sim.refresh_visibility()
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var hidden_pixels := root.get_texture().get_image().get_data()
	pending.aim = Vector2(600, 200)
	pending.origin = Vector2(-300, 300)
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().get_data() == hidden_pixels, "Hidden charge geometry changes no visible pixels.")
	view.free()
	await native_controller()
	await native_research_details()

func click_point(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame

func native_controller() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://doctrines/native.json"
	check(state.start_new_run(1, 42), "Start actual native disruption run.")
	state.research_points = 1000
	state.credits = 10000
	state.reduced_motion = true
	for id in ["applied_energy", "disruption_i", "disruption_ii"]:
		check(state.purchase_research(id), "Unlock actual native control source.")
	check(state.purchase_ship(blueprint([ShipPart.Type.ION_EMITTER, ShipPart.Type.GRAVITIC_SNARE]), "Control"), "Build actual native control ship.")
	check(state.travel_to(state.get_reachable_nodes(state.current_node_id)[0]), "Freeze native control departure.")
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_physics_process(false)
	await process_frame
	var sim: BattleSimulation = battle.simulation
	for member in sim.players:
		member.position = Vector2.ZERO
	for index in range(sim.aliens.size()):
		sim.aliens[index].position = Vector2(180 + index * 25, 0)
	sim.refresh_visibility()
	battle.visuals.camera_zoom = 0.8
	battle.visuals.camera_position = Vector2(80, 0)
	battle._auto_camera_active = false
	var bar: Control = battle.ability_bar
	await process_frame
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(bar.get_global_rect()), "Actual three-action controller bar fits 640x360.")
	await click_point(bar.pause_aim.get_global_rect().get_center())
	await click_point(bar.action_buttons.ion_pulse.get_global_rect().get_center())
	check(bar.targeting and battle.pause_button.button_pressed, "Pointer selects Ion Pulse and pauses aiming in the real controller.")
	await click_point(battle.visuals.world_transform() * sim.aliens[0].position)
	check(sim.abilities.remaining("ion_pulse") == 24 and state.ability_state.cooldowns.ion_pulse == 24,
		"Pointer cast validates and durably pays Ion Pulse through the production controller.")
	await click_point(bar.action_buttons.gravity_well.get_global_rect().get_center())
	await click_point(battle.visuals.world_transform() * sim.aliens[0].position)
	check(sim.abilities.remaining("gravity_well") == 30 and sim.abilities.movement_rate(sim.aliens[0]) == 0.65,
		"Pointer places the researched Gravity Well through the production controller.")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/doctrines/controller-640.png")
	battle.pause_button.button_pressed = true
	var before := sim.abilities.remaining("gravity_well")
	for frame in range(30):
		battle._physics_process(1.0 / 30)
	check(sim.abilities.remaining("gravity_well") == before, "Pause freezes the new control clocks.")
	battle.pause_button.button_pressed = false
	battle.fast_forward_button.button_pressed = true
	for frame in range(30 * 180):
		battle._physics_process(1.0 / 30)
		if sim.phase != BattleSimulation.Phase.COMBAT:
			break
	check(sim.phase == BattleSimulation.Phase.VICTORY, "The actual mixed disruption fleet wins at 2x.")
	for frame in range(60):
		battle._physics_process(1.0 / 30)
	check(not state.battle_pending and state.load_run_checkpoint(), "New controls settle and reload through the real controller.")
	battle.free()
	current_scene = null

func native_research_details() -> void:
	var map: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	map.panel_tabs.current_tab = 2
	await process_frame
	await process_frame
	var view: Control = map.panel_tabs.get_node("Upgrades").grouped_view
	for id in ["optics_i", "optics_ii", "renewal_ii"]:
		view.state_override = {"research_ids": ["foundation", "applied_energy", "field_engineering", "optics_i", "renewal_i"],
			"story_flags": {}, "branch_choices": {"energy": "optics", "survival": "renewal"}, "research_points": 0}
		view.refresh()
		view.tree_canvas.camera_position = view.tree_canvas.positions[id] + view.tree_canvas.CARD_SIZE * 0.5
		view.tree_canvas._update_camera()
		await process_frame
		await click_point(view.card_buttons[id].get_global_rect().get_center())
		check(view.selected_id == id and (view.focus_button == null or map.research_details.get_global_rect().encloses(view.focus_button.get_global_rect())),
			"New branch details and focus control fit at 640x360: %s." % id)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/doctrines/%s-details-640.png" % id)
	map.free()
	current_scene = null
