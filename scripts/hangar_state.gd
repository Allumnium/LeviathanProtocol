extends Node

signal fleet_changed
signal credits_changed
signal research_changed
signal travel_plan_changed

enum Difficulty { EASY, MEDIUM, HARD }
const ExpeditionSimulationScript = preload("res://scripts/expedition_simulation.gd")
const ShipLoadouts = preload("res://scripts/ship_loadouts.gd")
const STARTING_MISSILES := 30
const MISSILE_PACK := 10
const MISSILE_PACK_PRICE := 50
var fleet: Array[FleetShip] = []
var squadrons: Array = []
var next_ship_id := 1
var credits := 600
var missiles := 0
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
var research_offer: Array[String] = []
var research_points := 0.0
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
var battle_auto_pan := true
var battle_auto_zoom := true
var tutorials_enabled := true
var battle_speed := 1
var destroy_all_neutral_targets := false
var run_save_path := "user://expedition_run.json"
var last_save_error := ""
var last_event_result := ""
# Set by the main menu's New Run flow; the game screen shows the charter briefing once.
var pending_intro := false
# UI-only: refresh the arrived location when returning from an arrival battle.
var arrival_notice := ""
var research_completion_notices: Array[String] = []
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
var navigation: Dictionary = {}
var pending_encounter: Dictionary = {}
var run_score: Dictionary = {}
var expedition_simulation

func _ready() -> void:
	run_save_path = "user://expedition_run.json"
	run_seed = 1


func start_new_run(selected_difficulty: int = Difficulty.MEDIUM, seed_value: int = -1, _use_campaign := true, flagship_id := "flagship_basic") -> bool:
	var selected := SlotCatalog.find_chassis(flagship_id)
	if selected_difficulty not in [0, 1, 2] or seed_value < -1 or selected.is_empty() or not selected.flagship:
		push_error("Cannot start a run with invalid difficulty, seed or flagship.")
		return false
	var before := hangar_snapshot()
	var previous_generation := hangar_generation
	run_seed = _new_run_seed() if seed_value == -1 else seed_value
	expedition_simulation = ExpeditionSimulationScript.new()
	if not expedition_simulation.configure(run_seed):
		var setup_error: String = expedition_simulation.last_error
		if not before.is_empty():
			run_seed = int(before.seed)
			difficulty = int(before.difficulty) as Difficulty
			navigation = before.get("navigation", {}).duplicate(true)
			_build_campaign()
			_apply_hangar(before, true)
		hangar_generation = previous_generation
		last_save_error = setup_error
		return false
	difficulty = selected_difficulty as Difficulty
	run_id = Crypto.new().generate_random_bytes(16).hex_encode()
	credits = 700
	missiles = STARTING_MISSILES
	run_score = RunScore.initial()
	current_research_ids = ["foundation"]
	research_completion_notices.clear()
	research_offer.clear()
	research_points = 0.0
	story_flags.clear()
	research_branch_choices.clear()
	fleet.clear()
	squadrons.clear()
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
	navigation = SwarmNavigation.initial()
	pending_encounter = {}
	last_battle_report.clear()
	last_equipment_loot = ""
	_build_campaign()
	current_research_ids.assign(["foundation"])
	# Every starting ship arrives fully fitted with its class's default loadout.
	var lead := _add_chassis(flagship_id, true)
	lead.formation = Vector2.ZERO
	_install_loadout(lead, ShipLoadouts.default_for(flagship_id))
	var transport := _add_chassis("transport")
	transport.formation = Vector2(-0.85, 0)
	_install_loadout(transport, ShipLoadouts.default_for("transport"))
	var fighter := _add_chassis("fighter")
	fighter.formation = Vector2(0, -0.8)
	_install_loadout(fighter, ShipLoadouts.default_for("fighter"))
	for index in range(10):
		var drone := _add_chassis("drone")
		drone.formation = Vector2(1.6, 0) + HangarSquadrons.box_offset(index, 10, 0.6)
		_install_loadout(drone, ShipLoadouts.default_for("drone"))
	squadrons = HangarSquadrons.initial(hangar_snapshot())
	_apply_squadron_orders()
	hangar_generation = -1
	if not save_run_checkpoint():
		if not before.is_empty():
			run_seed = int(before.seed)
			difficulty = int(before.difficulty) as Difficulty
			navigation = before.get("navigation", {}).duplicate(true)
			_build_campaign()
			_apply_hangar(before, true)
		hangar_generation = previous_generation
		return false
	_notify_hangar()
	return true

func _install_loadout(owned: HangarShip, loadout: Dictionary) -> void:
	for slot_id: String in loadout.get("mounts", {}):
		var parsed := ShipLoadouts.parse_key(str(loadout.mounts[slot_id]))
		var instance := _new_equipment(parsed.id, parsed.rank)
		if not instance.is_empty():
			owned.mounts[slot_id] = instance
	owned.rebuild_units()
	owned.hull_hp = owned.hull_max

func _build_campaign() -> void:
	campaign_active = true
	campaign_dag = CampaignContent.populate(CampaignGraph.generate(run_seed, 2 if not navigation.is_empty() else 1), run_seed)
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
	var instance := {"uid": uid, "equipment_id": key, "rank": rank}
	equipment_inventory[uid] = instance
	return instance

func hangar_snapshot() -> Dictionary:
	var ships: Array = []
	for owned: HangarShip in fleet:
		ships.append(owned.to_hangar_data())
	var data := {"format": "physical_hangar", "version": 2, "run_id": run_id, "seed": str(run_seed),
		"difficulty": difficulty, "credits": credits, "missiles": missiles, "ships": ships, "equipment": equipment_inventory.duplicate(true),
		"squadrons": squadrons.duplicate(true),
		"next_ship_id": next_ship_id, "next_equipment_id": next_equipment_id,
		"current": current_node_id, "destination": destination_node_id, "planned": planned_destination_node_id,
		"visited": visited_nodes.duplicate(), "pending": battle_pending, "ended": run_ended, "completed": completed,
		"journey_rp": journey_rp, "pending_encounter": get_frozen_encounter(destination_node_id) if battle_pending else {},
		"battle_reserves": battle_reserves.duplicate(true), "research": {"research_ids": current_research_ids.duplicate(),
		"research_offer": research_offer.duplicate(),
		"research_points": research_points,
		"story_flags": story_flags.duplicate(), "branch_choices": research_branch_choices.duplicate()}}
	if not navigation.is_empty():
		data.navigation = navigation.duplicate(true)
	if not run_score.is_empty():
		data.score = run_score.duplicate(true)
	if expedition_simulation != null and expedition_simulation.state != null:
		data.expedition = expedition_simulation.state.snapshot()
	return data

