extends Node

signal fleet_changed
signal credits_changed
signal research_changed
signal travel_plan_changed

enum Difficulty { EASY, MEDIUM, HARD }
var fleet: Array[FleetShip] = []
var next_ship_id := 1
var credits := 600
var difficulty := Difficulty.MEDIUM
var run_seed := 1
var run_id := ""
var run_ended := false
var battle_pending := false
var player_ship_count := 0
var battle_aliens: Array[RefCounted] = []
var last_battle_report: Array[Dictionary] = []
var current_node_id := 0
var destination_node_id := -1
var planned_destination_node_id := -1
var visited_nodes: Array[int] = [0]
var current_research_ids: Array[String] = ["foundation"]
var research_points := 0.0
var research_focus := ""
var research_progress: Dictionary = {}
var research_pricing_version := 1
var story_flags: Dictionary[String, bool] = {}
var research_branch_choices: Dictionary[String, String] = {}
var campaign_active := true
var campaign_dag: Dictionary = {}
var frozen_encounters: Dictionary = {}
var NODE_POSITIONS: Array[Vector2] = []
var NODE_COLUMNS: Array[int] = []
var GRAPH_EDGES: Array[Vector2i] = []
var CONVERGENCE_NODE_IDS: Array[int] = []
var FINAL_NODE_ID := 0
var laser_upgrade_level := 0
var battle_auto_camera := true
var battle_fast_forward := false
var reduced_motion := false
var destroy_all_neutral_targets := false
var run_save_path := "user://hangar_run.json"
var last_save_error := ""
var _checkpoint_store := AtomicRunStore.new()


# The active game uses physical equipment and its own checkpoint namespace.
# Legacy material and blueprint state is not part of this runtime.
var equipment_inventory: Dictionary = {}
var next_equipment_id := 1
var journey_rp := 0.0
var hangar_generation := -1
var completed := false
var last_equipment_loot := ""
var battle_reserves: Dictionary = {}

func _ready() -> void:
	run_save_path = "user://hangar_run.json"
	run_seed = 1


func start_new_run(selected_difficulty: int = Difficulty.MEDIUM, seed_value: int = -1, _use_campaign := true) -> bool:
	if selected_difficulty not in [0, 1, 2] or seed_value < -1:
		return false
	var before := hangar_snapshot() if not run_id.is_empty() else {}
	var previous_generation := hangar_generation
	run_seed = _new_run_seed() if seed_value == -1 else seed_value
	difficulty = selected_difficulty as Difficulty
	run_id = Crypto.new().generate_random_bytes(16).hex_encode()
	credits = 600
	current_research_ids = ["foundation"]
	research_points = 0
	research_focus = ""
	research_progress = {}
	research_pricing_version = 1
	story_flags.clear()
	research_branch_choices.clear()
	fleet.clear()
	equipment_inventory.clear()
	next_ship_id = 1
	next_equipment_id = 1
	current_node_id = 0
	destination_node_id = -1
	planned_destination_node_id = -1
	visited_nodes = [0]
	battle_pending = false
	run_ended = false
	completed = false
	journey_rp = 0
	battle_reserves = {}
	last_battle_report.clear()
	last_equipment_loot = ""
	_build_campaign()
	var lead := _add_chassis("flagship_basic", true)
	_give_equipment(lead, "aft_port", "mini_turret")
	_give_equipment(lead, "aft_starboard", "mini_turret")
	_give_equipment(lead, "inner_port", "armor_block")
	# A starter lab makes the existing travel research loop immediately usable.
	_give_equipment(lead, "spine", "research_lab")
	hangar_generation = -1
	if not save_run_checkpoint():
		if not before.is_empty():
			run_seed = int(before.seed)
			difficulty = int(before.difficulty) as Difficulty
			_build_campaign()
			_apply_hangar(before)
		hangar_generation = previous_generation
		return false
	_notify_hangar()
	return true

func _build_campaign() -> void:
	campaign_active = true
	campaign_dag = CampaignContent.populate(CampaignGraph.generate(run_seed), run_seed)
	_apply_campaign_geometry()
	frozen_encounters = EncounterGenerator.freeze_campaign(run_seed, difficulty, campaign_dag)

