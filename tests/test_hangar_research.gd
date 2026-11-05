extends SceneTree

const ShipLoadouts = preload("res://scripts/ship_loadouts.gd")

var state: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func run() -> void:
	state = root.get_node("GameState")
	var view_registry := HangarResearch.view_registry()
	for node: Dictionary in view_registry.research:
		if node.id != "foundation":
			check(not ResearchViewModel.description(view_registry, node.id).is_empty(),
				"Every visible research has a basic gameplay description: " + node.id)
			check(not ResearchViewModel.description(view_registry, node.id).contains("available from the start")
				and not ResearchViewModel.description(view_registry, node.id).contains("required to fit it"),
				"Research descriptions omit starting-access boilerplate: " + node.id)
			var description := ResearchViewModel.description(view_registry, node.id)
			check(description.length() <= 85 and not description.contains("\n")
				and not description.contains("This research") and not description.contains("Requires")
				and not description.contains("DPS") and not description.contains("RP/day"),
				"Every research uses a short gameplay sentence without progression or stat prose: " + node.id)
	check(not ResearchViewModel.description(view_registry, "guided_munitions").contains("Unlocks")
		and ResearchViewModel.description(view_registry, "carrier_ii").contains("Bomber Bay")
		and ResearchViewModel.description(view_registry, "laboratory_iii").contains("research")
		and ResearchViewModel.description(view_registry, "energy_manipulation").contains("sustained beams"),
		"Descriptions retain actual advanced unlocks and gameplay upgrades")
	state.run_save_path = "user://ranked-research.json"
	check(state.start_new_run(1, 42), "Start rank fixture")
	var bank: Dictionary = state.hangar_snapshot()
	state._allocate_research(bank.research, 2.5)
	check(state._commit_hangar(bank) and state.load_run_checkpoint() and state.research_points == 2.5,
		"Fractional unfocused RP persists across Continue")
	check(state.start_new_run(1, 42), "Restart ranked production fixture")
	# This explicit late-game fixture tests the public purchase/fitting API for
	# equipment that cannot be obtained at the starting port in a natural run.
	var fixture: Dictionary = state.hangar_snapshot()
	fixture.credits = 5000
	if not "laboratory_ii" in fixture.research.research_ids:
		fixture.research.research_ids.append("laboratory_ii")
	fixture.research.research_ids.append("laboratory_iii")
	fixture.research.story_flags["boss_i_defeated"] = true
	check(state._commit_hangar(fixture), "Late-game fixture validates")
	check(state.buy_ship("transport"), "Buy ship with L civic mount")
	var frigate_id: int = state.fleet[-1].id
	check(state.swap_part(frigate_id, "port", ""), "Clear preinstalled Large Plate for ranked fitting fixture")
	check(state.swap_part(frigate_id, "starboard", ""), "Isolate one ranked lab on each side")
	check(state.swap_part(state.fleet[1].id, "port", "") and state.swap_part(state.fleet[1].id, "starboard", ""),
		"Isolate production from the other starting Transport")
	var before_invalid: Dictionary = state.hangar_snapshot()
	check(not state.swap_part(frigate_id, "port", "research_lab@2") and state.hangar_snapshot() == before_invalid,
		"Removed L lab cannot be fitted and leaves state unchanged")
	check(state.swap_part(frigate_id, "hold", "research_lab@3"), "Fit exact XL lab")
	var lab_iii: String = state.owned_ship(frigate_id).mounts.hold.uid
	var science := ScienceRules.snapshot(state.get_deployed_fleet())
	check(science.labs.size() == 2 and science.production_version == 2, "Physical snapshot identifies both lab sizes")
	check(is_equal_approx(ScienceRules.production_rate(science), 5.6), "M and XL labs produce 5.6 RP/day with Research Methods II")
	check(is_equal_approx(ScienceRules.journey_rp(science, 2), 11.2) and is_equal_approx(ScienceRules.journey_rp(science, 4), 22.4), "Both lab sizes multiply by travel days")
	check(ScienceRules.production_label(science) == "1 x Lab (M)\n1 x Lab (XL)", "Production panel names both lab sizes")
	check(ResearchViewModel.description(HangarResearch.view_registry(), "laboratory_ii").contains("20%"), "Research Methods I details match simulation")
	check(ResearchViewModel.description(HangarResearch.view_registry(), "laboratory_iii").contains("40%"), "Research Methods II details match simulation")
	check(ScienceRules.production_rate({"labs": [{"rank": 3}]}) == 1.0, "Historical snapshots retain their prior lab rate")
	check(state.load_run_checkpoint(), "Ranked equipment survives reload")
	check(is_equal_approx(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())), 5.6), "Reload retains ranked production")
	check(state.swap_part(frigate_id, "hold", ""), "Remove Lab (XL)")
	check(is_equal_approx(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())), 1.4), "Removed labs do not produce research")
	check(state.swap_part(frigate_id, "hold", "research_lab@3"), "Refit Lab (XL)")
	lab_iii = state.owned_ship(frigate_id).mounts.hold.uid
	var lead: HangarShip = state.owned_ship(frigate_id)
	var laboratories := lead.mounts.duplicate(true)
	lead.damage_cell(Vector2i(lead.units.size() - 1, 0), lead.hull_hp * 0.75)
	check(is_equal_approx(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())), 5.6)
		and lead.mounts == laboratories, "Substantial hull damage does not interrupt or replace ranked labs")
	check(state.save_run_checkpoint() and state.load_run_checkpoint(), "Damaged operational labs persist")
	check(is_equal_approx(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())), 5.6)
		and SaveValidation.same(state.owned_ship(frigate_id).mounts, laboratories), "Reload preserves ranked lab identities and operation")
	check(state.repair_ship(state.owned_ship(frigate_id)), "Repair lab host hull")
	check(is_equal_approx(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())), 5.6), "Hull repair does not change ranked production")
	var target: int = state.get_reachable_nodes(0)[0]
	var days: float = state.research_travel_time(0, target)
	check(state.travel_to(target), "Ranked research journey departs")
	check(is_equal_approx(state.journey_rp, days * 5.6), "Departure freezes ranked yield")
	var frozen: float = state.journey_rp
	check(state.load_run_checkpoint() and is_equal_approx(state.journey_rp, frozen), "Pending journey retains frozen yield on Continue")
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, state.battle_simulation_seed(), state.battle_support_context()), "Ranked-lab battle setup")
	sim.battle_id = state.battle_identity()
	var before_progress: float = state.research_points
	var expected_progress: float = before_progress + frozen
	for tick in range(90):
		sim.advance(1.0 / 30)
	check(is_equal_approx(state.research_points, before_progress), "Battle duration generates no research")
	lead = state.owned_ship(frigate_id)
	lead.damage_cell(Vector2i(0, 0), lead.hull_hp)
	check(is_equal_approx(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())), 5.6), "Zero-hull living lab host still produces all ranked research")
	lead.damage_cell(Vector2i(-1, 0), 0.01)
	check(is_equal_approx(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())), 1.4), "Only destroyed lab host stops production; flagship lab stays active")
	sim.phase = BattleSimulation.Phase.VICTORY
	check(state.settle_battle(sim), "Arrival settles research after battle losses")
	check(not state.equipment_inventory.has(lab_iii)
		and state.owned_ship(frigate_id) == null, "Settlement removes destroyed host and its unique labs")
	check(is_equal_approx(state.research_points, expected_progress), "Arrival banks the frozen journey research without auto-granting an upgrade")
	check(state.hangar_snapshot().research.research_points >= 0, "New checkpoints store unspent research")
	check(not state.settle_battle(sim), "Frozen research cannot settle twice")
	# Schema 2 pending saves store a numeric yield, not a recomputed rate.
	check(state.start_new_run(1, 1357), "Historical yield fixture")
	check(state.travel_to(state.get_reachable_nodes(0)[0]), "Historical yield departure")
	var saved: Dictionary = state.hangar_snapshot()
	saved.journey_rp = 1.5
	saved.research["research_points"] = 6.5
	check(state._commit_hangar(saved) and state.load_run_checkpoint() and state.journey_rp == 1.5, "Schema 2 pending yields reload without reinterpretation")
	check(state.research_points == 6.5, "Legacy unspent research points are preserved on load")
	saved = state.hangar_snapshot()
	saved.research.erase("research_points")
	check(not HangarCheckpoint.valid(saved), "Research bank is required in current checkpoints")
	for invalid: Variant in [-1, NAN, INF, "3", null]:
		var broken: Dictionary = state.hangar_snapshot()
		broken.research.research_points = invalid
		check(not HangarCheckpoint.valid(broken), "Malformed RP balances are rejected before mutation")
	# An undefined old ability must not remain a purchasable, lootable stub.
	check(state.start_new_run(1, 907), "Deferred purchase fixture")
	fixture = state.hangar_snapshot()
	fixture.credits = 5000
	fixture.research.story_flags["boss_i_defeated"] = true
	fixture.research.research_ids.append("applied_energy")
	fixture.research.research_ids.append("disruption_i")
	fixture.research.research_ids.append("bastion_ii")
	fixture.research.branch_choices["energy"] = "disruption"
	fixture.research.branch_choices["survival"] = "bastion"
	check(state._commit_hangar(fixture), "Previously earned disruption prerequisite remains valid")
	check(not state.choose_research("disruption_ii"), "Inactive ability cannot be chosen")
	fixture.research.research_ids.append("disruption_ii")
	check(state._commit_hangar(fixture), "Previously earned deferred research remains readable")
	check(not ShipLoadouts.obtainable(SlotCatalog.find_equipment("gravitic_snare")), "Inactive ability cannot be fitted")
	for node in range(state.campaign_dag.nodes.size()):
		check(state.equipment_loot(node).get("id") != "gravitic_snare", "Loot never awards inactive equipment")
	check(not HangarResearch.view_registry().research.any(func(node: Dictionary) -> bool: return node.id == "disruption_ii"), "Inactive research omitted from active tree")
	# Already-owned inactive equipment can be inspected, removed and sold; it
	# cannot silently become deployable or be duplicated by fitting another copy.
	check(state.buy_ship("corsair", "guardian"), "Legacy deferred equipment host")
	var host_id: int = state.fleet[-1].id
	fixture = state.hangar_snapshot()
	var uid := str(fixture.next_equipment_id)
	fixture.next_equipment_id += 1
	fixture.equipment[uid] = {"uid": uid, "equipment_id": "gravitic_snare", "rank": 1}
	fixture.equipment.erase(fixture.ships[-1].mounts["fore"])
	fixture.ships[-1].mounts["fore"] = uid
	fixture.ships[-1].hull_hp = 1
	HangarSquadrons.update_override(fixture, host_id)
	check(state._commit_hangar(fixture) and state.load_run_checkpoint(), "Legacy inactive item remains readable")
	check(state.deployment_error() == "Unequip deferred equipment", "Inactive loadout cannot depart")
	check(state.fit_equipment(host_id, "fore", "") and not state.equipment_inventory.has(uid), "Legacy inactive item can be removed (and is scrapped)")
	print("HANGAR RESEARCH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
