extends Node

signal build_area_changed
signal design_library_changed
signal fleet_changed
signal upgrades_changed
signal research_changed

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
const MIN_ALIEN_FLEET_SIZE := 3
const MAX_ALIEN_FLEET_SIZE := 8
const STARTING_CREDITS := 1200
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
var fleet_formation_index := 0
var battle_auto_camera := true
var battle_fast_forward := false
var archive_progress_file_path := ARCHIVE_PROGRESS_PATH

# Run authorization is deliberately independent of Archive discoveries/designs.
var current_research_ids: Array[String] = ["foundation"]
var research_points := 0
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
	get_tree().node_added.connect(_disable_non_text_keyboard_focus)
	_disable_keyboard_focus_recursively(get_tree().root)
	_load_archive_progress(archive_progress_file_path)
	_load_saved_ship_designs()


func _disable_keyboard_focus_recursively(node: Node) -> void:
	_disable_non_text_keyboard_focus(node)
	for child in node.get_children():
		_disable_keyboard_focus_recursively(child)


func _disable_non_text_keyboard_focus(node: Node) -> void:
	if node is BaseButton or node is Range:
		(node as Control).focus_mode = Control.FOCUS_NONE


func is_modal_ui_open() -> bool:
	var current_scene := get_tree().current_scene
	return current_scene != null and _node_contains_visible_modal(current_scene, current_scene)


func _node_contains_visible_modal(node: Node, scene_root: Node) -> bool:
	if node != scene_root and node is Window and node.visible:
		return true
	if (
		node != scene_root
		and node is Control
		and node.visible
		and node.name in [&"GraphModal", &"VictoryDialog", &"DefeatDialog", &"QuitConfirmOverlay"]
	):
		return true
	for child in node.get_children():
		if _node_contains_visible_modal(child, scene_root):
			return true
	return false


func start_new_run(selected_difficulty: int = Difficulty.MEDIUM, seed_value: int = -1) -> bool:
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
	current_node_id = 0
	destination_node_id = -1
	planned_destination_node_id = -1
	visited_nodes = [0]
	battle_pending = false
	player_ship_count = 0
	fleet.clear()
	current_run_design_names.clear()
	fleet_design_slots = ["", "", ""]
	fleet_formation_index = 0
	next_ship_id = 1
	laser_upgrade_level = 0
	build_area_level = 0
	last_battle_report.clear()
	current_ship_design_name = ""
	credits = STARTING_CREDITS
	difficulty = selected_difficulty as Difficulty
	frozen_encounters = EncounterGenerator.freeze_graph(run_seed, difficulty, NODE_COLUMNS)
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
	for part in drone.parts:
		discover_part(part.type)
	_refresh_fleet()
	design_library_changed.emit()
	tile_inventory_changed.emit()
	ship_stats_changed.emit()
	credits_changed.emit()
	player_ship_count_changed.emit()
	research_changed.emit()
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
		"research_ids": current_research_ids.duplicate(),
		"branch_choices": research_branch_choices.duplicate(),
		"story_flags": story_flags.duplicate(),
		"active_design_families": fleet_design_slots.duplicate(),
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
	research_points = int(data.research_points)
	current_research_ids.assign(data.research_ids)
	research_branch_choices.assign(data.branch_choices)
	story_flags.assign(data.story_flags)
	fleet_design_slots.assign(data.active_design_families)
	current_run_design_names.assign(data.current_run_design_names)
	destroy_all_neutral_targets = data.get("destroy_all_neutral_targets", false)
	run_ended = data.get("run_ended", false)
	_generate_campaign_graph()
	if notify:
		research_changed.emit()
		credits_changed.emit()
		design_library_changed.emit()
	return true


func save_run_checkpoint() -> bool:
	if run_id.is_empty():
		return false
	return _persist_checkpoint(RunCheckpoint.capture(self))


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
	if saved.payload.version == 1:
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
	economy_state = data.economy.duplicate(true)
	frozen_encounters = data.encounters.duplicate(true)
	_apply_accounting(data)
	fleet.assign(decoded.fleet)
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


func commit_event(kind: String, source_id: String, credits_delta := 0,
	material_delta: Array = [0, 0, 0, 0], rp_delta := 0, details: Dictionary = {}, economy_after: Variant = null) -> bool:
	var result := TransactionLedger.apply(RunCheckpoint.capture(self), kind, source_id,
		credits_delta, material_delta, rp_delta, details, economy_after)
	if result.is_empty():
		return false
	if result.replayed:
		return true
	if not _persist_checkpoint(result.checkpoint):
		return false
	# Keep physical ship references alive while combat is running.
	transaction_ledger = result.checkpoint.ledger
	economy_state = result.checkpoint.economy.duplicate(true)
	_apply_accounting(result.checkpoint)
	_emit_accounting_changes()
	return true