func _add_chassis(key: String, lead := false) -> HangarShip:
	var owned := HangarShip.new()
	owned.initialize_chassis(key, next_ship_id, lead)
	owned.formation = Vector2((fleet.size() % 3) - 1, floori(fleet.size() / 3.0))
	next_ship_id += 1
	fleet.append(owned)
	return owned

func _new_equipment(key: String, rank := 1) -> Dictionary:
	var item := SlotCatalog.find_equipment(key, rank)
	if item.is_empty():
		return {}
	var uid := str(next_equipment_id)
	next_equipment_id += 1
	var instance := {"uid": uid, "equipment_id": key, "rank": rank, "hp": float(item.hit_points)}
	equipment_inventory[uid] = instance
	return instance

func _give_equipment(owned: HangarShip, slot: String, key: String) -> void:
	var mount := {}
	for candidate: Dictionary in owned.chassis.slots:
		if candidate.id == slot:
			mount = candidate
	var item := SlotCatalog.find_equipment(key)
	if mount.is_empty() or not SlotCatalog.compatible(mount, item):
		return
	owned.mounts[slot] = _new_equipment(key)
	owned.rebuild_units(owned.health_by_mount())

func hangar_snapshot() -> Dictionary:
	var ships: Array = []
	for owned: HangarShip in fleet:
		ships.append(owned.to_hangar_data())
	return {"format": "physical_hangar", "version": 1, "run_id": run_id, "seed": str(run_seed),
		"difficulty": difficulty, "credits": credits, "ships": ships, "equipment": equipment_inventory.duplicate(true),
		"next_ship_id": next_ship_id, "next_equipment_id": next_equipment_id,
		"current": current_node_id, "destination": destination_node_id, "planned": planned_destination_node_id,
		"visited": visited_nodes.duplicate(), "pending": battle_pending, "ended": run_ended, "completed": completed,
		"journey_rp": journey_rp, "pending_encounter": get_frozen_encounter(destination_node_id) if battle_pending else {},
		"battle_reserves": battle_reserves.duplicate(true), "research": {"research_ids": current_research_ids.duplicate(),
		"research_points": research_points, "research_focus": research_focus, "research_progress": research_progress.duplicate(),
		"research_pricing_version": 1, "story_flags": story_flags.duplicate(), "branch_choices": research_branch_choices.duplicate()}}

func _apply_hangar(data: Dictionary) -> void:
	run_id = data.run_id
	run_seed = int(data.seed)
	difficulty = int(data.difficulty) as Difficulty
	credits = int(data.credits)
	next_ship_id = int(data.next_ship_id)
	next_equipment_id = int(data.next_equipment_id)
	equipment_inventory = data.equipment.duplicate(true)
	fleet.clear()
	for entry: Dictionary in data.ships:
		var owned := HangarShip.new()
		owned.initialize_chassis(entry.chassis, int(entry.id), entry.flagship)
		owned.formation = Vector2(entry.formation[0], entry.formation[1])
		for slot in entry.mounts:
			owned.mounts[slot] = equipment_inventory[entry.mounts[slot]]
		owned.rebuild_units(entry.builtins)
		owned.hull_hp = entry.hull_hp
		fleet.append(owned)
	current_node_id = int(data.current)
	destination_node_id = int(data.destination)
	planned_destination_node_id = int(data.planned)
	visited_nodes.assign(data.visited)
	battle_pending = data.pending
	run_ended = data.ended
	completed = data.completed
	journey_rp = data.journey_rp
	battle_reserves = data.get("battle_reserves", {}).duplicate(true)
	current_research_ids.assign(data.research.research_ids)
	research_points = data.research.research_points
	research_focus = data.research.research_focus
	research_progress = data.research.research_progress.duplicate()
	story_flags.assign(data.research.story_flags)
	research_branch_choices.assign(data.research.branch_choices)
	player_ship_count = fleet.size()
	battle_aliens.clear()
	if battle_pending:
		if data.has("pending_encounter"):
			frozen_encounters[str(destination_node_id)] = data.pending_encounter.duplicate(true)
		battle_aliens = EncounterGenerator.initial_fleet(get_frozen_encounter(destination_node_id))

