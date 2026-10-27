class_name TechTreeView
extends Control

const PAN_SPEED := 260.0
const MIN_ZOOM := 0.35
const MAX_ZOOM := 2.5
const ZOOM_STEP := 1.15
const FIT_MARGIN := 36.0
const NODE_SIZE := Vector2(92.0, 72.0)
const NODE_GAP := 18.0
const NODE_FILL := Color("182027")
const NODE_BORDER := Color("8295a3")
const AVAILABLE_BORDER := Color("63d77a")
const CORE_COLOR := Color("b7c4cc")
const ENERGY_COLOR := Color("55b8e8")
const UTILITY_COLOR := Color("73d083")

var camera_position := Vector2.ZERO
var camera_zoom := 1.0
var _dragging := false
var _initial_view_fitted := false
var _catalog_by_category: Dictionary = {}
var grouped_view: Control


func _ready() -> void:
	if GameState.campaign_active:
		grouped_view = load("res://scripts/research_panel.gd").new()
		add_child(grouped_view)
		grouped_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	for category in ShipPart.TechCategory.values():
		_catalog_by_category[category] = []
	for pattern in ShipPartPattern.get_catalog():
		_catalog_by_category[pattern.tech_category].append(pattern)
	_sort_categories_by_dependencies()
	resized.connect(_on_resized)
	call_deferred("_fit_initial_view")


func _process(delta: float) -> void:
	if grouped_view != null:
		return
	if not is_visible_in_tree() or _input_is_blocked():
		return
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	)
	if not direction.is_zero_approx():
		camera_position += direction.normalized() * PAN_SPEED * delta / camera_zoom
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if grouped_view != null:
		return
	if _input_is_blocked():
		return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var world_under_cursor := _screen_to_world(event.position)
			var factor := ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
			camera_zoom = clampf(camera_zoom * factor, MIN_ZOOM, MAX_ZOOM)
			camera_position = world_under_cursor - (event.position - size * 0.5) / camera_zoom
			queue_redraw()
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			_dragging = event.pressed
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		camera_position -= event.relative / camera_zoom
		queue_redraw()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if not is_visible_in_tree():
			_dragging = false
		elif not _initial_view_fitted:
			call_deferred("_fit_initial_view")


func _draw() -> void:
	if grouped_view != null:
		return
	draw_set_transform(size * 0.5 - camera_position * camera_zoom, 0.0, Vector2.ONE * camera_zoom)
	var layouts := _tree_layout()
	var core_nodes: Array = layouts[ShipPart.TechCategory.CORE]
	if core_nodes.is_empty():
		return
	for category in [ShipPart.TechCategory.CORE, ShipPart.TechCategory.ENERGY, ShipPart.TechCategory.UTILITY]:
		_draw_category(category, layouts[category])


func _tree_layout() -> Dictionary:
	var core_nodes := _category_layout(ShipPart.TechCategory.CORE, Vector2(-270.0, -245.0))
	var energy_nodes := _category_layout(ShipPart.TechCategory.ENERGY, Vector2(-25.0, -130.0))
	var utility_nodes := _category_layout(ShipPart.TechCategory.UTILITY, Vector2(220.0, 40.0))
	return {
		ShipPart.TechCategory.CORE: core_nodes,
		ShipPart.TechCategory.ENERGY: energy_nodes,
		ShipPart.TechCategory.UTILITY: utility_nodes,
	}


