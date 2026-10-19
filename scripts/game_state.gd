extends Node

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

var current_node_id := 0
var destination_node_id := -1
var visited_nodes: Array[int] = [0]
var battle_pending := false


func start_new_run() -> void:
	current_node_id = 0
	destination_node_id = -1
	visited_nodes = [0]
	battle_pending = false


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
