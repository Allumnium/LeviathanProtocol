extends Node

signal tile_inventory_changed
signal discovered_parts_changed
signal unviewed_discoveries_changed
signal part_transformations_changed

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
const STARTING_RED_TILE_COUNT := 18
const STARTING_BLUE_TILE_COUNT := 12
const STARTING_GREEN_TILE_COUNT := 6

var current_node_id := 0
var destination_node_id := -1
var visited_nodes: Array[int] = [0]
var battle_pending := false
var ship := Ship.new()
var discovered_part_types: Array[int] = []
var unviewed_discovered_part_types: Array[int] = []
var active_part_transformations := 0
var red_tiles_available := STARTING_RED_TILE_COUNT
var blue_tiles_available := STARTING_BLUE_TILE_COUNT
var green_tiles_available := STARTING_GREEN_TILE_COUNT


func start_new_run() -> void:
	current_node_id = 0
	destination_node_id = -1
	visited_nodes = [0]
	battle_pending = false
	ship.clear()
	red_tiles_available = STARTING_RED_TILE_COUNT
	blue_tiles_available = STARTING_BLUE_TILE_COUNT
	green_tiles_available = STARTING_GREEN_TILE_COUNT
	tile_inventory_changed.emit()


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


func get_reachable_nodes(from_node_id: int) -> Array[int]:
	var reachable_nodes: Array[int] = []
	for edge in GRAPH_EDGES:
		if edge.x == from_node_id:
			reachable_nodes.append(edge.y)
	return reachable_nodes


func set_destination(node_id: int) -> bool:
	if not get_reachable_nodes(current_node_id).has(node_id):
		return false
	destination_node_id = node_id
	battle_pending = true
	return true


func complete_battle() -> bool:
	if not battle_pending:
		push_error("Auto-battle finished without an active deployment.")
		return false
	if not get_reachable_nodes(current_node_id).has(destination_node_id):
		push_error("The deployed destination is no longer reachable.")
		return false

	current_node_id = destination_node_id
	if not visited_nodes.has(current_node_id):
		visited_nodes.append(current_node_id)
	destination_node_id = -1
	battle_pending = false
	return true


func cancel_battle() -> void:
	destination_node_id = -1
	battle_pending = false
