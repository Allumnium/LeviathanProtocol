extends SceneTree

var checks := 0
var failures := 0
var state: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func host(parts: Array, id := 1) -> HangarShip:
	var ship := HangarShip.new()
	ship.initialize_chassis("corsair", id, id == 1)
	for key: String in parts:
		var item := SlotCatalog.find_equipment(key)
		var slot := "fixture_%d" % ship.mounts.size()
		ship.chassis.slots.append({"id": slot, "type": item.type, "size": item.size, "rect": [240, 240, 32, 32]})
		ship.mounts[slot] = {"uid": "%d-%d" % [id, ship.mounts.size()], "equipment_id": key, "rank": 1}
	ship.rebuild_units()
	return ship

func battle(fleet: Array[FleetShip]) -> BattleSimulation:
	var stats := ShipStats.new()
	stats.integrity = 100000
	stats.weight = 10
	stats.collision_radius = 12
	stats.weapons.append(ShipWeaponStats.new("Target", 100, 0.01, 1, 1))
	var enemy := AlienShip.new("Target", AlienShip.SCOUT_TEXTURE, stats)
	var sim := BattleSimulation.new()
	check(sim.setup_owned(fleet, [enemy], 0, 0, 123, {"credits_only": true, "missiles": 30}), "Initialize focused firing sample")
	for member in sim.players + sim.aliens:
		member.speed = 0
		member.acceleration = 0
		member.heading = 0
	for index in range(sim.players.size()):
		sim.players[index].position = Vector2(0, index * 10)
	sim.aliens[0].position = Vector2(150, 0)
	return sim

func sample(key: String, distance: float, moving := false) -> float:
	var sim := battle([host([key])])
	for tick in range(360):
		var delta := 1.0 / 30
		sim.elapsed += delta
		sim.aliens[0].position = Vector2(distance, sin(sim.elapsed * 2) * 60 if moving else 0)
		sim._update_ship(sim.player, delta)
		sim._update_projectiles(delta)
	check(sim.missile_supply == 30, "Kinetic/laser shots do not spend missiles")
	print("EXPANSION FIRING: %s distance=%s moving=%s damage=%.3f" % [key, distance, moving, sim.player.damage_dealt])
	return sim.player.damage_dealt