func _apply_accounting(data: Dictionary) -> void:
	credits = int(data.progress.credits)
	research_points = int(data.progress.research_points)
	red_tiles_available = int(data.inventory[0])
	blue_tiles_available = int(data.inventory[1])
	green_tiles_available = int(data.inventory[2])
	core_tiles_available = int(data.inventory[3])


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
	if normalized_name == "Drone":
		return "Choose a new name to save a copy of Drone."
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


func is_equipment_available(part_type: int) -> bool:
	if not is_equipment_researched(part_type):
		return false
	for pattern in ShipPartPattern.get_catalog():
		if pattern.part_type == part_type:
			return true
	return false


func is_equipment_researched(part_type: int) -> bool:
	var definition := GameDefinitions.equipment(part_type)
	if definition.is_empty():
		return false
	for research_id in current_research_ids:
		var research := GameDefinitions.find("research", research_id)
		if not research.is_empty() and research.grants.equipment_ids.has(definition.id):
			return true
	return false


func design_research_error(design: Ship) -> String:
	for part in design.parts:
		if not is_equipment_available(part.type):
			var definition := GameDefinitions.equipment(part.type)
			return "Requires current-run research: %s." % definition.get("display_name", "Unknown equipment")
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


func construction_error(blueprint: Ship = null) -> String:
	var design := ship if blueprint == null else blueprint
	if run_ended:
		return "This run has ended. Start a new run to construct ships."
	if battle_pending or (design == ship and active_part_transformations > 0):
		return "Unavailable during deployment or transformation."
	if design.tiles.is_empty():
		return "Design a ship first."
	if not design_fits_build_area(design):
		return "Upgrade the build area to construct this design."
	var research_problem := design_research_error(design)
	if not research_problem.is_empty():
		return research_problem
	var candidate := FleetShip.new()
	candidate.initialize(design, next_ship_id, "")
	var problem := candidate.construction_error()
	if not problem.is_empty():
		return problem
	if credits < get_construction_credit_cost(design):
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

func purchase_material(category: int) -> bool:
	if battle_pending or category < 0 or category >= MATERIAL_PRICES.size():
		return false
	var price: int = MATERIAL_PRICES[category]
	if credits < price:
		return false
	credits -= price
	match category:
		0: red_tiles_available += 1
		1: blue_tiles_available += 1
		2: green_tiles_available += 1
		3: core_tiles_available += 1
	credits_changed.emit()
	tile_inventory_changed.emit()
	return true

func purchase_saved_ship(design_name: String) -> bool:
	for entry in get_visible_ship_designs():
		if entry.name == design_name:
			var blueprint := Ship.new()
			if not blueprint.load_design_data(entry.ship) or not construction_error(blueprint).is_empty():
				return false
			if not _ensure_fleet_design_slot(design_name):
				return false
			return purchase_ship(blueprint, design_name)
	return false


func _ensure_fleet_design_slot(design_name: String) -> bool:
	if fleet_design_slots.has(design_name):
		return true
	var empty_slot := fleet_design_slots.find("")
	if empty_slot < 0:
		return false
	fleet_design_slots[empty_slot] = design_name
	return true

func purchase_ship(blueprint: Ship = null, design_name: String = "") -> bool:
	var design := ship if blueprint == null else blueprint
	if not construction_error(design).is_empty():
		return false
	var construction_credit_cost := get_construction_credit_cost(design)
	var owned := FleetShip.new()
	var title := design_name
	if title.is_empty():
		title = current_ship_design_name if design == ship else "Ship"
	if title.is_empty():
		title = "Ship"
	owned.initialize(design, next_ship_id, "%s %d" % [title, next_ship_id])
	# Find room alongside the fleet without constraining placement to a grid.
	for other in fleet:
		owned.formation.x = maxf(owned.formation.x, other.formation.x + 1.0)
	fleet.append(owned)
	next_ship_id += 1
	credits -= construction_credit_cost
	var counts := _get_ship_tile_counts(design)
	red_tiles_available = maxi(0, red_tiles_available - counts[0])
	blue_tiles_available = maxi(0, blue_tiles_available - counts[1])
	green_tiles_available = maxi(0, green_tiles_available - counts[2])
	core_tiles_available = maxi(0, core_tiles_available - counts[3])
	_refresh_fleet()
	tile_inventory_changed.emit()
	credits_changed.emit()
	return true


