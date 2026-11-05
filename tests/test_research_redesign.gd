extends SceneTree
const ShipLoadouts = preload("res://scripts/ship_loadouts.gd")

var state: Node
var checks := 0
var failures := 0
var serial := 100

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func mods(ids: Array) -> Dictionary:
	return ResearchRules.resolve(["foundation"] + ids, HangarResearch.catalog()).modifiers

func ship(parts: Dictionary, ids: Array = [], chassis := "flagship_basic") -> HangarShip:
	serial += 1
	var result := HangarShip.new()
	check(result.initialize_chassis(chassis, serial, true), "Initialize physical research fixture")
	for slot: String in parts:
		result.mounts[slot] = {"uid": str(serial * 10 + result.mounts.size()), "equipment_id": parts[slot], "rank": 1}
	result.rebuild_units()
	result.hull_hp = result.hull_max
	result.research_modifiers = mods(ids)
	return result

func simulation(owned: HangarShip) -> BattleSimulation:
	var stats := ShipStats.new()
	stats.integrity = 10000
	stats.weight = 10
	stats.weapons.append(ShipWeaponStats.new("Target", 100, 0.01, 1, 1))
	var aliens: Array[RefCounted] = [AlienShip.new("Research target", AlienShip.SCOUT_TEXTURE, stats)]
	var fleet: Array[FleetShip] = [owned]
	var sim := BattleSimulation.new()
	check(sim.setup_owned(fleet, aliens, 0, 0, 81, {"credits_only": true}), "Configure research battle")
	sim.player.position = Vector2.ZERO
	sim.aliens[0].position = Vector2(150, 0)
	return sim

func weapons() -> void:
	var base := ship({"fore": "laser", "port": "double_laser", "spine": "beam_lance"})
	var improved := ship({"fore": "laser", "port": "double_laser", "spine": "beam_lance"}, ["applied_energy", "optics_ii"])
	var before := base.get_stats()
	var after := improved.get_stats()
	for index in range(before.weapons.size()):
		check(is_equal_approx(after.weapons[index].damage_per_shot, before.weapons[index].damage_per_shot * 1.15),
			"Laser-family damage multiplier applies once")
		check(is_equal_approx(after.weapons[index].range_units, before.weapons[index].range_units * 1.2), "Laser-family range improves")
	var future := before.weapons[0].copy()
	future.weapon_name = "Future laser variant"
	ResearchUpgrades.apply_weapon(future, improved.research_modifiers)
	check(is_equal_approx(future.damage_per_shot, after.weapons[0].damage_per_shot), "Future named variant uses capability, not weapon name")
	check(future.copy().research_capabilities == future.research_capabilities, "Weapon copies retain capability metadata")
	var untagged := before.weapons[0].copy()
	untagged.research_capabilities.clear()
	ResearchUpgrades.apply_weapon(untagged, improved.research_modifiers)
	check(untagged.damage_per_shot == before.weapons[0].damage_per_shot, "Untagged weapons receive no unrelated family bonus")
	var part_stats := SlotCatalog.stats_for("laser")
	check(part_stats.copy().research_capabilities == part_stats.research_capabilities, "Part-stat copies preserve the shared capability predicate")
	var missiles := ship({"fore": "missile_rack"}, ["guided_munitions"])
	check(is_equal_approx(missiles.get_stats().weapons[0].range_units, 425), "Guided Munitions increases missile range by 25%")
	check(is_equal_approx(missiles.get_stats().weapons[0].damage_per_shot, 12), "Range research preserves missile damage and ammunition")
	var ranged := simulation(missiles)
	ranged.aliens[0].position = Vector2(380, 0)
	ranged._update_ship(ranged.player, 0.01)
	check(not ranged.projectiles.is_empty(), "Researched missiles actually fire beyond their old range")
	var ordinary := ship({"fore": "missile_rack"})
	var short_range := simulation(ordinary)
	short_range.aliens[0].position = Vector2(380, 0)
	short_range._update_ship(short_range.player, 0.01)
	check(short_range.projectiles.is_empty(), "Unresearched missiles retain the old firing range")
	var rails := ship({"fore": "railgun"}, ["siege_ii"])
	var sim := simulation(rails)
	var target := sim.aliens[0]
	target.shields = 100
	var hull := target.integrity
	sim._damage(target, 80, Vector2.ZERO, sim.player, "Railgun", true, false, 1, rails.get_stats().weapons[0].hull_damage_multiplier)
	check(target.shields == 20 and target.integrity == hull, "Rail hull bonus never increases shield damage")
	sim._damage(target, 40, Vector2.ZERO, sim.player, "Railgun", true, false, 1, rails.get_stats().weapons[0].hull_damage_multiplier)
	check(target.shields == 0 and is_equal_approx(target.integrity, hull - 24), "Rail multiplier applies only to damage reaching hull")
	var parent := BattleSimulation.Projectile.new()
	parent.source = sim.player
	parent.target = target
	parent.position = target.position - Vector2(50, 0)
	parent.damage = 10
	parent.splinter = true
	check(sim.research_combat.split(sim, parent) and sim.projectiles.size() == 3, "Splitting remains exactly three fragments")
	check(is_equal_approx(sim.projectiles[0].damage, 6), "Siege II boosts each half-damage fragment by 20%")
	var prismatic := ResearchCombat.new()
	prismatic.configure({"prismatic_lasers": true})
	check(prismatic.is_prismatic(sim.player, future), "Prismatic conversion follows declared capability")
	check(not prismatic.is_prismatic(sim.player, after.weapons[-1]), "Charged Beam Lance is excluded from continuous conversion")
	var emitter := ship({"fore": "ion_emitter"})
	sim = simulation(emitter)
	for unit: Dictionary in emitter.units:
		if "ion" in ResearchUpgrades.capabilities(unit.part):
			unit.part.definition_id = "future_ion_variant"
	check(sim.abilities.sources(sim, 0, "ion_pulse").has(sim.player), "Future ion capability is usable by the actual ability-source resolver")
	var unchanged := rails.get_stats().weapons[0].hull_damage_multiplier
	sim = simulation(rails)
	sim._refresh_owned_stats(sim.player)
	check(sim.player.stats.weapons[0].hull_damage_multiplier == unchanged, "Damage refresh does not multiply research a second time")

