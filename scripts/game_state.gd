extends Node

signal build_area_changed
signal design_library_changed
signal fleet_changed
signal upgrades_changed
signal research_changed
signal travel_plan_changed

signal tile_inventory_changed
signal ship_stats_changed
signal credits_changed
signal player_ship_count_changed
signal discovered_parts_changed
signal unviewed_discoveries_changed
signal part_transformations_changed

const AlienShipType = preload("res://scripts/alien_ship.gd")

enum Difficulty { EASY, MEDIUM, HARD }

const GRAPH_COLUMN_COUNT := 15
const GRAPH_BRANCHES_PER_COLUMN := 2
var NODE_POSITIONS: Array[Vector2] = []
var NODE_COLUMNS: Array[int] = []
var GRAPH_EDGES: Array[Vector2i] = []
var CONVERGENCE_NODE_IDS: Array[int] = []
var FINAL_NODE_ID := 0
var campaign_dag: Dictionary = {}
var campaign_active := false
const MIN_ALIEN_FLEET_SIZE := 3
const MAX_ALIEN_FLEET_SIZE := 8
const STARTING_CREDITS := 300
const VICTORY_CREDIT_REWARD := 200
const SAVED_SHIP_DESIGNS_PATH := "user://ship_designs.json"
const SAVED_SHIP_DESIGNS_VERSION := 1
const ARCHIVE_PROGRESS_PATH := "user://archive_progress.json"
const ARCHIVE_PROGRESS_VERSION := 1
const RUN_PROGRESS_VERSION := RunProgressData.VERSION
const RUN_SAVE_PATH := "user://run_checkpoint.json"
const STARTING_RED_TILE_COUNT := 18
const STARTING_BLUE_TILE_COUNT := 12
const STARTING_GREEN_TILE_COUNT := 6
const STARTING_CORE_TILE_COUNT := 3
const BASE_BUILD_SIZE := 20

var fleet: Array[FleetShip] = []
var next_ship_id := 1
var laser_upgrade_level := 0
var build_area_level := 0
const MAX_BUILD_SIZE := 30
var last_battle_report: Array[Dictionary] = []

var current_node_id := 0
var destination_node_id := -1
var planned_destination_node_id := -1
var visited_nodes: Array[int] = [0]
var battle_pending := false
var player_ship_count := 0
var current_ship_design_name := ""
var credits := STARTING_CREDITS
var difficulty := Difficulty.MEDIUM
var battle_aliens: Array[RefCounted] = []
var ship := Ship.new()
var discovered_part_types: Array[int] = []
var unviewed_discovered_part_types: Array[int] = []
var active_part_transformations := 0
var red_tiles_available := STARTING_RED_TILE_COUNT
var blue_tiles_available := STARTING_BLUE_TILE_COUNT
var green_tiles_available := STARTING_GREEN_TILE_COUNT
var core_tiles_available := STARTING_CORE_TILE_COUNT
var saved_ship_designs: Array[Dictionary] = []
var current_run_design_names: Array[String] = []
var fleet_design_slots: Array[String] = ["", "", ""]
var roster_state: Dictionary = FleetRules.empty_roster()
var fleet_formation_index := 0
var battle_auto_camera := true
var battle_fast_forward := false
var reduced_motion := false
var archive_progress_file_path := ARCHIVE_PROGRESS_PATH

# Run authorization is deliberately independent of Archive discoveries/designs.
var current_research_ids: Array[String] = ["foundation"]
var _research_grant_key := ""
var _research_grant_cache: Dictionary = {}
var research_points := 0.0
var research_focus := ""
var research_progress: Dictionary = {}
var research_pricing_version := 0
var ability_state := BattleAbilities.initial_state()
var research_branch_choices: Dictionary[String, String] = {}
var story_flags: Dictionary[String, bool] = {}
var run_seed := 0
var run_id := ""
var transaction_ledger: Dictionary = {}
var economy_state: Dictionary = {}

var run_save_path := RUN_SAVE_PATH
var last_save_error := ""
var _checkpoint_generation := -1
var _checkpoint_store := AtomicRunStore.new()
var frozen_encounters: Dictionary = {}
var destroy_all_neutral_targets := false
var run_ended := false
# Durable per-node attempts and future finite mining fields, independent of enemy resets.
var encounter_progress: Dictionary = {}


func _ready() -> void:
	if NODE_POSITIONS.is_empty():
		run_seed = _new_run_seed()
		_generate_campaign_graph()
	_load_archive_progress(archive_progress_file_path)
	_load_saved_ship_designs()


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


func start_new_run(selected_difficulty: int = Difficulty.MEDIUM, seed_value: int = -1, use_campaign := true) -> bool:
	if not [
		Difficulty.EASY,
		Difficulty.MEDIUM,
		Difficulty.HARD,
	].has(selected_difficulty):
		push_error("Cannot start a run with an unknown difficulty.")
		return false
	if seed_value < -1:
		return false

	run_seed = _new_run_seed() if seed_value == -1 else seed_value
	current_research_ids = ["foundation"]
	research_points = 0
	research_focus = ""
	research_progress.clear()
	research_pricing_version = ResearchFocusRules.PRICING_VERSION
	ability_state = BattleAbilities.initial_state()
	research_branch_choices.clear()
	story_flags.clear()
	destroy_all_neutral_targets = false
	run_ended = false
	encounter_progress.clear()
	run_id = Crypto.new().generate_random_bytes(16).hex_encode()
	transaction_ledger.clear()
	economy_state.clear()
	_checkpoint_generation = -1
	_generate_campaign_graph()
	campaign_dag = CampaignGraph.generate(run_seed)
	if campaign_dag.is_empty():
		push_error("Could not generate a valid campaign DAG.")
		return false
	campaign_active = use_campaign
	if campaign_active:
		campaign_dag = CampaignContent.populate(campaign_dag, run_seed)
		_apply_campaign_geometry()
	current_node_id = 0
	destination_node_id = -1
	planned_destination_node_id = -1
	visited_nodes = [0]
	battle_pending = false
	player_ship_count = 0
	fleet.clear()
	current_run_design_names.clear()
	fleet_design_slots = ["", "", ""]
	roster_state = FleetRules.empty_roster()
	fleet_formation_index = 0
	next_ship_id = 1
	laser_upgrade_level = 0
	build_area_level = 0
	last_battle_report.clear()
	current_ship_design_name = ""
	credits = STARTING_CREDITS
	difficulty = selected_difficulty as Difficulty
	frozen_encounters = EncounterGenerator.freeze_campaign(run_seed, difficulty, campaign_dag) if campaign_active else EncounterGenerator.freeze_graph(run_seed, difficulty, NODE_COLUMNS)
	battle_aliens.clear()
	ship.clear()
	red_tiles_available = STARTING_RED_TILE_COUNT
	blue_tiles_available = STARTING_BLUE_TILE_COUNT
	green_tiles_available = STARTING_GREEN_TILE_COUNT
	core_tiles_available = STARTING_CORE_TILE_COUNT
	var drone := preload("res://scripts/builtin_ships.gd").drone()
	for index in range(3):
		var owned := FleetShip.new()
		owned.initialize(drone, next_ship_id, "Drone %d" % next_ship_id)
		owned.formation = Vector2(0, index - 1)
		fleet.append(owned)
		next_ship_id += 1
	fleet_design_slots[0] = "Drone"
	if campaign_active:
		_adopt_legacy_roster()
	for part in drone.parts:
		discover_part(part.type)
	_refresh_fleet()
	design_library_changed.emit()
	tile_inventory_changed.emit()
	ship_stats_changed.emit()
	credits_changed.emit()
	player_ship_count_changed.emit()
	research_changed.emit()
	if campaign_active:
		return dispatch_arrival()
	return save_run_checkpoint()


func _new_run_seed() -> int:
	var random := RandomNumberGenerator.new()
	random.randomize()
	return random.randi()


func run_progress_snapshot() -> Dictionary:
	return {
		"version": RUN_PROGRESS_VERSION,
		# JSON numbers cannot represent every 64-bit seed exactly.
		"seed": str(run_seed),
		"difficulty": difficulty,
		"credits": credits,
		"research_points": research_points,
		"research_focus": research_focus,
		"research_progress": research_progress.duplicate(),
		"research_pricing_version": research_pricing_version,
		"ability_state": ability_state.duplicate(true),
		"research_ids": current_research_ids.duplicate(),
		"branch_choices": research_branch_choices.duplicate(),
		"story_flags": story_flags.duplicate(),
		"active_design_families": fleet_design_slots.duplicate(),
		"family_identity_version": 1 if campaign_active else 0,
		"current_run_design_names": current_run_design_names.duplicate(),
		"destroy_all_neutral_targets": destroy_all_neutral_targets,
		"run_ended": run_ended,
	}


func restore_run_progress(data: Variant, notify := true) -> bool:
	# The future full save/ledger loader will restore this alongside fleet and graph
	# state. Validate everything before mutating; Archive is never consulted here.
	if not RunProgressData.validate(data).is_empty():
		return false
	run_seed = int(data.seed)
	difficulty = int(data.difficulty) as Difficulty
	credits = int(data.credits)
	research_points = float(data.research_points)
	research_focus = data.get("research_focus", "")
	research_progress = data.get("research_progress", {}).duplicate()
	research_pricing_version = int(data.get("research_pricing_version", 0))
	ability_state = data.get("ability_state", BattleAbilities.initial_state()).duplicate(true)
	current_research_ids.assign(data.research_ids)
	research_branch_choices.assign(data.branch_choices)
	story_flags.assign(data.story_flags)
	fleet_design_slots.assign(data.active_design_families)
	current_run_design_names.assign(data.current_run_design_names)
	destroy_all_neutral_targets = data.get("destroy_all_neutral_targets", false)
	run_ended = data.get("run_ended", false)
	if campaign_active and campaign_dag.get("seed", "") == data.seed:
		_apply_campaign_geometry()
	else:
		_generate_campaign_graph()
	if notify:
		research_changed.emit()
		credits_changed.emit()
		design_library_changed.emit()
	return true


func _capture_checkpoint(lost_ships: Array[int] = []) -> Dictionary:
	var checkpoint := RunCheckpoint.capture(self)
	if battle_pending and PassengerRules.occupied(economy_state) > 0:
		var proposal := PassengerRules.settle_losses(checkpoint, fleet, passenger_loss_scope(), lost_ships)
		if not proposal.is_empty():
			checkpoint = proposal
	if battle_pending and CargoRules.quantity(economy_state) > 0:
		var proposal := CargoRules.settle_losses(checkpoint, fleet, passenger_loss_scope(), lost_ships)
		if not proposal.is_empty():
			checkpoint = proposal
	# Leave malformed state for the checkpoint validator to reject.
	return checkpoint


func passenger_loss_scope() -> String:
	return "node/%d/attempt/%d" % [destination_node_id, int(encounter_progress.get(str(destination_node_id), {}).get("attempts", 1))]


func save_run_checkpoint() -> bool:
	if run_id.is_empty():
		return false
	var checkpoint := _capture_checkpoint()
	if not _persist_checkpoint(checkpoint):
		return false
	var changed: bool = credits != int(checkpoint.progress.credits) or economy_state != checkpoint.economy
	transaction_ledger = checkpoint.ledger
	_apply_accounting(checkpoint)
	if changed:
		_emit_accounting_changes()
	return true


func set_destroy_all_neutral_targets(enabled: bool) -> bool:
	var previous := destroy_all_neutral_targets
	destroy_all_neutral_targets = enabled
	if not save_run_checkpoint():
		destroy_all_neutral_targets = previous
		return false
	return true


func _persist_checkpoint(checkpoint: Dictionary) -> bool:
	var result := _checkpoint_store.commit(run_save_path, checkpoint, RunCheckpoint.valid, _checkpoint_generation)
	last_save_error = _checkpoint_store.last_error
	if not result.ok:
		return false
	_checkpoint_generation = int(result.generation)
	return true


