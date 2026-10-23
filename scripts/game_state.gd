extends Node

signal build_area_changed
signal design_library_changed
signal fleet_changed
signal upgrades_changed

signal tile_inventory_changed
signal ship_stats_changed
signal credits_changed
signal player_ship_count_changed
signal discovered_parts_changed
signal unviewed_discoveries_changed
signal part_transformations_changed

const AlienShipType = preload("res://scripts/alien_ship.gd")

enum Difficulty { EASY, MEDIUM, HARD }

const NODE_POSITIONS: Array[Vector2] = [
	Vector2(0.08, 0.5),
	Vector2(0.31, 0.23),
	Vector2(0.31, 0.77),
	Vector2(0.62, 0.23),
	Vector2(0.62, 0.77),
	Vector2(0.92, 0.5),
]
const GRAPH_EDGES: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(0, 2),
	Vector2i(1, 3),
	Vector2i(1, 4),
	Vector2i(2, 3),
	Vector2i(2, 4),
	Vector2i(3, 5),
	Vector2i(4, 5),
]
const FINAL_NODE_ID := 5
const MIN_ALIEN_FLEET_SIZE := 3
const MAX_ALIEN_FLEET_SIZE := 8
const STARTING_CREDITS := 1200
const VICTORY_CREDIT_REWARD := 200
const SAVED_SHIP_DESIGNS_PATH := "user://ship_designs.json"
const SAVED_SHIP_DESIGNS_VERSION := 1
const STARTING_RED_TILE_COUNT := 18
const STARTING_BLUE_TILE_COUNT := 12
const STARTING_GREEN_TILE_COUNT := 6

var fleet: Array[FleetShip] = []
var next_ship_id := 1
var laser_upgrade_level := 0
var build_area_level := 0
const MAX_BUILD_SIZE := 30
var last_battle_report: Array[Dictionary] = []

var current_node_id := 0
var destination_node_id := -1
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
var saved_ship_designs: Array[Dictionary] = []
var current_run_design_names: Array[String] = []
var include_previous_run_designs := false


func _ready() -> void:
	_load_saved_ship_designs()


func start_new_run(selected_difficulty: int = Difficulty.MEDIUM) -> bool:
	if not [
		Difficulty.EASY,
		Difficulty.MEDIUM,
		Difficulty.HARD,
	].has(selected_difficulty):
		push_error("Cannot start a run with an unknown difficulty.")
		return false

	current_node_id = 0
	destination_node_id = -1
	visited_nodes = [0]
	battle_pending = false
	player_ship_count = 0
	fleet.clear()
	current_run_design_names.clear()
	include_previous_run_designs = false
	next_ship_id = 1
	laser_upgrade_level = 0
	build_area_level = 0
	last_battle_report.clear()
	current_ship_design_name = ""
	credits = STARTING_CREDITS
	difficulty = selected_difficulty as Difficulty
	battle_aliens.clear()
	ship.clear()
	red_tiles_available = STARTING_RED_TILE_COUNT
	blue_tiles_available = STARTING_BLUE_TILE_COUNT
	green_tiles_available = STARTING_GREEN_TILE_COUNT
	var drone := preload("res://scripts/builtin_ships.gd").drone()
	for index in range(3):
		var owned := FleetShip.new()
		owned.initialize(drone, next_ship_id, "Drone %d" % next_ship_id)
		owned.formation = Vector2(0, index - 1)
		fleet.append(owned)
		next_ship_id += 1
	for part in drone.parts:
		discover_part(part.type)
	_refresh_fleet()
	design_library_changed.emit()
	tile_inventory_changed.emit()
	ship_stats_changed.emit()
	credits_changed.emit()
	player_ship_count_changed.emit()
	return true


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


func _get_ship_tile_counts(target_ship: Ship) -> Array[int]:
	var tile_counts: Array[int] = [0, 0, 0]
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
			return 0.75
		Difficulty.MEDIUM:
			return 1.0
		Difficulty.HARD:
			return 1.5
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
		_:
			push_error("Unknown ship part category: %s" % category)
			return 0


func discover_part(part_type: int) -> void:
	if discovered_part_types.has(part_type):
		return

	discovered_part_types.append(part_type)
	unviewed_discovered_part_types.append(part_type)
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
		_:
			push_error("Unknown ship part category: %s" % category)
			return

	tile_inventory_changed.emit()


func construction_error(blueprint: Ship = null) -> String:
	var design := ship if blueprint == null else blueprint
	if battle_pending or (design == ship and active_part_transformations > 0):
		return "Unavailable during deployment or transformation."
	if design.tiles.is_empty():
		return "Design a ship first."
	if not design_fits_build_area(design):
		return "Upgrade the build area to construct this design."
	var candidate := FleetShip.new()
	candidate.initialize(design, next_ship_id, "")
	var problem := candidate.construction_error()
	if not problem.is_empty():
		return problem
	if credits < get_construction_credit_cost(design):
		return "Insufficient credits."
	return ""


const MATERIAL_PRICES := [Ship.RED_TILE_CREDIT_COST, Ship.BLUE_TILE_CREDIT_COST, Ship.GREEN_TILE_CREDIT_COST]