func save_run_checkpoint() -> bool:
	return _save_hangar(hangar_snapshot())

func _save_hangar(data: Dictionary) -> bool:
	var result := _checkpoint_store.commit(run_save_path, data, HangarCheckpoint.valid, hangar_generation)
	last_save_error = _checkpoint_store.last_error
	if not result.ok:
		return false
	hangar_generation = int(result.generation)
	return true

func _commit_hangar(proposal: Dictionary) -> bool:
	if not _save_hangar(proposal):
		return false
	_apply_hangar(proposal)
	_notify_hangar()
	return true

func _notify_hangar() -> void:
	player_ship_count = fleet.size()
	fleet_changed.emit()
	credits_changed.emit()
	research_changed.emit()
	travel_plan_changed.emit()

func load_run_checkpoint() -> bool:
	var saved := _checkpoint_store.load_latest(run_save_path, HangarCheckpoint.valid)
	if saved.is_empty():
		last_save_error = "No hangar checkpoint."
		return false
	run_seed = int(saved.payload.seed)
	difficulty = int(saved.payload.difficulty) as Difficulty
	_build_campaign()
	_apply_hangar(saved.payload)
	hangar_generation = int(saved.generation)
	_notify_hangar()
	return true

func checkpoint_summary() -> Dictionary:
	var saved := _checkpoint_store.load_latest(run_save_path, HangarCheckpoint.valid)
	return {} if saved.is_empty() else {"ended": saved.payload.ended or saved.payload.completed, "pending": saved.payload.pending, "node": saved.payload.current}

func prepare_checkpoint_resume() -> bool:
	return not fleet.is_empty() and not run_ended

func buy_equipment(key: String, rank := 1) -> bool:
	if key in HangarResearch.DEFERRED_PURCHASES:
		return false
	var item := SlotCatalog.find_equipment(key, rank)
	if not _can_refit() or not is_shipyard_node(current_node_id) or not SlotCatalog.unlocked(item, research_grants()) or credits < int(item.price):
		return false
	var data := hangar_snapshot()
	var uid := str(next_equipment_id)
	data.equipment[uid] = {"uid": uid, "equipment_id": key, "rank": rank, "hp": float(item.hit_points)}
	data.next_equipment_id += 1
	data.credits -= int(item.price)
	return _commit_hangar(data)

func equipment_location(uid: String) -> Dictionary:
	for owned: HangarShip in fleet:
		for slot in owned.mounts:
			if owned.mounts[slot].uid == uid:
				return {"ship_id": owned.id, "slot": slot}
	return {}

func fit_equipment(ship_id: int, slot_id: String, uid: String) -> bool:
	if not _can_refit():
		return false
	var target := owned_ship(ship_id)
	if target == null:
		return false
	var slot := {}
	for candidate: Dictionary in target.chassis.slots:
		if candidate.id == slot_id:
			slot = candidate
	if slot.is_empty():
		return false
	if not uid.is_empty():
		if not equipment_inventory.has(uid):
			return false
		var instance: Dictionary = equipment_inventory[uid]
		var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
		if item.id in HangarResearch.DEFERRED_PURCHASES:
			return false
		if not SlotCatalog.compatible(slot, item) or not SlotCatalog.unlocked(item, research_grants()):
			return false
	var data := hangar_snapshot()
	for entry: Dictionary in data.ships:
		var armor_before := _fitted_integrity(entry, data.equipment)
		for key in entry.mounts.keys():
			if entry.mounts[key] == uid or (int(entry.id) == ship_id and key == slot_id):
				if HangarTrade.has_load(data.equipment[entry.mounts[key]]):
					last_save_error = "Deliver passengers/cargo first"
					return false # Deliver occupied cabins/holds before removing them.
				entry.mounts.erase(key)
		if int(entry.id) == ship_id and not uid.is_empty():
			entry.mounts[slot_id] = uid
		entry.hull_hp += _fitted_integrity(entry, data.equipment) - armor_before
		if entry.hull_hp < 0:
			return false
	return _commit_hangar(data)

