extends SceneTree

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
	ship.mounts[key] = {"uid": str(ship.mounts.size() + 1), "equipment_id": id, "rank": 1, "hp": item.hit_points}
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
	ship.units[second].hp = 0
	check(ship.weapon_cycle_rate() == 1.2, "Losing one magazine removes only its contribution")
	ship.units[first].hp = 0
	check(ship.weapon_cycle_rate() == 1.0, "Destroyed magazines grant no benefit")
	var bay_ship := hull()
	install(bay_ship, "flight_deck")
	install(bay_ship, "ammunition_magazine")
	install(bay_ship, "ammunition_magazine")
	var sim := setup(bay_ship)
	sim.doctrines.carriers.advance(sim, 0.01)
	sim.doctrines.carriers.advance(sim, 2.9)
	check(sim.doctrines.carriers.sorties.size() == 2, "Stacked magazines accelerate bay launch cycling too")
	check(sim.doctrines.carriers.reserves["1"].spent == 2, "Launch acceleration still spends finite replacements")

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
	ship.units[first].hp = 0
	ship.units[-1].hp = 0
	sim.player.cooldowns[0] = 99
	sim.doctrines._synchronize(sim, sim.player, 60)
	check(sim.player.cooldowns[0] == 99, "Computer source loss removes synchronization")

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
	ship.units[uplink].hp = 0
	check(sim._analysis_multiplier(sim.player, target) == 1.05, "Uplink destruction ends the mark immediately")
	ship.units[uplink].hp = 25
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
	check(sim.player.stats.weapons[0].range_units == 500 and sim.player.cooldowns[0] == 6, "Railgun retains its slow long-range cycle")

func transactions() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://intermediates.json"
	check(state.start_new_run(1, 642), "Start research/purchase checks")
	var base: Dictionary = state.hangar_snapshot()
	for id in ["ammunition_magazine", "railgun", "command_uplink", "tactical_computer"]:
		check(not state.buy_equipment(id) and state.hangar_snapshot() == base, "New equipment remains research-gated")
	var fixture := base.duplicate(true)
	fixture.credits = 5000
	fixture.research.research_ids.append_array(["guided_munitions", "siege_i", "siege_ii", "command_i", "command_ii"])
	fixture.research.branch_choices["force_projection"] = "siege"
	fixture.research.branch_choices["fleet_operations"] = "command"
	check(state._commit_hangar(fixture), "Siege/command prerequisites and branch choices validate")
	check(not state.set_research_focus("carrier_i"), "Siege choice excludes carrier research")
	for id in ["ammunition_magazine", "railgun", "command_uplink", "tactical_computer"]:
		check(state.buy_equipment(id), "Researched intermediate is purchasable at the shipyard")
	check(state.load_run_checkpoint(), "New identities survive physical checkpoint reload")
	for id in ["ammunition_magazine", "railgun", "command_uplink", "tactical_computer"]:
		var item := SlotCatalog.find_equipment(id)
		check(SlotCatalog.chassis().any(func(chassis: Dictionary) -> bool: return chassis.slots.any(func(slot: Dictionary) -> bool: return SlotCatalog.compatible(slot, item))), "Each intermediate has a real exact-type/size mount")

func mount(ship: HangarShip, slot: String, id: String, uid: int) -> void:
	var item := SlotCatalog.find_equipment(id)
	var location: Dictionary = ship.chassis.slots.filter(func(row: Dictionary) -> bool: return row.id == slot)[0]
	check(SlotCatalog.compatible(location, item), "Campaign sample uses a real matching mount")
	ship.mounts[slot] = {"uid": str(uid), "equipment_id": id, "rank": 1, "hp": item.hit_points}
	ship.rebuild_units()

func campaign_samples() -> void:
	# Funded loadout fixtures, NOT a claim that these builds are naturally earned
	# at this row. Play all combats to actual outcomes, with fresh finite reserves.
	var state := root.get_node("GameState")
	var nodes: Array = state.campaign_dag.nodes.filter(func(node: Dictionary) -> bool: return node.act == 2 and node.kind == "combat")
	var results: Array = []
	for doctrine in ["siege", "carrier", "command"]:
		for index in range(2):
			var flagship := hull()
			mount(flagship, "port", "double_laser", 1)
			mount(flagship, "starboard", "double_laser", 2)
			mount(flagship, "aft_port", "point_defense_turret", 3)
			mount(flagship, "aft_starboard", "mini_turret", 4)
			mount(flagship, "inner_port", "armor_block", 5)
			mount(flagship, "fore", "tactical_computer", 6)
			mount(flagship, "inner_starboard", "ammunition_magazine" if doctrine == "siege" else "command_uplink", 7)
			var escort := HangarShip.new()
			escort.initialize_chassis("corsair", 2)
			mount(escort, "fore", "railgun" if doctrine == "siege" else ("torpedo_bomber_bay" if doctrine == "carrier" else "beam_lance"), 8)
			mount(escort, "port", "flight_deck" if doctrine == "carrier" else "double_laser", 9)
			mount(escort, "starboard", "double_laser", 10)
			mount(escort, "center", "ammunition_magazine" if doctrine != "command" else "command_uplink", 11)
			var encounter: Dictionary = state.get_frozen_encounter(int(nodes[index].id))
			var enemies: Array[RefCounted] = []
			for entry: Dictionary in encounter.roster:
				enemies.append(AlienShip.from_snapshot(entry))
			var ships: Array[FleetShip] = [flagship, escort]
			var sim := BattleSimulation.new()
			check(sim.setup_owned(ships, enemies, 0, 0, int(encounter.seed), {"credits_only": true,
				"enemy_roles": true, "encounter_plan": encounter if encounter.has("arena_layout") else {}}), "Act II doctrine setup")
			check(sim.set_objective_targets(EncounterGenerator.objective_ids(encounter)), "Use actual campaign objective identities")
			for tick in range(3600):
				sim.advance(1.0 / 30)
				if sim.phase != BattleSimulation.Phase.COMBAT:
					break
			check(sim.phase != BattleSimulation.Phase.COMBAT, "Act II doctrine combat reaches a bounded natural outcome")
			check(sim.player.damage_dealt > 0, "Intermediate loadout contributes actual combat damage")
			check(CombatDoctrines.valid_pool(sim.doctrines.pool), "Natural combat conserves valid finite reserves")
			results.append({"doctrine": doctrine, "node": nodes[index].id, "phase": sim.phase,
				"seconds": sim.elapsed, "damage": sim.player.damage_dealt + sim.players[1].damage_dealt})
	print("INTERMEDIATE COMBAT SAMPLES ", JSON.stringify(results))