func _apply_hangar(data: Dictionary, restore_expedition := false, announce_research := false) -> void:
	if announce_research:
		for id: String in data.research.research_ids:
			if id != "foundation" and id not in current_research_ids:
				research_completion_notices.append(id)
	run_id = data.run_id
	run_seed = int(data.seed)
	difficulty = int(data.difficulty) as Difficulty
	credits = int(data.credits)
	missiles = int(data.get("missiles", 0))
	run_score = data.get("score", {}).duplicate(true)
	next_ship_id = int(data.next_ship_id)
	next_equipment_id = int(data.next_equipment_id)
	equipment_inventory = data.equipment.duplicate(true)
	fleet.clear()
	var earned_modifiers: Dictionary = ResearchRules.resolve(data.research.research_ids, HangarResearch.catalog()).modifiers
	for entry: Dictionary in data.ships:
		var owned := HangarShip.new()
		owned.initialize_chassis(entry.chassis, int(entry.id), entry.flagship)
		owned.formation = Vector2(entry.formation[0], entry.formation[1])
		for slot in entry.mounts:
			owned.mounts[slot] = equipment_inventory[entry.mounts[slot]]
		owned.rebuild_units()
		owned.hull_hp = entry.hull_hp
		owned.research_modifiers = earned_modifiers
		fleet.append(owned)
	squadrons = data.squadrons.duplicate(true) if data.has("squadrons") else HangarSquadrons.initial(data)
	for group: Dictionary in squadrons:
		group.members = group.members.map(func(id: Variant) -> int: return int(id))
		group.overrides = group.overrides.map(func(id: Variant) -> int: return int(id))
	_apply_squadron_orders()
	current_node_id = int(data.current)
	destination_node_id = int(data.destination)
	planned_destination_node_id = int(data.planned)
	visited_nodes.assign(data.visited)
	battle_pending = data.pending
	run_ended = data.ended
	completed = data.completed
	journey_rp = data.journey_rp
	battle_reserves = data.get("battle_reserves", {}).duplicate(true)
	navigation = data.get("navigation", {}).duplicate(true)
	pending_encounter = data.get("pending_encounter", {}).duplicate(true)
	current_research_ids.assign(data.research.research_ids)
	research_offer.assign(data.research.research_offer)
	research_points = float(data.research.get("research_points", 0.0))
	story_flags.assign(data.research.story_flags)
	research_branch_choices.assign(data.research.branch_choices)
	player_ship_count = fleet.size()
	battle_aliens.clear()
	if battle_pending:
		if navigation.is_empty() and data.has("pending_encounter"):
			frozen_encounters[str(destination_node_id)] = data.pending_encounter.duplicate(true)
		battle_aliens = EncounterGenerator.initial_fleet(pending_encounter if pending_encounter.has("expedition_event_id")
			else get_frozen_encounter(destination_node_id))
	if restore_expedition and not data.has("expedition"):
		expedition_simulation = null
	elif data.has("expedition") and (restore_expedition or expedition_simulation == null
			or expedition_simulation.state == null
			or expedition_simulation.state.seed != int(data.expedition.seed)):
		expedition_simulation = ExpeditionSimulationScript.new()
		if not expedition_simulation.configure(run_seed) or not expedition_simulation.restore(data.expedition):
			last_save_error = expedition_simulation.last_error
			push_error("Could not restore the saved expedition state: " + last_save_error)

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
	_apply_hangar(proposal, false, true)
	_notify_hangar()
	return true

func _notify_hangar() -> void:
	player_ship_count = fleet.size()
	fleet_changed.emit()
	credits_changed.emit()
	research_changed.emit()
	travel_plan_changed.emit()

func _apply_squadron_orders() -> void:
	for owned: HangarShip in fleet:
		var group := HangarSquadrons.for_ship(squadrons, owned.id)
		owned.squadron_id = int(group.get("id", 0))
		owned.stance = str(group.get("stance", "seek"))

func set_squadron_stance(group_id: int, stance: String) -> bool:
	if not _can_refit() or stance not in HangarSquadrons.STANCES:
		last_save_error = "Squadron orders are unavailable."
		return false
	var data := hangar_snapshot()
	var group := HangarSquadrons.find(data.squadrons, group_id)
	if group.is_empty():
		last_save_error = "Unknown squadron."
		return false
	group.stance = stance
	return _commit_hangar(data)

func assign_squadron(ship_id: int, group_id := 0) -> bool:
	if not _can_refit():
		last_save_error = "Squadron assignments are unavailable."
		return false
	var owned := owned_ship(ship_id)
	var data := hangar_snapshot()
	var target := HangarSquadrons.find(data.squadrons, group_id)
	if owned == null or (group_id != 0 and (target.is_empty() or target.chassis != owned.chassis_id)):
		last_save_error = "Choose a squadron of the same ship class."
		return false
	var previous := HangarSquadrons.for_ship(data.squadrons, ship_id)
	if previous.id == group_id or (group_id == 0 and previous.members.size() == 1):
		last_save_error = "Already assigned."
		return false
	previous.members.erase(ship_id)
	previous.overrides.erase(ship_id)
	if group_id == 0:
		var id := 1
		for group: Dictionary in data.squadrons:
			id = maxi(id, int(group.id) + 1)
		target = previous.duplicate(true)
		target.id = id
		target.members = []
		target.overrides = []
		data.squadrons.append(target)
	for entry: Dictionary in data.ships:
		if int(entry.id) == ship_id:
			HangarSquadrons.add_ship(data, entry, int(target.id))
			break
	return _commit_hangar(data)

func refit_squadron(group_id: int, loadout_id: String, reset_overrides := false) -> bool:
	if not _require_shipyard():
		return false
	var data := hangar_snapshot()
	var group := HangarSquadrons.find(data.squadrons, group_id)
	var loadout := ShipLoadouts.find(str(group.get("chassis", "")), loadout_id)
	if group.is_empty() or loadout.is_empty():
		last_save_error = "Unknown squadron loadout."
		return false
	if not ShipLoadouts.available(loadout, current_research_ids):
		last_save_error = "Research this loadout's equipment first."
		return false
	var overrides: Array = group.overrides.duplicate()
	group.loadout = loadout_id
	for id: int in group.members:
		if reset_overrides or id not in overrides:
			if not _stage_refit(data, id, loadout.mounts, true):
				return false
		HangarSquadrons.update_override(data, id)
	return _commit_hangar(data)

func squadron_repair_cost(group_id: int) -> int:
	var cost := 0
	for id: int in HangarSquadrons.find(squadrons, group_id).get("members", []):
		var owned := owned_ship(id)
		if owned != null and owned.is_alive():
			cost += owned.repair_cost()
	return cost

func repair_squadron(group_id: int) -> bool:
	if not _require_shipyard():
		return false
	var data := hangar_snapshot()
	var group := HangarSquadrons.find(data.squadrons, group_id)
	if group.is_empty():
		last_save_error = "Unknown squadron."
		return false
	var cost := squadron_repair_cost(group_id)
	if cost <= 0 or credits < cost:
		last_save_error = "No repairs needed." if cost <= 0 else "Not enough credits. Cost: %d." % cost
		return false
	for entry: Dictionary in data.ships:
		if int(entry.id) in group.members:
			var owned := owned_ship(int(entry.id))
			if owned.is_alive():
				entry.hull_hp = owned.hull_max
	data.credits -= cost
	return _commit_hangar(data)

func load_run_checkpoint() -> bool:
	var saved := _checkpoint_store.load_latest(run_save_path, HangarCheckpoint.valid)
	if saved.is_empty():
		last_save_error = "No hangar checkpoint."
		return false
	run_seed = int(saved.payload.seed)
	research_completion_notices.clear()
	difficulty = int(saved.payload.difficulty) as Difficulty
	navigation = saved.payload.get("navigation", {}).duplicate(true)
	_build_campaign()
	_apply_hangar(saved.payload, true)
	hangar_generation = int(saved.generation)
	_notify_hangar()
	return true

func checkpoint_summary() -> Dictionary:
	var saved := _checkpoint_store.load_latest(run_save_path, HangarCheckpoint.valid)
	return {} if saved.is_empty() else {"ended": saved.payload.ended or saved.payload.completed,
		"pending": saved.payload.pending, "node": saved.payload.current,
		"expedition": saved.payload.has("expedition")}

func save_expedition_checkpoint() -> bool:
	if expedition_simulation == null or expedition_simulation.state == null:
		last_save_error = "No active expedition state."
		return false
	return save_run_checkpoint()