func support() -> void:
	var sim: BattleSimulation
	var command := ship({"spine": "command_uplink", "fore": "laser"}, ["command_i"])
	sim = simulation(command)
	sim.doctrines._mark(sim, sim.player, 0)
	check(is_equal_approx(sim.doctrines.mark_multiplier(sim, sim.player, sim.aliens[0]), 1.3), "Command I replaces mark benefit with 30% total")
	var computer := ship({"spine": "tactical_computer", "fore": "laser"}, ["command_ii"])
	sim = simulation(computer)
	sim.doctrines._synchronize(sim, sim.player, 9)
	check(is_equal_approx(sim.doctrines.synchronization[sim.player.entity_id], 11.25), "Command II fills synchronization 25% faster")
	sim.doctrines._synchronize(sim, sim.player, 0.6)
	check(is_zero_approx(sim.doctrines.synchronization[sim.player.entity_id]), "One computer triggers at 9.6 seconds")
	var repair := ship({"spine": "repair_drone_bay", "fore": "laser"}, ["renewal_i"])
	sim = simulation(repair)
	repair.hull_hp -= 10
	var before_hp := repair.hull_hp
	sim.doctrines._heal(sim, sim.player, 1)
	check(is_equal_approx(repair.hull_hp - before_hp, 2.5), "Renewal boosts shared hangar healing by 25%")
	check(is_equal_approx(state.self_repair_rate(repair), float(repair.chassis.self_repair_hp_per_second) * 1.25), "Renewal increases passive hull repair")

