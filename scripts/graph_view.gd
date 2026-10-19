class_name GraphView
extends Control

signal destination_selected(node_id: int)

const NODE_SIZE := Vector2(28.0, 28.0)
const NODE_HIT_RADIUS := 24.0

var current_node_id := 0
var selected_node_id := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	queue_redraw()


func set_current_node(node_id: int) -> void:
	current_node_id = node_id
	selected_node_id = -1
	queue_redraw()


func _draw() -> void:
	var reachable_nodes := GameState.get_reachable_nodes(current_node_id)

	for edge in GameState.GRAPH_EDGES:
		var edge_color := Color(0.32, 0.32, 0.32)
		if current_node_id == edge.x:
			edge_color = Color(0.48, 0.48, 0.48)
		if GameState.visited_nodes.has(edge.x) and GameState.visited_nodes.has(edge.y):
			edge_color = Color(0.22, 0.58, 0.66)
		_draw_arrow(edge.x, edge.y, edge_color)

	for node_id in range(GameState.NODE_POSITIONS.size()):
		var center := _node_center(node_id)
		var node_rect := Rect2(center - NODE_SIZE / 2.0, NODE_SIZE)
		var fill_color := Color(0.12, 0.12, 0.12)
		var border_color := Color(0.42, 0.42, 0.42)

		if GameState.visited_nodes.has(node_id):
			fill_color = Color(0.1, 0.24, 0.29)
			border_color = Color(0.35, 0.68, 0.76)
		if reachable_nodes.has(node_id):
			fill_color = Color(0.18, 0.28, 0.32)
			border_color = Color(0.55, 0.68, 0.72)
		if node_id == current_node_id:
			fill_color = Color(0.14, 0.43, 0.52)
			border_color = Color(0.48, 0.78, 0.86)
		if node_id == selected_node_id:
			fill_color = Color(0.48, 0.34, 0.12)
			border_color = Color(0.9, 0.7, 0.3)

		draw_rect(node_rect, fill_color, true)
		draw_rect(node_rect, border_color, false, 2.0)


func _gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null:
		return
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	for node_id in GameState.get_reachable_nodes(current_node_id):
		if _node_center(node_id).distance_to(mouse_event.position) <= NODE_HIT_RADIUS:
			selected_node_id = node_id
			queue_redraw()
			destination_selected.emit(node_id)
			accept_event()
			return


func _node_center(node_id: int) -> Vector2:
	var normalized_position: Vector2 = GameState.NODE_POSITIONS[node_id]
	return Vector2(size.x * normalized_position.x, size.y * normalized_position.y)


func _draw_arrow(from_node_id: int, to_node_id: int, color: Color) -> void:
	var from_position := _node_center(from_node_id)
	var to_position := _node_center(to_node_id)
	var direction := (to_position - from_position).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var tip := to_position - direction * (NODE_SIZE.x / 2.0 + 1.0)
	var arrow_base := tip - direction * 8.0
	var line_start := from_position + direction * (NODE_SIZE.x / 2.0 + 1.0)

	draw_line(line_start, arrow_base, color, 2.0, true)
	var arrowhead := PackedVector2Array([
		tip,
		arrow_base + perpendicular * 4.0,
		arrow_base - perpendicular * 4.0,
	])
	draw_colored_polygon(arrowhead, color)