func refuel_expedition() -> bool:
	if expedition_simulation == null or expedition_simulation.state == null:
		last_save_error = "No active expedition state."
		return false
	last_save_error = station_service_error("refuel")
	if not last_save_error.is_empty():
		return false
	var expedition_state = expedition_simulation.state
	var missing: float = expedition_state.fuel_capacity - expedition_state.fuel
	if missing <= 0.000001:
		last_save_error = "The expedition fuel tanks are already full."
		return false
	var price := int(ceil(missing * 2.0))
	if credits < price:
		last_save_error = "Not enough credits to refuel. Cost: %d." % price
		return false
	var proposal := hangar_snapshot()
	proposal.credits = credits - price
	proposal.expedition.fuel = expedition_state.fuel_capacity
	if not _save_hangar(proposal):
		return false
	credits = int(proposal.credits)
	expedition_state.fuel = expedition_state.fuel_capacity
	credits_changed.emit()
	return true

func buy_missiles() -> bool:
	last_save_error = station_service_error("ammunition")
	if not last_save_error.is_empty():
		return false
	if credits < MISSILE_PACK_PRICE:
		last_save_error = "Not enough credits. Cost: %d." % MISSILE_PACK_PRICE
		return false
	if missiles > 2147483647 - MISSILE_PACK:
		last_save_error = "Missile storage limit reached."
		return false
	var proposal := hangar_snapshot()
	proposal.credits -= MISSILE_PACK_PRICE
	proposal.missiles += MISSILE_PACK
	return _commit_hangar(proposal)

func prepare_checkpoint_resume() -> bool:
	if fleet.is_empty() or run_ended:
		return false
	if expedition_simulation == null:
		return true
	var previous: Dictionary = expedition_simulation.state.snapshot()
	if not expedition_simulation.set_pause(ExpeditionSimulationScript.State.PauseReason.USER, true):
		last_save_error = expedition_simulation.last_error
		return false
	if not save_expedition_checkpoint():
		if not expedition_simulation.restore(previous):
			push_error("Could not restore the expedition after a failed Continue save.")
		return false
	return true

func resolve_expedition_event(event_id: String, choice: String) -> bool:
	last_event_result = ""
	if expedition_simulation == null or expedition_simulation.state == null:
		last_save_error = "No active expedition state."
		return false
	if run_ended or completed or battle_pending:
		last_save_error = "Encounter choices are unavailable during combat or after the run ends."
		return false
	if ExpeditionSimulationScript.State.PauseReason.SAVE_ERROR in expedition_simulation.state.pause_reasons:
		last_save_error = "Retry the failed save before resolving this encounter."
		return false
	var event: Dictionary = ExpeditionSimulationScript.Events.find(expedition_simulation.events, event_id)
	var selected: Dictionary = ExpeditionSimulationScript.Events.option(event, choice)
	var effects: Dictionary = selected.get("effects", {})
	if credits < int(effects.get("requires_credits", 0)):
		last_save_error = "Not enough credits."
		return false
	var staged = ExpeditionSimulationScript.new()
	if not staged.configure(run_seed) or not staged.restore(expedition_simulation.state.snapshot()) \
			or not staged.resolve_event(event_id, choice):
		last_save_error = staged.last_error
		return false
	var proposal := hangar_snapshot()
	proposal.expedition = staged.state.snapshot()
	var summary: PackedStringArray = []
	if effects.has("credits") and int(effects.credits) != 0:
		if int(effects.credits) > 0:
			RunScore.earn_credits(proposal, int(effects.credits))
		else:
			proposal.credits += int(effects.credits)
		summary.append("%+d credits" % int(effects.credits))
	if effects.has("fuel"):
		summary.append("%+.1f fuel" % (float(proposal.expedition.fuel) - expedition_simulation.state.fuel))
	if effects.has("rescue_ship"):
		summary.append(_rescue_ship(proposal, str(effects.rescue_ship)))
	if effects.has("missiles"):
		proposal.missiles += int(effects.missiles)
		summary.append("+%d missiles" % int(effects.missiles))
	if float(effects.get("research", 0.0)) > 0.0:
		_allocate_research(proposal.research, float(effects.research))
		summary.append("+%s RP" % ScienceRules.format_points(float(effects.research)))
	if float(effects.get("hull_damage", 0.0)) > 0.0:
		for entry: Dictionary in proposal.ships:
			var owned := owned_ship(int(entry.id))
			if owned != null and owned.is_alive():
				entry.hull_hp = maxf(0.0, float(entry.hull_hp) - owned.hull_max * float(effects.hull_damage))
		summary.append("Hull damage %d%%" % roundi(float(effects.hull_damage) * 100))
	if effects.has("flag"):
		summary.append("New destination revealed")
	if effects.has("combat"):
		var encounter := _expedition_encounter(event_id, effects)
		if encounter.is_empty():
			last_save_error = "Could not generate the encounter."
			return false
		proposal.pending = true
		proposal.pending_encounter = encounter
	if not _save_hangar(proposal):
		return false
	var hangar_changed := false
	for key in ["credits", "research", "hull_damage", "combat", "rescue_ship", "missiles"]:
		hangar_changed = hangar_changed or effects.has(key)
	if hangar_changed:
		_apply_hangar(proposal, false, true)
	if not expedition_simulation.restore(proposal.expedition):
		last_save_error = expedition_simulation.last_error
		push_error("Could not apply the committed encounter choice: " + last_save_error)
		return false
	last_event_result = " · ".join(summary)
	if hangar_changed:
		_notify_hangar()
	else:
		travel_plan_changed.emit()
	return true

func _expedition_encounter(event_id: String, effects: Dictionary) -> Dictionary:
	var combat: Dictionary = effects.combat
	var index: int = expedition_simulation.events.find(ExpeditionSimulationScript.Events.find(expedition_simulation.events, event_id))
	var node_id := 1000 + maxi(0, index)
	var environment := {"version": 1, "asteroid_density": int(combat.get("asteroids", 0)),
		"solar_intensity": 1.0, "nebula": bool(combat.get("nebula", false))}
	var encounter := EncounterGenerator.generate(run_seed, node_id, int(combat.row), difficulty,
		str(combat.template), clampi(int(combat.row), 1, 14), false, environment)
	if encounter.is_empty():
		return {}
	# Hostile strength reuses the Swarm hull/shield/damage scaling.
	var strength := float(combat.get("strength", 1.0))
	if strength > 1.0:
		encounter = SwarmNavigation.encounter(encounter, (strength - 1.0) / SwarmNavigation.STRENGTH_PER_POINT)
	if combat.has("credits"):
		encounter.rewards.credits = int(combat.credits)
	for key in ["research", "fuel", "rescue_ship", "missiles"]:
		if combat.has(key):
			encounter.rewards[key] = combat[key]
	# The arena plan carries waves/objectives into the battle, as for campaign encounters.
	if not encounter.has("arena_layout"):
		encounter["arena_layout"] = "open"
	encounter["expedition_event_id"] = event_id
	encounter["complete"] = bool(effects.get("complete", false))
	return encounter

func _rescue_ship(data: Dictionary, chassis_id: String) -> String:
	var chassis := SlotCatalog.find_chassis(chassis_id)
	var loadout := ShipLoadouts.default_for(chassis_id)
	ShipLoadouts.append_ship(data, chassis_id, loadout)
	HangarSquadrons.add_ship(data, data.ships.back())
	return "%s joined the fleet" % chassis.name