func access_and_offers() -> void:
	check(ResearchRules.validate_registry(GameDefinitions.snapshot()).is_empty(), "Definition registry validates approved modifiers and dependencies")
	var malformed := GameDefinitions.snapshot()
	malformed.research[1].equipment_capabilities_any = ["laser", "laser"]
	check(not GameDefinitions.validate(malformed).is_empty(), "Reject duplicate research capabilities")
	var registry := HangarResearch.view_registry()
	check(registry.research.size() == 19, "Eighteen meaningful cards remain plus Foundation")
	for node: Dictionary in registry.research:
		if node.id == "foundation":
			continue
		check(not node.grants.modifiers.is_empty() or not node.grants.ability_ids.is_empty(), "Every card grants an active modifier or ability: " + node.id)
		check(node.grants.equipment_ids.all(func(id: String) -> bool: return id in ["beam_lance"]),
			"Only Beam Lance remains a rare equipment unlock: " + node.id)
	check(ShipLoadouts.equipment_available(SlotCatalog.find_equipment("research_lab", 3), ["foundation"])
		and ShipLoadouts.equipment_available(SlotCatalog.find_equipment("tactical_computer"), ["foundation"]), "Lab (XL) and computer are ordinary purchases")
	check(not ShipLoadouts.equipment_available(SlotCatalog.find_equipment("beam_lance"), ["foundation"])
		and not ShipLoadouts.equipment_available(SlotCatalog.find_equipment("torpedo_bomber_bay"), ["foundation"]), "Beam Lance stays locked and retired Bomber Bay stays unavailable")
	state.run_save_path = "user://redesign.json"
	check(state.start_new_run(1, 7341), "Start matching-offer fixture")
	var deployed: Array[FleetShip] = state.get_deployed_fleet()
	check(not ResearchUpgrades.matches("carrier_i", deployed) and not ResearchUpgrades.matches("command_i", deployed),
		"Inventory-free starting fleet excludes irrelevant carrier/command cards")
	check(ResearchUpgrades.matches("laboratory_ii", deployed) and ResearchUpgrades.matches("renewal_i", deployed),
		"Existing labs and passive repair qualify useful cards")
	var data: Dictionary = state.hangar_snapshot()
	state._allocate_research(data.research, 20)
	check(state._commit_hangar(data), "Save funded relevant offer")
	check(state.research_offer.all(func(id: String) -> bool: return ResearchUpgrades.matches(id, state.get_deployed_fleet())),
		"All generated cards match actual deployed equipment")
	var offered: Array = state.research_offer.duplicate()
	check(state.load_run_checkpoint() and state.research_offer == offered, "Continue preserves relevant offer order")
	data = state.hangar_snapshot()
	data.research.research_offer = ["laboratory_ii"]
	check(state._commit_hangar(data), "Save explicit lab offer to isolate refitting boundary")
	for owned: HangarShip in state.fleet.duplicate():
		for slot: String in owned.mounts.keys():
			if owned.mounts[slot].equipment_id == "research_lab":
				check(state.swap_part(owned.id, slot, ""), "Remove last relevant lab without rerolling")
	var before: Dictionary = state.hangar_snapshot()
	check(not state.choose_research("laboratory_ii") and state.last_save_error.begins_with("Deploy")
		and SaveValidation.same(before, state.hangar_snapshot()), "Missing equipment rejects saved choice without reroll, RP debit or mutation")
	check(state.load_run_checkpoint() and state.research_offer == ["laboratory_ii"], "Stale-match saved card remains valid through Continue")
	var zero := ship({"spine": "research_lab"})
	var live: Array[FleetShip] = [zero]
	zero.hull_hp = 0
	check(ResearchUpgrades.matches("laboratory_ii", live), "Zero-hull living lab host qualifies")
	zero.hull_hp = -0.01
	check(not ResearchUpgrades.matches("laboratory_ii", live), "Destroyed host cannot qualify research")

func science() -> void:
	var owned := ship({"spine": "research_lab"}, [], "flagship_science")
	var fleet: Array[FleetShip] = [owned]
	var baseline := ScienceRules.production_rate(ScienceRules.snapshot(fleet))
	owned.research_modifiers = mods(["laboratory_ii"])
	check(is_equal_approx(ScienceRules.production_rate(ScienceRules.snapshot(fleet)), baseline * 1.2), "Science I multiplies existing labs and chassis bonus")
	owned.research_modifiers = mods(["laboratory_ii", "laboratory_iii"])
	check(is_equal_approx(ScienceRules.production_rate(ScienceRules.snapshot(fleet)), baseline * 1.4), "Science II replaces I with 40% total")
	check(HangarResearch.option_count(fleet) == 4, "Science output changes preserve fourth option")

func run() -> void:
	state = root.get_node("GameState")
	weapons()
	support()
	access_and_offers()
	science()
	print("RESEARCH REDESIGN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