func _fitted_integrity(entry: Dictionary, inventory: Dictionary) -> float:
	var total := 0.0
	for uid in entry.mounts.values():
		var instance: Dictionary = inventory[uid]
		total += SlotCatalog.stats_for(instance.equipment_id, int(instance.rank)).integrity
	return total

func repair_equipment(uid: String) -> bool:
	if not _can_refit() or not equipment_inventory.has(uid) or not equipment_location(uid).is_empty():
		return false
	var instance: Dictionary = equipment_inventory[uid]
	var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
	var price := ceili(float(item.hit_points) - float(instance.hp))
	if price <= 0 or credits < price:
		return false
	var data := hangar_snapshot()
	data.credits -= price
	data.equipment[uid].hp = float(item.hit_points)
	return _commit_hangar(data)

func sell_equipment(uid: String) -> bool:
	if not _can_refit() or not equipment_inventory.has(uid) or not equipment_location(uid).is_empty() or HangarTrade.has_load(equipment_inventory[uid]):
		return false
	var instance: Dictionary = equipment_inventory[uid]
	var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
	var data := hangar_snapshot()
	data.credits += floori(float(item.price) * 0.5 * float(instance.hp) / float(item.hit_points))
	data.equipment.erase(uid)
	return _commit_hangar(data)

func buy_chassis(key: String) -> bool:
	var chassis := SlotCatalog.find_chassis(key)
	if not _can_refit() or not is_shipyard_node(current_node_id) or chassis.is_empty() or int(chassis.command) > 0 or credits < int(chassis.price) or used_command() + int(chassis.command_cost) > command_limit():
		return false
	var data := hangar_snapshot()
	var candidate := HangarShip.new()
	candidate.initialize_chassis(key, next_ship_id)
	candidate.formation = Vector2(fleet.size() % 3 - 1, floori(fleet.size() / 3.0))
	data.ships.append(candidate.to_hangar_data())
	data.next_ship_id += 1
	data.credits -= int(chassis.price)
	return _commit_hangar(data)

func salvage_hangar_ship(ship_id: int) -> bool:
	var target := owned_ship(ship_id)
	if not _can_refit() or target == null or target.flagship:
		return false
	var data := hangar_snapshot()
	HangarTrade.settle_losses(data, [ship_id])
	data.ships = data.ships.filter(func(entry: Dictionary) -> bool: return int(entry.id) != ship_id)
	data.credits += floori(float(target.chassis.price) * 0.5 * maxf(0, target.hull_hp) / target.hull_max)
	# Equipment is returned to stock, retaining its instance identity and damage.
	return _commit_hangar(data)

func owned_ship(ship_id: int) -> HangarShip:
	for owned: HangarShip in fleet:
		if owned.id == ship_id:
			return owned
	return null

func _can_refit() -> bool:
	return not run_id.is_empty() and not battle_pending and not run_ended and not completed

func command_limit() -> int:
	for owned: HangarShip in fleet:
		if owned.flagship:
			return int(owned.chassis.command)
	return 0

func used_command() -> int:
	var total := 0
	for owned: HangarShip in fleet:
		if not owned.flagship:
			total += int(owned.chassis.command_cost)
	return total

func get_deployed_fleet() -> Array[FleetShip]:
	return fleet.filter(func(owned: FleetShip) -> bool: return owned.is_alive())

func is_ship_deployed(owned: FleetShip) -> bool:
	return fleet.has(owned) and owned.is_alive()

func deployment_error() -> String:
	if run_ended or completed:
		return "Run ended"
	if not fleet.any(func(owned: FleetShip) -> bool: return owned.is_flagship() and owned.is_alive()):
		return "Flagship lost"
	if used_command() > command_limit():
		return "Command limit"
	if not fleet.any(func(owned: FleetShip) -> bool: return not owned.get_stats().weapons.is_empty() or HangarCarriers.has_bay(owned)):
		return "Equip a weapon"
	for owned: HangarShip in fleet:
		for instance: Dictionary in owned.mounts.values():
			if instance.equipment_id in HangarResearch.DEFERRED_PURCHASES:
				return "Unequip deferred equipment"
	return ""

func is_run_lost() -> bool:
	return run_ended

