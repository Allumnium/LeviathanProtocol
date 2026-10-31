extends SceneTree

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
	state.run_save_path = "user://ranked-research.json"
	check(state.start_new_run(1, 42), "Start rank fixture")
	# This explicit late-game fixture tests the public purchase/fitting API for
	# equipment that cannot be obtained at the starting port in a natural run.
	var fixture: Dictionary = state.hangar_snapshot()
	fixture.credits = 5000
	fixture.research.research_ids.append("laboratory_ii")
	fixture.research.research_ids.append("laboratory_iii")
	fixture.research.story_flags["boss_i_defeated"] = true
	check(state._commit_hangar(fixture), "Late-game fixture validates")
	check(state.buy_chassis("frigate"), "Buy chassis with L civic mount")
	var frigate_id: int = state.fleet[-1].id
	check(state.buy_equipment("research_lab", 2), "Buy Lab II")
	var lab_ii := str(state.next_equipment_id - 1)
	check(state.fit_equipment(frigate_id, "center", lab_ii), "Fit exact L Lab II")
	check(state.buy_equipment("research_lab", 3), "Buy Lab III")
	var lab_iii := str(state.next_equipment_id - 1)
	check(state.fit_equipment(1, "hold", lab_iii), "Fit exact XL Lab III")
	var science := ScienceRules.snapshot(state.get_deployed_fleet())
	check(science.labs.size() == 3 and science.production_version == 2, "Physical snapshot identifies ranked production")
	check(ScienceRules.production_rate(science) == 6.5, "Lab I + II + III + baseline = 6.5 RP/day")
	check(ScienceRules.journey_rp(science, 2) == 13 and ScienceRules.journey_rp(science, 4) == 26, "Ranked labs multiply by travel days")
	check(ScienceRules.production_label(science) == "1 x Lab I\n1 x Lab II\n1 x Lab III", "Production panel explains lab mix")
	check(ResearchViewModel.effect_summary(HangarResearch.view_registry(), "laboratory_ii").contains("2 RP/day"), "Lab II research details match simulation")
	check(ResearchViewModel.effect_summary(HangarResearch.view_registry(), "laboratory_iii").contains("3 RP/day"), "Lab III research details match simulation")
	check(ScienceRules.production_rate({"labs": [{"rank": 3}]}) == 1.5, "Historical snapshots retain their prior rate")
	check(state.load_run_checkpoint(), "Ranked equipment survives reload")
	check(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())) == 6.5, "Reload retains ranked production")
	check(state.fit_equipment(frigate_id, "center", ""), "Unequip Lab II")
	check(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())) == 4.5, "Stock labs do not produce research")
	check(state.fit_equipment(frigate_id, "center", lab_ii), "Refit Lab II")
	var lead: HangarShip = state.owned_ship(1)
	for unit in lead.units:
		if unit.key == "hold":
			unit.hp = 0
	lead.sync_equipment_health()
	check(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())) == 3.5, "Destroyed Lab III stops production")
	check(state.repair_ship(lead), "Repair destroyed lab")
	check(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())) == 6.5, "Repair restores ranked production")
	var target: int = state.get_reachable_nodes(0)[0]
	var days: float = state.research_travel_time(0, target)
	check(state.travel_to(target), "Ranked research journey departs")
	check(state.journey_rp == days * 6.5, "Departure freezes ranked yield")
	var frozen: float = state.journey_rp
	check(state.load_run_checkpoint() and state.journey_rp == frozen, "Pending journey retains frozen yield on Continue")
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, state.battle_simulation_seed(), state.battle_support_context()), "Ranked-lab battle setup")
	sim.battle_id = state.battle_identity()
	var before: float = state.research_points
	for tick in range(90):
		sim.advance(1.0 / 30)
	check(state.research_points == before, "Battle duration generates no research")
	for owned: HangarShip in state.fleet:
		for unit in owned.units:
			if unit.part.type == ShipPart.Type.RESEARCH_LAB:
				unit.hp = 0
		owned.sync_equipment_health()
	check(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())) == 0.5, "Lost labs leave baseline only")
	sim.phase = BattleSimulation.Phase.VICTORY
	check(state.settle_battle(sim) and state.research_points == before + frozen, "Arrival pays departure yield despite battle losses")
	check(not state.settle_battle(sim), "Frozen research cannot settle twice")
	# Old pending saves already store a numeric yield. Do not reinterpret it
	# retroactively after a production rule change.
	check(state.start_new_run(1, 1357), "Historical yield fixture")
	check(state.travel_to(state.get_reachable_nodes(0)[0]), "Historical yield departure")
	var saved: Dictionary = state.hangar_snapshot()
	saved.journey_rp = 1.5
	check(state._commit_hangar(saved) and state.load_run_checkpoint() and state.journey_rp == 1.5, "Older pending yields remain unchanged")
	# An undefined old ability must not remain a purchasable, lootable stub.
	check(state.start_new_run(1, 907), "Deferred purchase fixture")
	fixture = state.hangar_snapshot()
	fixture.credits = 5000
	fixture.research.story_flags["boss_i_defeated"] = true
	fixture.research.research_ids.append("applied_energy")
	fixture.research.research_ids.append("disruption_i")
	fixture.research.branch_choices["energy"] = "disruption"
	check(state._commit_hangar(fixture), "Previously earned disruption prerequisite remains valid")
	check(not state.set_research_focus("disruption_ii"), "No new research focus on inactive ability")
	fixture.research.research_ids.append("disruption_ii")
	check(state._commit_hangar(fixture), "Previously earned deferred research remains readable")
	check(not state.buy_equipment("gravitic_snare"), "Inactive ability cannot be purchased")
	for node in range(state.campaign_dag.nodes.size()):
		check(state.equipment_loot(node).get("id") != "gravitic_snare", "Loot never awards inactive equipment")
	check(not HangarResearch.view_registry().research.any(func(node: Dictionary) -> bool: return node.id == "disruption_ii"), "Inactive research omitted from active tree")
	# Already-owned inactive equipment can be inspected, removed and sold; it
	# cannot silently become deployable or be duplicated by fitting another copy.
	check(state.buy_chassis("corsair"), "Legacy deferred equipment host")
	var host_id: int = state.fleet[-1].id
	fixture = state.hangar_snapshot()
	var uid := str(fixture.next_equipment_id)
	fixture.next_equipment_id += 1
	fixture.equipment[uid] = {"uid": uid, "equipment_id": "gravitic_snare", "rank": 1, "hp": 40.0}
	fixture.ships[-1].mounts["fore"] = uid
	check(state._commit_hangar(fixture) and state.load_run_checkpoint(), "Legacy inactive item remains readable")
	check(state.deployment_error() == "Unequip deferred equipment", "Inactive loadout cannot depart")
	check(state.fit_equipment(host_id, "fore", ""), "Legacy inactive item can be removed")
	check(state.sell_equipment(uid), "Legacy inactive item can be sold")
	print("HANGAR RESEARCH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
