extends Control

signal selection_changed

const SPACING := 65.0
var selected: FleetShip
var dragging := false
var previews: Dictionary = {}
var view_center := Vector2.ZERO
var view_scale := 1.0
var drag_offset := Vector2.ZERO
var drag_position := Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(160, 90)
	GameState.fleet_changed.connect(_sync_ships)
	resized.connect(_fit)
	_sync_ships()

func _sync_ships() -> void:
	for preview in previews.values():
		remove_child(preview)
		preview.queue_free()
	previews.clear()
	for owned in GameState.fleet:
		var preview := preload("res://scripts/fleet_ship_preview.gd").new()
		preview.owned = owned
		previews[owned] = preview
		add_child(preview)
	if not GameState.fleet.has(selected):
		selected = null if GameState.fleet.is_empty() else GameState.fleet[0]
	selection_changed.emit()
	_fit()

func _fit() -> void:
	if dragging:
		return
	var bounds := Rect2(-Vector2(50, 20), Vector2(100, 40))
	if not GameState.fleet.is_empty():
		bounds = Rect2(GameState.fleet[0].formation * SPACING, Vector2.ZERO)
		for owned in GameState.fleet:
			bounds = bounds.expand(owned.formation * SPACING)
	bounds = bounds.grow(40.0)
	view_center = bounds.get_center()
	custom_minimum_size.y = clampf(bounds.size.y, 64.0, 90.0)
	view_scale = minf(maxf(size.x, 1.0) / bounds.size.x, maxf(size.y, 1.0) / bounds.size.y)
	view_scale = minf(view_scale, 1.0)
	_layout_ships()

func _screen_position(owned: FleetShip) -> Vector2:
	var world := drag_position if dragging and owned == selected else owned.formation * SPACING
	return (world - view_center) * view_scale + size * 0.5

func _layout_ships() -> void:
	for owned in previews:
		var preview: Control = previews[owned]
		preview.size = Vector2.ONE * 56.0 * view_scale
		preview.position = _screen_position(owned) - preview.size * 0.5
		preview.queue_redraw()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.2, 0.25), false)
	if selected != null and previews.has(selected):
		draw_rect(Rect2(_screen_position(selected) - Vector2.ONE * 28.0 * view_scale, Vector2.ONE * 56.0 * view_scale), Color(0.4, 0.85, 1.0), false)

func _ship_at(point: Vector2) -> FleetShip:
	for owned in GameState.fleet:
		if Rect2(_screen_position(owned) - Vector2.ONE * 28.0 * view_scale, Vector2.ONE * 56.0 * view_scale).has_point(point):
			return owned
	return null

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected = _ship_at(event.position)
		selection_changed.emit()
		if selected != null:
			dragging = true
			drag_position = selected.formation * SPACING
			drag_offset = drag_position - ((event.position - size * 0.5) / view_scale + view_center)
		queue_redraw()
		accept_event()

func _input(event: InputEvent) -> void:
	if not dragging:
		return
	if event is InputEventMouseMotion:
		drag_position = (get_local_mouse_position() - size * 0.5) / view_scale + view_center + drag_offset
		_layout_ships()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		GameState.move_ship(selected, drag_position / SPACING)
		_fit()
		get_viewport().set_input_as_handled()