func repair_ship(owned: FleetShip) -> bool:
	if not _can_refit() or not fleet.has(owned) or not owned.is_alive() or not owned.needs_repair() or credits < owned.repair_cost():
		return false
	var before := hangar_snapshot()
	credits -= owned.repair_cost()
	owned.repair()
	if not save_run_checkpoint():
		_apply_hangar(before)
		return false
	_notify_hangar()
	return true

func move_ship(owned: FleetShip, position: Vector2) -> void:
	if not _can_refit() or not fleet.has(owned) or not position.is_finite():
		return
	var old := owned.formation
	owned.formation = position.clamp(Vector2(-5, -4), Vector2(5, 4))
	if not save_run_checkpoint():
		owned.formation = old
	fleet_changed.emit()

func set_research_focus(key: String) -> bool:
	if not _can_refit() or not HangarResearch.eligible(key, hangar_snapshot().research):
		return false
	var data := hangar_snapshot()
	data.research.research_focus = key
	_allocate_research(data.research)
	return _commit_hangar(data)

func _allocate_research(progress: Dictionary) -> void:
	var key: String = progress.research_focus
	if key.is_empty() or not HangarResearch.eligible(key, progress, true):
		return
	var required := ResearchFocusRules.cost(key, progress)
	var value := float(progress.research_progress.get(key, 0))
	var amount := minf(float(progress.research_points), required - value)
	progress.research_points -= amount
	value += amount
	if value < required:
		progress.research_progress[key] = value
		return
	progress.research_ids.append(key)
	progress.research_progress.erase(key)
	progress.research_focus = ""
	var definition := GameDefinitions.find("research", key)
	if not definition.family_id.is_empty():
		progress.branch_choices[definition.family_id] = definition.path_id
	for project in progress.research_progress.keys():
		if not HangarResearch.eligible(project, progress, true):
			progress.research_progress.erase(project)

func research_grants() -> Dictionary:
	return ResearchRules.resolve(current_research_ids, HangarResearch.catalog())

func set_planned_destination(node_id: int) -> bool:
	if not _can_refit() or not get_reachable_nodes(current_node_id).has(node_id):
		return false
	planned_destination_node_id = node_id
	travel_plan_changed.emit()
	return true

func node_preview(node_id: int) -> Dictionary:
	var node := campaign_node(node_id)
	var encounter := get_frozen_encounter(node_id)
	return {"title": node.get("name", "Destination"), "text": "%s | %.0f days" % [str(node.get("type", "")).capitalize(), research_travel_time(current_node_id, node_id)] + (" | %d cr" % int(encounter.rewards.credits) if not encounter.is_empty() else "")}

func travel_to(node_id: int) -> bool:
	if not _can_refit() or not can_deploy() or not get_reachable_nodes(current_node_id).has(node_id):
		return false
	var data := hangar_snapshot()
	var yield_rp := ScienceRules.journey_rp(ScienceRules.snapshot(get_deployed_fleet()), research_travel_time(current_node_id, node_id))
	HangarTrade.depart(data, campaign_node(current_node_id), campaign_node(node_id))
	data.planned = -1
	if not get_frozen_encounter(node_id).is_empty():
		data.destination = node_id
		data.pending = true
		data.pending_encounter = get_frozen_encounter(node_id)
		data.journey_rp = yield_rp
	else:
		data.current = node_id
		data.visited.append(node_id)
		data.research.research_points += yield_rp
		HangarTrade.arrive(data, campaign_node(node_id))
		_allocate_research(data.research)
	return _commit_hangar(data)

func set_destination(node_id: int) -> bool:
	return travel_to(node_id)

func battle_support_context() -> Dictionary:
	var encounter := get_frozen_encounter(destination_node_id)
	# No material drops, extraction, inventory-consuming abilities or grid bonuses.
	return {"credits_only": true, "energy_efficiency": energy_efficiency(), "enemy_roles": encounter.get("enemy_roles", false), "doctrine_pool": battle_reserves.get(str(destination_node_id), {}), "encounter_plan": encounter if encounter.has("arena_layout") else {}}

func battle_material_rewards() -> Array[int]:
	return []

func allied_salvage_chance() -> float:
	return 0.0

func battle_identity() -> String:
	return "%s/%d" % [run_id, destination_node_id]