func station_trade_node(location_id: String) -> Dictionary:
	if expedition_simulation == null:
		return {}
	var location: Dictionary = expedition_simulation.locations.get(location_id, {})
	if location.is_empty():
		return {}
	var value := int(location.get("goods_unit_value", 6))
	return {"id": expedition_simulation.locations.keys().find(location_id),
		"inhabited": location.kind == "station" and "trade" in location.get("services", []),
		"goods_unit_value": value if value in [3, 6, 10] else 6}

# Commits a course change; leaving a dock loads cargo/passengers atomically.
func depart_expedition(location_id: String, engage := false) -> bool:
	last_event_result = ""
	if expedition_simulation == null or expedition_simulation.state == null:
		last_save_error = "No active expedition state."
		return false
	if battle_pending or run_ended or completed:
		last_save_error = "The fleet cannot change course right now."
		return false
	var sim_state = expedition_simulation.state
	var origin: String = sim_state.docked_location_id
	var staged = ExpeditionSimulationScript.new()
	if not staged.configure(run_seed) or not staged.restore(sim_state.snapshot()) \
			or not staged.request_destination(location_id):
		last_save_error = staged.last_error
		return false
	if engage and not staged.set_pause(ExpeditionSimulationScript.State.PauseReason.USER, false):
		last_save_error = staged.last_error
		return false
	var proposal := hangar_snapshot()
	proposal.expedition = staged.state.snapshot()
	var loaded := {"cargo": 0, "passengers": 0}
	if not origin.is_empty() and staged.state.docked_location_id.is_empty():
		var before := HangarTrade.summary(proposal)
		HangarTrade.depart(proposal, station_trade_node(origin), station_trade_node(location_id))
		var after := HangarTrade.summary(proposal)
		loaded.cargo = after.cargo - before.cargo
		loaded.passengers = after.passengers - before.passengers
	if not _save_hangar(proposal):
		expedition_simulation.set_pause(ExpeditionSimulationScript.State.PauseReason.SAVE_ERROR, true)
		return false
	# Loads live on shared instance dictionaries; update them in place so the
	# live fleet (and any open view of it) is not rebuilt.
	for uid: String in proposal.equipment:
		if equipment_inventory.has(uid):
			equipment_inventory[uid]["load"] = proposal.equipment[uid].get("load", {}).duplicate(true)
			if equipment_inventory[uid].load.is_empty():
				equipment_inventory[uid].erase("load")
	if not expedition_simulation.restore(proposal.expedition):
		last_save_error = expedition_simulation.last_error
		return false
	var boarding: PackedStringArray = []
	if loaded.cargo > 0:
		boarding.append("%d cargo loaded" % loaded.cargo)
	if loaded.passengers > 0:
		boarding.append("%d passengers boarded" % loaded.passengers)
	last_event_result = " · ".join(boarding)
	travel_plan_changed.emit()
	return true

func self_repair_rate(owned: HangarShip) -> float:
	return float(owned.chassis.get("self_repair_hp_per_second", 0.0)) * ResearchUpgrades.value(owned.research_modifiers, "passive_repair_multiplier")

func expedition_fuel_multiplier() -> float:
	return float(research_grants().modifiers.get("cruise_fuel_multiplier", {}).get("value", 1.0))

func expedition_fuel_rate() -> float:
	return float(expedition_simulation.tuning.fuel_per_nav_unit) * expedition_fuel_multiplier()

func expedition_cruise_rate() -> float:
	var multiplier := float(research_grants().modifiers.get("cruise_speed_multiplier", {}).get("value", 1.0))
	return expedition_simulation.cruise_rate(multiplier)

func stranded() -> bool:
	var simulation = expedition_simulation
	return simulation != null and simulation.state != null and not battle_pending and not run_ended \
		and ExpeditionSimulationScript.State.PauseReason.FUEL in simulation.state.pause_reasons \
		and simulation.state.fuel <= 0.000001

# Nearest accessible refueling station and the disclosed tow price: the refill
# plus a base and distance fee. Towing may leave the convoy in credit debt.
func rescue_quote() -> Dictionary:
	if not stranded():
		return {}
	var simulation = expedition_simulation
	var best := {}
	var best_distance := INF
	for location: Dictionary in simulation.locations.values():
		if location.kind != "station" or "refuel" not in location.services \
				or location.id not in simulation.state.discovered_location_ids or not simulation.location_accessible(location):
			continue
		var distance: float = simulation.state.position_nu.distance_to(Vector2(location.position[0], location.position[1]))
		if distance < best_distance:
			best_distance = distance
			best = location
	if best.is_empty():
		return {}
	var refill: float = simulation.state.fuel_capacity - simulation.state.fuel
	return {"location_id": best.id, "name": best.name, "distance": best_distance,
		"fee": int(ceil(refill * 2.0 + 100.0 + best_distance * 0.2))}

func accept_rescue() -> bool:
	var quote := rescue_quote()
	if quote.is_empty():
		last_save_error = "No rescue is needed or available."
		return false
	var simulation = expedition_simulation
	var station: Dictionary = simulation.locations[quote.location_id]
	var proposal := hangar_snapshot()
	proposal.credits = credits - int(quote.fee)
	var travel: Dictionary = proposal.expedition
	travel.position_nu = [float(station.position[0]), float(station.position[1])]
	travel.docked_location_id = station.id
	travel.destination_location_id = ""
	travel.return_destination_id = ""
	travel.travel_state = ExpeditionSimulationScript.State.TravelState.DOCKED
	travel.fuel = travel.fuel_capacity
	travel.departure_choice_pending = false
	travel.pause_reasons.erase(ExpeditionSimulationScript.State.PauseReason.FUEL)
	if station.id not in travel.visited_location_ids:
		travel.visited_location_ids.append(station.id)
	if not _save_hangar(proposal):
		return false
	credits = int(proposal.credits)
	if not simulation.restore(proposal.expedition):
		last_save_error = simulation.last_error
		return false
	credits_changed.emit()
	travel_plan_changed.emit()
	return true