func _category_layout(category: int, start: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var patterns: Array = _catalog_by_category.get(category, [])
	var positions_by_type: Dictionary = {}
	var root_index := 0
	for pattern in patterns:
		if not pattern.prerequisite_types.is_empty():
			continue
		positions_by_type[pattern.part_type] = (
			start + Vector2(0.0, root_index * (NODE_SIZE.y + NODE_GAP))
		)
		root_index += 1
	for pattern in patterns:
		if pattern.prerequisite_types.is_empty():
			continue
		var required_type: int = pattern.prerequisite_types[0]
		var required_position: Vector2 = positions_by_type.get(required_type, start)
		positions_by_type[pattern.part_type] = (
			required_position - Vector2(NODE_SIZE.x + NODE_GAP, 0.0)
		)
	for pattern in patterns:
		result.append({
			"pattern": pattern,
			"position": positions_by_type.get(pattern.part_type, start),
		})
	return result


func _draw_category(category: int, nodes: Array) -> void:
	if nodes.is_empty():
		return
	var color := _category_color(category)
	var header_position: Vector2 = nodes[0].position
	for node in nodes:
		header_position.x = minf(header_position.x, node.position.x)
		header_position.y = minf(header_position.y, node.position.y)
	draw_string(get_theme_default_font(), header_position + Vector2(0.0, -10.0),
		_category_name(category), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, color)
	for index in range(nodes.size()):
		var node: Dictionary = nodes[index]
		for prerequisite_type in node.pattern.prerequisite_types:
			var prerequisite_position := _find_part_position(nodes, prerequisite_type)
			if prerequisite_position != Vector2.INF:
				draw_line(node.position + Vector2(NODE_SIZE.x, NODE_SIZE.y * 0.5),
					prerequisite_position + Vector2(0.0, NODE_SIZE.y * 0.5), color, 2.0)
		_draw_equipment_node(node.pattern, node.position, color)


func _draw_equipment_node(pattern: ShipPartPattern, position: Vector2, color: Color) -> void:
	var rect := Rect2(position, NODE_SIZE)
	draw_rect(rect, NODE_FILL, true)
	var border_color := (
		AVAILABLE_BORDER if GameState.is_equipment_available(pattern.part_type)
		else NODE_BORDER
	)
	draw_rect(rect, border_color, false, 2.0)
	draw_texture_rect(pattern.preview_texture,
		Rect2(position + Vector2(26.0, 7.0), Vector2(40.0, 40.0)), false)
	draw_string(get_theme_default_font(), position + Vector2(4.0, 64.0),
		pattern.display_name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER,
		NODE_SIZE.x - 8.0, 9, color)


func _find_part_position(nodes: Array, part_type: int) -> Vector2:
	for node in nodes:
		if node.pattern.part_type == part_type:
			return node.position
	return Vector2.INF


func _sort_categories_by_dependencies() -> void:
	for category in _catalog_by_category:
		var patterns: Array = _catalog_by_category[category]
		var ordered: Array = []
		for pattern in patterns:
			_append_with_prerequisites(pattern, patterns, ordered)
		_catalog_by_category[category] = ordered


func _append_with_prerequisites(
	pattern: ShipPartPattern,
	patterns: Array,
	ordered: Array
) -> void:
	if ordered.has(pattern):
		return
	for prerequisite_type in pattern.prerequisite_types:
		for candidate in patterns:
			if candidate.part_type == prerequisite_type:
				_append_with_prerequisites(candidate, patterns, ordered)
				break
	ordered.append(pattern)


func _tree_bounds() -> Rect2:
	var bounds := Rect2()
	var has_node := false
	for nodes in _tree_layout().values():
		for node in nodes:
			var node_rect := Rect2(node.position + Vector2(0.0, -18.0), NODE_SIZE + Vector2(0.0, 18.0))
			bounds = node_rect if not has_node else bounds.merge(node_rect)
			has_node = true
	return bounds


func _fit_initial_view() -> void:
	if _initial_view_fitted or size.x <= 1.0 or size.y <= 1.0:
		return
	var bounds := _tree_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	camera_position = bounds.get_center()
	camera_zoom = clampf(minf(
		(size.x - FIT_MARGIN * 2.0) / bounds.size.x,
		(size.y - FIT_MARGIN * 2.0) / bounds.size.y
	), MIN_ZOOM, 1.0)
	_initial_view_fitted = true
	queue_redraw()


func _on_resized() -> void:
	if not _initial_view_fitted:
		_fit_initial_view()
	queue_redraw()


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return camera_position + (screen_position - size * 0.5) / camera_zoom


func _category_name(category: int) -> String:
	match category:
		ShipPart.TechCategory.ENERGY: return "ENERGY"
		ShipPart.TechCategory.UTILITY: return "UTILITY"
		_: return "FOUNDATION"


func _category_color(category: int) -> Color:
	match category:
		ShipPart.TechCategory.ENERGY: return ENERGY_COLOR
		ShipPart.TechCategory.UTILITY: return UTILITY_COLOR
		_: return CORE_COLOR


func _input_is_blocked() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null and (focus_owner is LineEdit or focus_owner is TextEdit):
		return true
	var scene := get_tree().current_scene
	if scene == null:
		return false
	for child in scene.get_children():
		if not child.visible:
			continue
		if child is Window or "modal" in child.name.to_lower() or "dialog" in child.name.to_lower():
			return true
	return false
