extends Control

signal ship_selected(id: int)
signal equipment_requested(id: int)
var selected_id := 0
var dragging := false
var panning := false
var camera := Vector2.ZERO
var zoom := 1.0
var drag_point := Vector2.ZERO
var actions: HBoxContainer

func _ready() -> void:
	clip_contents = true
	actions = HBoxContainer.new()
	add_child(actions)
	var owned: HangarShip = GameState.owned_ship(selected_id)
	if owned != null:
		_action("EQUIP", func() -> void: equipment_requested.emit(selected_id))
		if not owned.flagship:
			_action("SALVAGE", func() -> void: GameState.salvage_hangar_ship(selected_id))
	resized.connect(queue_redraw)

func _action(title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.theme_type_variation = &"CompactButton"
	button.focus_mode = FOCUS_NONE
	button.pressed.connect(callback)
	actions.add_child(button)

func point(owned: FleetShip) -> Vector2:
	var position := drag_point if dragging and owned.id == selected_id else owned.formation
	return size * 0.5 + (position * 52 - camera) * zoom

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var world: Vector2 = camera + (event.position - size * 0.5) / zoom
			zoom = clampf(zoom * (1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.2), 0.4, 2.5)
			camera = world - (event.position - size * 0.5) / zoom
			queue_redraw()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
			return
	if event is InputEventMouseMotion and panning:
		camera -= event.relative / zoom
		queue_redraw()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			for owned in GameState.fleet:
				if point(owned).distance_to(event.position) < 28:
					selected_id = owned.id
					dragging = true
					drag_point = owned.formation
					queue_redraw()
					return
		elif dragging:
			dragging = false
			var owned: HangarShip = GameState.owned_ship(selected_id)
			if owned != null:
				GameState.move_ship(owned, (camera + (event.position - size * 0.5) / zoom) / 52)
			ship_selected.emit(selected_id)
	elif event is InputEventMouseMotion and dragging:
		var owned: HangarShip = GameState.owned_ship(selected_id)
		if owned != null:
			drag_point = ((camera + (event.position - size * 0.5) / zoom) / 52).clamp(Vector2(-5, -4), Vector2(5, 4))
			queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), get_theme_color("background_color", "SlotCanvas"))
	for owned: HangarShip in GameState.fleet:
		var rect := Rect2(point(owned) - Vector2.ONE * 26 * zoom, Vector2.ONE * 52 * zoom)
		draw_texture_rect(owned.art_texture, rect, false)
		if owned.id == selected_id:
			draw_arc(point(owned), 28 * zoom, 0, TAU, 32, get_theme_color("tech_color", "SlotCanvas"), 1)
			actions.position = (point(owned) + Vector2(-actions.size.x / 2, 30 * zoom)).clamp(Vector2.ZERO, (size - actions.size).max(Vector2.ZERO))
	actions.visible = not dragging