func load_run_checkpoint() -> bool:
	var saved := _checkpoint_store.load_latest(run_save_path, RunCheckpoint.valid)
	if saved.is_empty():
		last_save_error = "No valid run checkpoint or backup."
		return false
	var decoded := RunCheckpoint.decode(saved.payload)
	var data: Dictionary = decoded.data
	if saved.payload.version == 1 or (saved.payload.get("campaign_active", false) and int(saved.payload.get("fleet_roster", {}).get("version", 1)) < 2):
		# Freeze migration results durably before exposing them to callers/previews.
		var migrated := _checkpoint_store.commit(run_save_path, data, RunCheckpoint.valid, int(saved.generation))
		if not migrated.ok:
			last_save_error = _checkpoint_store.last_error
			return false
		saved.generation = migrated.generation
	# Validation/decoding finished before touching any live state or Archive.
	restore_run_progress(data.progress, false)
	encounter_progress = data.get("encounter_progress", {}).duplicate(true)
	run_id = data.run_id
	transaction_ledger = data.ledger.duplicate(true)
	frozen_encounters = data.encounters.duplicate(true)
	campaign_dag = data.get("campaign_graph", {}).duplicate(true)
	campaign_active = data.get("campaign_active", false)
	_apply_accounting(data)
	fleet.assign(decoded.fleet)
	roster_state = data.get("fleet_roster", FleetRules.empty_roster()).duplicate(true)
	if campaign_active and not data.has("fleet_roster"):
		_adopt_legacy_roster()
	ship = decoded.editor
	current_ship_design_name = data.editor_name
	next_ship_id = int(data.next_ship_id)
	laser_upgrade_level = int(data.laser_level)
	build_area_level = int(data.build_level)
	NODE_POSITIONS.clear()
	for point in data.graph.positions:
		NODE_POSITIONS.append(Vector2(point[0], point[1]))
	NODE_COLUMNS.clear()
	for column in data.graph.columns:
		NODE_COLUMNS.append(int(column))
	GRAPH_EDGES.clear()
	for edge in data.graph.edges:
		GRAPH_EDGES.append(Vector2i(int(edge[0]), int(edge[1])))
	CONVERGENCE_NODE_IDS.clear()
	for node in data.graph.convergences:
		CONVERGENCE_NODE_IDS.append(int(node))
	FINAL_NODE_ID = int(data.graph.final)
	_apply_location(data, decoded.aliens)
	_checkpoint_generation = int(saved.generation)
	last_battle_report.clear()
	active_part_transformations = 0
	last_save_error = ""
	_refresh_fleet()
	_emit_accounting_changes()
	design_library_changed.emit()
	ship_stats_changed.emit()
	build_area_changed.emit()
	return true


func checkpoint_summary() -> Dictionary:
	var saved := _checkpoint_store.load_latest(run_save_path, RunCheckpoint.valid)
	if saved.is_empty():
		return {}
	return {"seed": int(saved.payload.progress.seed), "ended": bool(saved.payload.progress.get("run_ended", false)),
		"pending": bool(saved.payload.location.pending), "node": int(saved.payload.location.current)}


func prepare_checkpoint_resume() -> bool:
	if not battle_pending or get_deployed_fleet().any(func(owned: FleetShip) -> bool: return not owned.get_stats(laser_upgrade_level).weapons.is_empty()):
		return true
	# A checkpoint may already contain a lost deployment. Preserve its losses
	# and expose emergency reserves rather than opening an empty simulation.
	var checkpoint := _capture_checkpoint()
	var lost: Array[int] = []
	for owned in fleet:
		if not owned.is_alive():
			lost.append(owned.id)
	_stage_fleet_losses(checkpoint, lost)
	if not cancel_battle(-1, checkpoint.fleet.is_empty(), checkpoint):
		return false
	fleet = fleet.filter(func(owned: FleetShip) -> bool: return owned.id not in lost)
	roster_state = checkpoint.fleet_roster
	for owned in fleet:
		if owned.escort_target_id in lost:
			owned.escort_target_id = 0
	_refresh_fleet()
	return true


func commit_event(kind: String, source_id: String, credits_delta := 0,
	material_delta: Array = [0, 0, 0, 0], rp_delta := 0.0, details: Dictionary = {}, economy_after: Variant = null) -> bool:
	var result := TransactionLedger.apply(_capture_checkpoint(), kind, source_id,
		credits_delta, material_delta, rp_delta, details, economy_after)
	if result.is_empty():
		return false
	if result.replayed:
		return true
	if not _persist_checkpoint(result.checkpoint):
		return false
	# Keep physical ship references alive while combat is running.
	transaction_ledger = result.checkpoint.ledger
	_apply_accounting(result.checkpoint)
	_emit_accounting_changes()
	return true


func _apply_accounting(data: Dictionary) -> void:
	economy_state = data.economy.duplicate(true)
	credits = int(data.progress.credits)
	research_points = float(data.progress.research_points)
	research_focus = data.progress.get("research_focus", "")
	research_progress = data.progress.get("research_progress", {}).duplicate()
	research_pricing_version = int(data.progress.get("research_pricing_version", 0))
	ability_state = data.progress.get("ability_state", BattleAbilities.initial_state()).duplicate(true)
	current_research_ids.assign(data.progress.research_ids)
	research_branch_choices.assign(data.progress.branch_choices)
	red_tiles_available = int(data.inventory[0])
	blue_tiles_available = int(data.inventory[1])
	green_tiles_available = int(data.inventory[2])
	core_tiles_available = int(data.inventory[3])
	# All pending occupied losses were settled before this successful checkpoint.
	for owned in fleet:
		for unit in owned.units:
			unit.erase("load_lost")


func _emit_accounting_changes() -> void:
	credits_changed.emit()
	tile_inventory_changed.emit()
	research_changed.emit()


func _apply_location(data: Dictionary, aliens: Array = []) -> void:
	current_node_id = int(data.location.current)
	destination_node_id = int(data.location.destination)
	planned_destination_node_id = int(data.location.planned)
	visited_nodes.clear()
	for node in data.location.visited:
		visited_nodes.append(int(node))
	battle_pending = data.location.pending
	battle_aliens.clear()
	for alien in aliens:
		battle_aliens.append(alien)


func _generate_campaign_graph() -> void:
	NODE_POSITIONS.clear()
	NODE_COLUMNS.clear()
	GRAPH_EDGES.clear()
	CONVERGENCE_NODE_IDS.clear()
	var random := RandomNumberGenerator.new()
	random.seed = run_seed
	# Fifteen columns leave fourteen steps after the origin. Three 3–5 column
	# sections ending at the final column therefore use one length 4 and two
	# length 5 sections, shuffled for each run.
	var section_lengths: Array[int] = [4, 5, 5]
	for index in range(section_lengths.size() - 1, 0, -1):
		var swap_index := random.randi_range(0, index)
		var value := section_lengths[index]
		section_lengths[index] = section_lengths[swap_index]
		section_lengths[swap_index] = value
	var convergence_columns: Dictionary[int, bool] = {0: true}
	var convergence_column := 0
	for section_length in section_lengths:
		convergence_column += section_length
		convergence_columns[convergence_column] = true

	var previous_column_nodes: Array[int] = []
	for column in range(GRAPH_COLUMN_COUNT):
		var column_nodes: Array[int] = []
		var node_count := 1 if convergence_columns.has(column) else GRAPH_BRANCHES_PER_COLUMN
		for lane in range(node_count):
			var node_id := NODE_POSITIONS.size()
			var normalized_y := 0.5 if node_count == 1 else lerpf(0.28, 0.72, float(lane) / float(node_count - 1))
			NODE_POSITIONS.append(Vector2(
				lerpf(0.035, 0.965, float(column) / float(GRAPH_COLUMN_COUNT - 1)),
				normalized_y
			))
			NODE_COLUMNS.append(column)
			column_nodes.append(node_id)
			if column > 0 and convergence_columns.has(column):
				CONVERGENCE_NODE_IDS.append(node_id)
		if previous_column_nodes.size() == 1:
			for to_node in column_nodes:
				GRAPH_EDGES.append(Vector2i(previous_column_nodes[0], to_node))
		elif column_nodes.size() == 1:
			for from_node in previous_column_nodes:
				GRAPH_EDGES.append(Vector2i(from_node, column_nodes[0]))
		else:
			# Preserve each lane between convergence points so choosing a branch
			# remains meaningful until both routes meet again.
			for lane in range(mini(previous_column_nodes.size(), column_nodes.size())):
				GRAPH_EDGES.append(Vector2i(previous_column_nodes[lane], column_nodes[lane]))
		previous_column_nodes = column_nodes
	FINAL_NODE_ID = previous_column_nodes[0]


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


func get_saved_ship_designs() -> Array[Dictionary]:
	var designs: Array[Dictionary] = []
	for saved_design in saved_ship_designs:
		designs.append(saved_design.duplicate(true))
	return designs


func save_current_ship_design(
	design_name: String,
	file_path: String = SAVED_SHIP_DESIGNS_PATH
) -> String:
	if active_part_transformations > 0:
		return "Wait for ship parts to finish transforming."
	if ship.tiles.is_empty():
		return "Add at least one tile before saving this ship."

	var normalized_name := design_name.strip_edges()
	if is_builtin_ship_design(normalized_name):
		return "Choose a new name to save a copy of %s." % normalized_name
	if normalized_name.is_empty():
		return "Enter a name for this ship."
	var designs := get_saved_ship_designs()
	var existing_design_index := -1
	for index in range(designs.size()):
		if designs[index].get("name", "") == normalized_name:
			existing_design_index = index
			break
	if (
		existing_design_index >= 0
		and normalized_name != current_ship_design_name
	):
		return "A saved design already uses that name."

	var design_entry := {
		"name": normalized_name,
		"ship": ship.to_design_data(),
	}
	if existing_design_index >= 0:
		designs[existing_design_index] = design_entry
	else:
		designs.append(design_entry)
	if not _write_saved_ship_designs(designs, file_path):
		return "Could not save the ship design."

	saved_ship_designs = designs
	current_ship_design_name = normalized_name
	if not current_run_design_names.has(normalized_name):
		current_run_design_names.append(normalized_name)
	design_library_changed.emit()
	return ""


func load_saved_ship_design(design_name: String) -> bool:
	if active_part_transformations > 0:
		push_error("Cannot load a ship design while parts are transforming.")
		return false

	var serialized_ship: Variant
	if design_name == "Drone":
		serialized_ship = preload("res://scripts/builtin_ships.gd").drone().to_design_data()
	for saved_design in saved_ship_designs:
		if design_name == "Drone":
			break
		if saved_design.get("name", "") == design_name:
			serialized_ship = saved_design.get("ship")
			break
	if serialized_ship == null:
		var builtins := preload("res://scripts/builtin_ships.gd").designs()
		if builtins.has(design_name):
			serialized_ship = builtins[design_name].to_design_data()
	if serialized_ship == null:
		push_error("Could not find the saved ship design '%s'." % design_name)
		return false

	var loaded_ship := Ship.new()
	if not loaded_ship.load_design_data(serialized_ship):
		return false

	if not design_fits_build_area(loaded_ship):
		return false
	var origin := design_bounds(loaded_ship).position
	if origin != Vector2i.ZERO:
		var normalized: Dictionary[Vector2i, int] = {}
		for cell in loaded_ship.tiles:
			normalized[cell - origin] = loaded_ship.tiles[cell]
		loaded_ship.tiles = normalized
		for part in loaded_ship.parts:
			part.origin -= origin
	ship = loaded_ship
	current_ship_design_name = design_name
	ship_stats_changed.emit()
	return true


