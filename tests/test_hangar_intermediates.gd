extends SceneTree

const ShipLoadouts = preload("res://scripts/ship_loadouts.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

# Physics fixtures add future matching mounts in memory, without editing player
# chassis/art or bypassing exact-size fitting in the actual transaction API.
func install(ship: HangarShip, id: String) -> int:
	var item := SlotCatalog.find_equipment(id)
	var key := "fixture_%d" % ship.mounts.size()
	ship.chassis.slots.append({"id": key, "type": item.type, "size": item.size, "rect": [80, 80, 32, 32]})
	ship.mounts[key] = {"uid": str(ship.mounts.size() + 1), "equipment_id": id, "rank": 1}
	ship.rebuild_units()
	return ship.units.size() - 1

func hull() -> HangarShip:
	var ship := HangarShip.new()
	ship.initialize_chassis("flagship_basic", 1, true)
	return ship

func enemy(role := "fighter") -> AlienShip:
	var stats := ShipStats.new()
	stats.integrity = 5000
	stats.weight = 10
	stats.weapons.append(ShipWeaponStats.new("Fixture pulse", 100, 0.01, 1, 1))
	var result := AlienShip.new("Fixture", AlienShip.SCOUT_TEXTURE, stats)
	result.role_id = role
	return result

func setup(ship: HangarShip) -> BattleSimulation:
	var sim := BattleSimulation.new()
	var ships: Array[FleetShip] = [ship]
	var enemies: Array[RefCounted] = [enemy(), enemy("sentinel")]
	check(sim.setup_owned(ships, enemies, 0, 0, 327, {"credits_only": true, "enemy_roles": true}), "Set up physical intermediate equipment")
	sim.player.position = Vector2.ZERO
	sim.aliens[0].position = Vector2(100, 0)
	sim.aliens[1].position = Vector2(180, 0)
	return sim

func run() -> void:
	magazines()
	computers()
	marks()
	railguns()
	hull_repairs()
	fighter_mechanics()
	transactions()
	campaign_samples()
	print("HANGAR INTERMEDIATES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func magazines() -> void:
	var ship := hull()
	for id in ["mini_turret", "double_laser", "missile_rack", "railgun", "point_defense_turret"]:
		install(ship, id)
	var base := ship.get_stats()
	var first := install(ship, "ammunition_magazine")
	var one := ship.get_stats()
	var second := install(ship, "ammunition_magazine")
	var two := ship.get_stats()
	check(ship.weapon_cycle_rate() == 1.4, "Two magazines add 40% cycling, without multiplicative stacking")
	for index in range(base.weapons.size()):
		check(is_equal_approx(one.weapons[index].fire_interval_seconds, base.weapons[index].fire_interval_seconds / 1.2), "Magazine supports every host weapon")
		check(is_equal_approx(two.weapons[index].fire_interval_seconds, base.weapons[index].fire_interval_seconds / 1.4), "Copies stack on every host weapon")
		check(two.weapons[index].damage_per_shot == base.weapons[index].damage_per_shot, "Magazine does not multiply damage as well")
	var identities := ship.mounts.duplicate(true)
	ship.damage_cell(Vector2i(second, 0), ship.hull_hp * 0.75)
	check(ship.weapon_cycle_rate() == 1.4 and ship.mounts == identities, "Substantial magazine hit leaves both unique magazines and cycling operational")
	ship.damage_cell(Vector2i(first, 0), ship.hull_hp + 1)
	check(ship.is_alive() and ship.weapon_cycle_rate() == 1.4, "Zero-hull ship retains both magazine contributions")

func computers() -> void:
	var ship := hull()
	install(ship, "double_laser")
	install(ship, "railgun")
	var first := install(ship, "tactical_computer")
	var sim := setup(ship)
	for index in range(sim.player.cooldowns.size()):
		sim.player.cooldowns[index] = 99
	sim.doctrines._synchronize(sim, sim.player, 6)
	check(sim.player.cooldowns[0] == 99, "One computer needs twelve seconds")
	sim.doctrines._synchronize(sim, sim.player, 6)
	check(sim.player.cooldowns.all(func(value: float) -> bool: return value == 0), "Synchronization includes all host weapons")
	install(ship, "tactical_computer")
	sim._refresh_owned_stats(sim.player)
	for index in range(sim.player.cooldowns.size()):
		sim.player.cooldowns[index] = 99
	sim.doctrines._synchronize(sim, sim.player, 6)
	check(sim.player.cooldowns.all(func(value: float) -> bool: return value == 0), "Two computers synchronize twice as often")
	sim.aliens[0].shields = 10
	sim.aliens[1].shields = 10
	sim.player.cooldowns[0] = 99
	sim.doctrines._synchronize(sim, sim.player, 12)
	check(sim.player.cooldowns[0] == 99, "Enemy shields counter the vulnerability-window salvo")
	sim.aliens[0].shields = 0
	sim.doctrines._synchronize(sim, sim.player, 0)
	check(sim.player.cooldowns[0] == 0, "Stored synchronization fires when a visible target becomes unshielded")
	var charge_key := "%s/%d" % [sim.player.entity_id, sim.player.stats.weapons[0].component_index]
	sim.doctrines.charges[charge_key] = {}
	sim.player.cooldowns[0] = 99
	sim.doctrines._synchronize(sim, sim.player, 6)
	check(sim.player.cooldowns[0] == 99, "Synchronization never restarts an in-progress beam charge")
	ship.damage_cell(Vector2i(first, 0), ship.hull_hp * 0.75)
	sim.doctrines.charges.clear()
	sim.player.cooldowns[0] = 99
	sim.doctrines._synchronize(sim, sim.player, 6)
	check(sim.player.cooldowns[0] == 0 and CombatDoctrines.operational(sim.player, ShipPart.Type.TACTICAL_COMPUTER).size() == 2, "Hull damage leaves both computers synchronizing")
	ship.damage_cell(Vector2i(-1, 0), ship.hull_hp + 1.01)
	sim.player.cooldowns[0] = 99
	sim.doctrines._synchronize(sim, sim.player, 60)
	check(sim.player.cooldowns[0] == 99, "Destroyed computer host removes synchronization")

func marks() -> void:
	var ship := hull()
	install(ship, "double_laser")
	var uplink := install(ship, "command_uplink")
	install(ship, "research_lab")
	var sim := setup(ship)
	sim.doctrines._mark(sim, sim.player, 0.01)
	check(sim.doctrines.marks.size() == 1, "Uplink marks an enemy automatically without a new modal or ability bar")
	var target: BattleSimulation.Combatant = sim.aliens[0]
	check(sim._analysis_multiplier(sim.player, target) == 1.2, "Marked target takes twenty percent more allied damage")
	sim.player.analysis_target_id = target.entity_id
	check(sim._analysis_multiplier(sim.player, target) == 1.2, "Research analysis and command mark use strongest effect")
	check(sim.doctrines.mark_multiplier(sim, target, sim.player) == 1.0, "Mark never buffs enemy attacks")
	ship.damage_cell(Vector2i(uplink, 0), ship.hull_hp * 0.75)
	check(sim._analysis_multiplier(sim.player, target) == 1.2, "Hull damage does not interrupt automatic command mark")
	sim.doctrines.marks.clear()
	sim.doctrines.mark_timers.clear()
	sim.aliens[0].position = Vector2(600, 0)
	sim.aliens[1].position = Vector2(800, 0)
	sim.doctrines._mark(sim, sim.player, 1)
	check(sim.doctrines.marks.is_empty(), "Uplink range is bounded")
	sim.aliens[0].position = Vector2(400, 0)
	sim.visibility_enabled = true
	sim.refresh_visibility()
	sim.doctrines._mark(sim, sim.player, 1)
	check(sim.doctrines.marks.is_empty(), "Uplink cannot reveal or mark a hidden enemy")
	ship.damage_cell(Vector2i(uplink, 0), ship.hull_hp + 1.01)
	check(sim._analysis_multiplier(sim.player, target) == 1.0, "Destroyed host supplies neither command mark nor lab analysis")

func railguns() -> void:
	var ship := hull()
	install(ship, "railgun")
	var sim := setup(ship)
	var target: BattleSimulation.Combatant = sim.aliens[0]
	var before := target.integrity
	sim._damage(target, 10, sim.player.position, sim.player, "Fixture projectile")
	check(is_equal_approx(before - target.integrity, 8), "Sentinel protects nearby hull from ordinary fire")
	before = target.integrity
	sim._damage(target, 10, sim.player.position, sim.player, "Railgun")
	check(is_equal_approx(before - target.integrity, 10), "Railgun penetrates Sentinel hull cover")
	target.shields = 20
	sim._damage(target, 10, sim.player.position, sim.player, "Railgun")
	check(is_equal_approx(target.shields, 12), "Shields retain Sentinel protection against railgun shots")
	sim._update_ship(sim.player, 0.01)
	check(sim.projectiles.size() == 1 and not sim.projectiles[0].interceptable, "Railgun projectile cannot be removed by missile interception")
	check(sim.player.stats.weapons[0].range_units == 1500 and sim.player.cooldowns[0] == 6, "Railgun retains its slow long-range cycle")

func transactions() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://intermediates.json"
	check(state.start_new_run(1, 642), "Start research/purchase checks")
	var base: Dictionary = state.hangar_snapshot()
	for id in ["ammunition_magazine", "railgun", "command_uplink", "tactical_computer"]:
		check(ShipLoadouts.obtainable(SlotCatalog.find_equipment(id))
			and ShipLoadouts.equipment_available(SlotCatalog.find_equipment(id), state.current_research_ids) == (id != "tactical_computer"),
			"Intermediate support starts available; Tactical Computer remains advanced")
	var fixture := base.duplicate(true)
	fixture.credits = 5000
	fixture.research.research_ids.append_array(["applied_energy", "guided_munitions", "siege_i", "siege_ii", "command_i", "command_ii"])
	fixture.research.branch_choices["force_projection"] = "siege"
	fixture.research.branch_choices["fleet_operations"] = "command"
	check(state._commit_hangar(fixture), "Siege/command prerequisites and branch choices validate")
	check(not state.choose_research("carrier_i"), "Retired carrier research cannot be chosen")
	check(state.buy_ship("corsair") and state.buy_ship("drone"), "Buy intermediate hosts")
	var drone_host: int = state.fleet[-1].id
	var corsair_host: int = state.fleet[-2].id
	if state.owned_ship(corsair_host).mounts.get("fore", {}).get("equipment_id", "") != "railgun":
		check(state.swap_part(corsair_host, "fore", "railgun"), "Fit a railgun")
	check(state.owned_ship(corsair_host).mounts.fore.equipment_id == "railgun" and state.swap_part(1, "spine", "ammunition_magazine")
			and state.swap_part(drone_host, "center", "command_uplink") and state.swap_part(2, "port", "tactical_computer"),
			"Intermediates are fitted at the shipyard")
	check(state.load_run_checkpoint(), "New identities survive physical checkpoint reload")
	for id in ["ammunition_magazine", "railgun", "command_uplink", "tactical_computer"]:
		var item := SlotCatalog.find_equipment(id)
		check(SlotCatalog.chassis().any(func(chassis: Dictionary) -> bool: return chassis.slots.any(func(slot: Dictionary) -> bool: return SlotCatalog.compatible(slot, item))), "Each intermediate has a real exact-type/size mount")

func fighter_mechanics() -> void:
	var flagship := hull()
	mount(flagship, "fore", "mini_turret", 1)
	var fighter := HangarShip.new()
	check(fighter.initialize_chassis("fighter", 2), "Initialize supplied fighter")
	mount(fighter, "fore", "mini_turret", 2)
	var base := SlotCatalog.stats_for("mini_turret").weapons[0].damage_per_shot
	check(fighter.get_stats().weapons[0].damage_per_shot == base * 1.3
		and fighter.chassis.dodge_chance == 0.2, "Fighter retains draft thirty-percent weapon damage and twenty-percent dodge")
	var identities := fighter.mounts.duplicate(true)
	fighter.damage_cell(Vector2i(1, 0), 75)
	var sim := BattleSimulation.new()
	var ships: Array[FleetShip] = [flagship, fighter]
	var enemies: Array[RefCounted] = [enemy()]
	check(sim.setup_owned(ships, enemies, 0, 0, 327, {"credits_only": true}), "Damaged fighter enters shared combat")
	var target: BattleSimulation.Combatant = sim.players[1]
	var expected := RandomNumberGenerator.new()
	var dodges := 0
	for seed_value in range(64):
		sim.random.seed = seed_value
		expected.seed = seed_value
		var dodged := expected.randf() < 0.2
		dodges += 1 if dodged else 0
		var before := fighter.hull_hp
		sim._damage(target, 0.1, sim.aliens[0].position, sim.aliens[0], "Fixture pulse", false, true)
		check(is_equal_approx(fighter.hull_hp, before if dodged else before - 0.1), "Damaged fighter retains deterministic weapon-hit dodge chance")
	check(dodges > 0 and dodges < 64 and fighter.mounts == identities
		and fighter.get_stats().weapons[0].damage_per_shot == base * 1.3, "Dodge and damage bonuses operate without changing fitted instances")
	var before := fighter.hull_hp
	sim._damage(target, 1, sim.aliens[0].position, sim.aliens[0], "Fixture collision")
	check(fighter.hull_hp == before - 1, "Fighter dodge does not evade bare-hull environmental damage")

func hull_repairs() -> void:
	var ship := hull()
	install(ship, "mini_turret")
	install(ship, "repair_drone_bay")
	var identities := ship.mounts.duplicate(true)
	var dps := ship.get_stats().dps
	var sim := setup(ship)
	sim._damage(sim.player, sim.player.shields + 100, sim.aliens[0].position, sim.aliens[0], "Fixture hit")
	var damaged := ship.hull_hp
	sim.doctrines._heal(sim, sim.player, 15)
	check(is_equal_approx(ship.hull_hp, damaged + 30) and sim.player.repaired_hp == 30, "Repair Drone Hangar continuously heals self beyond its former allowance")
	check(ship.mounts == identities and ship.get_stats().dps == dps, "Hull healing retains equipment identities and weapon output")
	# Station remains a compatibility fixture, not a newly enabled purchase.
	var station_ship := hull()
	install(station_ship, "mini_turret")
	var station := install(station_ship, "repair_station")
	var station_sim := setup(station_ship)
	var station_identity := station_ship.mounts.duplicate(true)
	station_ship.damage_cell(Vector2i(station, 0), 50)
	var station_hp := station_ship.hull_hp
	SharedSupport.repair(station_sim, 2)
	check(station_ship.hull_hp == station_hp + 4 and station_sim.repair_spent == 4, "Compatibility station heals hull at its existing two-point rate")
	SharedSupport.repair(station_sim, 60)
	check(station_ship.hull_hp == station_hp + 20 and station_sim.repair_spent == 20, "Station retains finite twenty-point allowance")
	SharedSupport.repair(station_sim, 60)
	check(station_ship.hull_hp == station_hp + 20 and station_ship.mounts == station_identity, "Spent station cannot refill or mutate equipment")
	station_ship.damage_cell(Vector2i(station, 0), station_ship.hull_hp + 2)
	var station_dead := station_ship.hull_hp
	SharedSupport.repair(station_sim, 60)
	check(station_ship.hull_hp == station_dead, "Station cannot resurrect a destroyed hull")

func mount(ship: HangarShip, slot: String, id: String, uid: int) -> void:
	var item := SlotCatalog.find_equipment(id)
	var location: Dictionary = ship.chassis.slots.filter(func(row: Dictionary) -> bool: return row.id == slot)[0]
	check(SlotCatalog.compatible(location, item), "Campaign sample uses a real matching mount")
	ship.mounts[slot] = {"uid": str(uid), "equipment_id": id, "rank": 1}
	ship.rebuild_units()

func campaign_samples() -> void:
	# Funded loadout fixtures, NOT a claim that these builds are naturally earned
	# at this row. Play all combats to actual outcomes, with fresh finite reserves.
	var state := root.get_node("GameState")
	var nodes: Array = state.campaign_dag.nodes.filter(func(node: Dictionary) -> bool: return node.act == 2 and node.kind == "combat")
	var results: Array = []
	for doctrine in ["siege", "repair", "command"]:
		for index in range(2):
			var flagship := hull()
			mount(flagship, "port", "laser", 1)
			mount(flagship, "starboard", "laser", 2)
			mount(flagship, "fore", "point_defense_turret", 3)
			mount(flagship, "aft_starboard", "thruster", 4)
			mount(flagship, "inner_port", "hull_plate", 5)
			mount(flagship, "aft_port", "hull_plate", 6)
			mount(flagship, "spine", "ammunition_magazine" if doctrine == "siege" else "command_uplink", 7)
			var escort := HangarShip.new()
			escort.initialize_chassis("corsair", 2)
			mount(escort, "fore", "railgun" if doctrine == "siege" else ("repair_drone_bay" if doctrine == "repair" else "beam_lance"), 8)
			mount(escort, "port", "double_laser", 9)
			mount(escort, "starboard", "double_laser", 10)
			var support := HangarShip.new()
			support.initialize_chassis("transport", 3)
			mount(support, "port", "tactical_computer", 11)
			mount(support, "starboard", "tactical_computer", 12)
			var encounter: Dictionary = state.get_frozen_encounter(int(nodes[index].id))
			var enemies: Array[RefCounted] = []
			for entry: Dictionary in encounter.roster:
				enemies.append(AlienShip.from_snapshot(entry))
			var ships: Array[FleetShip] = [flagship, escort, support]
			var sim := BattleSimulation.new()
			var context := {"credits_only": true,
				"enemy_roles": true, "encounter_plan": encounter if encounter.has("arena_layout") else {}}
			for key in ["asteroids", "environment"]:
				if encounter.has(key):
					context[key] = encounter[key].duplicate(true)
			check(sim.setup_owned(ships, enemies, 0, 0, int(encounter.seed), context), "Act II doctrine setup")
			check(sim.set_objective_targets(EncounterGenerator.objective_ids(encounter)), "Use actual campaign objective identities")
			for tick in range(3600):
				sim.advance(1.0 / 30)
				if sim.phase != BattleSimulation.Phase.COMBAT:
					break
			check(sim.phase != BattleSimulation.Phase.COMBAT, "Act II doctrine combat reaches a bounded natural outcome")
			check(sim.players[1].damage_dealt > 0, "Intermediate-equipped escort contributes actual combat damage")
			check(CombatDoctrines.valid_pool(sim.doctrines.pool), "Natural combat conserves valid finite reserves")
			results.append({"doctrine": doctrine, "node": nodes[index].id, "phase": sim.phase,
				"seconds": sim.elapsed, "damage": sim.player.damage_dealt + sim.players[1].damage_dealt})
	print("INTERMEDIATE COMBAT SAMPLES ", JSON.stringify(results))