func update_battle_support(_simulation: BattleSimulation) -> void:
	pass

func settle_battle(simulation: BattleSimulation) -> bool:
	if not battle_pending or simulation.battle_id != battle_identity() or simulation.phase == BattleSimulation.Phase.COMBAT:
		return false
	var data := hangar_snapshot()
	var lost: Array[int] = []
	data.battle_reserves[str(destination_node_id)] = simulation.doctrines.pool.duplicate(true)
	for owned: HangarShip in fleet:
		if not owned.is_alive():
			lost.append(owned.id)
			if owned.flagship:
				data.ended = true
	HangarTrade.settle_losses(data, lost)
	for owned: HangarShip in fleet:
		if owned.id in lost:
			for instance: Dictionary in owned.mounts.values():
				data.equipment.erase(instance.uid)
	data.ships = data.ships.filter(func(entry: Dictionary) -> bool: return int(entry.id) not in lost)
	var won: bool = simulation.phase == BattleSimulation.Phase.VICTORY and not data.ended
	if won:
		data.credits += int(get_frozen_encounter(destination_node_id).rewards.credits)
		var loot := equipment_loot(destination_node_id)
		if not loot.is_empty():
			var uid := str(data.next_equipment_id)
			data.equipment[uid] = {"uid": uid, "equipment_id": loot.id, "rank": int(loot.rank), "hp": float(loot.hit_points)}
			data.next_equipment_id += 1
		data.current = destination_node_id
		data.visited.append(destination_node_id)
		data.research.research_points += journey_rp
		var node := campaign_node(destination_node_id)
		if node.kind == "boss":
			data.research.story_flags[["boss_i_defeated", "boss_ii_defeated", "boss_iii_defeated"][int(node.act) - 1]] = true
		data.completed = destination_node_id == FINAL_NODE_ID
		HangarTrade.arrive(data, node)
		_allocate_research(data.research)
	data.destination = -1
	data.pending = false
	data.pending_encounter = {}
	data.journey_rp = 0
	if not _save_hangar(data):
		return false
	last_battle_report.clear()
	last_equipment_loot = equipment_loot(destination_node_id).get("name", "") if won else ""
	for actor in simulation.players:
		last_battle_report.append({"ship": actor.owned_ship, "damage": actor.damage_dealt, "taken": actor.damage_taken,
			"repair_damage": actor.permanent_damage_taken, "deflected": actor.damage_deflected(), "weapons": actor.weapon_damage.duplicate(), "destroyed": not actor.is_alive()})
	_apply_hangar(data)
	_notify_hangar()
	return true

func equipment_loot(node_id: int) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var grants := research_grants()
	for item in SlotCatalog.equipment():
		if item.id not in HangarResearch.DEFERRED_PURCHASES and SlotCatalog.unlocked(item, grants) and fleet.any(func(owned: FleetShip) -> bool:
			return (owned as HangarShip).chassis.slots.any(func(slot: Dictionary) -> bool: return SlotCatalog.compatible(slot, item))):
			candidates.append(item)
	if candidates.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed + node_id * 7919
	return candidates[rng.randi_range(0, candidates.size() - 1)]

func cancel_battle(_surviving_player_ship_count := -1, _terminal_defeat := false, _staged: Dictionary = {}) -> bool:
	var data := hangar_snapshot()
	data.pending = false
	data.pending_encounter = {}
	data.destination = -1
	data.journey_rp = 0
	return _commit_hangar(data)


func _new_run_seed() -> int:
	var random := RandomNumberGenerator.new()
	random.randomize()
	return random.randi()


func _apply_campaign_geometry() -> void:
	NODE_POSITIONS.clear()
	NODE_COLUMNS.clear()
	GRAPH_EDGES.clear()
	CONVERGENCE_NODE_IDS.clear()
	for node in campaign_dag.nodes:
		NODE_POSITIONS.append(Vector2(node.position[0], node.position[1]))
		NODE_COLUMNS.append(int(node.row))
	for edge in campaign_dag.edges:
		GRAPH_EDGES.append(Vector2i(int(edge[0]), int(edge[1])))
	for id in campaign_dag.staging:
		CONVERGENCE_NODE_IDS.append(int(id))
	FINAL_NODE_ID = int(campaign_dag.final)