func _load_saved_ship_designs(
	file_path: String = SAVED_SHIP_DESIGNS_PATH
) -> bool:
	if not FileAccess.file_exists(file_path):
		saved_ship_designs.clear()
		return true

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error(
			"Could not read saved ship designs: %s"
			% error_string(FileAccess.get_open_error())
		)
		return false
	var serialized_file := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_error := json.parse(serialized_file)
	if parse_error != OK:
		push_error(
			"Could not parse saved ship designs at line %d: %s"
			% [json.get_error_line(), json.get_error_message()]
		)
		return false
	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("Saved ship designs must be stored in a JSON object.")
		return false
	var file_data: Dictionary = json.data
	if (
		not _is_integer_number(file_data.get("version"))
		or int(file_data["version"]) != SAVED_SHIP_DESIGNS_VERSION
	):
		push_error("Saved ship designs use an unsupported format version.")
		return false
	var serialized_designs: Variant = file_data.get("designs")
	if typeof(serialized_designs) != TYPE_ARRAY:
		push_error("Saved ship designs must contain a design array.")
		return false

	var loaded_designs: Array[Dictionary] = []
	var loaded_names: Array[String] = []
	for index in range(serialized_designs.size()):
		var serialized_design: Variant = serialized_designs[index]
		if typeof(serialized_design) != TYPE_DICTIONARY:
			push_error("Skipping malformed saved ship design at index %d." % index)
			continue
		if (
			typeof(serialized_design.get("name")) != TYPE_STRING
			or str(serialized_design["name"]).strip_edges().is_empty()
		):
			push_error("Skipping a saved ship design with an invalid name.")
			continue
		var design_name: String = serialized_design["name"]
		if loaded_names.has(design_name):
			push_error("Skipping duplicate saved ship design '%s'." % design_name)
			continue

		var serialized_ship: Variant = serialized_design.get("ship")
		var loaded_ship := Ship.new()
		if not loaded_ship.load_design_data(serialized_ship):
			push_error("Skipping invalid saved ship design '%s'." % design_name)
			continue
		loaded_designs.append({
			"name": design_name,
			"ship": serialized_ship.duplicate(true),
		})
		loaded_names.append(design_name)

	saved_ship_designs = loaded_designs
	return true


func _write_saved_ship_designs(
	designs: Array[Dictionary],
	file_path: String = SAVED_SHIP_DESIGNS_PATH
) -> bool:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error(
			"Could not save ship designs: %s"
			% error_string(FileAccess.get_open_error())
		)
		return false
	file.store_string(
		JSON.stringify({
			"version": SAVED_SHIP_DESIGNS_VERSION,
			"designs": designs,
		}, "\t")
	)
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		push_error("Could not finish writing saved ship designs: %s" % error_string(write_error))
		return false
	return true


func _load_archive_progress(file_path: String = ARCHIVE_PROGRESS_PATH) -> bool:
	if not FileAccess.file_exists(file_path):
		discovered_part_types.clear()
		unviewed_discovered_part_types.clear()
		return true
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Could not read Archive progress: %s" % error_string(FileAccess.get_open_error()))
		return false
	var serialized_file := file.get_as_text()
	file.close()
	var json := JSON.new()
	var parse_error := json.parse(serialized_file)
	if parse_error != OK:
		push_error(
			"Could not parse Archive progress at line %d: %s"
			% [json.get_error_line(), json.get_error_message()]
		)
		return false
	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("Archive progress must be stored in a JSON object.")
		return false
	var file_data: Dictionary = json.data
	if (
		not _is_integer_number(file_data.get("version"))
		or int(file_data["version"]) != ARCHIVE_PROGRESS_VERSION
	):
		push_error("Archive progress uses an unsupported format version.")
		return false
	var serialized_discovered: Variant = file_data.get("discovered")
	var serialized_unviewed: Variant = file_data.get("unviewed", [])
	if typeof(serialized_discovered) != TYPE_ARRAY or typeof(serialized_unviewed) != TYPE_ARRAY:
		push_error("Archive progress must contain discovered and unviewed arrays.")
		return false
	var valid_types: Dictionary[int, bool] = {}
	for pattern in ShipPartPattern.get_catalog():
		valid_types[pattern.part_type] = true
	var loaded_discovered: Array[int] = []
	for value in serialized_discovered:
		if not _is_integer_number(value):
			continue
		var part_type := int(value)
		if valid_types.has(part_type) and not loaded_discovered.has(part_type):
			loaded_discovered.append(part_type)
	var loaded_unviewed: Array[int] = []
	for value in serialized_unviewed:
		if not _is_integer_number(value):
			continue
		var part_type := int(value)
		if loaded_discovered.has(part_type) and not loaded_unviewed.has(part_type):
			loaded_unviewed.append(part_type)
	discovered_part_types = loaded_discovered
	unviewed_discovered_part_types = loaded_unviewed
	discovered_parts_changed.emit()
	unviewed_discoveries_changed.emit()
	return true


func _write_archive_progress(file_path: String = ARCHIVE_PROGRESS_PATH) -> bool:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not save Archive progress: %s" % error_string(FileAccess.get_open_error()))
		return false
	var discovered := discovered_part_types.duplicate()
	var unviewed := unviewed_discovered_part_types.duplicate()
	discovered.sort()
	unviewed.sort()
	file.store_string(JSON.stringify({
		"version": ARCHIVE_PROGRESS_VERSION,
		"discovered": discovered,
		"unviewed": unviewed,
	}, "\t"))
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		push_error("Could not finish writing Archive progress: %s" % error_string(write_error))
		return false
	return true


func _get_ship_tile_counts(target_ship: Ship) -> Array[int]:
	var tile_counts: Array[int] = [0, 0, 0, 0]
	for cell in target_ship.get_tile_cells():
		var category := target_ship.get_tile_category_at(cell)
		if category < 0 or category >= tile_counts.size():
			push_error("Ship design contains an unknown tile category: %s" % category)
			return []
		tile_counts[category] += 1
	return tile_counts


func _is_integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and value == roundf(value)


func get_difficulty_multiplier() -> float:
	match difficulty:
		Difficulty.EASY:
			return 0.8
		Difficulty.MEDIUM:
			return 1.0
		Difficulty.HARD:
			return 1.25
		_:
			push_error("Unknown game difficulty: %s" % difficulty)
			return 0.0


func get_available_tile_count(category: int) -> int:
	match category:
		ShipPart.Category.OFFENSE:
			return red_tiles_available
		ShipPart.Category.DEFENSE:
			return blue_tiles_available
		ShipPart.Category.SPECIAL:
			return green_tiles_available
		ShipPart.Category.CORE:
			return core_tiles_available
		_:
			push_error("Unknown ship part category: %s" % category)
			return 0


func is_equipment_available(part_type: int, rank := 1) -> bool:
	if not is_equipment_researched(part_type):
		return false
	for pattern in ShipPartPattern.get_catalog():
		if pattern.part_type == part_type and pattern.rank == rank:
			return rank <= int(research_grants().ranks.get(pattern.definition_id, 0))
	return false


func is_equipment_researched(part_type: int) -> bool:
	var definition := GameDefinitions.equipment(part_type)
	if definition.is_empty():
		return false
	return research_grants().equipment_ids.has(definition.id)


func research_grants() -> Dictionary:
	# Assembly checks many candidate origins. Reuse authorization while its
	# actual inputs are unchanged, even when callers edit IDs without a signal.
	var key := JSON.stringify([current_research_ids, story_flags, research_branch_choices])
	if key == _research_grant_key and not _research_grant_cache.is_empty():
		return _research_grant_cache.duplicate(true)
	var problem := ResearchRules.selection_error(current_research_ids, story_flags, research_branch_choices)
	if not problem.is_empty():
		_research_grant_cache = {"equipment_ids": [], "ranks": {}, "ability_ids": [], "modifiers": {}, "error": problem}
	else:
		_research_grant_cache = ResearchRules.resolve(current_research_ids)
	_research_grant_key = key
	return _research_grant_cache.duplicate(true)

func passenger_manifest() -> Array[Dictionary]:
	return PassengerRules.snapshot(fleet, economy_state)


func fleet_economy_summary(ship_id := 0) -> Dictionary:
	var ships := get_deployed_fleet() if ship_id == 0 else fleet.filter(func(owned: FleetShip) -> bool: return owned.id == ship_id)
	var ids: Array[int] = []
	var deployed_ids: Array[int] = []
	for owned in ships:
		ids.append(owned.id)
		if is_ship_deployed(owned):
			deployed_ids.append(owned.id)
	var result := {"passengers": 0, "places": 0, "luxury_min": 0, "luxury_max": 0,
		"cargo": 0, "cargo_capacity": 0, "cargo_value": 0, "tickets": 0, "has_cabins": false, "has_holds": false}
	for entry in PassengerRules.snapshot(fleet, economy_state):
		if int(entry.ship_id) not in ids:
			continue
		result.has_cabins = true
		result.passengers += int(entry.occupied)
		result.places += int(entry.capacity)
		if entry.operational:
			var luxury := int(entry.luxury)
			result.luxury_min = luxury if result.luxury_min == 0 else mini(result.luxury_min, luxury)
			result.luxury_max = maxi(result.luxury_max, luxury)
			if deployed_ids.has(int(entry.ship_id)):
				result.tickets += int(entry.capacity) * PassengerRules.ticket_price(luxury)
	for entry in CargoRules.manifest(fleet).values():
		if int(entry.ship_id) not in ids:
			continue
		result.has_holds = true
		result.cargo_capacity += int(entry.capacity)
	for record: Dictionary in economy_state.get("cargo", {}).get("holds", {}).values():
		if int(record.ship_id) in ids:
			result.cargo += int(record.quantity)
			result.cargo_value += int(record.quantity) * int(record.unit_value)
	result["planned"] = get_reachable_nodes(current_node_id).has(planned_destination_node_id)
	var inhabited: bool = not result.planned or campaign_node(planned_destination_node_id).get("inhabited", false)
	result["income"] = (result.cargo_value + result.tickets) if inhabited else 0
	return result

func energy_efficiency() -> float:
	return float(research_grants().modifiers.get("energy_efficiency", {}).get("value", 0.0))

func set_research_focus(id: String) -> bool:
	if not campaign_active or battle_pending or run_ended:
		return false
	var checkpoint := _capture_checkpoint()
	if not ResearchFocusRules.eligible(id, checkpoint.progress):
		return false
	checkpoint.progress.research_focus = id
	checkpoint = ResearchFocusRules.allocate(checkpoint)
	if checkpoint.is_empty() or not _persist_checkpoint(checkpoint):
		return false
	transaction_ledger = checkpoint.ledger
	_apply_accounting(checkpoint)
	_emit_accounting_changes()
	ship_stats_changed.emit()
	return true

# Compatibility for older callers/fixtures. The player UI sets a research focus.
func purchase_research(id: String) -> bool:
	if not campaign_active or battle_pending or run_ended:
		return false
	var requirements := ResearchRules.requirements(id, current_research_ids, story_flags, research_branch_choices)
	if not requirements.known or not requirements.implemented or requirements.owned \
		or not requirements.missing_prerequisites.is_empty() or not requirements.missing_story_gates.is_empty() \
		or not requirements.conflicts.is_empty() or requirements.branch_conflict:
		return false
	var definition := GameDefinitions.find("research", id)
	var price := ResearchFocusRules.cost(id, run_progress_snapshot())
	if price > research_points:
		return false
	var result := TransactionLedger.apply(_capture_checkpoint(), "research", id, 0, [0, 0, 0, 0], -price, {"research_id": id})
	if result.is_empty() or result.replayed:
		return false
	var checkpoint: Dictionary = result.checkpoint
	checkpoint.progress.research_ids.append(id)
	checkpoint.progress.research_progress.erase(id)
	if checkpoint.progress.research_focus == id:
		checkpoint.progress.research_focus = ""
	if not definition.family_id.is_empty():
		checkpoint.progress.branch_choices[definition.family_id] = definition.path_id
	if not _persist_checkpoint(checkpoint):
		return false
	transaction_ledger = checkpoint.ledger
	current_research_ids.assign(checkpoint.progress.research_ids)
	research_branch_choices.assign(checkpoint.progress.branch_choices)
	_apply_accounting(checkpoint)
	_emit_accounting_changes()
	ship_stats_changed.emit()
	return true

func battle_support_context() -> Dictionary:
	var progress: Dictionary = encounter_progress.get(str(destination_node_id), {})
	var context: Dictionary = progress.get("deployment", {}).get("shared_context", {"energy_efficiency": energy_efficiency(),
		"repair_reserves": progress.get("field", {}).get("repair_reserves", {}).duplicate(true)}).duplicate(true)
	if progress.get("field", {}).has("repair_reserves"):
		context.repair_reserves = progress.field.repair_reserves.duplicate(true)
	context["doctrine_pool"] = progress.get("field", {}).get("doctrine_pool", {}).duplicate(true)
	context["repair_pool"] = progress.get("field", {}).get("repair_pool", {"capacity": 0, "spent": 0.0}).duplicate(true)
	if progress.get("field", {}).has("asteroids"):
		context["asteroids"] = progress.field.asteroids.duplicate(true)
	if not context.get("ability_ids", []).is_empty():
		context["ability_state"] = ability_state.duplicate(true)
	return context


