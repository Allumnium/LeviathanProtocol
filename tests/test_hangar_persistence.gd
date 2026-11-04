extends SceneTree

const ShipLoadouts = preload("res://scripts/ship_loadouts.gd")

var checks := 0
var failures := 0
var state: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func canonical(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://hangar-persistence.json"
	check(state.start_new_run(1, 808), "Start state")
	state.current_research_ids.append("applied_energy")
	check(state.save_run_checkpoint(), "Persist earned laser research before backup recovery tests")
	var valid: Dictionary = state.hangar_snapshot()
	check(valid.version == 2 and not valid.ships[0].has("builtins"), "Whole-ship checkpoint has schema 2 and no builtins")
	check(valid.equipment.values().all(func(instance: Dictionary) -> bool: return not instance.has("hp")), "Equipment saves contain identity rather than durability")
	for key in ["research_focus", "research_progress", "research_ids", "story_flags", "branch_choices"]:
		var broken: Dictionary = valid.duplicate(true)
		broken.research.erase(key)
		check(not HangarCheckpoint.valid(broken), "Reject missing " + key)
	for hp in [-1.0, state.fleet[0].hull_max + 1.0, INF, NAN]:
		var broken: Dictionary = valid.duplicate(true)
		broken.ships[0].hull_hp = hp
		check(not HangarCheckpoint.valid(broken), "Reject invalid hull HP")
	var broken: Dictionary = valid.duplicate(true)
	broken.version = 1
	check(not HangarCheckpoint.valid(broken) and not state._commit_hangar(broken), "Intentionally reject schema 1 rather than migrate components")
	broken = valid.duplicate(true)
	broken.ships[0]["builtins"] = {"core": 100, "engine": 50}
	check(not HangarCheckpoint.valid(broken), "Reject removed builtin component state")
	for hp in [0.0, 1.0, 16.0]:
		broken = valid.duplicate(true)
		broken.equipment["1"]["hp"] = hp
		check(not HangarCheckpoint.valid(broken) and not state._commit_hangar(broken), "Reject all equipment HP fields without mutation")
	check(canonical(state.hangar_snapshot()) == canonical(valid), "Rejected old health schemas leave the entire state unchanged")
	broken = valid.duplicate(true)
	broken.ships[0].mounts["unknown"] = "1"
	check(not HangarCheckpoint.valid(broken), "Reject invented slot")
	for key in ["crew_quarters", "focusing_lens", "reactive_bulkhead", "observation_deck", "repair_station", "mining_laser"]:
		check(not ShipLoadouts.obtainable(SlotCatalog.find_equipment(key)), "No unsupported part offered " + key)
	check(not state.swap_part(1, "spine", "crew_quarters"), "Unsupported part cannot be fitted")
	check(state.save_run_checkpoint(), "Create second verified generation and backup")
	var file := FileAccess.open(state.run_save_path, FileAccess.WRITE)
	file.store_string("corrupt")
	file.close()
	check(state.load_run_checkpoint(), "Recover valid backup/staged generation")
	check(state.fleet[0].is_alive(), "Recovered physical ship")
	check(state.save_run_checkpoint(), "Recovered save can commit")
	var before: Dictionary = canonical(state.hangar_snapshot())
	var real_path: String = state.run_save_path
	state.run_save_path = "res://project.godot/not-a-directory/save.json"
	check(not state.swap_part(1, "fore", "laser"), "Failed save rejects refit")
	check(canonical(state.hangar_snapshot()) == before, "Failed save leaves credits and ownership unchanged")
	state.run_save_path = real_path
	var lead: HangarShip = state.owned_ship(1)
	var identity := lead.mounts.duplicate(true)
	var dps := lead.get_stats().dps
	lead.damage_cell(Vector2i(0, 0), 120.25)
	var damaged: Dictionary = canonical(state.hangar_snapshot())
	check(state.save_run_checkpoint() and state.load_run_checkpoint(), "Substantial hull damage persists and reloads")
	lead = state.owned_ship(1)
	check(canonical(state.hangar_snapshot()) == damaged and lead.mounts == identity and lead.get_stats().dps == dps, "Reload preserves hull damage and all equipment operation")
	state.run_save_path = "res://project.godot/not-a-directory/save.json"
	check(not state.repair_ship(lead) and canonical(state.hangar_snapshot()) == damaged, "Failed hull repair save leaves credits, hull and identities unchanged")
	state.run_save_path = real_path
	lead = state.owned_ship(1)
	var repair_credits: int = state.credits
	check(lead.repair_cost() == 120 and state.repair_ship(lead) and state.credits == repair_credits - 120, "Alive hull repairs cost ceiling of actual armored hull damage")
	check(state.load_run_checkpoint() and state.owned_ship(1).hull_hp == state.owned_ship(1).hull_max
		and state.owned_ship(1).mounts == identity, "Paid hull-only repair reloads without replacing equipment")
	check(not state.has_method("repair_equipment"), "No separate equipment repair backend")
	state.owned_ship(1).damage_cell(Vector2i(1, 0), 20)
	before = canonical(state.hangar_snapshot())
	state.run_save_path = "res://project.godot/not-a-directory/save.json"
	check(not state.swap_part(1, "fore", "laser") and canonical(state.hangar_snapshot()) == before, "Failed refit save preserves credits and exact identities")
	state.run_save_path = real_path
	var hull_before: float = state.owned_ship(1).hull_hp
	check(state.swap_part(1, "fore", "laser") and state.owned_ship(1).hull_hp == hull_before, "Refitting a damaged host keeps its hull damage")
	# Command budget is independent of credits and cannot be bypassed by direct calls.
	state.credits = 10000
	check(state.save_run_checkpoint(), "Fund command test")
	for index in range(state.command_limit() - state.used_command()):
		check(state.buy_ship("drone"), "Buy within command budget")
	check(state.used_command() == state.command_limit(), "Command budget filled")
	check(not state.buy_ship("drone"), "Command overflow rejected")
	check(not state.buy_ship("flagship_basic"), "Cannot buy second flagship")
	var slowest := 0
	for index in range(20):
		var start := Time.get_ticks_msec()
		check(state.swap_part(1, "fore", "mini_turret" if index % 2 == 0 else "laser"), "Repeated part swap")
		slowest = maxi(slowest, Time.get_ticks_msec() - start)
	check(slowest < 500, "Refits finish within 500ms")
	# Trade runs on physical gear and commits along with travel, damage and credits.
	check(state.start_new_run(1, 909), "Trade run")
	state.credits = 2000
	state.current_research_ids.append("civil_hospitality")
	check(state.buy_ship("transport"), "Buy physical cargo host")
	var transport_id: int = state.fleet[-1].id
	var cargo_uid: String = state.owned_ship(transport_id).mounts.hold.uid
	check(SlotCatalog.find_equipment(state.equipment_inventory[cargo_uid].equipment_id).id == "cargo_hold", "Freighter arrives with a working hold")
	check(state.swap_part(1, "spine", "passenger_cabin"), "Equip cabin, scrapping the lab")
	var cabin_uid: String = state.owned_ship(1).mounts.spine.uid
	var data: Dictionary = state.hangar_snapshot()
	var source: Dictionary = state.campaign_node(0)
	var target := {"id": 1, "inhabited": true}
	HangarTrade.depart(data, source, target)
	check(data.equipment[cargo_uid].load.quantity == 10, "Hold loads ten physical goods")
	check(data.equipment[cabin_uid].load.quantity == 4, "Cabin boards four passengers")
	check(HangarCheckpoint.valid(data), "Loaded physical checkpoint valid")
	check(HangarCheckpoint.valid(canonical(data)), "Loaded serialized checkpoint valid")
	check(state._commit_hangar(data), "Loaded contents persist")
	if not state.last_save_error.is_empty():
		print("SAVE ERROR: ", state.last_save_error)
		quit(1)
		return
	check(not state.fit_equipment(1, "spine", ""), "Cannot warehouse passengers between ports")
	check(state.load_run_checkpoint() and state.equipment_inventory[cargo_uid].load.quantity == 10, "Cargo resumes by item identity")
	var credits: int = state.credits
	data = state.hangar_snapshot()
	for ship: Dictionary in data.ships:
		ship.hull_hp = 0 if ship.flagship else 1
	HangarTrade.settle_losses(data, [])
	check(data.equipment[cargo_uid].load.quantity == 10 and data.equipment[cabin_uid].load.quantity == 4, "Substantial host damage including zero hull retains loads")
	check(state._commit_hangar(data) and state.load_run_checkpoint(), "Damaged loaded ships save and resume atomically")
	data = state.hangar_snapshot()
	var expected_delivery := 0
	for ship: Dictionary in data.ships:
		for uid: String in ship.mounts.values():
			var contents: Dictionary = data.equipment[uid].get("load", {})
			if not contents.is_empty():
				expected_delivery += roundi(int(contents.quantity) * int(contents.unit_value)
					* float(SlotCatalog.find_chassis(ship.chassis).get("delivery_income_multiplier", 1.0)))
	HangarTrade.arrive(data, target)
	check(expected_delivery >= 30 + 32 and data.credits == credits + expected_delivery, "Damaged living hosts deliver cargo and passengers for credits")
	var paid: int = data.credits
	HangarTrade.arrive(data, target)
	check(data.credits == paid, "Arrival cannot pay a load twice")
	HangarTrade.depart(data, source, target)
	for ship: Dictionary in data.ships:
		ship.hull_hp = -1
	var lost: Array[int] = [1, transport_id]
	HangarTrade.arrive(data, target)
	check(data.credits == paid and data.equipment[cabin_uid].load.quantity == 4, "Destroyed hosts cannot deliver their loads")
	HangarTrade.settle_losses(data, lost)
	check(data.equipment[cargo_uid].load.is_empty() and data.equipment[cabin_uid].load.is_empty(), "Only destroyed hosts lose their equipment loads")
	check(data.credits == paid - 80, "Passenger casualty fee retained")
	HangarTrade.settle_losses(data, lost)
	check(data.credits == paid - 80, "Casualties charged once")
	check(state.repair_ship(state.owned_ship(1)) and state.repair_ship(state.owned_ship(transport_id)), "Living damaged cargo hosts accept hull-only repair")
	check(state.equipment_inventory[cargo_uid].load.quantity == 10 and state.equipment_inventory[cabin_uid].load.quantity == 4, "Hull repairs neither destroy nor recreate existing loads")
	# Losing the flagship ends battle despite armed escorts.
	state.credits = 1000
	check(state.buy_ship("drone"), "Escort purchase")
	check(state.fit_equipment(state.fleet[-1].id, "fore", "1"), "Escort armed")
	check(state.travel_to(state.get_reachable_nodes(0)[0]), "Flagship loss battle")
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, state.battle_simulation_seed(), state.battle_support_context()), "Flagship loss setup")
	sim.battle_id = state.battle_identity()
	var terminal_credits: int = state.credits
	state.owned_ship(1).damage_cell(Vector2i(-1, 0), 10000)
	var destroyed_transport: HangarShip = state.owned_ship(transport_id)
	destroyed_transport.damage_cell(Vector2i(0, 0), destroyed_transport.hull_hp + 1)
	var destroyed_hull := destroyed_transport.hull_hp
	destroyed_transport.repair()
	check(destroyed_transport.hull_hp == destroyed_hull and destroyed_transport.repair_hull(100) == 0, "Destroyed trade chassis cannot heal or reconstruct its loads")
	sim.advance(1.0 / 30)
	check(sim.phase == BattleSimulation.Phase.DEFEAT and sim.living_player_count() > 0, "Flagship loss overrides surviving escort")
	before = canonical(state.hangar_snapshot())
	state.run_save_path = "res://project.godot/not-a-directory/save.json"
	check(not state.settle_battle(sim) and canonical(state.hangar_snapshot()) == before, "Failed loss settlement preserves all live ownership, hulls, loads and credits")
	state.run_save_path = real_path
	check(state.settle_battle(sim), "Terminal loss persists")
	check(state.credits == terminal_credits - 80 and not state.equipment_inventory.has(cargo_uid)
		and not state.equipment_inventory.has(cabin_uid) and state.owned_ship(transport_id) == null, "Battle settlement removes destroyed hosts and equipment and charges passenger fee once")
	check(state.is_run_lost() and state.load_run_checkpoint() and state.is_run_lost(), "Cannot resume a destroyed flagship")
	check(state.credits == terminal_credits - 80 and not state.settle_battle(sim), "Reload and repeated settlement cannot charge casualties again")
	print("HANGAR PERSISTENCE: %d checks, %d failures; slowest refit %dms" % [checks, failures, slowest])
	quit(1 if failures else 0)
