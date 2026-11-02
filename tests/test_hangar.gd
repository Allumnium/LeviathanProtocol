extends SceneTree

var failures := 0
var checks := 0
var state: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://hangar-test.json"
	check(state.start_new_run(1, 74321), "New actual campaign")
	check(state.hangar_snapshot().version == 2, "Whole-ship saves use schema 2")
	check(state.fleet.size() == 4 and state.fleet[0].chassis_id == "flagship_basic", "Supplied flagship with Transport and two Fighters")
	check(HangarCheckpoint.valid(state.hangar_snapshot()), "Checkpoint valid")
	check(state.fleet[0].mounts.size() == 8, "Starter flagship arrives fully fitted")
	check(state.can_deploy(), "Armed deployment")
	check(state.is_shipyard_node(0), "Start shipyard")
	var original: Dictionary = state.hangar_snapshot()
	check(not state.swap_part(1, "fore", "cargo_hold"), "Incompatible part rejected")
	check(state.hangar_snapshot() == original, "Failed refit unchanged")
	var credits: int = state.credits
	check(state.buy_ship("drone"), "Buy fitted ship")
	var ship_id: int = state.fleet[-1].id
	credits = state.credits
	check(state.swap_part(ship_id, "fore", "laser") and state.credits == credits - 10, "Part swap charges its fee once")
	var uid: String = state.owned_ship(ship_id).mounts.fore.uid
	check(state.equipment_location(uid).ship_id == ship_id, "Ownership is unique")
	credits = state.credits
	check(state.fit_equipment(1, "fore", uid), "Transfer between ships")
	check(state.credits == credits, "Free transfer")
	check(not state.owned_ship(ship_id).mounts.has("fore"), "Old mount emptied")
	check(not state.fit_equipment(ship_id, "center", uid), "Wrong type/size rejected")
	check(state.fit_equipment(1, "fore", "") and not state.equipment_inventory.has(uid), "Unequipping scraps the part; there is no stock")
	check(not state.salvage_hangar_ship(1), "Cannot salvage mandatory flagship")
	check(state.salvage_hangar_ship(ship_id), "Immediate chassis salvage")
	var lead: HangarShip = state.owned_ship(1)
	var hp := lead.hull_hp
	var index: int = lead.units.find(lead.units.filter(func(unit: Dictionary) -> bool: return unit.key == "port")[0])
	var equipment := lead.mounts.duplicate(true)
	var stats := lead.get_stats()
	var amount := hp * 0.5 + 0.25
	var damage := lead.damage_cell(Vector2i(index, 0), amount)
	check(lead.hull_hp == hp - (amount - 1) and damage.damage == amount - 1 and damage.removed.is_empty(), "Equipment hit applies armored hull damage without removing mounts")
	check(lead.mounts == equipment and lead.units.all(func(unit: Dictionary) -> bool: return unit.hp == 1 and unit.max_hp == 1), "Substantial damage preserves equipment identity and operational markers")
	check(lead.get_stats().dps == stats.dps and lead.get_stats().thrust == stats.thrust and lead.get_stats().shields == stats.shields, "Damaged ship retains weapons, engine and shields")
	check(lead.units[0].key == "engine" and not lead.units.any(func(unit: Dictionary) -> bool: return unit.key == "core"), "Combat bridge has engine at zero and no command-center component")
	if lead.chassis.has("builtin_shield"):
		check(lead.units[1].key == "shield" and lead.units[1].hp == 1, "Optional builtin shield follows engine with an operational marker")
	check(not lead.to_hangar_data().has("builtins") and lead.mounts.values().all(func(instance: Dictionary) -> bool: return not instance.has("hp")), "Snapshots store hull health only")
	var quote := ceili(amount - 1)
	check(lead.repair_cost() == quote, "Hull repair rounds fractional missing integrity up")
	credits = state.credits
	check(state.repair_ship(lead) and state.credits == credits - quote, "Credits-only hull repair charges quoted cost")
	lead = state.owned_ship(1)
	check(not lead.needs_repair() and lead.mounts == equipment, "Hull repair preserves fitted equipment")
	var before_invalid := lead.hull_hp
	for invalid in [-1.0, 0.0, INF, NAN]:
		damage = lead.damage_cell(Vector2i(0, 0), invalid)
		check(lead.hull_hp == before_invalid and damage.damage == 0 and damage.removed.is_empty(), "Invalid damage cannot mutate hull or equipment")
	lead.hull_hp = 0
	check(lead.is_alive() and lead.get_stats().dps == stats.dps and lead.mounts == equipment, "Hull survives zero with all equipment operational")
	damage = lead.damage_cell(Vector2i(-1, 0), 1.01)
	check(not lead.is_alive() and damage.removed.is_empty(), "Hull dies strictly below zero without component removals")
	var destroyed_hp := lead.hull_hp
	lead.repair()
	check(lead.hull_hp == destroyed_hp and lead.repair_hull(100) == 0 and not state.repair_ship(lead), "Destroyed chassis cannot be repaired")
	state._apply_hangar(original)
	check(state.save_run_checkpoint(), "Save restored test state")
	var snapshot: Dictionary = state.hangar_snapshot()
	check(state.load_run_checkpoint(), "Load checkpoint")
	check(JSON.parse_string(JSON.stringify(state.hangar_snapshot())) == JSON.parse_string(JSON.stringify(snapshot)), "Roundtrip ship, gear, health and progress")
	var bad: Dictionary = snapshot.duplicate(true)
	bad.ships[0].mounts["fore"] = bad.ships[0].mounts.port
	check(not HangarCheckpoint.valid(bad), "Duplicate physical item rejected")
	bad = snapshot.duplicate(true)
	bad.credits = 0.5
	check(not HangarCheckpoint.valid(bad), "Fractional credits rejected")
	var destination := -1
	for node in state.get_reachable_nodes(0):
		if not state.get_frozen_encounter(node).is_empty():
			destination = node
	check(destination >= 0, "First route has combat")
	if destination >= 0:
		check(state.travel_to(destination), "Depart for encounter")
		check(not state.swap_part(1, "fore", "laser"), "No refits during travel/combat")
		check(not state.fit_equipment(1, "aft_port", ""), "No battle refit")
		var sim := BattleSimulation.new()
		check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, state.battle_simulation_seed(), state.battle_support_context()), "Actual slot fleet enters battle")
		sim.battle_id = state.battle_identity()
		check(sim.set_objective_targets(state.battle_objective_ids()), "Battle objectives")
		for tick in range(90):
			sim.advance(1.0 / 30)
		check(sim.drops.is_empty(), "No material drops")
		var before_gear: int = state.equipment_inventory.size()
		var travel_rp: float = state.journey_rp
		sim.phase = BattleSimulation.Phase.VICTORY
		check(state.settle_battle(sim), "Settle encounter")
		check(state.equipment_inventory.size() == before_gear + 1, "One physical loot instance")
		check(travel_rp > 0 and state.research_focus.is_empty() and state.research_progress.is_empty(), "Travel research is discarded when there is no focus")
		check(not state.settle_battle(sim), "No duplicate rewards")
		check(state.load_run_checkpoint() and state.current_node_id == destination, "Settled checkpoint resumes")
	if "--capture" in OS.get_cmdline_user_args():
		var scene: Control = load("res://scenes/game_map.tscn").instantiate()
		root.add_child(scene)
		current_scene = scene
		await process_frame
		await process_frame
		await create_timer(0.3).timeout
		root.get_texture().get_image().save_png("res://.local/hangar/hangar.png")
	print("HANGAR: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