func _ready_ability_ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in research_grants().ability_ids:
		var definition := GameDefinitions.find("abilities", id)
		if not definition.is_empty() and definition.implemented:
			result.append(id)
	return result


func _mining_materials() -> Array[int]:
	if current_research_ids.has("deep_extraction"):
		return [0, 1, 2, 3]
	if current_research_ids.has("basic_extraction"):
		return [0, 1]
	return []


func commit_battle_ability(simulation: BattleSimulation, proposal: Dictionary) -> bool:
	if not battle_pending or simulation.battle_id != battle_identity() or not BattleAbilities.valid(proposal):
		return false
	var ids: Array[int] = []
	for id in encounter_progress.get(str(destination_node_id), {}).get("ship_ids", []):
		ids.append(int(id))
	for member in simulation.players:
		if member.owned_ship == null or not ids.has(member.owned_ship.id):
			return false
	var checkpoint := _capture_checkpoint()
	checkpoint.progress["ability_state"] = proposal.duplicate(true)
	var field: Dictionary = checkpoint.encounter_progress[str(destination_node_id)].field
	field["doctrine_pool"] = simulation.doctrines.pool.duplicate(true)
	field["repair_reserves"] = simulation.repair_reserves.duplicate(true)
	field["repair_pool"] = {"capacity": simulation.repair_capacity, "spent": simulation.repair_spent}
	if not _persist_checkpoint(checkpoint):
		return false
	transaction_ledger = checkpoint.ledger
	encounter_progress = checkpoint.encounter_progress
	_apply_accounting(checkpoint)
	return true

func update_battle_support(simulation: BattleSimulation) -> void:
	if battle_pending and simulation.battle_id == battle_identity() and encounter_progress.has(str(destination_node_id)):
		encounter_progress[str(destination_node_id)].field["doctrine_pool"] = simulation.doctrines.pool.duplicate(true)
	if battle_pending and not simulation.abilities.available.is_empty():
		ability_state = simulation.abilities.snapshot()
	if battle_pending and encounter_progress.has(str(destination_node_id)) and not simulation.asteroid_field.records.is_empty():
		simulation.asteroid_field.remember(simulation)
		# Live references avoid copying a whole fracture tree each physics tick.
		# RunCheckpoint.capture detaches the tree at every persistence boundary.
		encounter_progress[str(destination_node_id)].field["asteroids"] = {"version": 1,
			"records": simulation.asteroid_field.records, "roots": simulation.asteroid_field.roots,
			"impacts": simulation.asteroid_field.impacts}
	if not battle_pending or simulation.repair_reserves.is_empty() or not encounter_progress.has(str(destination_node_id)) or not SharedSupport.valid_reserves(simulation.repair_reserves):
		return
	var ids: Array[int] = []
	for id in encounter_progress[str(destination_node_id)].get("ship_ids", []):
		ids.append(int(id))
	if ids.size() != simulation.players.size():
		return
	for member in simulation.players:
		if member.owned_ship == null or not ids.has(member.owned_ship.id):
			return
	encounter_progress[str(destination_node_id)].field["repair_reserves"] = simulation.repair_reserves.duplicate(true)
	encounter_progress[str(destination_node_id)].field["repair_pool"] = {"capacity": simulation.repair_capacity, "spent": simulation.repair_spent}


func design_research_error(design: Ship) -> String:
	var grants := research_grants()
	if not grants.error.is_empty():
		return grants.error
	var implemented: Array[int] = []
	for pattern in ShipPartPattern.get_catalog():
		implemented.append(pattern.part_type)
	for part in design.parts:
		var definition := GameDefinitions.equipment(part.type)
		if definition.is_empty() or part.definition_id != definition.id:
			return "Invalid assembled equipment identity."
		if part.type not in implemented or not grants.equipment_ids.has(definition.id):
			return "Requires current-run research: %s." % definition.get("display_name", "Unknown equipment")
		if part.rank < 1 or part.rank > int(grants.ranks.get(definition.id, 0)):
			return "Requires a researched rank for %s." % definition.display_name
	return ""


func discover_part(part_type: int) -> void:
	if discovered_part_types.has(part_type):
		return

	discovered_part_types.append(part_type)
	unviewed_discovered_part_types.append(part_type)
	_write_archive_progress(archive_progress_file_path)
	discovered_parts_changed.emit()
	unviewed_discoveries_changed.emit()


func has_discovered_part(part_type: int) -> bool:
	return discovered_part_types.has(part_type)


func get_unviewed_discovery_count() -> int:
	return unviewed_discovered_part_types.size()


func mark_discoveries_viewed() -> void:
	if unviewed_discovered_part_types.is_empty():
		return

	unviewed_discovered_part_types.clear()
	_write_archive_progress(archive_progress_file_path)
	unviewed_discoveries_changed.emit()


func begin_part_transformation() -> void:
	active_part_transformations += 1
	part_transformations_changed.emit()


func end_part_transformation() -> void:
	if active_part_transformations <= 0:
		push_error("Finished a ship-part transformation when none was active.")
		return

	active_part_transformations -= 1
	part_transformations_changed.emit()


func try_consume_tile(category: int) -> bool:
	match category:
		ShipPart.Category.OFFENSE:
			if red_tiles_available <= 0:
				return false
			red_tiles_available -= 1
		ShipPart.Category.DEFENSE:
			if blue_tiles_available <= 0:
				return false
			blue_tiles_available -= 1
		ShipPart.Category.SPECIAL:
			if green_tiles_available <= 0:
				return false
			green_tiles_available -= 1
		ShipPart.Category.CORE:
			if core_tiles_available <= 0:
				return false
			core_tiles_available -= 1
		_:
			push_error("Unknown ship part category: %s" % category)
			return false

	tile_inventory_changed.emit()
	return true


func refund_tile(category: int) -> void:
	match category:
		ShipPart.Category.OFFENSE:
			red_tiles_available += 1
		ShipPart.Category.DEFENSE:
			blue_tiles_available += 1
		ShipPart.Category.SPECIAL:
			green_tiles_available += 1
		ShipPart.Category.CORE:
			core_tiles_available += 1
		_:
			push_error("Unknown ship part category: %s" % category)
			return

	tile_inventory_changed.emit()


func construction_error(blueprint: Ship = null, role := "regular", reserve_copies := false) -> String:
	role = "regular" if role in FleetRules.ROLES else role
	var design := ship if blueprint == null else blueprint
	if role not in FleetRules.ROLES:
		return "Unknown fleet slot role."
	if run_ended:
		return "This run has ended. Start a new run to construct ships."
	if campaign_active and not is_shipyard_node(current_node_id):
		return "Construction requires a secured port."
	if battle_pending or (design == ship and active_part_transformations > 0):
		return "Unavailable during deployment or transformation."
	if design.tiles.is_empty():
		return "Design a ship first."
	if not design_fits_build_area(design):
		return "Upgrade the build area to construct this design."
	var research_problem := design_research_error(design)
	if not research_problem.is_empty():
		return research_problem
	if campaign_active:
		var slot_problem := FleetRules.design_error(design, role)
		if not slot_problem.is_empty():
			return slot_problem
		if role == "regular":
			var family := family_for_design(design)
			if (family.is_empty() or not roster_state.active.has(family)) and not roster_state.active.has(""):
				return "Assign this family to one of the three regular slots first."
		elif int(roster_state.support_ids[role]) != 0 and not reserve_copies:
			return "Reserve the existing %s ship before constructing another." % role.capitalize()
	var candidate := FleetShip.new()
	if not candidate.initialize(design, next_ship_id, ""):
		return "Invalid assembled equipment footprint or orientation."
	var problem := FleetRules.design_error(design)
	if not problem.is_empty():
		return problem
	if get_construction_credit_cost(design) > 0 and credits < get_construction_credit_cost(design):
		return "Insufficient credits."
	return ""


const MATERIAL_PRICES := [Ship.RED_TILE_CREDIT_COST, Ship.BLUE_TILE_CREDIT_COST, Ship.GREEN_TILE_CREDIT_COST, Ship.CORE_TILE_CREDIT_COST]


func get_construction_credit_cost(blueprint: Ship = null) -> int:
	var design := ship if blueprint == null else blueprint
	var total := 0
	var counts := _get_ship_tile_counts(design)
	if counts.size() != MATERIAL_PRICES.size():
		return total
	for category in range(MATERIAL_PRICES.size()):
		var missing := maxi(0, counts[category] - get_available_tile_count(category))
		total += missing * MATERIAL_PRICES[category]
	return total


func get_construction_material_costs(blueprint: Ship = null) -> Array[int]:
	var design := ship if blueprint == null else blueprint
	var required := _get_ship_tile_counts(design)
	if required.size() != MATERIAL_PRICES.size():
		return []
	var costs: Array[int] = []
	for category in range(required.size()):
		costs.append(mini(required[category], get_available_tile_count(category)))
	return costs


func get_design_material_costs(blueprint: Ship = null) -> Array[int]:
	return _get_ship_tile_counts(ship if blueprint == null else blueprint)

func purchase_saved_ship(design_name: String, role := "regular") -> bool:
	for entry in get_visible_ship_designs():
		if entry.name == design_name:
			var blueprint := Ship.new()
			if not blueprint.load_design_data(entry.ship) or not construction_error(blueprint, role).is_empty():
				return false
			if not campaign_active and not _ensure_fleet_design_slot(design_name):
				return false
			return purchase_ship(blueprint, design_name, role)
	return false


func _ensure_fleet_design_slot(design_name: String) -> bool:
	if fleet_design_slots.has(design_name):
		return true
	var empty_slot := fleet_design_slots.find("")
	if empty_slot < 0:
		return false
	fleet_design_slots[empty_slot] = design_name
	return true

func purchase_ship(blueprint: Ship = null, design_name: String = "", role := "regular") -> bool:
	return purchase_ships(blueprint, design_name, role, 1)


func construction_order_quote(design: Ship, quantity: int) -> Dictionary:
	if design == null or quantity < 1 or quantity > 2147483647:
		return {}
	var required := get_design_material_costs(design)
	var stock: Array[int] = []
	var shortages: Array[int] = []
	var credit_cost := 0
	for category in range(4):
		required[category] *= quantity
		stock.append(mini(required[category], get_available_tile_count(category)))
		shortages.append(required[category] - stock[category])
		credit_cost += shortages[category] * MATERIAL_PRICES[category]
	return {"quantity": quantity, "required": required, "stock": stock, "shortages": shortages, "credits": credit_cost}


func construction_order_error(design: Ship, role: String, quantity: int) -> String:
	var quote := construction_order_quote(design, quantity)
	if quote.is_empty():
		return "Enter a whole quantity of at least 1."
	var problem := construction_error(design, role, true)
	if not problem.is_empty():
		return problem
	if int(quote.credits) > 0 and int(quote.credits) > credits:
		return "Insufficient credits for this order."
	return ""