# Advances travel once per frame. Distance funds research; moving expedition
# time repairs hulls; docking delivers trade loads. Returns facts
# for the UI. A failed boundary save rolls everything back to `before`.
func advance_expedition(delta: float, force_save := false) -> Dictionary:
	var result := {"ok": true, "boundary": false, "saved": false, "research_ready": false, "repaired": false,
		"delivered": 0, "income": 0, "error": ""}
	var simulation = expedition_simulation
	if simulation == null or simulation.state == null or battle_pending or run_ended or completed:
		return result
	var sim_before: Dictionary = simulation.state.snapshot()
	var hangar_before := {}
	var sequence: int = simulation.boundary_sequence
	var days_before: float = simulation.state.traveled_days
	var seconds_before: float = simulation.state.simulation_seconds
	var modifiers: Dictionary = research_grants().modifiers
	var income_rate := float(modifiers.get("travel_credits_per_day", {}).get("value", 0.0))
	var fuel_multiplier := float(modifiers.get("cruise_fuel_multiplier", {}).get("value", 1.0))
	var cruise_multiplier := float(modifiers.get("cruise_speed_multiplier", {}).get("value", 1.0))
	if not simulation.advance(delta, fuel_multiplier, cruise_multiplier):
		simulation.restore(sim_before)
		result.ok = false
		result.error = "Navigation error: " + simulation.last_error
		return result
	var days: float = simulation.state.traveled_days - days_before
	var seconds: float = simulation.state.simulation_seconds - seconds_before
	var earned_rp := ScienceRules.production_rate(ScienceRules.snapshot(get_deployed_fleet())) * days
	var progress := run_progress_snapshot()
	_allocate_research(progress, earned_rp)
	var offers_ready: bool = research_offer.is_empty() and not progress.research_offer.is_empty()
	result.research_ready = offers_ready
	result.boundary = simulation.boundary_sequence != sequence
	if result.boundary or force_save or offers_ready:
		hangar_before = hangar_snapshot()
		hangar_before.expedition = sim_before
	if days > 0.0:
		# The saved distance clock retains fractional earnings without another save field.
		result.income = floori(simulation.state.traveled_days * income_rate + 0.00000001) \
			- floori(days_before * income_rate + 0.00000001)
		if result.income > 0:
			var income := {"credits": credits}
			if not run_score.is_empty():
				income.score = run_score
			RunScore.earn_credits(income, int(result.income))
			credits = int(income.credits)
	research_points = progress.research_points
	research_offer.assign(progress.research_offer)
	if seconds > 0.0:
		var damaged_before := false
		var damaged_after := false
		for owned: HangarShip in fleet:
			if not owned.is_alive() or not owned.needs_repair():
				continue
			damaged_before = true
			owned.hull_hp = minf(owned.hull_max, owned.hull_hp + self_repair_rate(owned) * seconds)
			damaged_after = damaged_after or owned.needs_repair()
		if damaged_before and not damaged_after:
			result.repaired = true
	if result.boundary:
		var emitted: Array = simulation.emitted_boundaries
		var count: int = mini(emitted.size(), simulation.boundary_sequence - sequence)
		for index in range(emitted.size() - count, emitted.size()):
			var boundary: Dictionary = emitted[index]
			if int(boundary.kind) == ExpeditionSimulationScript.State.BoundaryKind.DOCK:
				result.delivered += _deliver_loads(str(boundary.details.location_id))
	if result.boundary or force_save or offers_ready:
		if not save_expedition_checkpoint():
			if not hangar_before.is_empty():
				_apply_hangar(hangar_before)
				simulation.restore(sim_before)
			result.ok = false
			result.research_ready = false
			result.income = 0
			result.delivered = 0
			result.error = "Save failed: " + last_save_error
			return result
		result.saved = true
		if offers_ready:
			research_changed.emit()
	if result.delivered > 0 or result.income > 0:
		credits_changed.emit()
	return result

func _deliver_loads(location_id: String) -> int:
	var node := station_trade_node(location_id)
	if node.is_empty() or not node.inhabited:
		return 0
	var data := {"ships": [], "equipment": equipment_inventory, "credits": credits}
	if not run_score.is_empty():
		data["score"] = run_score
	for owned: HangarShip in fleet:
		data.ships.append(owned.to_hangar_data())
	var before := credits
	HangarTrade.arrive(data, node, int(node.id))
	credits = int(data.credits)
	# Fitted instances share the inventory dictionaries; refresh mounts.
	for owned: HangarShip in fleet:
		for slot in owned.mounts:
			owned.mounts[slot] = equipment_inventory[owned.mounts[slot].uid]
	return credits - before

func equipment_location(uid: String) -> Dictionary:
	for owned: HangarShip in fleet:
		for slot in owned.mounts:
			if owned.mounts[slot].uid == uid:
				return {"ship_id": owned.id, "slot": slot}
	return {}

# Moves an existing instance to a mount (internal primitive). There is no
# stock: a displaced or removed part is scrapped.
func fit_equipment(ship_id: int, slot_id: String, uid: String) -> bool:
	if not _require_shipyard():
		return false
	var target := owned_ship(ship_id)
	if target == null:
		return false
	var slot := ShipLoadouts.slot_by_id(target.chassis, slot_id)
	if slot.is_empty():
		return false
	if not uid.is_empty():
		if not equipment_inventory.has(uid):
			return false
		var instance: Dictionary = equipment_inventory[uid]
		var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
		if not SlotCatalog.compatible(slot, item) or not ShipLoadouts.obtainable(item):
			return false
		if not ShipLoadouts.equipment_available(item, current_research_ids):
			last_save_error = "Research this equipment first."
			return false
	var data := hangar_snapshot()
	for entry: Dictionary in data.ships:
		var armor_before := _fitted_integrity(entry, data.equipment)
		for key in entry.mounts.keys():
			if entry.mounts[key] == uid or (int(entry.id) == ship_id and key == slot_id):
				if HangarTrade.has_load(data.equipment[entry.mounts[key]]):
					last_save_error = "Deliver passengers/cargo first"
					return false # Deliver occupied cabins/holds before removing them.
				if entry.mounts[key] != uid:
					data.equipment.erase(entry.mounts[key])
				entry.mounts.erase(key)
		if int(entry.id) == ship_id and not uid.is_empty():
			entry.mounts[slot_id] = uid
		entry.hull_hp += _fitted_integrity(entry, data.equipment) - armor_before
		if entry.hull_hp < 0:
			return false
		HangarSquadrons.update_override(data, int(entry.id))
	return _commit_hangar(data)

func _fitted_integrity(entry: Dictionary, inventory: Dictionary) -> float:
	var total := 0.0
	for uid in entry.mounts.values():
		var instance: Dictionary = inventory[uid]
		total += SlotCatalog.stats_for(instance.equipment_id, int(instance.rank)).integrity
	return total

func ship_loadout_id(ship_id: int) -> String:
	var owned := owned_ship(ship_id)
	return "" if owned == null else ShipLoadouts.matching(owned.chassis_id, owned.mounts)

func refit_quote(ship_id: int, target: Dictionary) -> int:
	var owned := owned_ship(ship_id)
	return 0 if owned == null else ShipLoadouts.refit_fee(ShipLoadouts.current_keys(owned.mounts), target)

func refit_ship(ship_id: int, loadout_id: String) -> bool:
	var owned := owned_ship(ship_id)
	var loadout: Dictionary = {} if owned == null else ShipLoadouts.find(owned.chassis_id, loadout_id)
	if loadout.is_empty():
		last_save_error = "Unknown loadout."
		return false
	if not ShipLoadouts.available(loadout, current_research_ids):
		last_save_error = "Research this loadout's equipment first."
		return false
	return _refit(ship_id, loadout.mounts)

# Swaps one mount to `key` ("id" or "id@rank"); an empty key strips the mount.
func swap_part(ship_id: int, slot_id: String, key: String) -> bool:
	var owned := owned_ship(ship_id)
	if owned == null:
		return false
	var target := ShipLoadouts.current_keys(owned.mounts)
	if key.is_empty():
		target.erase(slot_id)
	else:
		target[slot_id] = key
	return _refit(ship_id, target)

# Atomic, free shipyard refit to the given mount keys.
func _refit(ship_id: int, target: Dictionary) -> bool:
	if not _require_shipyard():
		return false
	var data := hangar_snapshot()
	if not _stage_refit(data, ship_id, target):
		return false
	HangarSquadrons.update_override(data, ship_id)
	return _commit_hangar(data)

