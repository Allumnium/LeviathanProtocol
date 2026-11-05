extends "res://tests/test_equipment_balance.gd"
const ShipLoadouts = preload("res://scripts/ship_loadouts.gd")

func hurt(sim: BattleSimulation, index: int, amount: float) -> void:
	var member := sim.players[index]
	member.owned_ship.hull_hp -= amount
	sim._refresh_owned_stats(member)

func run() -> void:
	for copies in [1, 2]:
		var parts: Array = ["repair_drone_bay"]
		if copies == 2:
			parts.append("repair_drone_bay")
		var sim := setup([owned(parts), owned([], 2)])
		hurt(sim, 0, 20)
		hurt(sim, 1, 20)
		var first: float = sim.player.owned_ship.hull_hp
		var second: float = sim.players[1].owned_ship.hull_hp
		var mounts: Dictionary = sim.players[1].owned_ship.mounts.duplicate(true)
		sim.doctrines.advance(sim, 1)
		check(is_equal_approx(sim.player.owned_ship.hull_hp - first, copies)
			and is_equal_approx(sim.players[1].owned_ship.hull_hp - second, copies), "Hangars add total output and share equally with self/allies")
		check(sim.living_combatant_count() == 3 and sim.doctrines.carriers.sorties.is_empty(), "Healing creates no combat craft")
		check(sim.players[1].owned_ship.mounts == mounts, "Healing does not recreate or replace equipment/load UIDs")
		sim.doctrines.advance(sim, 0)
		check(is_equal_approx(sim.player.owned_ship.hull_hp, first + copies), "Paused time produces no healing")
	var sim := setup([owned(["repair_drone_bay"]), owned([], 2), owned([], 3)])
	hurt(sim, 1, 0.1)
	hurt(sim, 2, 20)
	var before: float = sim.players[2].owned_ship.hull_hp
	sim.doctrines.advance(sim, 1)
	check(is_equal_approx(sim.players[1].owned_ship.hull_hp, sim.players[1].owned_ship.hull_max)
		and is_equal_approx(sim.players[2].owned_ship.hull_hp - before, 1.9), "Unused healing shares redistribute without exceeding the total rate")
	check(sim.player.owned_ship.hull_hp == sim.player.owned_ship.hull_max, "Healthy hosts do not consume healing")
	sim = setup([owned(["repair_drone_bay"], 1, ["renewal_i"]), owned([], 2)])
	hurt(sim, 1, 100)
	before = sim.players[1].owned_ship.hull_hp
	for tick in range(150):
		sim.doctrines.advance(sim, 0.1)
	check(is_equal_approx(sim.players[1].owned_ship.hull_hp - before, 37.5), "Renewal improves continuous healing to 2.5/s beyond the former 20-hull allowance")
	check(sim.doctrines.pool.repair_spent == 0 and sim.doctrines.pool.repair_capacity == 0, "Continuous healing neither draws nor replenishes finite reserves")
	sim.players[1].position = Vector2(220, 0)
	before = sim.players[1].owned_ship.hull_hp
	sim.doctrines.advance(sim, 1)
	check(is_equal_approx(sim.players[1].owned_ship.hull_hp - before, 2.5), "Healing includes the exact range boundary")
	sim.players[1].position = Vector2(220.01, 0)
	before = sim.players[1].owned_ship.hull_hp
	sim.doctrines.advance(sim, 1)
	check(sim.players[1].owned_ship.hull_hp == before and sim.doctrines.healing_links.is_empty(), "Out-of-range allies get no healing or particles")
	sim.players[1].position = Vector2(100, 0)
	sim.players[1].faction = BattleSimulation.Faction.ALIEN
	sim.doctrines.advance(sim, 1)
	check(sim.players[1].owned_ship.hull_hp == before, "Enemies never receive hangar healing")
	sim.players[1].faction = BattleSimulation.Faction.PLAYER
	sim.players[1].owned_ship.hull_hp = 0
	sim.doctrines.advance(sim, 1)
	check(is_equal_approx(sim.players[1].owned_ship.hull_hp, 2.5), "Zero hull remains alive and can heal")
	sim.players[1].owned_ship.hull_hp = -0.01
	sim.doctrines.advance(sim, 1)
	check(sim.players[1].owned_ship.hull_hp == -0.01, "Destroyed allies are never revived")
	sim.players[1].owned_ship.hull_hp = 20
	sim.player.owned_ship.hull_hp = -0.01
	sim.doctrines.advance(sim, 1)
	check(sim.players[1].owned_ship.hull_hp == 20, "Destroyed hangar host stops all healing")
	var state := root.get_node("GameState")
	state.run_save_path = "user://healing.json"
	check(state.start_new_run(1, 7341), "Start a current production run")
	check(SlotCatalog.find_equipment("repair_drone_bay").name == "Repair Drone Hangar", "Equipment has the requested name")
	check(SlotCatalog.equipment().all(func(item: Dictionary) -> bool: return item.id not in ["flight_deck", "torpedo_bomber_bay"]), "Both carrier modules are absent from the active catalog")
	check(HangarResearch.view_registry().research.all(func(node: Dictionary) -> bool: return node.id not in ["carrier_i", "carrier_ii"]), "Carrier research is removed from choices")
	check(HangarResearch.RESEARCH_ONLY_EQUIPMENT == ["beam_lance"], "Beam Lance is the remaining equipment unlock")
	for chassis: Dictionary in SlotCatalog.chassis():
		for fit: Dictionary in ShipLoadouts.for_chassis(chassis.id):
			check(not fit.mounts.values().any(func(key: String) -> bool: return key in ["flight_deck", "torpedo_bomber_bay"]), "Named fits contain no retired carrier modules")
	var drone := SlotCatalog.find_chassis("drone")
	check(drone.command_cost == 1 and drone.slots.all(func(slot: Dictionary) -> bool: return slot.type == "general"), "Drone retains its inexpensive flexible fleet role")
	check(state.swap_part(2, "port", "repair_drone_bay") and state.load_run_checkpoint()
		and state.owned_ship(2).mounts.port.equipment_id == "repair_drone_bay", "Repair Drone Hangar fits normally and survives Continue")
	print("HANGAR HEALING: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