func purchase_ships(blueprint: Ship, design_name: String, role: String, quantity: int) -> bool:
	role = "regular" if role in FleetRules.ROLES else role
	var design := ship if blueprint == null else blueprint
	if not construction_order_error(design, role, quantity).is_empty():
		return false
	var quote := construction_order_quote(design, quantity)
	var title := design_name
	if title.is_empty():
		title = current_ship_design_name if design == ship else "Ship"
	if title.is_empty():
		title = "Ship"
	var checkpoint := _capture_checkpoint()
	var family_id := ""
	var support_occupied := campaign_active and role != "regular" and int(roster_state.support_ids[role]) != 0
	if campaign_active:
		if role == "regular":
			family_id = family_for_design(design)
			if family_id.is_empty():
				family_id = "family/%d" % int(checkpoint.fleet_roster.next_family)
				checkpoint.fleet_roster.next_family += 1
				checkpoint.fleet_roster.families[family_id] = {"name": title, "blueprints": [FleetRules.fingerprint(design)], "design": design.to_design_data()}
			if not checkpoint.fleet_roster.active.has(family_id):
				var index: int = checkpoint.fleet_roster.active.find("")
				checkpoint.fleet_roster.active[index] = family_id
				checkpoint.progress.active_design_families[index] = title
		elif not support_occupied:
			checkpoint.fleet_roster.support_ids[role] = next_ship_id
			checkpoint.fleet_roster.support_names[role] = title
	var placement := 0.0
	for other in get_deployed_fleet():
		placement = maxf(placement, other.formation.x + 1.0)
	var constructed: Array[FleetShip] = []
	for index in range(quantity):
		var owned := FleetShip.new()
		if not owned.initialize(design, next_ship_id + index, "%s %d" % [title, next_ship_id + index]):
			return false
		owned.slot_role = role if campaign_active else "regular"
		owned.family_id = family_id
		owned.in_reserve = campaign_active and role != "regular" and (index > 0 or support_occupied)
		owned.formation = Vector2(placement + index, 0)
		constructed.append(owned)
		checkpoint.fleet.append(RunCheckpoint.ship_entry(owned))
	checkpoint.next_ship_id += quantity
	checkpoint.progress.credits -= int(quote.credits)
	for category in range(4):
		checkpoint.inventory[category] -= int(quote.stock[category])
	if not run_id.is_empty() and not _persist_checkpoint(checkpoint):
		return false
	_apply_accounting(checkpoint)
	roster_state = checkpoint.fleet_roster
	fleet_design_slots.assign(checkpoint.progress.active_design_families)
	next_ship_id = int(checkpoint.next_ship_id)
	fleet.append_array(constructed)
	_refresh_fleet()
	tile_inventory_changed.emit()
	credits_changed.emit()
	return true


func repair_ship(owned: FleetShip) -> bool:
	if owned == null:
		return false
	if not design_research_error(owned.design).is_empty():
		return false
	if campaign_active and not is_shipyard_node(current_node_id):
		return false
	if battle_pending or not fleet.has(owned) or not owned.is_alive():
		return false
	var quote := repair_quote(owned)
	if (int(quote.credits) > 0 and int(quote.credits) > credits) or not owned.needs_repair():
		return false
	var checkpoint := _capture_checkpoint()
	checkpoint.progress.credits -= int(quote.credits)
	for category in range(4):
		checkpoint.inventory[category] -= int(quote.materials[category])
	for entry: Dictionary in checkpoint.fleet:
		if int(entry.id) == owned.id:
			for index in range(owned.units.size()):
				entry.hp[index] = owned.units[index].max_hp
	if not run_id.is_empty() and not _persist_checkpoint(checkpoint):
		return false
	_apply_accounting(checkpoint)
	owned.repair()
	credits_changed.emit()
	tile_inventory_changed.emit()
	fleet_changed.emit()
	return true

func repair_quote(owned: FleetShip) -> Dictionary:
	var required := owned.material_counts(true)
	var materials: Array[int] = [0, 0, 0, 0]
	var price := owned.repair_cost()
	for category in range(4):
		materials[category] = mini(required[category], get_available_tile_count(category))
		price += (required[category] - materials[category]) * MATERIAL_PRICES[category]
	return {"credits": price, "materials": materials, "reconstruction": required, "repair_credits": owned.repair_cost()}


func salvage_ship_type(design_name: String) -> bool:
	if battle_pending or design_name.is_empty():
		return false
	var candidate: FleetShip
	var candidate_damage := -1.0
	for owned in fleet:
		if _fleet_ship_type_name(owned.display_name) != design_name:
			continue
		var damage := _fleet_ship_damage_fraction(owned)
		if candidate == null or damage > candidate_damage:
			candidate = owned
			candidate_damage = damage
	if candidate == null:
		return false
	return dismantle_ship(candidate)

func dismantle_ship(owned: FleetShip) -> bool:
	if owned == null or battle_pending or not fleet.has(owned) or (campaign_active and not is_shipyard_node(current_node_id)):
		return false
	if PassengerRules.occupied(economy_state, owned.id) > 0 or CargoRules.quantity(economy_state, owned.id) > 0:
		return false
	var checkpoint := _capture_checkpoint()
	var counts := owned.material_counts(false)
	for category in range(4):
		checkpoint.inventory[category] += counts[category]
	checkpoint.fleet = checkpoint.fleet.filter(func(entry: Dictionary) -> bool: return int(entry.id) != owned.id)
	for entry: Dictionary in checkpoint.fleet:
		if int(entry.escort_target_id) == owned.id:
			entry.escort_target_id = 0
	for role in ["science", "civic"]:
		if int(checkpoint.fleet_roster.support_ids[role]) == owned.id:
			checkpoint.fleet_roster.support_ids[role] = 0
	if not run_id.is_empty() and not _persist_checkpoint(checkpoint):
		return false
	_apply_accounting(checkpoint)
	roster_state = checkpoint.fleet_roster
	fleet.erase(owned)
	for other in fleet:
		if other.escort_target_id == owned.id:
			other.escort_target_id = 0
	_refresh_fleet()
	tile_inventory_changed.emit()
	return true


func _fleet_ship_type_name(display_name: String) -> String:
	var pieces := display_name.rsplit(" ", true, 1)
	return pieces[0] if pieces.size() == 2 and pieces[1].is_valid_int() else display_name


func _fleet_ship_damage_fraction(owned: FleetShip) -> float:
	var current_health := 0.0
	var maximum_health := 0.0
	for unit in owned.units:
		current_health += maxf(0.0, unit.hp)
		maximum_health += unit.max_hp
	return 1.0 - current_health / maximum_health if maximum_health > 0.0 else 1.0


func move_ship(owned: FleetShip, position: Vector2) -> void:
	if battle_pending or not fleet.has(owned) or not position.is_finite():
		return
	# Preserve separation without snapping the player's placement to slots.
	for other in fleet:
		if other != owned and other.formation.distance_to(position) < 0.8:
			return
	owned.formation = position
	fleet_changed.emit()


func _refresh_fleet() -> void:
	if campaign_active:
		for role in ["science", "civic"]:
			if not fleet.any(func(owned: FleetShip) -> bool: return owned.id == int(roster_state.support_ids[role])):
				roster_state.support_ids[role] = 0
	player_ship_count = fleet.size()
	player_ship_count_changed.emit()
	fleet_changed.emit()


func family_for_design(design: Ship) -> String:
	var key := FleetRules.fingerprint(design)
	for id in roster_state.families:
		if roster_state.families[id].blueprints.has(key):
			return id
	return ""


func _register_family(design: Ship, title: String) -> String:
	var existing := family_for_design(design)
	if not existing.is_empty():
		return existing
	var id := "family/%d" % int(roster_state.next_family)
	roster_state.next_family = int(roster_state.next_family) + 1
	roster_state.families[id] = {"name": title, "blueprints": [FleetRules.fingerprint(design)], "design": design.to_design_data()}
	return id


func _adopt_legacy_roster() -> void:
	roster_state = FleetRules.empty_roster()
	fleet_design_slots = ["", "", ""]
	for owned in fleet:
		owned.slot_role = "regular"
		owned.family_id = _register_family(owned.design, _fleet_ship_type_name(owned.display_name))
		if not roster_state.active.has(owned.family_id) and roster_state.active.has(""):
			var index: int = roster_state.active.find("")
			roster_state.active[index] = owned.family_id
			fleet_design_slots[index] = roster_state.families[owned.family_id].name


func fleet_slot_name(index: int) -> String:
	return fleet_design_slots[index] if index >= 0 and index < 3 else ""


func emergency_roster_available() -> bool:
	# Surviving reserves must be able to replace a lost combat force between
	# ports. This grants no construction, repairs, refits or abandonment.
	return campaign_active and not battle_pending and not run_ended and not get_deployed_fleet().any(func(owned: FleetShip) -> bool:
		return not owned.get_stats(laser_upgrade_level).weapons.is_empty())


func assign_fleet_design(index: int, title: String, design: Ship, revision := false) -> bool:
	if not campaign_active or index < 0 or index >= 3 or title.is_empty() or battle_pending:
		return false
	if not is_shipyard_node(current_node_id):
		if revision or not emergency_roster_available() or not fleet.any(func(owned: FleetShip) -> bool:
			return owned.is_alive() and FleetRules.fingerprint(owned.design) == FleetRules.fingerprint(design)):
			return false
	var role := "regular" if index < 3 else ("science" if index == 3 else "civic")
	if not FleetRules.design_error(design, role).is_empty():
		return false
	if not design_research_error(design).is_empty():
		return false
	var verified := Ship.new()
	if not verified.load_design_data(design.to_design_data()):
		return false
	var before := roster_state.duplicate(true)
	var names := fleet_design_slots.duplicate()
	if index < 3:
		var id := family_for_design(design)
		if revision:
			var current: String = roster_state.active[index]
			if current.is_empty() or (not id.is_empty() and id != current):
				return false
			id = current
			var key := FleetRules.fingerprint(design)
			if not roster_state.families[id].blueprints.has(key):
				roster_state.families[id].blueprints.append(key)
			roster_state.families[id].design = design.to_design_data()
		else:
			id = _register_family(design, title)
		var already: int = roster_state.active.find(id)
		if already >= 0 and already != index:
			roster_state = before
			return false
		roster_state.families[id].design = design.to_design_data()
		roster_state.active[index] = id
		fleet_design_slots[index] = title
	else:
		if roster_state.support_names[role] != title:
			# Selection changes deployment, never the physical design or its HP.
			roster_state.support_ids[role] = 0
		roster_state.support_names[role] = title
	for owned in fleet:
		if (PassengerRules.occupied(economy_state, owned.id) > 0 or CargoRules.quantity(economy_state, owned.id) > 0) and not is_ship_deployed(owned):
			roster_state = before
			fleet_design_slots.assign(names)
			return false
	if not save_run_checkpoint():
		roster_state = before
		fleet_design_slots.assign(names)
		return false
	fleet_changed.emit()
	return true


func set_ship_reserve(owned: FleetShip, reserve: bool) -> bool:
	if not campaign_active or battle_pending or not fleet.has(owned):
		return false
	if not is_shipyard_node(current_node_id) and (reserve or not emergency_roster_available()):
		return false
	if reserve and (PassengerRules.occupied(economy_state, owned.id) > 0 or CargoRules.quantity(economy_state, owned.id) > 0):
		return false
	if not reserve:
		if not design_research_error(owned.design).is_empty():
			return false
		if owned.slot_role == "regular" and not _is_active_revision(owned):
			return false
		if not FleetRules.operational_error(owned).is_empty():
			return false
		if owned.slot_role != "regular" and int(roster_state.support_ids[owned.slot_role]) not in [0, owned.id]:
			return false
	var before := roster_state.duplicate(true)
	var was_reserve := owned.in_reserve
	owned.in_reserve = reserve
	if owned.slot_role != "regular":
		if not reserve:
			roster_state.support_ids[owned.slot_role] = owned.id
		elif int(roster_state.support_ids[owned.slot_role]) == owned.id:
			roster_state.support_ids[owned.slot_role] = 0
	if not save_run_checkpoint():
		owned.in_reserve = was_reserve
		roster_state = before
		return false
	fleet_changed.emit()
	return true


func slot_blueprint(index: int) -> Ship:
	if index >= 0 and index < 3 and not str(roster_state.active[index]).is_empty():
		var design := Ship.new()
		var family: Dictionary = roster_state.families[roster_state.active[index]]
		if design.load_design_data(family.get("design", {})):
			return design
	return null


func salvage_fleet_slot(index: int) -> bool:
	if not campaign_active or battle_pending or not is_shipyard_node(current_node_id) or index < 0 or index > 4:
		return false
	var candidate: FleetShip
	for owned in fleet:
		var matches: bool = owned.family_id == roster_state.active[index] and owned.slot_role == "regular" if index < 3 else owned.id == int(roster_state.support_ids["science" if index == 3 else "civic"])
		if matches and (candidate == null or _fleet_ship_damage_fraction(owned) > _fleet_ship_damage_fraction(candidate)):
			candidate = owned
	if candidate == null:
		return false
	return dismantle_ship(candidate)