func trade() -> void:
	check(state.start_new_run(1, 52), "New trade fixture")
	var drone: HangarShip = state.fleet.filter(func(s: HangarShip) -> bool: return s.chassis_id == "drone")[0]
	var transport: HangarShip = state.fleet.filter(func(s: HangarShip) -> bool: return s.chassis_id == "transport")[0]
	var drone_id := drone.id
	var transport_id := transport.id
	state.credits = 0
	check(state.refit_ship(drone_id, "courier") and state.refit_ship(transport_id, "passenger_liner"), "New complete fits remain free at zero credits")
	drone = state.owned_ship(drone_id)
	transport = state.owned_ship(transport_id)
	check(drone.hangar_summary().cargo == 4 and transport.hangar_summary().passengers == 12, "Ship summaries use metadata capacities")
	var before: Dictionary = state.hangar_snapshot()
	var group := HangarSquadrons.for_ship(state.squadrons, drone_id)
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-equipment.json"
	check(not state.refit_squadron(int(group.id), "courier", true) and state.hangar_snapshot() == before, "Failed group refit is atomic")
	state.run_save_path = path
	check(state.depart_expedition("refuel_station_1", true), "Load civilian variants on departure")
	var data: Dictionary = state.hangar_snapshot()
	var totals := HangarTrade.summary(data)
	check(totals.cargo == 4 and totals.passengers == 12, "Variants board exactly their capacities")
	for uid: String in data.equipment:
		check(HangarTrade.valid(data.equipment[uid]), "Validate owned load " + uid)
	var pod_uid: String = state.owned_ship(drone_id).mounts.center.uid
	var berth_uid: String = state.owned_ship(transport_id).mounts.hold.uid
	var invalid: Dictionary = data.equipment[pod_uid].duplicate(true)
	invalid.load.quantity = 5
	check(not HangarTrade.valid(invalid), "Reject cargo over-capacity")
	check(state.load_run_checkpoint() and state.owned_ship(drone_id).mounts.center.uid == pod_uid \
		and state.owned_ship(transport_id).mounts.hold.uid == berth_uid, "Continue retains loads on their equipment UIDs")
	var origin := {"id": 0, "inhabited": true, "goods_unit_value": 3}
	var dest := {"id": 1, "inhabited": true, "goods_unit_value": 6}
	var unchanged: Dictionary = data.duplicate(true)
	HangarTrade.arrive(data, origin, 0)
	check(data == unchanged, "Returning to origin never pays out")
	for ship: Dictionary in data.ships:
		if int(ship.id) in [drone_id, transport_id]:
			ship.hull_hp = 0
	HangarTrade.arrive(data, dest, 1)
	check(data.credits == 108 and HangarTrade.summary(data).cargo == 0 and HangarTrade.summary(data).passengers == 0, "Zero-hull living hosts deliver four goods and twelve passengers once")
	HangarTrade.arrive(data, dest, 1)
	check(data.credits == 108, "Second arrival cannot duplicate income")
	var lost: Dictionary = unchanged.duplicate(true)
	HangarTrade.settle_losses(lost, [transport_id])
	check(lost.credits == -240 and not HangarTrade.has_load(lost.equipment[berth_uid]), "Berth casualties charge existing fee and can create debt")
	HangarTrade.settle_losses(lost, [transport_id])
	check(lost.credits == -240, "Casualty fee paid once")
	var empty: Dictionary = data.duplicate(true)
	HangarTrade.depart(empty, {"id": 1, "inhabited": false, "goods_unit_value": 6}, dest)
	check(HangarTrade.summary(empty).passengers == 0 and HangarTrade.summary(empty).cargo == 0, "Abandoned ports cannot board either load kind")
	# Return to the starting yard with the actual occupied loads, without simulating a route.
	var docked: Dictionary = state.hangar_snapshot()
	docked.expedition.position_nu = [0, 0]
	docked.expedition.docked_location_id = "start_station"
	docked.expedition.destination_location_id = ""
	docked.expedition.travel_state = ExpeditionState.TravelState.DOCKED
	check(state._commit_hangar(docked), "Dock occupied-load fixture")
	check(state.expedition_simulation.restore(docked.expedition) and state.can_use_shipyard(), "Occupied-load test has real shipyard access")
	before = state.hangar_snapshot()
	check(not state.refit_ship(drone_id, "gun_drone") and state.hangar_snapshot() == before and state.last_save_error == "Deliver passengers/cargo first", "Occupied pod prevents replacement")
	check(not state.refit_ship(transport_id, "freighter") and state.hangar_snapshot() == before and state.last_save_error == "Deliver passengers/cargo first", "Occupied berth prevents replacement")

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://expansion-equipment.json"
	if "--trade-only" in OS.get_cmdline_user_args():
		trade()
		print("EXPANSION TRADE: %d checks, %d failures; COMPLETE" % [checks, failures])
		quit(0 if failures == 0 else 1)
		return
	check(GameDefinitions.validate(GameDefinitions.snapshot()).is_empty(), "Definitions validate")
	check(SlotCatalog.equipment().size() > 0, "Equipment catalog validates")
	var count := 0
	var mounted := {}
	for chassis: String in preload("res://scripts/ship_loadouts.gd").all():
		var fits := preload("res://scripts/ship_loadouts.gd").for_chassis(chassis)
		check(fits.size() == 4, "Four complete legal presets for " + chassis)
		count += fits.size()
		for fit: Dictionary in fits:
			for key: String in fit.mounts.values():
				mounted[key] = true
	check(count == 36, "36 active complete presets")
	for key in ["autocannon", "light_shield", "cargo_pod", "passenger_berth", "ion_emitter", "beam_lance", "ammunition_magazine", "tactical_computer"]:
		check(mounted.has(key), "Equipment reachable through a complete fit: " + key)
	check(not preload("res://scripts/ship_loadouts.gd").available(preload("res://scripts/ship_loadouts.gd").find("corsair", "lance_raider"), ["foundation"]), "Beam Lance fit retains research gate")
	var kinetic := sample("autocannon", 150)
	var laser := sample("double_laser", 150)
	check(kinetic > laser, "Close stationary sample realizes autocannon advantage")
	check(sample("autocannon", 600) == 0 and sample("double_laser", 600) > 0, "Autocannon trades away laser reach")
	check(sample("autocannon", 150, true) > 0 and sample("double_laser", 150, true) > 0, "Both moving-target samples produce impacts")
	var weapon := SlotCatalog.stats_for("autocannon").weapons[0]
	ResearchUpgrades.apply_weapon(weapon, ResearchRules.resolve(["foundation", "applied_energy", "guided_munitions"], HangarResearch.catalog()).modifiers)
	check(weapon.damage_per_shot == 4 and weapon.range_units == 480 and weapon.research_capabilities.is_empty(), "Autocannon never inherits energy/missile research")
	var sim := battle([host(["mini_turret", "light_shield"]), host(["shield_relay"], 2)])
	sim.player.shields = 0
	sim.player.since_damage = 4
	sim._update_ship(sim.player, 1, false)
	check(is_equal_approx(sim.player.shields, 0.24), "Light Shield uses normal 4-percent recharge")
	sim.research_combat.configure({"pulse_shields": true})
	sim.research_combat.begin_step(sim, 8)
	check(is_equal_approx(sim.player.shields, 1.74), "Light Shield receives Bastion pulse")
	var total: float = sim.player.shields + sim.players[1].shields
	sim.doctrines._relay(sim, sim.players[1], 1)
	check(sim.player.shields > 1.74 and is_equal_approx(sim.player.shields + sim.players[1].shields, total), "Light Shield can receive conserved relay shields")
	trade()
	print("EXPANSION EQUIPMENT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