func current_act() -> int:
	var node := campaign_node(current_node_id)
	var act := maxi(1, int(node.get("act", 1)))
	# Securing the act boss opens the next act's first fork immediately.
	return mini(3, act + 1) if node.get("kind") == "boss" else act


func node_visible(node_id: int) -> bool:
	return not campaign_active or int(campaign_node(node_id).get("act", 4)) <= current_act()


func edge_preview(source: int, target: int) -> Dictionary:
	if campaign_active:
		for route in campaign_dag.routes:
			if int(route.from) == source and int(route.to) == target:
				return route.duplicate(true)
	return {}


func research_travel_time(from_id: int, to_id: int) -> float:
	var steps := research_travel_distance(from_id, to_id)
	if steps <= 0:
		return 0.0
	if campaign_active:
		var from := campaign_node(from_id)
		var to := campaign_node(to_id)
		var lateral := absf(float(to.position[1]) - float(from.position[1]))
		return steps * (2.0 + clampi(roundi(lateral / 0.34), 0, 2))
	return steps * 3.0


func research_travel_distance(from_id: int, to_id: int) -> int:
	if campaign_active:
		return maxi(0, int(campaign_node(to_id).get("row", 0)) - int(campaign_node(from_id).get("row", 0)))
	if from_id < 0 or to_id < 0 or from_id >= NODE_COLUMNS.size() or to_id >= NODE_COLUMNS.size():
		return 0
	return maxi(0, NODE_COLUMNS[to_id] - NODE_COLUMNS[from_id])


func get_frozen_encounter(node_id: int) -> Dictionary:
	return frozen_encounters.get(str(node_id), {}).duplicate(true)


func battle_simulation_seed() -> int:
	return int(get_frozen_encounter(destination_node_id).get("seed", "0"))


func battle_objective_ids() -> Array[String]:
	return EncounterGenerator.objective_ids(get_frozen_encounter(destination_node_id))


func is_modal_ui_open() -> bool:
	var current_scene := get_tree().current_scene
	return current_scene != null and _node_contains_visible_modal(current_scene, current_scene)


func _node_contains_visible_modal(node: Node, scene_root: Node) -> bool:
	if node != scene_root and node is Window and node.visible:
		return true
	if (
		node != scene_root
		and node is Control
		and node.is_visible_in_tree()
		and (node.name in [&"GraphModal", &"VictoryDialog", &"DefeatDialog", &"QuitConfirmOverlay"] or node.is_in_group("modal_ui"))
	):
		return true
	for child in node.get_children():
		if _node_contains_visible_modal(child, scene_root):
			return true
	return false


func get_reachable_nodes(from_node_id: int) -> Array[int]:
	var reachable_nodes: Array[int] = []
	for edge in GRAPH_EDGES:
		if edge.x == from_node_id:
			reachable_nodes.append(edge.y)
	return reachable_nodes


func campaign_node(node_id: int) -> Dictionary:
	if not campaign_active or node_id < 0 or node_id >= campaign_dag.nodes.size():
		return {}
	return campaign_dag.nodes[node_id].duplicate(true)


func energy_efficiency() -> float:
	return float(research_grants().modifiers.get("energy_efficiency", {}).get("value", 0.0))


func can_deploy() -> bool:
	return not run_ended and deployment_error().is_empty() and get_deployed_fleet().any(func(owned: FleetShip) -> bool:
		return owned.is_alive() and (not owned.get_stats(laser_upgrade_level).weapons.is_empty() or HangarCarriers.has_bay(owned)))


func set_destroy_all_neutral_targets(enabled: bool) -> bool:
	var previous := destroy_all_neutral_targets
	destroy_all_neutral_targets = enabled
	if not save_run_checkpoint():
		destroy_all_neutral_targets = previous
		return false
	return true

func run_progress_snapshot() -> Dictionary:
	return hangar_snapshot().research

func is_shipyard_node(node_id: int) -> bool:
	return not battle_pending and not run_ended and node_id == current_node_id and campaign_node(node_id).get("inhabited", false)