func repair_ship(owned: FleetShip) -> bool:
	if battle_pending or not fleet.has(owned) or not owned.is_alive():
		return false
	var price := owned.repair_cost()
	if price > credits:
		return false
	credits -= price
	owned.repair()
	credits_changed.emit()
	fleet_changed.emit()
	return true


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
	var counts := _get_ship_tile_counts(candidate.design)
	red_tiles_available += counts[ShipPart.Category.OFFENSE]
	blue_tiles_available += counts[ShipPart.Category.DEFENSE]
	green_tiles_available += counts[ShipPart.Category.SPECIAL]
	core_tiles_available += counts[ShipPart.Category.CORE]
	fleet.erase(candidate)
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
	player_ship_count = fleet.size()
	player_ship_count_changed.emit()
	fleet_changed.emit()


func can_deploy() -> bool:
	return not run_ended and not fleet.is_empty() and fleet.any(func(owned: FleetShip) -> bool:
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
		if candidate.construction_error().is_empty() and credits >= get_construction_credit_cost(design):
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
	if red_tiles_available < materials or credits < price:
		return false
	red_tiles_available -= materials
	credits -= price
	laser_upgrade_level += 1
	tile_inventory_changed.emit()
	credits_changed.emit()
	upgrades_changed.emit()
	fleet_changed.emit()
	return true


func record_battle(simulation: BattleSimulation) -> void:
	last_battle_report.clear()
	for combatant in simulation.players:
		var owned: FleetShip = combatant.owned_ship
		if owned == null:
			continue
		last_battle_report.append({"ship": owned, "damage": combatant.damage_dealt,
			"taken": combatant.damage_taken,
			"repair_damage": combatant.permanent_damage_taken,
			"deflected": combatant.damage_deflected(),
			"weapons": combatant.weapon_damage.duplicate(),
			"destroyed": not combatant.is_alive()})
		if not combatant.is_alive():
			fleet.erase(owned)
	for combatant in simulation.aliens:
		if combatant.alien == null:
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
	_refresh_fleet()


func get_reachable_nodes(from_node_id: int) -> Array[int]:
	var reachable_nodes: Array[int] = []
	for edge in GRAPH_EDGES:
		if edge.x == from_node_id:
			reachable_nodes.append(edge.y)
	return reachable_nodes


func set_planned_destination(node_id: int) -> bool:
	if battle_pending or not get_reachable_nodes(current_node_id).has(node_id):
		return false
	planned_destination_node_id = node_id
	return true


func is_shipyard_node(node_id: int) -> bool:
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
	if not EncounterGenerator.valid(encounter) or encounter.template_id != "patrol":
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
	progress.attempts = int(progress.attempts) + 1
	progress.outcome = "active"
	progress.ship_ids = []
	for owned: FleetShip in fleet:
		progress.ship_ids.append(owned.id)
	var deployment := RunCheckpoint.capture(self)
	progress.deployment = {"fleet": deployment.fleet, "aliens": deployment.aliens,
		"seed": str(battle_simulation_seed()), "salvage_chance": allied_salvage_chance(),
		"upgrade_level": laser_upgrade_level, "neutral_cleanup": destroy_all_neutral_targets,
		"objectives": battle_objective_ids(), "materials": battle_material_rewards()}
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


func complete_battle(surviving_player_ship_count: int = -1, salvage_categories: Array = []) -> bool:
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
	var result := TransactionLedger.apply(RunCheckpoint.capture(self), "victory", "node/%d" % destination_node_id,
		int(encounter.rewards.credits), materials, 0)
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
	if not _persist_checkpoint(checkpoint):
		return false
	transaction_ledger = checkpoint.ledger
	_apply_accounting(checkpoint)
	_apply_location(checkpoint)
	encounter_progress = checkpoint.encounter_progress
	if surviving_player_ship_count >= 0:
		player_ship_count = surviving_player_ship_count
		player_ship_count_changed.emit()
	_emit_accounting_changes()
	return true


func cancel_battle(surviving_player_ship_count: int = -1, terminal_defeat := false) -> bool:
	if surviving_player_ship_count < -1 or surviving_player_ship_count > player_ship_count:
		push_error("Battle cancellation reported an invalid surviving player ship count.")
		return false
	if not battle_pending:
		return true
	var checkpoint := RunCheckpoint.capture(self)
	checkpoint.location.destination = -1
	checkpoint.location.planned = -1
	checkpoint.location.pending = false
	checkpoint.aliens.clear()
	_set_encounter_outcome(checkpoint, "defeat" if terminal_defeat else "withdrawn")
	checkpoint.progress.run_ended = run_ended or terminal_defeat
	if not _persist_checkpoint(checkpoint):
		return false
	run_ended = checkpoint.progress.run_ended
	encounter_progress = checkpoint.encounter_progress
	if surviving_player_ship_count >= 0:
		player_ship_count = surviving_player_ship_count
		player_ship_count_changed.emit()
	destination_node_id = -1
	planned_destination_node_id = -1
	battle_pending = false
	battle_aliens.clear()
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
	if simulation.players.size() != expected_ids.size():
		return false
	var seen_ids: Array[int] = []
	for member in simulation.players:
		if member.owned_ship == null or not expected_ids.has(member.owned_ship.id) or seen_ids.has(member.owned_ship.id):
			return false
		if not fleet.has(member.owned_ship) and member.is_alive():
			return false
		seen_ids.append(member.owned_ship.id)
	if not encounter_progress.has(str(destination_node_id)):
		encounter_progress[str(destination_node_id)] = {"attempts": 1, "outcome": "active", "field": {}}
	encounter_progress[str(destination_node_id)].journal = {"battle_id": simulation.battle_id,
		"deployment": progress.get("deployment", {}).duplicate(true),
		"commands": simulation.command_log.duplicate(true), "events": simulation.event_log.duplicate(true),
		"snapshot": simulation.authoritative_snapshot()}
	record_battle(simulation)
	if simulation.phase == BattleSimulation.Phase.VICTORY:
		return complete_battle(-1, simulation.collected_categories)
	return cancel_battle(-1, simulation.phase == BattleSimulation.Phase.DEFEAT)


func commit_field_pickup(pickup_id: String, materials: Array, field_after: Dictionary) -> bool:
	# Future mining commits the finite field and pickup ledger in one generation.
	# A withdrawal/retry preserves this field while enemies reset from the frozen roster.
	if not battle_pending or pickup_id.is_empty() or not RunCheckpoint._json_value(field_after):
		return false
	for amount in materials:
		if not RunProgressData._integer(amount) or amount < 0:
			return false
	var checkpoint := RunCheckpoint.capture(self)
	var key := str(destination_node_id)
	if not checkpoint.encounter_progress.has(key):
		checkpoint.encounter_progress[key] = {"attempts": 1, "outcome": "active", "field": {}}
	var result := TransactionLedger.apply(checkpoint, "ore_pickup", "node/%s/%s" % [key, pickup_id], 0, materials, 0, {"field": field_after})
	if result.is_empty():
		return false
	checkpoint = result.checkpoint
	if not result.replayed:
		checkpoint.encounter_progress[key].field = field_after.duplicate(true)
	if not RunCheckpoint.valid(checkpoint) or not _persist_checkpoint(checkpoint):
		return false
	transaction_ledger = checkpoint.ledger
	encounter_progress = checkpoint.encounter_progress
	_apply_accounting(checkpoint)
	_emit_accounting_changes()
	return true


func get_visible_ship_designs(query: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if query.strip_edges().is_empty() or "drone".contains(query.strip_edges().to_lower()):
		result.append({"name": "Drone", "ship": preload("res://scripts/builtin_ships.gd").drone().to_design_data(), "builtin": true})
	for entry in saved_ship_designs:
		var title: String = entry.name
		if title == "Drone":
			continue
		if not query.strip_edges().is_empty() and not title.to_lower().contains(query.strip_edges().to_lower()):
			continue
		result.append(entry.duplicate(true))
	return result


func delete_saved_ship_design(design_name: String, file_path: String = SAVED_SHIP_DESIGNS_PATH) -> bool:
	if design_name == "Drone":
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
	if battle_pending or build_area_size() >= MAX_BUILD_SIZE or credits < 50:
		return false
	if red_tiles_available < 1 or blue_tiles_available < 1 or green_tiles_available < 1 or core_tiles_available < 1:
		return false
	credits -= 50
	red_tiles_available -= 1
	blue_tiles_available -= 1
	green_tiles_available -= 1
	core_tiles_available -= 1
	build_area_level += 1
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