func _stage_refit(data: Dictionary, ship_id: int, target: Dictionary, allow_unchanged := false) -> bool:
	var owned := owned_ship(ship_id)
	if not _can_refit() or owned == null:
		last_save_error = "Refits are unavailable right now."
		return false
	var current := ShipLoadouts.current_keys(owned.mounts)
	for slot_id: String in target:
		var item := ShipLoadouts.item_for(str(target[slot_id]))
		if not SlotCatalog.compatible(ShipLoadouts.slot_by_id(owned.chassis, slot_id), item) or not ShipLoadouts.obtainable(item):
			last_save_error = "That part does not fit this mount."
			return false
		if str(current.get(slot_id, "")) != str(target[slot_id]) and not ShipLoadouts.equipment_available(item, current_research_ids):
			last_save_error = "Research this equipment first."
			return false
	if SaveValidation.same(current, target):
		if allow_unchanged:
			return true
		last_save_error = "Already fitted."
		return false
	var entry: Dictionary = {}
	for candidate: Dictionary in data.ships:
		if int(candidate.id) == ship_id:
			entry = candidate
	var armor_before := _fitted_integrity(entry, data.equipment)
	var slots := current.keys()
	for slot_id: String in target:
		if slot_id not in slots:
			slots.append(slot_id)
	for slot_id: String in slots:
		if str(current.get(slot_id, "")) == str(target.get(slot_id, "")):
			continue
		if entry.mounts.has(slot_id):
			var old_uid: String = entry.mounts[slot_id]
			if HangarTrade.has_load(data.equipment[old_uid]):
				last_save_error = "Deliver passengers/cargo first"
				return false
			data.equipment.erase(old_uid)
			entry.mounts.erase(slot_id)
		if target.has(slot_id):
			var parsed := ShipLoadouts.parse_key(str(target[slot_id]))
			var uid := str(data.next_equipment_id)
			data.next_equipment_id += 1
			data.equipment[uid] = {"uid": uid, "equipment_id": parsed.id, "rank": int(parsed.rank)}
			entry.mounts[slot_id] = uid
	var fitted := _fitted_integrity(entry, data.equipment)
	entry.hull_hp = clampf(float(entry.hull_hp) + fitted - armor_before, 0.0, float(owned.chassis.integrity) + fitted)
	return true

# Ships are sold fully fitted; an unspecified loadout uses the first available fit.
func buy_ship(key: String, loadout_id := "") -> bool:
	return buy_ships(key, 1, 0, loadout_id)

func buy_ships(key: String, count: Variant, group_id := 0, loadout_id := "") -> bool:
	if not _require_shipyard():
		return false
	if not SaveValidation.integer(count) or count <= 0:
		last_save_error = "Choose a positive whole number of ships."
		return false
	var group := HangarSquadrons.find(squadrons, group_id)
	if group_id != 0:
		if group.is_empty() or group.chassis != key:
			last_save_error = "Choose a squadron of the same ship class."
			return false
		loadout_id = group.loadout
	var chassis := SlotCatalog.find_chassis(key)
	var loadout := ShipLoadouts.purchase_for(key, current_research_ids) if loadout_id.is_empty() else ShipLoadouts.find(key, loadout_id)
	var price := ShipLoadouts.ship_price(key, loadout)
	if not _can_refit() or chassis.is_empty() or chassis.flagship or loadout.is_empty():
		last_save_error = "Ships are unavailable."
		return false
	if not ShipLoadouts.available(loadout, current_research_ids):
		last_save_error = "Research this loadout's equipment first."
		return false
	# Bound the batch by its real price before multiplying or allocating ships.
	if int(count) > credits / maxi(1, price):
		last_save_error = "Not enough credits."
		return false
	price *= int(count)
	if credits < price:
		last_save_error = "Not enough credits. Cost: %d." % price
		return false
	var data := hangar_snapshot()
	for index in range(int(count)):
		ShipLoadouts.append_ship(data, key, loadout)
		HangarSquadrons.add_ship(data, data.ships.back(), group_id, loadout.id)
	data.credits -= price
	return _commit_hangar(data)

func salvage_hangar_ship(ship_id: int) -> bool:
	if not _require_shipyard():
		return false
	var target := owned_ship(ship_id)
	if not _can_refit() or target == null or target.flagship:
		return false
	var data := hangar_snapshot()
	HangarTrade.settle_losses(data, [ship_id])
	data.ships = data.ships.filter(func(entry: Dictionary) -> bool: return int(entry.id) != ship_id)
	HangarSquadrons.sync(data)
	RunScore.earn_credits(data, floori(float(target.chassis.price) * 0.5 * maxf(0, target.hull_hp) / target.hull_max))
	# Equipment is returned to stock, retaining its instance identity.
	return _commit_hangar(data)

func owned_ship(ship_id: int) -> HangarShip:
	for owned: HangarShip in fleet:
		if owned.id == ship_id:
			return owned
	return null

func _can_refit() -> bool:
	return not run_id.is_empty() and not battle_pending and not run_ended and not completed

func station_service_error(service: String) -> String:
	if not _can_refit():
		return "Station services are unavailable during combat or after the run ends."
	if expedition_simulation == null:
		return "" if campaign_node(current_node_id).get("inhabited", false) else "Dock at a shipyard to use this service."
	var state = expedition_simulation.state
	if state == null:
		return "No active expedition state."
	if ExpeditionSimulationScript.State.PauseReason.SAVE_ERROR in state.pause_reasons:
		return "Retry the failed save before using station services."
	if state.travel_state != ExpeditionSimulationScript.State.TravelState.DOCKED:
		if service == "ammunition":
			return "Dock at a station to buy missiles."
		return "Dock at a shipyard to refit, sell, salvage or repair." if service == "shipyard" \
			else "Dock at a refueling station to refuel."
	var location: Dictionary = expedition_simulation.locations.get(state.docked_location_id, {})
	if location.is_empty() or location.get("kind") != "station" \
			or state.position_nu.distance_to(Vector2(location.position[0], location.position[1])) > 0.000001:
		return "The fleet is not docked at a valid station."
	if service != "ammunition" and service not in location.get("services", []):
		return "This station has no shipyard." if service == "shipyard" else "This station does not offer refueling."
	return ""

func can_use_shipyard() -> bool:
	return station_service_error("shipyard").is_empty()

func _require_shipyard() -> bool:
	last_save_error = station_service_error("shipyard")
	return last_save_error.is_empty()

func get_deployed_fleet() -> Array[FleetShip]:
	return fleet.filter(func(owned: FleetShip) -> bool: return owned.is_alive())

func is_ship_deployed(owned: FleetShip) -> bool:
	return fleet.has(owned) and owned.is_alive()

func deployment_error() -> String:
	if run_ended or completed:
		return "Run ended"
	if not fleet.any(func(owned: FleetShip) -> bool: return owned.is_flagship() and owned.is_alive()):
		return "Flagship lost"
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
	if not _require_shipyard():
		return false
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
	var old_groups := squadrons.duplicate(true)
	owned.formation = position.clamp(Vector2(-5, -4), Vector2(5, 4))
	var staged := hangar_snapshot()
	HangarSquadrons.sync(staged)
	squadrons = staged.squadrons
	if not save_run_checkpoint():
		owned.formation = old
		squadrons = old_groups
	fleet_changed.emit()

func move_ships(positions: Dictionary) -> bool:
	if not _can_refit() or positions.is_empty():
		return false
	var data := hangar_snapshot()
	for id: int in positions:
		if owned_ship(id) == null or not positions[id] is Vector2 or not positions[id].is_finite():
			return false
		var position: Vector2 = positions[id]
		if position.x < -5 or position.x > 5 or position.y < -4 or position.y > 4:
			return false
		for entry: Dictionary in data.ships:
			if entry.id == id:
				entry.formation = [position.x, position.y]
	HangarSquadrons.sync(data)
	return _commit_hangar(data)

