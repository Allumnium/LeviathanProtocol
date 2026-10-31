extends SceneTree

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
	var valid: Dictionary = state.hangar_snapshot()
	for key in ["research_focus", "research_progress", "research_ids", "story_flags", "branch_choices"]:
		var broken: Dictionary = valid.duplicate(true)
		broken.research.erase(key)
		check(not HangarCheckpoint.valid(broken), "Reject missing " + key)
	for hp in [-1.0, 311.0, INF, NAN]:
		var broken: Dictionary = valid.duplicate(true)
		broken.ships[0].hull_hp = hp
		check(not HangarCheckpoint.valid(broken), "Reject invalid hull HP")
	var broken: Dictionary = valid.duplicate(true)
	broken.ships[0].builtins.core = 0
	check(not HangarCheckpoint.valid(broken), "Reject dead core in peaceful fleet")
	broken = valid.duplicate(true)
	broken.equipment["1"].hp = 16
	check(not HangarCheckpoint.valid(broken), "Reject excessive item health")
	broken = valid.duplicate(true)
	broken.ships[0].mounts["unknown"] = "1"
	check(not HangarCheckpoint.valid(broken), "Reject invented slot")
	for key in ["crew_quarters", "focusing_lens", "reactive_bulkhead", "observation_deck", "repair_station", "mining_laser"]:
		check(not state.buy_equipment(key), "No unsupported purchase " + key)
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
	check(not state.buy_equipment("mini_turret"), "Failed save rejects purchase")
	check(canonical(state.hangar_snapshot()) == before, "Failed save leaves credits and ownership unchanged")
	state.run_save_path = real_path
	# Command budget is independent of credits and cannot be bypassed by direct calls.
	state.credits = 10000
	check(state.save_run_checkpoint(), "Fund command test")
	for index in range(12):
		check(state.buy_chassis("drone"), "Buy within command budget")
	check(state.used_command() == state.command_limit(), "Command budget filled")
	check(not state.buy_chassis("drone"), "Command overflow rejected")
	check(not state.buy_chassis("flagship_basic"), "Cannot buy second flagship")
	var slowest := 0
	for index in range(20):
		var start := Time.get_ticks_msec()
		check(state.fit_equipment(1, "aft_port", "1"), "Repeated equipment selection")
		slowest = maxi(slowest, Time.get_ticks_msec() - start)
	check(slowest < 500, "Refits finish within 500ms")
	# Trade runs on physical gear and commits along with travel, damage and credits.
	check(state.start_new_run(1, 909), "Trade run")
	state.current_research_ids.append("civil_hospitality")
	check(state.buy_equipment("cargo_hold"), "Buy working cargo hold")
	var cargo_uid := str(state.next_equipment_id - 1)
	check(state.fit_equipment(1, "hold", cargo_uid), "Equip hold")
	check(state.buy_equipment("passenger_cabin"), "Buy working cabin")
	var cabin_uid := str(state.next_equipment_id - 1)
	check(state.fit_equipment(1, "spine", cabin_uid), "Equip cabin, returning lab to stock")
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
	HangarTrade.arrive(data, target)
	check(data.credits == credits + 30 + 32, "Cargo sale and passenger fare use credits")
	var paid: int = data.credits
	HangarTrade.arrive(data, target)
	check(data.credits == paid, "Arrival cannot pay a load twice")
	HangarTrade.depart(data, source, target)
	data.equipment[cargo_uid].hp = 0
	data.equipment[cabin_uid].hp = 0
	HangarTrade.settle_losses(data, [])
	check(data.equipment[cargo_uid].load.is_empty() and data.equipment[cabin_uid].load.is_empty(), "Destroyed equipment loses its loads")
	check(data.credits == paid - 80, "Passenger casualty fee retained")
	HangarTrade.settle_losses(data, [])
	check(data.credits == paid - 80, "Casualties charged once")
	check(state._commit_hangar(data), "Losses and fees commit together")
	check(state.repair_ship(state.owned_ship(1)), "Reconstruct ruined equipment")
	check(not HangarTrade.has_load(state.equipment_inventory[cargo_uid]) and not HangarTrade.has_load(state.equipment_inventory[cabin_uid]), "Repair cannot restore lost loads")
	# Losing the flagship ends battle despite armed escorts.
	state.credits = 1000
	check(state.buy_chassis("drone"), "Escort purchase")
	check(state.fit_equipment(state.fleet[-1].id, "fore", "1"), "Escort armed")
	check(state.travel_to(state.get_reachable_nodes(0)[0]), "Flagship loss battle")
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, state.battle_simulation_seed(), state.battle_support_context()), "Flagship loss setup")
	sim.battle_id = state.battle_identity()
	state.owned_ship(1).damage_cell(Vector2i(-1, 0), 10000)
	sim.advance(1.0 / 30)
	check(sim.phase == BattleSimulation.Phase.DEFEAT and sim.living_player_count() > 0, "Flagship loss overrides surviving escort")
	check(state.settle_battle(sim), "Terminal loss persists")
	check(state.is_run_lost() and state.load_run_checkpoint() and state.is_run_lost(), "Cannot resume a destroyed flagship")
	print("HANGAR PERSISTENCE: %d checks, %d failures; slowest refit %dms" % [checks, failures, slowest])
	quit(1 if failures else 0)
