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
	check(state.fleet.size() == 1 and state.fleet[0].chassis_id == "flagship_basic", "Supplied flagship")
	check(HangarCheckpoint.valid(state.hangar_snapshot()), "Checkpoint valid")
	check(state.fleet[0].mounts.size() == 4, "Starter physical equipment")
	check(state.can_deploy(), "Armed deployment")
	check(state.is_shipyard_node(0), "Start shipyard")
	var original: Dictionary = state.hangar_snapshot()
	check(not state.buy_equipment("laser"), "Locked purchase rejected")
	check(state.hangar_snapshot() == original, "Failed purchase unchanged")
	var credits: int = state.credits
	check(state.buy_equipment("mini_turret"), "Buy equipment instance")
	check(state.credits == credits - 40, "Credits charged once")
	var uid := str(state.next_equipment_id - 1)
	check(state.equipment_location(uid).is_empty(), "Purchased item in stock")
	check(state.buy_chassis("drone"), "Buy physical chassis")
	var ship_id: int = state.fleet[-1].id
	check(state.fit_equipment(ship_id, "fore", uid), "Fit stock item")
	check(state.equipment_location(uid).ship_id == ship_id, "Ownership is unique")
	credits = state.credits
	check(state.fit_equipment(1, "aft_port", uid), "Transfer between ships")
	check(state.credits == credits, "Free transfer")
	check(state.owned_ship(ship_id).mounts.is_empty(), "Old mount emptied")
	check(not state.fit_equipment(ship_id, "center", uid), "Wrong type/size rejected")
	check(not state.sell_equipment(uid), "Equipped item cannot be sold")
	check(state.fit_equipment(1, "aft_port", ""), "Unequip")
	check(state.sell_equipment(uid), "Sell stock")
	check(not state.sell_equipment(uid), "Cannot sell twice")
	check(not state.salvage_hangar_ship(1), "Cannot salvage mandatory flagship")
	check(state.salvage_hangar_ship(ship_id), "Immediate chassis salvage")
	var lead: HangarShip = state.owned_ship(1)
	var hp := lead.hull_hp
	var component: float = lead.units[2].hp
	lead.damage_cell(Vector2i(2, 0), 10)
	check(lead.hull_hp == hp - 5 and lead.units[2].hp == component - 5, "Half equipment / half chassis damage")
	check(lead.mounts[lead.units[2].key].hp == lead.units[2].hp, "Instance damage retained")
	check(state.repair_ship(lead), "Credits-only repair")
	lead = state.owned_ship(1)
	check(not lead.needs_repair(), "Hull and components repaired")
	lead.hull_hp = 0
	check(lead.is_alive(), "Hull survives zero")
	lead.damage_cell(Vector2i(-1, 0), 0.01)
	check(not lead.is_alive(), "Hull dies below zero")
	state._apply_hangar(original)
	check(state.save_run_checkpoint(), "Save restored test state")
	var snapshot: Dictionary = state.hangar_snapshot()
	check(state.load_run_checkpoint(), "Load checkpoint")
	check(JSON.parse_string(JSON.stringify(state.hangar_snapshot())) == JSON.parse_string(JSON.stringify(snapshot)), "Roundtrip ship, gear, health and progress")
	var bad: Dictionary = snapshot.duplicate(true)
	bad.ships[0].mounts["aft_starboard"] = bad.ships[0].mounts.aft_port
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
		check(not state.buy_equipment("mini_turret"), "No buying during travel/combat")
		check(not state.fit_equipment(1, "aft_port", ""), "No battle refit")
		var sim := BattleSimulation.new()
		check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, state.battle_simulation_seed(), state.battle_support_context()), "Actual slot fleet enters battle")
		sim.battle_id = state.battle_identity()
		check(sim.set_objective_targets(state.battle_objective_ids()), "Battle objectives")
		for tick in range(90):
			sim.advance(1.0 / 30)
		check(sim.drops.is_empty(), "No material drops")
		var before_gear: int = state.equipment_inventory.size()
		var before_rp: float = state.research_points
		var travel_rp: float = state.journey_rp
		sim.phase = BattleSimulation.Phase.VICTORY
		check(state.settle_battle(sim), "Settle encounter")
		check(state.equipment_inventory.size() == before_gear + 1, "One physical loot instance")
		check(state.research_points == before_rp + travel_rp, "Labs and travel produce RP")
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