func fleet_slot_members(index: int) -> Array[FleetShip]:
	var result: Array[FleetShip] = []
	if index < 0 or index > 4:
		return result
	for owned in fleet:
		if index < 3:
			if owned.slot_role == "regular" and owned.family_id == roster_state.active[index]:
				result.append(owned)
		elif owned.id == int(roster_state.support_ids["science" if index == 3 else "civic"]):
			result.append(owned)
	return result


func _is_active_revision(owned: FleetShip) -> bool:
	if not roster_state.active.has(owned.family_id):
		return false
	var selected := Ship.new()
	return selected.load_design_data(roster_state.families[owned.family_id].get("design", {})) and FleetRules.fingerprint(selected) == FleetRules.fingerprint(owned.design)


func is_ship_deployed(owned: FleetShip) -> bool:
	if not owned.is_alive():
		return false
	if not campaign_active:
		return true
	if owned.in_reserve:
		return false
	if battle_pending:
		var progress: Dictionary = encounter_progress.get(str(destination_node_id), {})
		if progress.get("migrated_support_attempt", false) and progress.get("outcome") == "active" and progress.get("ship_ids", []).has(owned.id):
			return true
	if owned.slot_role == "regular":
		return _is_active_revision(owned)
	return int(roster_state.support_ids.get(owned.slot_role, 0)) == owned.id


func set_escort_target(owned: FleetShip, host: FleetShip) -> bool:
	if not campaign_active or battle_pending or not is_shipyard_node(current_node_id) or not fleet.has(owned) or not fleet.has(host):
		return false
	if owned == host or not is_ship_deployed(host):
		return false
	var before := owned.escort_target_id
	owned.escort_target_id = host.id
	if not save_run_checkpoint():
		owned.escort_target_id = before
		return false
	fleet_changed.emit()
	return true


func get_deployed_fleet() -> Array[FleetShip]:
	var result: Array[FleetShip] = []
	for owned in fleet:
		if is_ship_deployed(owned):
			result.append(owned)
	return result


func deployment_capacity() -> int:
	return FleetRules.capacity_for_act(current_act())


func used_deployment_capacity() -> int:
	var total := 0
	for owned in get_deployed_fleet():
		total += FleetRules.ship_capacity(owned)
	return total


func deployment_error() -> String:
	if run_ended:
		return "This run has ended. Start a new run."
	for owned in get_deployed_fleet():
		var research_problem := design_research_error(owned.design)
		if not research_problem.is_empty():
			return research_problem
	if not campaign_active:
		return ""
	if not FleetRules.valid(roster_state, fleet):
		return "Invalid fleet assignments. Reassign designs at a secured port."
	for owned in get_deployed_fleet():
		var problem := FleetRules.operational_error(owned)
		if not problem.is_empty():
			return problem
	var used := used_deployment_capacity()
	var limit := deployment_capacity()
	if used > limit:
		return "Deployment capacity %d/%d. Reserve ships at a secured port before departing." % [used, limit]
	if not get_deployed_fleet().any(func(owned: FleetShip) -> bool: return not owned.get_stats(laser_upgrade_level).weapons.is_empty()):
		return "No operational weapons. Repair at a port or select an armed reserve."
	return ""


func can_deploy() -> bool:
	return not run_ended and deployment_error().is_empty() and get_deployed_fleet().any(func(owned: FleetShip) -> bool:
		return owned.is_alive() and not owned.get_stats(laser_upgrade_level).weapons.is_empty())


func can_afford_any_ship() -> bool:
	for entry in get_visible_ship_designs():
		var design := Ship.new()
		if not design.load_design_data(entry.ship) or not design_fits_build_area(design):
			continue
		if not design_research_error(design).is_empty():
			continue
		var candidate := FleetShip.new()
		candidate.initialize(design, next_ship_id, "")
		if candidate.construction_error().is_empty() and (get_construction_credit_cost(design) == 0 or credits >= get_construction_credit_cost(design)):
			return true
	return false


func is_run_lost() -> bool:
	return run_ended or (fleet.is_empty() and not can_deploy() and not can_afford_any_ship())


func allied_salvage_chance() -> float:
	return [0.5, 0.3, 0.0][difficulty]


func purchase_laser_upgrade() -> bool:
	if battle_pending or laser_upgrade_level >= 3:
		return false
	var materials: int = [3, 7, 15][laser_upgrade_level]
	var price: int = [20, 50, 100][laser_upgrade_level]
	price += maxi(0, materials - red_tiles_available) * MATERIAL_PRICES[0]
	if credits < price:
		return false
	red_tiles_available = maxi(0, red_tiles_available - materials)
	credits -= price
	laser_upgrade_level += 1
	tile_inventory_changed.emit()
	credits_changed.emit()
	upgrades_changed.emit()
	fleet_changed.emit()
	return true


func record_battle(simulation: BattleSimulation, casualty_scope := "") -> void:
	last_battle_report.clear()
	for combatant in simulation.players:
		var owned: FleetShip = combatant.owned_ship
		if owned == null:
			continue
		var casualties := PassengerRules.casualty_summary(transaction_ledger, casualty_scope, owned.id)
		last_battle_report.append({"ship": owned, "damage": combatant.damage_dealt,
			"passenger_deaths": casualties.deaths, "passenger_fees": casualties.fee,
			"taken": combatant.damage_taken,
			"repair_damage": combatant.permanent_damage_taken,
			"deflected": combatant.damage_deflected(),
			"weapons": combatant.weapon_damage.duplicate(),
			"destroyed": not combatant.is_alive()})
		if not combatant.is_alive():
			fleet.erase(owned)
	# A midbattle checkpoint can already contain a lost host. Restarting the
	# remaining escorts must still explain that host's committed casualty fee.
	for owned in fleet:
		if owned.is_alive() or simulation.players.any(func(member: BattleSimulation.Combatant) -> bool: return member.owned_ship == owned):
			continue
		var casualties := PassengerRules.casualty_summary(transaction_ledger, casualty_scope, owned.id)
		last_battle_report.append({"ship": owned, "damage": 0.0, "taken": 0.0, "repair_damage": 0.0,
			"deflected": 0.0, "weapons": {}, "destroyed": true,
			"passenger_deaths": casualties.deaths, "passenger_fees": casualties.fee})
	for combatant in simulation.aliens:
		if combatant.alien == null or (simulation.visibility_enabled and not simulation.team_can_see(BattleSimulation.Faction.PLAYER, combatant)):
			continue
		last_battle_report.append({
			"alien": combatant.alien,
			"damage": combatant.damage_dealt,
			"taken": combatant.damage_taken,
			"repair_damage": 0.0,
			"deflected": combatant.damage_deflected(),
			"weapons": combatant.weapon_damage.duplicate(),
			"destroyed": not combatant.is_alive(),
			"is_alien": true,
		})
	fleet = fleet.filter(func(owned: FleetShip) -> bool: return owned.is_alive())
	_refresh_fleet()


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


func node_preview(node_id: int) -> Dictionary:
	var node := campaign_node(node_id)
	if node.is_empty():
		return {"title": "Sector %d" % (node_id + 1), "text": "Eliminate the hostile fleet."}
	if not node_visible(node_id):
		var act := int(node.act) - 1
		return {"title": CampaignContent.THEMES[act], "text": "Boss: %s. Routes reveal on entry." % CampaignContent.BOSSES[act]}
	var text: String = node.type.capitalize()
	text += " • Inhabited • %s goods: %d cr/unit" % [node.goods_grade, int(node.goods_unit_value)] if node.inhabited else " • Uninhabited"
	var encounter := get_frozen_encounter(node_id)
	if encounter.has("warden") and get_reachable_nodes(current_node_id).has(node_id):
		var roles: Array[String] = []
		for entry: Dictionary in encounter.roster:
			if not roles.has(entry.role):
				roles.append(entry.role)
		var count: int = encounter.roster.size()
		var summary := "Threat %.0f | %d cr | %d materials | %d-%d contacts: %s" % [encounter.budget, encounter.rewards.credits, _sum_materials(encounter.rewards.materials), maxi(1, count - 1), count + 1, ", ".join(roles)]
		var objective := "Destroy body | Pylons 2x20% | Exposed 6s | Lance 12s / 3s warning | Focus interrupts" if encounter.warden.lance else "Clear fleet | Pylon protects lead ship: 20% | Destroy pylon: exposed 6s"
		return {"title": node.name, "text": summary + "\n" + objective}
	if not encounter.is_empty():
		if encounter.has("asteroids"):
			text += "\nAsteroids / optional ore"
		text += "\nThreat %.0f • %d credits • %d materials" % [float(encounter.budget), int(encounter.rewards.credits), _sum_materials(encounter.rewards.materials)]
		if get_reachable_nodes(current_node_id).has(node_id):
			var roles: Array[String] = []
			for entry in encounter.roster:
				if not roles.has(entry.role):
					roles.append(entry.role)
			var count: int = encounter.roster.size()
			text += "\n%d–%d alien contacts • %s" % [maxi(1, count - 1), count + 1, ", ".join(roles)]
			if encounter.has("warden"):
				text += "\nDestroy body / 2 pylons: 20% each / Lance 12s, warning 3s" if encounter.warden.lance else "\nPylon protects lead ship: 20% / Clear fleet"
			elif encounter.has("arena_layout"):
				text += "\n%s | %s" % ["Defense: 3 waves / 0, 6, 12s / right entry" if int(encounter.wave_count) > 1 else "Clear marked fleet", str(encounter.arena_layout).capitalize()]
			else:
				text += "\nObjective: destroy marked hostile fleet."
			text += "\nSalvage: Defense 35%, Offense 30%, Tech 20%, Civic 15% (rounded)."
			if encounter.get("enemy_roles", false):
				var behavior: Array[String] = []
				for role in roles:
					behavior.append({"scout": "flank", "fighter": "pressure", "sentinel": "shield", "support": "repair", "chrysalis": "finite drones"}.get(role, role))
				text += "\n" + " / ".join(behavior)
	else:
		text += "\nNo battle."
		if node.type == "salvage":
			text += " Recover %d materials." % _sum_materials(node.material_reward)
	if get_reachable_nodes(current_node_id).has(node_id):
		var route := edge_preview(current_node_id, node_id)
		if not route.is_empty() and route.hazard != "none":
			text += "\nCharted %s • safe passage. Mineral potential: %s; extraction unavailable." % [str(route.hazard).replace("_", " "), route.mining_potential]
		else:
			text += "\nSafe passage • asteroid density: none."
		var ids: Array[int] = []
		for owned in get_deployed_fleet():
			ids.append(owned.id)
		var boarding := PassengerRules.boarding(economy_state, fleet, ids) if node.inhabited else {}
		text += "\nPassenger tickets: %d • cargo sale: %d" % [int(boarding.get("tickets", 0)), CargoRules.value(economy_state) if node.inhabited else 0]
	if node_id == current_node_id:
		text += "\nAct %d: %s" % [current_act(), CampaignContent.THEMES[current_act() - 1]]
		if current_act() < 3:
			text += "\nNext act: %s | Boss: %s. Routes reveal on entry." % [CampaignContent.THEMES[current_act()], CampaignContent.BOSSES[current_act()]]
	return {"title": node.name, "text": text.replace("•", "|").replace("–", "-")}


func _sum_materials(values: Array) -> int:
	var total := 0
	for amount in values:
		total += int(amount)
	return total


func travel_to(node_id: int) -> bool:
	if not campaign_active:
		return set_destination(node_id)
	if battle_pending or run_ended or not can_deploy() or not get_reachable_nodes(current_node_id).has(node_id):
		return false
	var node := campaign_node(node_id)
	if node.kind in ["combat", "boss"]:
		return set_destination(node_id)
	var checkpoint := _capture_checkpoint()
	var science := ScienceRules.snapshot(get_deployed_fleet())
	var travel_days := research_travel_time(current_node_id, node_id)
	var reward := TransactionLedger.apply(checkpoint, "node_reward", "node/%d" % node_id, 0, node.material_reward,
		ScienceRules.journey_rp(science, travel_days), {"science_snapshot": science, "research_travel_days": travel_days})
	if reward.is_empty():
		return false
	checkpoint = _secure_node(reward.checkpoint, node_id)
	if checkpoint.is_empty():
		return false
	checkpoint.location.current = node_id
	checkpoint.location.destination = -1
	checkpoint.location.planned = -1
	checkpoint.location.visited.append(node_id)
	return _commit_campaign_checkpoint(checkpoint)


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

