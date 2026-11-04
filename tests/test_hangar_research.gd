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
	check(ResearchViewModel.description(view_registry, "guided_munitions").contains("already available")
		and not ResearchViewModel.description(view_registry, "energy_manipulation").contains("does not"),
		"Descriptions distinguish existing equipment access from actual fleet upgrades")
	state.run_save_path = "user://ranked-research.json"
	check(state.start_new_run(1, 42), "Start rank fixture")
	var bank: Dictionary = state.hangar_snapshot()
	state._allocate_research(bank.research, 2.5)
	check(state._commit_hangar(bank) and state.load_run_checkpoint() and state.research_points == 2.5,
		"Fractional unfocused RP persists across Continue")
	var before_bank: Dictionary = state.hangar_snapshot()
	var save_path: String = state.run_save_path
	state.run_save_path = "res://project.godot/blocked-research.json"
	check(not state.set_research_focus("applied_energy") and state.hangar_snapshot() == before_bank,
		"Failed focus save leaves bank and project progress unchanged")
	state.run_save_path = save_path
	check(state.set_research_focus("applied_energy") and state.research_points == 0.5
		and state.research_progress.applied_energy == 2, "Setting focus spends only whole RP and retains fractional earnings")
	var fractional: Dictionary = state.hangar_snapshot().research
	state._allocate_research(fractional, 0.25)
	check(fractional.research_progress.applied_energy == 2 and fractional.research_points == 0.75,
		"Fractional earnings cannot purchase fractional project progress")
	state._allocate_research(fractional, 0.25)
	check(fractional.research_progress.applied_energy == 3 and fractional.research_points == 0,
		"Fractional earnings combine into the next spendable whole RP")
	fractional.research_progress.applied_energy = 3.5
	state._allocate_research(fractional, 0.25)
	check(fractional.research_progress.applied_energy == 3 and fractional.research_points == 0.75,
		"Historical fractional project progress returns to the bank without losing science")
	fractional.research_points = 0
	fractional.research_progress.applied_energy = 3.5
	state._allocate_research(fractional, 0)
	check(fractional.research_progress.applied_energy == 3 and fractional.research_points == 0.5,
		"Setting focus preserves legacy fractional progress even with an empty bank")
	check(ScienceRules.format_points(7.99) == "7" and ScienceRules.format_points(8) == "8",
		"Science displays only spendable integer RP, never rounded-up purchasing power")
	var completion_fixture: Dictionary = state.hangar_snapshot()
	completion_fixture.research.research_points = 100
	check(state._commit_hangar(completion_fixture), "Save focused completion fixture")
	state.research_completion_notices.clear()
	state.run_save_path = "res://project.godot/blocked-completion.json"
	check(not state.set_research_focus("applied_energy") and state.research_completion_notices.is_empty(),
		"Failed research completion cannot queue a success banner")
	state.run_save_path = save_path
	check(state.set_research_focus("applied_energy")
		and state.research_completion_notices == ["applied_energy"],
		"Bank-funded completion queues the exact upgrade only after committing")
	check(state.load_run_checkpoint() and state.research_completion_notices.is_empty(),
		"Continue does not replay historical completion banners")
	check(state.start_new_run(1, 42), "Restart rank fixture with empty bank")
	var overflow_progress: Dictionary = state.hangar_snapshot().research
	overflow_progress.research_focus = "applied_energy"
	var overflow_cost := float(ResearchFocusRules.cost("applied_energy", overflow_progress))
	state._allocate_research(overflow_progress, overflow_cost + 10)
	check("applied_energy" in overflow_progress.research_ids and overflow_progress.research_focus.is_empty()
		and overflow_progress.research_points == 10, "Excess output is banked when a project completes")
	# This explicit late-game fixture tests the public purchase/fitting API for
	# equipment that cannot be obtained at the starting port in a natural run.
	var fixture: Dictionary = state.hangar_snapshot()
	fixture.credits = 5000
	fixture.research.research_ids.append("laboratory_ii")
	fixture.research.research_ids.append("laboratory_iii")
	fixture.research.story_flags["boss_i_defeated"] = true
	check(state._commit_hangar(fixture), "Late-game fixture validates")
	check(state.buy_ship("transport"), "Buy ship with L civic mount")
	var frigate_id: int = state.fleet[-1].id
	check(state.swap_part(frigate_id, "port", "research_lab@2"), "Fit exact L Lab II")
	var lab_ii: String = state.owned_ship(frigate_id).mounts.port.uid
	check(state.swap_part(frigate_id, "hold", "research_lab@3"), "Fit exact XL Lab III")
	var lab_iii: String = state.owned_ship(frigate_id).mounts.hold.uid
	var science := ScienceRules.snapshot(state.get_deployed_fleet())
	check(science.labs.size() == 3 and science.production_version == 2, "Physical snapshot identifies ranked production")
	check(ScienceRules.production_rate(science) == 6.0, "Lab I + II + III = 6 RP/day")
	check(ScienceRules.journey_rp(science, 2) == 12 and ScienceRules.journey_rp(science, 4) == 24, "Ranked labs multiply by travel days")
	check(ScienceRules.production_label(science) == "1 x Lab I\n1 x Lab II\n1 x Lab III", "Production panel explains lab mix")
	check(ResearchViewModel.effect_summary(HangarResearch.view_registry(), "laboratory_ii").contains("2 RP/day"), "Lab II research details match simulation")
	check(ResearchViewModel.effect_summary(HangarResearch.view_registry(), "laboratory_iii").contains("3 RP/day"), "Lab III research details match simulation")
	check(ScienceRules.production_rate({"labs": [{"rank": 3}]}) == 1.0, "Historical snapshots retain their prior lab rate")
	check(state.load_run_checkpoint(), "Ranked equipment survives reload")
	check(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())) == 6.0, "Reload retains ranked production")
	check(state.swap_part(frigate_id, "port", ""), "Remove Lab II")
	check(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())) == 4.0, "Removed labs do not produce research")
	check(state.swap_part(frigate_id, "port", "research_lab@2"), "Refit Lab II")
	lab_ii = state.owned_ship(frigate_id).mounts.port.uid
	var lead: HangarShip = state.owned_ship(frigate_id)
	var laboratories := lead.mounts.duplicate(true)
	lead.damage_cell(Vector2i(lead.units.size() - 1, 0), lead.hull_hp * 0.75)
	check(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())) == 6.0
		and lead.mounts == laboratories, "Substantial hull damage does not interrupt or replace ranked labs")
	check(state.save_run_checkpoint() and state.load_run_checkpoint(), "Damaged operational labs persist")
	check(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())) == 6.0
		and SaveValidation.same(state.owned_ship(frigate_id).mounts, laboratories), "Reload preserves ranked lab identities and operation")
	check(state.repair_ship(state.owned_ship(frigate_id)), "Repair lab host hull")
	check(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())) == 6.0, "Hull repair does not change ranked production")
	check(state.set_research_focus("applied_energy"), "Set focus before travel")
	var target: int = state.get_reachable_nodes(0)[0]
	var days: float = state.research_travel_time(0, target)
	check(state.travel_to(target), "Ranked research journey departs")
	check(state.journey_rp == days * 6.0, "Departure freezes ranked yield")
	var frozen: float = state.journey_rp
	check(state.load_run_checkpoint() and state.journey_rp == frozen, "Pending journey retains frozen yield on Continue")
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, state.battle_simulation_seed(), state.battle_support_context()), "Ranked-lab battle setup")
	sim.battle_id = state.battle_identity()
	var research_cost := float(ResearchFocusRules.cost("applied_energy", state.hangar_snapshot().research))
	var before_progress := float(state.research_progress.get("applied_energy", 0))
	var expected_progress := minf(research_cost, floorf(before_progress + frozen + state.research_points))
	for tick in range(90):
		sim.advance(1.0 / 30)
	check(is_equal_approx(float(state.research_progress.get("applied_energy", 0)), before_progress), "Battle duration generates no research")
	lead = state.owned_ship(frigate_id)
	lead.damage_cell(Vector2i(0, 0), lead.hull_hp)
	check(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())) == 6.0, "Zero-hull living lab host still produces all ranked research")
	lead.damage_cell(Vector2i(-1, 0), 0.01)
	check(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())) == 1.0, "Only destroyed lab host stops production; flagship lab stays active")
	sim.phase = BattleSimulation.Phase.VICTORY
	check(state.settle_battle(sim), "Arrival settles research after battle losses")
	check(not state.equipment_inventory.has(lab_ii) and not state.equipment_inventory.has(lab_iii)
		and state.owned_ship(frigate_id) == null, "Settlement removes destroyed host and its unique labs")
	if expected_progress >= research_cost:
		check("applied_energy" in state.current_research_ids and state.research_focus.is_empty(), "Arrival completes focused research and discards excess output")
	else:
		check(is_equal_approx(float(state.research_progress.get("applied_energy", 0)), expected_progress), "Arrival adds frozen output directly to focused research")
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
	check(state._commit_hangar(saved) and state.load_run_checkpoint() and state.research_points == 0,
		"Older checkpoints without a bank load with zero unspent RP")
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
	fixture.research.branch_choices["energy"] = "disruption"
	check(state._commit_hangar(fixture), "Previously earned disruption prerequisite remains valid")
	check(not state.set_research_focus("disruption_ii"), "No new research focus on inactive ability")
	fixture.research.research_ids.append("disruption_ii")
	check(state._commit_hangar(fixture), "Previously earned deferred research remains readable")
	check(not ShipLoadouts.obtainable(SlotCatalog.find_equipment("gravitic_snare")), "Inactive ability cannot be fitted")
	for node in range(state.campaign_dag.nodes.size()):
		check(state.equipment_loot(node).get("id") != "gravitic_snare", "Loot never awards inactive equipment")
	check(not HangarResearch.view_registry().research.any(func(node: Dictionary) -> bool: return node.id == "disruption_ii"), "Inactive research omitted from active tree")
	# Already-owned inactive equipment can be inspected, removed and sold; it
	# cannot silently become deployable or be duplicated by fitting another copy.
	check(state.buy_ship("corsair"), "Legacy deferred equipment host")
	var host_id: int = state.fleet[-1].id
	fixture = state.hangar_snapshot()
	var uid := str(fixture.next_equipment_id)
	fixture.next_equipment_id += 1
	fixture.equipment[uid] = {"uid": uid, "equipment_id": "gravitic_snare", "rank": 1}
	fixture.ships[-1].mounts["fore"] = uid
	HangarSquadrons.update_override(fixture, host_id)
	check(state._commit_hangar(fixture) and state.load_run_checkpoint(), "Legacy inactive item remains readable")
	check(state.deployment_error() == "Unequip deferred equipment", "Inactive loadout cannot depart")
	check(state.fit_equipment(host_id, "fore", "") and not state.equipment_inventory.has(uid), "Legacy inactive item can be removed (and is scrapped)")
	print("HANGAR RESEARCH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