func save_battle_deployment(positions: Dictionary) -> bool:
	if not battle_pending or run_ended or completed or positions.size() != get_deployed_fleet().size():
		last_save_error = "Battle deployment is unavailable."
		return false
	var area := BattleSimulation.deployment_area(pending_encounter)
	var data := hangar_snapshot()
	for ship: HangarShip in get_deployed_fleet():
		var position: Variant = positions.get(ship.id)
		if not position is Vector2 or not position.is_finite() or not area.has_point(position):
			last_save_error = "Place every ship inside the deployment area."
			return false
		var radius := Vector2.ONE * ship.get_stats().collision_radius
		if position != position.clamp(area.position + radius, area.end - radius):
			last_save_error = "Place every ship inside the deployment area."
			return false
		var formation: Vector2 = (position - BattleSimulation.PLAYER_FORMATION_CENTER) / BattleSimulation.DEPLOYMENT_SCALE
		for entry: Dictionary in data.ships:
			if int(entry.id) == ship.id:
				entry.formation = [formation.x, formation.y]
	HangarSquadrons.sync(data)
	return _commit_hangar(data)

func fleet_repair_cost() -> int:
	var cost := 0
	for owned: HangarShip in fleet:
		if owned.is_alive() and owned.needs_repair():
			cost += owned.repair_cost()
	return cost

func repair_all_ships() -> bool:
	if not _require_shipyard():
		return false
	var cost := fleet_repair_cost()
	if not _can_refit() or cost <= 0 or credits < cost:
		return false
	var before := hangar_snapshot()
	credits -= cost
	for owned: HangarShip in fleet:
		if owned.is_alive():
			owned.repair()
	if not save_run_checkpoint():
		_apply_hangar(before)
		return false
	_notify_hangar()
	return true

func research_choice_ready() -> bool:
	return not research_offer.is_empty() and research_points >= HangarResearch.threshold(run_progress_snapshot())

func choose_research(key: String) -> bool:
	if battle_pending or run_ended or completed or not research_choice_ready() or key not in research_offer:
		last_save_error = "Choose one of the offered upgrades."
		return false
	var data := hangar_snapshot()
	if not HangarResearch.eligible(key, data.research):
		last_save_error = "This upgrade is no longer available."
		return false
	if not ResearchUpgrades.matches(key, get_deployed_fleet()):
		last_save_error = ResearchUpgrades.requirement(key)
		return false
	data.research.research_points -= HangarResearch.threshold(data.research)
	data.research.research_ids.append(key)
	data.research.research_offer.clear()
	var definition := GameDefinitions.find("research", key)
	if not definition.family_id.is_empty():
		data.research.branch_choices[definition.family_id] = definition.path_id
	_allocate_research(data.research, 0.0)
	return _commit_hangar(data)

func _allocate_research(progress: Dictionary, amount: float) -> void:
	progress.research_points = float(progress.research_points) + maxf(0, amount)
	var deployed := get_deployed_fleet()
	HangarResearch.prepare_offer(progress, run_seed, HangarResearch.option_count(deployed), deployed)

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

func node_environment(node_id: int) -> Dictionary:
	var node := campaign_node(node_id)
	if node.is_empty():
		push_error("Cannot inspect conditions for an unknown map node.")
		return {}
	var conditions: Dictionary = node.environment.duplicate(true)
	var frozen: Dictionary = navigation.get("encounters", {}).get(str(node_id), get_frozen_encounter(node_id))
	if frozen.has("environment"):
		return frozen.environment.duplicate(true)
	if not frozen.is_empty():
		# Older saved encounters retain their original field instead of rerolling.
		conditions.asteroid_density = 2 if frozen.has("asteroids") else 0
	return conditions

func travel_to(node_id: int) -> bool:
	if not _can_refit() or not can_deploy() or not get_reachable_nodes(current_node_id).has(node_id):
		return false
	var data := hangar_snapshot()
	var yield_rp := ScienceRules.journey_rp(ScienceRules.snapshot(get_deployed_fleet()), research_travel_time(current_node_id, node_id))
	if not navigation.is_empty():
		var days := research_travel_time(current_node_id, node_id)
		data.navigation.days += days
		data.navigation.intensity += days
	HangarTrade.depart(data, campaign_node(current_node_id), campaign_node(node_id))
	data.planned = -1
	var encounter := get_frozen_encounter(node_id)
	if not navigation.is_empty():
		encounter = {} if visited_nodes.has(node_id) else data.navigation.encounters.get(str(node_id),
			SwarmNavigation.encounter(frozen_encounters.get(str(node_id), {}), data.navigation.intensity))
	if not encounter.is_empty():
		if not navigation.is_empty():
			data.navigation.encounters[str(node_id)] = encounter.duplicate(true)
		data.destination = node_id
		data.pending = true
		data.pending_encounter = encounter
		data.journey_rp = yield_rp
	else:
		data.current = node_id
		if not data.visited.has(node_id):
			data.visited.append(node_id)
		if not navigation.is_empty():
			SwarmNavigation.arrive(data, campaign_dag)
		HangarTrade.arrive(data, campaign_node(node_id))
		_allocate_research(data.research, yield_rp)
	return _commit_hangar(data)

func resolve_map_event(choice: String) -> bool:
	var event := SwarmNavigation.event(campaign_dag, current_node_id)
	if navigation.is_empty() or not _can_refit() or event.is_empty() or navigation.events.has(str(current_node_id)) or choice not in ["relay", "disrupt"]:
		last_save_error = "This encounter choice is no longer available."
		return false
	var data := hangar_snapshot()
	var key := str(current_node_id)
	data.navigation.events[key] = choice
	if choice == "relay":
		data.navigation.quests[key] = "active"
	else:
		data.navigation.intensity = maxf(0, data.navigation.intensity - event.disruption)
	return _commit_hangar(data)

func quest_targets() -> Array[int]:
	var targets: Array[int] = []
	for key: String in navigation.get("quests", {}):
		if navigation.quests[key] == "active":
			targets.append(SwarmNavigation.event(campaign_dag, int(key)).target)
	return targets

func set_destination(node_id: int) -> bool:
	return travel_to(node_id)

func battle_support_context() -> Dictionary:
	var encounter := get_frozen_encounter(destination_node_id)
	# No material drops, extraction, inventory-consuming abilities or grid bonuses.
	var context := {"credits_only": true, "energy_efficiency": energy_efficiency(), "enemy_roles": encounter.get("enemy_roles", false), "doctrine_pool": battle_reserves.get(str(destination_node_id), {}), "encounter_plan": encounter if encounter.has("arena_layout") else {}}
	context.missiles = missiles
	context.ability_ids = research_grants().ability_ids
	# Continue restarts the encounter; cooldowns and aim preferences are encounter-local.
	context.ability_state = BattleAbilities.initial_state()
	context.ability_state.auto["ion_pulse"] = false
	context.research_effects = {}
	var modifiers: Dictionary = research_grants().modifiers
	for id: String in ResearchCombat.EFFECTS:
		if modifiers.get(id, {}).get("value", false):
			context.research_effects[id] = true
	for key in ["asteroids", "environment"]:
		if encounter.has(key):
			context[key] = encounter[key].duplicate(true)
	return context

func battle_material_rewards() -> Array[int]:
	return []

func allied_salvage_chance() -> float:
	return 0.0

func battle_identity() -> String:
	if pending_encounter.has("expedition_event_id"):
		return "%s/%s" % [run_id, pending_encounter.expedition_event_id]
	return "%s/%d" % [run_id, destination_node_id]

func update_battle_support(_simulation: BattleSimulation) -> void:
	pass

