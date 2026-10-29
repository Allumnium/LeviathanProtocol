extends Control

signal node_selected(id: String)

const CARD_SIZE := Vector2(108, 66)
var buttons: Dictionary = {}
var positions: Dictionary = {}
var edges: Array = []
var camera_position := Vector2.ZERO
var camera_zoom := 1.0
var dragging := false
var cards: Control
var initial_view_fitted := false
var branch_roots: Dictionary = {}

func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	cards = Control.new()
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cards)
	resized.connect(_update_camera)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree() and not initial_view_fitted:
			call_deferred("fit_view"))
	mouse_default_cursor_shape = Control.CURSOR_DRAG

func populate(rows: Array[Dictionary], registry: Dictionary, selected: String, focus: String, progress: Dictionary = {}, fit := false) -> void:
	for child in cards.get_children():
		cards.remove_child(child)
		child.queue_free()
	buttons.clear()
	positions.clear()
	edges.clear()
	branch_roots.clear()
	var depths: Dictionary = {}
	while depths.size() < rows.size():
		var advanced := false
		for row in rows:
			if depths.has(row.id):
				continue
			var depth := 0
			var ready := true
			for parent: String in ResearchViewModel.find(registry, "research", row.id).prerequisite_ids:
				if not rows.any(func(other: Dictionary) -> bool: return other.id == parent):
					continue
				if not depths.has(parent):
					ready = false
					break
				depth = maxi(depth, int(depths[parent]) + 1)
			if ready:
				depths[row.id] = depth
				advanced = true
		if not advanced:
			break
	var groups: Array[String] = []
	for row in rows:
		if not groups.has(row.group):
			groups.append(row.group)
	var band_y := 0.0
	for group in groups:
		var counts: Dictionary = {}
		var group_depth := 100
		for row in rows:
			if row.group == group:
				group_depth = mini(group_depth, int(depths.get(row.id, 0)))
		var band_rows := 1
		for row in rows:
			if row.group != group:
				continue
			var depth := int(depths.get(row.id, 0))
			var index := int(counts.get(depth, 0))
			counts[depth] = index + 1
			band_rows = maxi(band_rows, index + 1)
			positions[row.id] = Vector2(108 + depth * 140, band_y + index * 82)
		var root_point := Vector2(0, band_y + (band_rows - 1) * 41 + CARD_SIZE.y * 0.5)
		branch_roots[group] = root_point
		var heading := Label.new()
		heading.text = "Engineering" if group == "shared" else ResearchViewModel.GROUP_NAMES[group]
		heading.position = root_point - Vector2(0, 22)
		heading.size = Vector2(96, 44)
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cards.add_child(heading)
		for row in rows:
			if row.group == group and int(depths.get(row.id, 0)) == group_depth:
				edges.append([group, row.id])
		band_y += band_rows * 82 + 28
	for row in rows:
		var button := Button.new()
		button.name = row.id
		button.theme_type_variation = &"ResearchButton"
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.text = ""
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size = CARD_SIZE
		button.position = positions[row.id]
		button.pressed.connect(func() -> void: node_selected.emit(row.id))
		cards.add_child(button)
		buttons[row.id] = button
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(box)
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 4
		box.offset_right = -4
		box.offset_top = 5
		box.offset_bottom = -5
		var marker := Label.new()
		marker.name = "Progress"
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.custom_minimum_size.y = 14
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(marker)
		if row.status == "Owned":
			var check := Line2D.new()
			check.name = "Completed"
			check.default_color = get_theme_color("completed_color", "ResearchButton")
			check.width = 2
			check.points = PackedVector2Array([Vector2(43, 7), Vector2(48, 12), Vector2(57, 2)])
			marker.add_child(check)
		elif float(progress.get(row.id, 0)) > 0:
			marker.text = "%s / %d" % [ScienceRules.format_rp(float(progress[row.id])), int(row.cost)]
		var title := Label.new()
		title.text = row.name
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(title)
		if row.id == focus:
			button.modulate = get_theme_color("focused_color", "ResearchButton")
		for parent: String in ResearchViewModel.find(registry, "research", row.id).prerequisite_ids:
			if positions.has(parent):
				edges.append([parent, row.id])
	select(selected)
	if fit:
		call_deferred("fit_view")
	else:
		_update_camera()

func select(id: String) -> void:
	for key in buttons:
		buttons[key].set_pressed_no_signal(key == id)
	queue_redraw()

func fit_view() -> void:
	if size.x <= 0 or size.y <= 0 or not is_visible_in_tree():
		return
	initial_view_fitted = true
	var extent := CARD_SIZE
	for point: Vector2 in positions.values():
		extent = extent.max(point + CARD_SIZE)
	# Preserve readable theme-sized bitmap text. Larger trees are explored by pan/zoom.
	camera_zoom = 1.0
	camera_position = Vector2(minf(extent.x * 0.5, size.x * 0.5 - 12), minf(extent.y * 0.5, size.y * 0.5 - 12))
	_update_camera()

func _update_camera() -> void:
	if cards == null:
		return
	cards.scale = Vector2.ONE * camera_zoom
	cards.position = (size * 0.5 - camera_position * camera_zoom).round()
	queue_redraw()

func _draw() -> void:
	if cards == null:
		return
	if branch_roots.size() > 1:
		var roots: Array = branch_roots.values()
		var a: Vector2 = cards.position + (roots[0] + Vector2(-8, 0)) * camera_zoom
		var b: Vector2 = cards.position + (roots[-1] + Vector2(-8, 0)) * camera_zoom
		draw_line(a, b, get_theme_color("font_color", "Label"), 1.0)
		for point: Vector2 in roots:
			draw_line(cards.position + (point + Vector2(-8, 0)) * camera_zoom,
				cards.position + (point + Vector2(-2, 0)) * camera_zoom, get_theme_color("font_color", "Label"), 1.0)
	for edge: Array in edges:
		var a: Vector2 = branch_roots[edge[0]] + Vector2(92, 0) if branch_roots.has(edge[0]) else positions[edge[0]] + Vector2(CARD_SIZE.x, CARD_SIZE.y * 0.5)
		var b: Vector2 = positions[edge[1]] + Vector2(0, CARD_SIZE.y * 0.5)
		var middle := (a.x + b.x) * 0.5
		var points := PackedVector2Array([a, Vector2(middle, a.y), Vector2(middle, b.y), b])
		for index in range(points.size()):
			points[index] = cards.position + points[index] * camera_zoom
		draw_polyline(points, get_theme_color("font_color", "Label"), 1.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			dragging = event.pressed
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var world: Vector2 = camera_position + (event.position - size * 0.5) / camera_zoom
			camera_zoom = clampf(camera_zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.4, 2.5)
			camera_position = world - (event.position - size * 0.5) / camera_zoom
			_update_camera()
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		camera_position -= event.relative / camera_zoom
		_update_camera()
		accept_event()