func _secure_node(checkpoint: Dictionary, node_id: int) -> Dictionary:
	var node := campaign_node(node_id)
	if node.is_empty():
		return {}
	for id in node.story_ids:
		checkpoint.progress.story_flags["delivered/" + id] = true
	if node.kind == "boss":
		checkpoint.progress.story_flags[["boss_i_defeated", "boss_ii_defeated", "boss_iii_defeated"][int(node.act) - 1]] = true
	if node.inhabited:
		var physical: Array[FleetShip] = []
		if ArrivalRules.has_arrival_components(checkpoint):
			var decoded := RunCheckpoint.decode(checkpoint)
			if decoded.is_empty():
				return {}
			physical.assign(decoded.fleet)
		checkpoint = ArrivalRules.apply(checkpoint, node, physical)
	return ResearchFocusRules.allocate(checkpoint)


func _commit_campaign_checkpoint(checkpoint: Dictionary) -> bool:
	if not _persist_checkpoint(checkpoint):
		return false
	transaction_ledger = checkpoint.ledger
	_apply_accounting(checkpoint)
	_apply_location(checkpoint)
	story_flags.assign(checkpoint.progress.story_flags)
	_emit_accounting_changes()
	return true


func dispatch_arrival() -> bool:
	# Secured inhabited arrival only; opening a port is a separate read-only operation.
	if not campaign_active or battle_pending or not visited_nodes.has(current_node_id) or not campaign_node(current_node_id).get("inhabited", false):
		return false
	var checkpoint := _secure_node(_capture_checkpoint(), current_node_id)
	return not checkpoint.is_empty() and _commit_campaign_checkpoint(checkpoint)


func port_services() -> Dictionary:
	if not is_shipyard_node(current_node_id):
		return {}
	return campaign_node(current_node_id)


func commit_port_service(action: String, economy_after: Dictionary) -> bool:
	if not campaign_active or port_services().is_empty() or action not in ["offload", "disembark"] or not RunCheckpoint._json_value(economy_after):
		return false
	return commit_event("port_service", "node/%d/%s" % [current_node_id, action], 0, [0, 0, 0, 0], 0, {}, economy_after)


func disembark_passengers(ship_id := 0) -> bool:
	if battle_pending or port_services().is_empty() or not PassengerRules.valid(economy_state, fleet):
		return false
	if ship_id != 0 and not fleet.any(func(owned: FleetShip) -> bool: return owned.id == ship_id):
		return false
	if PassengerRules.occupied(economy_state, ship_id) == 0:
		return true
	var economy := economy_state.duplicate(true)
	for record: Dictionary in economy.passengers.components.values():
		if ship_id == 0 or int(record.ship_id) == ship_id:
			record.occupied = 0
	if ship_id != 0:
		return commit_event("port_service", "node/%d/disembark/ship/%d" % [current_node_id, ship_id], 0, [0, 0, 0, 0], 0, {}, economy)
	return commit_port_service("disembark", economy)


func offload_cargo(ship_id := 0) -> bool:
	if not campaign_active or battle_pending or not visited_nodes.has(current_node_id) \
		or not campaign_node(current_node_id).get("inhabited", false):
		return false
	if ship_id != 0 and not fleet.any(func(owned: FleetShip) -> bool: return owned.id == ship_id):
		return false
	if CargoRules.quantity(economy_state, ship_id) == 0:
		return true
	var checkpoint := CargoRules.sell(_capture_checkpoint(), fleet, ship_id)
	if checkpoint.is_empty() or not _persist_checkpoint(checkpoint):
		return false
	transaction_ledger = checkpoint.ledger
	_apply_accounting(checkpoint)
	_emit_accounting_changes()
	return true


func story_archive() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id in CampaignContent.STORIES:
		if story_flags.get("delivered/" + id, false):
			var entry: Dictionary = CampaignContent.STORIES[id].duplicate()
			entry.id = id
			entries.append(entry)
	return entries


func mark_story_seen(ids: Array[String]) -> bool:
	var before := story_flags.duplicate()
	for id in ids:
		if not story_flags.get("delivered/" + id, false):
			return false
	for id in ids:
		story_flags["seen/" + id] = true
	if not save_run_checkpoint():
		story_flags.assign(before)
		return false
	return true


func set_planned_destination(node_id: int) -> bool:
	if battle_pending or not get_reachable_nodes(current_node_id).has(node_id):
		return false
	if planned_destination_node_id != node_id:
		planned_destination_node_id = node_id
		travel_plan_changed.emit()
	return true


func is_shipyard_node(node_id: int) -> bool:
	if campaign_active:
		return not battle_pending and node_id == current_node_id and campaign_node(node_id).get("inhabited", false)
	var convergence_index := CONVERGENCE_NODE_IDS.find(node_id)
	return convergence_index == 0 or convergence_index == 1


func get_frozen_encounter(node_id: int) -> Dictionary:
	return frozen_encounters.get(str(node_id), {}).duplicate(true)


func battle_material_rewards() -> Array[int]:
	var result: Array[int] = []
	var encounter := get_frozen_encounter(destination_node_id)
	if encounter.is_empty() or encounter.legacy:
		return result
	for category in range(4):
		for unit in range(int(encounter.rewards.materials[category])):
			result.append(category)
	return result


func battle_simulation_seed() -> int:
	return int(get_frozen_encounter(destination_node_id).get("seed", "0"))


func battle_identity() -> String:
	var progress: Dictionary = encounter_progress.get(str(destination_node_id), {})
	return "%s/node/%d/attempt/%d" % [run_id, destination_node_id, int(progress.get("attempts", 1))]


func battle_objective_ids() -> Array[String]:
	return EncounterGenerator.objective_ids(get_frozen_encounter(destination_node_id))


func set_destination(node_id: int) -> bool:
	if battle_pending or not can_deploy():
		return false
	if not get_reachable_nodes(current_node_id).has(node_id):
		return false
	var encounter := get_frozen_encounter(node_id)
	if not EncounterGenerator.valid(encounter) or encounter.template_id not in ["patrol", "elite", "boss_patrol", "relay_defense", "bastion_warden", "pylon_escort"]:
		return false
	if encounter.template_id == "relay_defense" and not encounter.has("arena_layout"):
		return false
	var next_battle_aliens := EncounterGenerator.initial_fleet(encounter)
	if next_battle_aliens.is_empty():
		push_error("Could not create the alien fleet for the selected destination.")
		return false

	destination_node_id = node_id
	planned_destination_node_id = node_id
	battle_pending = true
	battle_aliens.clear()
	for alien in next_battle_aliens:
		battle_aliens.append(alien)
	var previous_progress: Dictionary = encounter_progress.duplicate(true)
	var progress: Dictionary = encounter_progress.get(str(node_id), {"attempts": 0, "outcome": "withdrawn", "field": {}}).duplicate(true)
	progress.erase("migrated_support_attempt")
	progress.attempts = int(progress.attempts) + 1
	progress.outcome = "active"
	if encounter.has("asteroids") and not progress.field.has("asteroids"):
		progress.field["asteroids"] = encounter.asteroids.duplicate(true)
	progress.ship_ids = []
	for owned: FleetShip in get_deployed_fleet():
		progress.ship_ids.append(owned.id)
	var deployment := _capture_checkpoint()
	var deployed_snapshots: Array = deployment.fleet.filter(func(entry: Dictionary) -> bool: return progress.ship_ids.has(int(entry.id)))
	progress.deployment = {"fleet": deployed_snapshots, "aliens": deployment.aliens,
		"seed": str(battle_simulation_seed()), "salvage_chance": allied_salvage_chance(),
		"upgrade_level": laser_upgrade_level, "neutral_cleanup": destroy_all_neutral_targets,
		"objectives": battle_objective_ids(), "materials": battle_material_rewards()}
	progress.science_snapshot = ScienceRules.snapshot(get_deployed_fleet())
	progress.research_distance = research_travel_distance(current_node_id, node_id)
	progress.research_travel_days = research_travel_time(current_node_id, node_id)
	progress.deployment["shared_context"] = {"energy_efficiency": energy_efficiency(),
		"visibility_enabled": true,
		"enemy_roles": not encounter.legacy and encounter.get("enemy_roles", false),
		"mining_materials": _mining_materials(),
		"ability_state": ability_state.duplicate(true),
		"ability_ids": _ready_ability_ids(),
		"repair_reserves": progress.field.get("repair_reserves", {}).duplicate(true),
		"doctrine_pool": progress.field.get("doctrine_pool", {}).duplicate(true),
		"repair_pool": progress.field.get("repair_pool", {"capacity": 0, "spent": 0.0}).duplicate(true)}
	if encounter.has("arena_layout"):
		progress.deployment.shared_context["encounter_plan"] = encounter.duplicate(true)
	if progress.field.has("asteroids"):
		progress.deployment.shared_context["asteroids"] = progress.field.asteroids.duplicate(true)
	progress.erase("journal")
	encounter_progress[str(node_id)] = progress
	if not save_run_checkpoint():
		encounter_progress = previous_progress
		destination_node_id = -1
		planned_destination_node_id = -1
		battle_pending = false
		battle_aliens.clear()
		return false
	return true


func complete_battle(surviving_player_ship_count: int = -1, salvage_categories: Array = [], staged: Dictionary = {}) -> bool:
	if not battle_pending:
		push_error("Auto-battle finished without an active deployment.")
		return false
	if not get_reachable_nodes(current_node_id).has(destination_node_id):
		push_error("The deployed destination is no longer reachable.")
		return false
	if surviving_player_ship_count < -1 or surviving_player_ship_count > player_ship_count:
		push_error("Battle victory reported an invalid surviving player ship count.")
		return false

	var materials: Array[int] = [0, 0, 0, 0]
	var encounter := get_frozen_encounter(destination_node_id)
	if encounter.is_empty():
		return false
	if not encounter.legacy:
		salvage_categories = battle_material_rewards()
	for category in salvage_categories:
		if not RunProgressData._integer(category) or category < 0 or category > 3:
			return false
		materials[int(category)] += 1
	var progress: Dictionary = encounter_progress.get(str(destination_node_id), {})
	var science: Dictionary = progress.get("science_snapshot", {"version": 1, "labs": [], "total_rp": 0})
	if not ScienceRules.valid(science, progress.get("ship_ids", [])):
		return false
	var distance := research_travel_distance(current_node_id, destination_node_id)
	if progress.has("research_distance") and progress.research_distance != distance:
		return false
	var travel_days := research_travel_time(current_node_id, destination_node_id)
	if progress.has("research_travel_days") and not is_equal_approx(float(progress.research_travel_days), travel_days):
		return false
	var result := TransactionLedger.apply(_capture_checkpoint() if staged.is_empty() else staged, "victory", "node/%d" % destination_node_id,
		int(encounter.rewards.credits), materials, ScienceRules.journey_rp(science, travel_days),
		{"science_snapshot": science, "research_travel_days": travel_days})
	if result.is_empty():
		return false
	var checkpoint: Dictionary = result.checkpoint
	checkpoint.location.current = destination_node_id
	if not checkpoint.location.visited.has(destination_node_id):
		checkpoint.location.visited.append(destination_node_id)
	checkpoint.location.destination = -1
	checkpoint.location.planned = -1
	checkpoint.location.pending = false
	checkpoint.aliens.clear()
	_set_encounter_outcome(checkpoint, "victory")
	if campaign_active:
		checkpoint = _secure_node(checkpoint, destination_node_id)
		if checkpoint.is_empty():
			return false
	if not _persist_checkpoint(checkpoint):
		return false
	transaction_ledger = checkpoint.ledger
	_apply_accounting(checkpoint)
	_apply_location(checkpoint)
	if campaign_active:
		story_flags.assign(checkpoint.progress.story_flags)
	encounter_progress = checkpoint.encounter_progress
	if surviving_player_ship_count >= 0:
		player_ship_count = surviving_player_ship_count
		player_ship_count_changed.emit()
	_emit_accounting_changes()
	return true