func settle_battle(simulation: BattleSimulation) -> bool:
	if not battle_pending or simulation.battle_id != battle_identity() or simulation.phase == BattleSimulation.Phase.COMBAT:
		return false
	if pending_encounter.has("expedition_event_id"):
		return _settle_expedition_battle(simulation)
	var data := hangar_snapshot()
	if not _stage_battle_missiles(data, simulation):
		return false
	var lost: Array[int] = []
	if data.has("score"):
		data.score.swarm_damage += simulation.swarm_damage_dealt
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
	HangarSquadrons.sync(data)
	var won: bool = simulation.phase == BattleSimulation.Phase.VICTORY and not data.ended
	if won:
		RunScore.earn_credits(data, int(get_frozen_encounter(destination_node_id).rewards.credits))
		var loot := equipment_loot(destination_node_id)
		if not loot.is_empty():
			var uid := str(data.next_equipment_id)
			data.equipment[uid] = {"uid": uid, "equipment_id": loot.id, "rank": int(loot.rank)}
			data.next_equipment_id += 1
		data.current = destination_node_id
		if not data.visited.has(destination_node_id):
			data.visited.append(destination_node_id)
		if not navigation.is_empty():
			SwarmNavigation.arrive(data, campaign_dag)
		var node := campaign_node(destination_node_id)
		if node.kind == "boss":
			data.research.story_flags[["boss_i_defeated", "boss_ii_defeated", "boss_iii_defeated"][int(node.act) - 1]] = true
		data.completed = destination_node_id == FINAL_NODE_ID
		HangarTrade.arrive(data, node)
		_allocate_research(data.research, journey_rp)
	data.destination = -1
	data.pending = false
	data.pending_encounter = {}
	data.journey_rp = 0
	if not _save_hangar(data):
		return false
	last_battle_report.clear()
	var legacy_loot := str(equipment_loot(destination_node_id).get("name", "")) if won else ""
	last_equipment_loot = "" if legacy_loot.is_empty() else "Loot: " + legacy_loot
	for actor in simulation.players:
		last_battle_report.append({"ship": actor.owned_ship, "damage": actor.damage_dealt, "taken": actor.damage_taken,
			"repair_damage": actor.owned_ship.repair_cost() if actor.is_alive() else 0, "deflected": actor.damage_deflected(), "weapons": actor.weapon_damage.duplicate(), "destroyed": not actor.is_alive()})
	_apply_hangar(data, false, true)
	_notify_hangar()
	return true

func _settle_expedition_battle(simulation: BattleSimulation) -> bool:
	var data := hangar_snapshot()
	if not _stage_battle_missiles(data, simulation):
		return false
	var lost: Array[int] = []
	if data.has("score"):
		data.score.swarm_damage += simulation.swarm_damage_dealt
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
	HangarSquadrons.sync(data)
	var won: bool = simulation.phase == BattleSimulation.Phase.VICTORY and not data.ended
	var event_id: String = pending_encounter.get("expedition_event_id", "")
	var rewards: PackedStringArray = []
	if won:
		RunScore.earn_credits(data, int(pending_encounter.rewards.credits))
		# Victories yield research data instead of loose equipment.
		var rp := float(pending_encounter.rewards.get("research", 2.0 + float(pending_encounter.get("global_row", 1))))
		_allocate_research(data.research, rp)
		if rp > 0:
			rewards.append("+%s RP" % ScienceRules.format_points(rp))
		if pending_encounter.rewards.has("fuel"):
			var before := float(data.expedition.fuel)
			data.expedition.fuel = minf(float(data.expedition.fuel_capacity), before + float(pending_encounter.rewards.fuel))
			rewards.append("+%.1f fuel" % (float(data.expedition.fuel) - before))
		if pending_encounter.rewards.has("rescue_ship"):
			rewards.append(_rescue_ship(data, str(pending_encounter.rewards.rescue_ship)))
		if pending_encounter.rewards.has("missiles"):
			data.missiles += int(pending_encounter.rewards.missiles)
			rewards.append("+%d missiles" % int(pending_encounter.rewards.missiles))
		if pending_encounter.get("complete", false):
			data.completed = true
			data.research.story_flags["boss_i_defeated"] = true
	elif not data.ended:
		# Unbeaten arrival encounters remain at their location for a later attempt.
		var event: Dictionary = ExpeditionSimulationScript.Events.find(expedition_simulation.events, event_id)
		if ExpeditionSimulationScript.Events.trigger(event) == "arrival":
			data.expedition.event_receipts.erase(event_id)
	data.pending = false
	data.pending_encounter = {}
	if not _save_hangar(data):
		return false
	last_battle_report.clear()
	last_equipment_loot = " · ".join(rewards)
	for actor in simulation.players:
		last_battle_report.append({"ship": actor.owned_ship, "damage": actor.damage_dealt, "taken": actor.damage_taken,
			"repair_damage": actor.owned_ship.repair_cost() if actor.is_alive() else 0, "deflected": actor.damage_deflected(), "weapons": actor.weapon_damage.duplicate(), "destroyed": not actor.is_alive()})
	_apply_hangar(data, false, true)
	expedition_simulation.restore(data.expedition)
	_notify_hangar()
	return true

func _stage_battle_missiles(data: Dictionary, simulation: BattleSimulation) -> bool:
	if simulation.initial_missiles < 0:
		return true
	if simulation.initial_missiles != missiles or simulation.missile_supply < 0 \
			or simulation.missile_supply > simulation.initial_missiles:
		last_save_error = "Battle missile expenditure does not match the saved supply."
		return false
	data.missiles = simulation.missile_supply
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
	var unlocked_act := 1
	for act in range(1, 3):
		if story_flags.get("boss_%s_defeated" % ["i", "ii"][act - 1], false):
			unlocked_act = act + 1
	return not campaign_active or int(campaign_node(node_id).get("act", 4)) <= (current_act() if navigation.is_empty() else unlocked_act)


func edge_preview(source: int, target: int) -> Dictionary:
	if campaign_active:
		for route in campaign_dag.routes:
			if (int(route.from) == source and int(route.to) == target) or (not navigation.is_empty() and int(route.to) == source and int(route.from) == target):
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
		var distance := int(campaign_node(to_id).get("row", 0)) - int(campaign_node(from_id).get("row", 0))
		return maxi(0, distance) if navigation.is_empty() else absi(distance)
	if from_id < 0 or to_id < 0 or from_id >= NODE_COLUMNS.size() or to_id >= NODE_COLUMNS.size():
		return 0
	return maxi(0, NODE_COLUMNS[to_id] - NODE_COLUMNS[from_id])


func get_frozen_encounter(node_id: int) -> Dictionary:
	if battle_pending and pending_encounter.has("expedition_event_id"):
		return pending_encounter.duplicate(true)
	if not navigation.is_empty():
		if battle_pending and node_id == destination_node_id:
			return pending_encounter.duplicate(true)
		if visited_nodes.has(node_id):
			return {}
		if navigation.encounters.has(str(node_id)):
			return navigation.encounters[str(node_id)].duplicate(true)
		return SwarmNavigation.encounter(frozen_encounters.get(str(node_id), {}), navigation.intensity)
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
		if edge.x == from_node_id and (navigation.is_empty() or node_visible(edge.y)):
			reachable_nodes.append(edge.y)
	for edge in GRAPH_EDGES:
		if not navigation.is_empty() and edge.y == from_node_id and node_visible(edge.x):
			reachable_nodes.append(edge.x)
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
	return {"research_ids": current_research_ids.duplicate(), "research_offer": research_offer.duplicate(),
		"research_points": research_points, "story_flags": story_flags.duplicate(), "branch_choices": research_branch_choices.duplicate()}

func is_shipyard_node(node_id: int) -> bool:
	return node_id == current_node_id and can_use_shipyard()