func get_construction_credit_cost(blueprint: Ship = null) -> int:
	var design := ship if blueprint == null else blueprint
	var total := design.cost
	var counts := _get_ship_tile_counts(design)
	if counts.size() != MATERIAL_PRICES.size():
		return total
	for category in range(MATERIAL_PRICES.size()):
		var missing := maxi(0, counts[category] - get_available_tile_count(category))
		total += missing * MATERIAL_PRICES[category]
	return total

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
	credits_changed.emit()
	tile_inventory_changed.emit()
	return true

func purchase_saved_ship(design_name: String) -> bool:
	for entry in get_visible_ship_designs():
		if entry.name == design_name:
			var blueprint := Ship.new()
			if blueprint.load_design_data(entry.ship):
				return purchase_ship(blueprint, design_name)
	return false

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
	return not fleet.is_empty() and fleet.any(func(owned: FleetShip) -> bool:
		return owned.is_alive() and not owned.get_stats(laser_upgrade_level).weapons.is_empty())


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
			"taken": combatant.damage_taken, "weapons": combatant.weapon_damage.duplicate(),
			"destroyed": not combatant.is_alive()})
		if not combatant.is_alive():
			fleet.erase(owned)
	_refresh_fleet()


func get_reachable_nodes(from_node_id: int) -> Array[int]:
	var reachable_nodes: Array[int] = []
	for edge in GRAPH_EDGES:
		if edge.x == from_node_id:
			reachable_nodes.append(edge.y)
	return reachable_nodes


func set_destination(node_id: int) -> bool:
	if battle_pending or not can_deploy():
		return false
	if not get_reachable_nodes(current_node_id).has(node_id):
		return false
	var difficulty_multiplier := get_difficulty_multiplier()
	if difficulty_multiplier <= 0.0:
		return false
	var base_fleet_size := randi_range(MIN_ALIEN_FLEET_SIZE, MAX_ALIEN_FLEET_SIZE)
	var fleet_size := base_fleet_size * player_ship_count
	var next_battle_aliens: Array[AlienShipType] = AlienShipType.create_random_fleet(
		fleet_size,
		difficulty_multiplier,
		-1,
		player_ship_count
	)
	if next_battle_aliens.size() != fleet_size:
		push_error("Could not create the alien fleet for the selected destination.")
		return false

	destination_node_id = node_id
	battle_pending = true
	battle_aliens.clear()
	for alien in next_battle_aliens:
		battle_aliens.append(alien)
	return true


func complete_battle(surviving_player_ship_count: int = -1) -> bool:
	if not battle_pending:
		push_error("Auto-battle finished without an active deployment.")
		return false
	if not get_reachable_nodes(current_node_id).has(destination_node_id):
		push_error("The deployed destination is no longer reachable.")
		return false
	if surviving_player_ship_count < -1 or surviving_player_ship_count > player_ship_count:
		push_error("Battle victory reported an invalid surviving player ship count.")
		return false

	if surviving_player_ship_count >= 0:
		player_ship_count = surviving_player_ship_count
		player_ship_count_changed.emit()
	current_node_id = destination_node_id
	if not visited_nodes.has(current_node_id):
		visited_nodes.append(current_node_id)
	destination_node_id = -1
	battle_pending = false
	battle_aliens.clear()
	credits += VICTORY_CREDIT_REWARD
	credits_changed.emit()
	return true


func cancel_battle(surviving_player_ship_count: int = -1) -> void:
	if surviving_player_ship_count < -1 or surviving_player_ship_count > player_ship_count:
		push_error("Battle cancellation reported an invalid surviving player ship count.")
		return
	if surviving_player_ship_count >= 0:
		player_ship_count = surviving_player_ship_count
		player_ship_count_changed.emit()
	destination_node_id = -1
	battle_pending = false
	battle_aliens.clear()


func get_visible_ship_designs(query: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if query.strip_edges().is_empty() or "drone".contains(query.strip_edges().to_lower()):
		result.append({"name": "Drone", "ship": preload("res://scripts/builtin_ships.gd").drone().to_design_data(), "builtin": true})
	for entry in saved_ship_designs:
		var title: String = entry.name
		if title == "Drone":
			continue
		if not include_previous_run_designs and not current_run_design_names.has(title):
			continue
		if not query.strip_edges().is_empty() and not title.to_lower().contains(query.strip_edges().to_lower()):
			continue
		result.append(entry.duplicate(true))
	return result


func set_include_previous_designs(enabled: bool) -> void:
	include_previous_run_designs = enabled
	design_library_changed.emit()


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
	return 8 + 2 * build_area_level


func purchase_build_area_upgrade() -> bool:
	if battle_pending or build_area_size() >= MAX_BUILD_SIZE or credits < 50:
		return false
	if red_tiles_available < 1 or blue_tiles_available < 1 or green_tiles_available < 1:
		return false
	credits -= 50
	red_tiles_available -= 1
	blue_tiles_available -= 1
	green_tiles_available -= 1
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
	if current_node_id == 0:
		return 1
	if current_node_id <= 2:
		return 2
	if current_node_id <= 4:
		return 3
	return 4