func cancel_battle(surviving_player_ship_count: int = -1, terminal_defeat := false, staged: Dictionary = {}) -> bool:
	if surviving_player_ship_count < -1 or surviving_player_ship_count > player_ship_count:
		push_error("Battle cancellation reported an invalid surviving player ship count.")
		return false
	if not battle_pending:
		return true
	var checkpoint := _capture_checkpoint() if staged.is_empty() else staged
	checkpoint.location.destination = -1
	checkpoint.location.planned = -1
	checkpoint.location.pending = false
	checkpoint.aliens.clear()
	_set_encounter_outcome(checkpoint, "defeat" if terminal_defeat else "withdrawn")
	checkpoint.progress.run_ended = run_ended or terminal_defeat
	if not _persist_checkpoint(checkpoint):
		return false
	transaction_ledger = checkpoint.ledger
	_apply_accounting(checkpoint)
	run_ended = checkpoint.progress.run_ended
	encounter_progress = checkpoint.encounter_progress
	if surviving_player_ship_count >= 0:
		player_ship_count = surviving_player_ship_count
		player_ship_count_changed.emit()
	destination_node_id = -1
	planned_destination_node_id = -1
	battle_pending = false
	battle_aliens.clear()
	_emit_accounting_changes()
	return true


func _set_encounter_outcome(checkpoint: Dictionary, outcome: String) -> void:
	var key := str(destination_node_id)
	if not checkpoint.encounter_progress.has(key):
		checkpoint.encounter_progress[key] = {"attempts": 1, "outcome": outcome, "field": {}}
	checkpoint.encounter_progress[key].outcome = outcome


func settle_battle(simulation: BattleSimulation) -> bool:
	if not battle_pending or simulation.phase not in [BattleSimulation.Phase.VICTORY, BattleSimulation.Phase.WITHDRAWN, BattleSimulation.Phase.DEFEAT]:
		return false
	# Setup owns the same physical ships; never settle an unrelated simulation.
	var progress: Dictionary = encounter_progress.get(str(destination_node_id), {})
	var expected_ids: Array[int] = []
	for id in progress.get("ship_ids", []):
		expected_ids.append(int(id))
	if expected_ids.is_empty():
		for owned: FleetShip in fleet:
			expected_ids.append(owned.id)
	if simulation.players.size() > expected_ids.size():
		return false
	var seen_ids: Array[int] = []
	for member in simulation.players:
		if member.owned_ship == null or not expected_ids.has(member.owned_ship.id) or seen_ids.has(member.owned_ship.id):
			return false
		if not fleet.has(member.owned_ship) and member.is_alive():
			return false
		seen_ids.append(member.owned_ship.id)
	for owned in fleet:
		if owned.id in expected_ids and owned.is_alive() and owned.id not in seen_ids:
			return false
	update_battle_support(simulation)
	# Settle occupied losses while the dead hosts still exist, then stage hull
	# removal. Failed writes leave funds, loads, roster and fleet retryable.
	var lost: Array[int] = []
	for owned in fleet:
		if not owned.is_alive():
			lost.append(owned.id)
	for member in simulation.players:
		if not member.is_alive() and member.owned_ship.id not in lost:
			lost.append(member.owned_ship.id)
	var checkpoint := _capture_checkpoint(lost)
	checkpoint.encounter_progress[str(destination_node_id)].journal = {"battle_id": simulation.battle_id,
		"deployment": progress.get("deployment", {}).duplicate(true),
		"commands": simulation.command_log.duplicate(true), "events": simulation.event_log.duplicate(true),
		"snapshot": simulation.authoritative_snapshot()}
	_stage_fleet_losses(checkpoint, lost)
	var settled: bool
	var casualty_scope := passenger_loss_scope()
	if simulation.phase == BattleSimulation.Phase.VICTORY:
		settled = complete_battle(-1, simulation.collected_categories, checkpoint)
	else:
		settled = cancel_battle(-1, simulation.phase == BattleSimulation.Phase.DEFEAT and checkpoint.fleet.is_empty(), checkpoint)
	if not settled:
		return false
	roster_state = checkpoint.fleet_roster
	for owned in fleet:
		if owned.escort_target_id in lost:
			owned.escort_target_id = 0
	record_battle(simulation, casualty_scope)
	return true


func _stage_fleet_losses(checkpoint: Dictionary, lost: Array[int]) -> void:
	checkpoint.fleet = checkpoint.fleet.filter(func(entry: Dictionary) -> bool: return int(entry.id) not in lost)
	for entry: Dictionary in checkpoint.fleet:
		if int(entry.escort_target_id) in lost:
			entry.escort_target_id = 0
	for role in ["science", "civic"]:
		if int(checkpoint.fleet_roster.support_ids[role]) in lost:
			checkpoint.fleet_roster.support_ids[role] = 0


func commit_field_pickup(pickup_id: String, materials: Array, field_after: Dictionary) -> bool:
	# Future mining commits the finite field and pickup ledger in one generation.
	# A withdrawal/retry preserves this field while enemies reset from the frozen roster.
	if not battle_pending or pickup_id.is_empty() or not RunCheckpoint._json_value(field_after):
		return false
	for amount in materials:
		if not RunProgressData._integer(amount) or amount < 0:
			return false
	var checkpoint := _capture_checkpoint()
	var key := str(destination_node_id)
	field_after = field_after.duplicate(true)
	# Repair expenditure is durable battle state, not part of ore pickup identity.
	field_after.erase("repair_reserves")
	field_after.erase("repair_pool")
	field_after.erase("doctrine_pool")
	if not checkpoint.encounter_progress.has(key):
		checkpoint.encounter_progress[key] = {"attempts": 1, "outcome": "active", "field": {}}
	var result := TransactionLedger.apply(checkpoint, "ore_pickup", "node/%s/%s" % [key, pickup_id], 0, materials, 0, {"field": field_after})
	if result.is_empty():
		return false
	checkpoint = result.checkpoint
	if not result.replayed:
		if checkpoint.encounter_progress[key].field.has("doctrine_pool"):
			field_after["doctrine_pool"] = checkpoint.encounter_progress[key].field.doctrine_pool.duplicate(true)
		if checkpoint.encounter_progress[key].field.has("repair_reserves"):
			field_after["repair_reserves"] = checkpoint.encounter_progress[key].field.repair_reserves.duplicate(true)
			field_after["repair_pool"] = checkpoint.encounter_progress[key].field.get("repair_pool", {"capacity": 0, "spent": 0.0}).duplicate(true)
		checkpoint.encounter_progress[key].field = field_after.duplicate(true)
	if not RunCheckpoint.valid(checkpoint) or not _persist_checkpoint(checkpoint):
		return false
	transaction_ledger = checkpoint.ledger
	encounter_progress = checkpoint.encounter_progress
	_apply_accounting(checkpoint)
	_emit_accounting_changes()
	return true


func commit_asteroid_pickup(simulation: BattleSimulation, pickup_id: String, materials: Array, asteroids: Dictionary) -> bool:
	if not battle_pending or simulation.battle_id != battle_identity() or not AsteroidField.valid(asteroids):
		return false
	var ids: Array[String] = []
	for id: String in asteroids.records:
		if asteroids.records[id].claimed and simulation.asteroid_field.records.has(id) and not simulation.asteroid_field.records[id].claimed:
			ids.append(id)
	if ids.is_empty() or AsteroidField.pickup_key(ids) != pickup_id:
		return false
	var proposal: Dictionary = simulation.asteroid_field.propose_pickups(ids)
	if proposal.is_empty() or proposal.materials != materials or proposal.field != asteroids:
		return false
	var expected: Array = encounter_progress.get(str(destination_node_id), {}).get("ship_ids", [])
	for member in simulation.players:
		if member.owned_ship == null or not expected.any(func(id: Variant) -> bool: return int(id) == member.owned_ship.id):
			return false
	var old_field: Dictionary = encounter_progress.get(str(destination_node_id), {}).get("field", {}).duplicate(true)
	var field := old_field.duplicate(true)
	field["asteroids"] = asteroids.duplicate(true)
	# Include current physical losses, ability cooldowns and repair expenditure in
	# the same durable generation as the pickup, never a separate material grant.
	update_battle_support(simulation)
	var ok := commit_field_pickup("asteroid/" + pickup_id, materials, field)
	if not ok:
		encounter_progress[str(destination_node_id)].field = old_field
	return ok


func is_builtin_ship_design(design_name: String) -> bool:
	if design_name == "Drone":
		return true
	# Preserve player designs that predate these additional templates.
	for entry in saved_ship_designs:
		if entry.name == design_name:
			return false
	return design_name in preload("res://scripts/builtin_ships.gd").NAMES


func get_visible_ship_designs(query: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var search := query.strip_edges().to_lower()
	var builtins := preload("res://scripts/builtin_ships.gd").designs()
	for title: String in builtins:
		if not is_builtin_ship_design(title) or (not search.is_empty() and not title.to_lower().contains(search)):
			continue
		var builtin: Ship = builtins[title]
		result.append({"name": title, "ship": builtin.to_design_data(), "builtin": true})
	for entry in saved_ship_designs:
		var title: String = entry.name
		if title == "Drone":
			continue
		if not query.strip_edges().is_empty() and not title.to_lower().contains(query.strip_edges().to_lower()):
			continue
		result.append(entry.duplicate(true))
	return result


func delete_saved_ship_design(design_name: String, file_path: String = SAVED_SHIP_DESIGNS_PATH) -> bool:
	if is_builtin_ship_design(design_name):
		return false
	var designs := get_saved_ship_designs()
	var index := -1
	for i in range(designs.size()):
		if designs[i].name == design_name:
			index = i
	if index < 0:
		return false
	designs.remove_at(index)
	if not _write_saved_ship_designs(designs, file_path):
		return false
	saved_ship_designs = designs
	current_run_design_names.erase(design_name)
	if current_ship_design_name == design_name:
		current_ship_design_name = ""
	design_library_changed.emit()
	return true


func build_area_size() -> int:
	return BASE_BUILD_SIZE + 2 * build_area_level


func purchase_build_area_upgrade() -> bool:
	if battle_pending or build_area_size() >= MAX_BUILD_SIZE:
		return false
	var price := 50
	for category in range(4):
		if get_available_tile_count(category) == 0:
			price += MATERIAL_PRICES[category]
	if credits < price:
		return false
	if campaign_active and not is_shipyard_node(current_node_id):
		return false
	var checkpoint := _capture_checkpoint()
	checkpoint.progress.credits -= price
	for category in range(4):
		checkpoint.inventory[category] = maxi(0, int(checkpoint.inventory[category]) - 1)
	checkpoint.build_level += 1
	if not run_id.is_empty() and not _persist_checkpoint(checkpoint):
		return false
	_apply_accounting(checkpoint)
	build_area_level = int(checkpoint.build_level)
	build_area_changed.emit()
	upgrades_changed.emit()
	credits_changed.emit()
	tile_inventory_changed.emit()
	return true


func design_bounds(design: Ship) -> Rect2i:
	if design.tiles.is_empty():
		return Rect2i()
	var cells := design.get_tile_cells()
	var lower := cells[0]
	var upper := cells[0]
	for cell in cells:
		lower = Vector2i(mini(lower.x, cell.x), mini(lower.y, cell.y))
		upper = Vector2i(maxi(upper.x, cell.x), maxi(upper.y, cell.y))
	return Rect2i(lower, upper - lower + Vector2i.ONE)


func design_fits_build_area(design: Ship) -> bool:
	var bounds := design_bounds(design)
	return bounds.size.x <= build_area_size() and bounds.size.y <= build_area_size()


func campaign_level() -> int:
	if current_node_id < 0 or current_node_id >= NODE_COLUMNS.size():
		return 1
	return NODE_COLUMNS[current_node_id] + 1
