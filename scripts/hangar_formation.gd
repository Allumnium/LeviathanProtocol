extends Control

signal ship_selected(id: int)
signal equipment_requested(id: int)
signal salvage_requested(id: int)
const GLOW = preload("res://shaders/ship_selection.gdshader")
var selected_id := 0
var selected_ids: Array[int] = []
var dragging := false
var panning := false
var camera := Vector2.ZERO
var zoom := 1.0
var drag_start := Vector2.ZERO
var drag_delta := Vector2.ZERO
var box_selecting := false
var box_start := Vector2.ZERO
var box_end := Vector2.ZERO
var actions: HBoxContainer
var glows: Dictionary = {}
var starfield: Control
var hit_images: Dictionary = {}

func _ready() -> void:
	SurfaceArt.apply(self)
	clip_contents = true
	focus_mode = FOCUS_NONE
	starfield = load("res://scripts/main_menu_starfield.gd").new()
	starfield.stationary = true
	starfield.show_behind_parent = true
	starfield.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(starfield)
	starfield.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	if selected_ids.is_empty() and selected_id > 0:
		selected_ids.append(selected_id)
	for owned: HangarShip in GameState.fleet:
		hit_images[owned.id] = SurfaceArt.diffuse(owned.art_texture).get_image()
		var glow := TextureRect.new()
		glow.texture = SurfaceArt.diffuse(owned.art_texture)
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.mouse_filter = MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		material.shader = GLOW
		material.set_shader_parameter("glow_color", get_theme_color("selection_color", "SlotCanvas"))
		glow.material = material
		add_child(glow)
		glows[owned.id] = glow
	actions = HBoxContainer.new()
	add_child(actions)
	if selected_ids.size() == 1:
		_action("EQUIP", func() -> void: equipment_requested.emit(selected_id))
		var owned: HangarShip = GameState.owned_ship(selected_id)
		if owned != null and not owned.flagship:
			_action("SALVAGE", func() -> void: salvage_requested.emit(selected_id))
	resized.connect(queue_redraw)

func _action(title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.theme_type_variation = &"CompactButton"
	button.focus_mode = FOCUS_NONE
	button.pressed.connect(callback)
	actions.add_child(button)

func point(owned: FleetShip) -> Vector2:
	var position := owned.formation + (drag_delta if dragging and owned.id in selected_ids else Vector2.ZERO)
	return size * 0.5 + (position * 52 - camera) * zoom

func _world(position: Vector2) -> Vector2:
	return (camera + (position - size * 0.5) / zoom) / 52

func ship_rect(owned: HangarShip) -> Rect2:
	var extent := Vector2.ONE * 52 * zoom * owned.fleet_view_scale()
	return Rect2(point(owned) - extent * 0.5, extent)

func _hit(position: Vector2) -> int:
	for owned: HangarShip in GameState.fleet:
		var rect := ship_rect(owned)
		if rect.has_point(position):
			var pixel := (position - rect.position) / rect.size * owned.art_texture.get_size()
			if hit_images[owned.id].get_pixelv(Vector2i(pixel)).a > 0.1:
				return owned.id
	return 0

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
			var hit := _hit(event.position)
			if hit > 0:
				AudioManager.play_ui_sfx(&"select_tab")
				if hit not in selected_ids:
					selected_ids.assign([hit])
				selected_id = hit if selected_ids.size() == 1 else 0
				dragging = true
				drag_start = _world(event.position)
				drag_delta = Vector2.ZERO
			else:
				box_selecting = true
				box_start = event.position
				box_end = event.position
				selected_ids.clear()
				selected_id = 0
				starfield._gui_input(event)
		else:
			if dragging:
				dragging = false
				if not drag_delta.is_zero_approx():
					var positions := {}
					for id in selected_ids:
						positions[id] = GameState.owned_ship(id).formation + drag_delta
					GameState.move_ships(positions)
				drag_delta = Vector2.ZERO
			elif box_selecting:
				box_selecting = false
				var rect := Rect2(box_start, box_end - box_start).abs()
				if rect.size.length() > 4:
					for owned: HangarShip in GameState.fleet:
						if rect.has_point(point(owned)):
							selected_ids.append(owned.id)
				selected_id = selected_ids[0] if selected_ids.size() == 1 else 0
			ship_selected.emit(selected_id)
		queue_redraw()
	elif event is InputEventMouseMotion:
		if dragging:
			var delta := _world(event.position) - drag_start
			var lower := Vector2(-INF, -INF)
			var upper := Vector2(INF, INF)
			for id in selected_ids:
				var origin: Vector2 = GameState.owned_ship(id).formation
				lower = lower.max(Vector2(-5, -4) - origin)
				upper = upper.min(Vector2(5, 4) - origin)
			drag_delta = delta.clamp(lower, upper)
		elif box_selecting:
			box_end = event.position
		queue_redraw()

func _draw() -> void:
	for owned: HangarShip in GameState.fleet:
		var rect := ship_rect(owned)
		draw_texture_rect(owned.art_texture, rect, false)
		owned.draw_fitted_equipment(self, rect)
		if glows.has(owned.id):
			var glow: TextureRect = glows[owned.id]
			glow.position = rect.position
			glow.size = rect.size
			glow.visible = owned.id in selected_ids
		if owned.id == selected_id:
			actions.position = (point(owned) + Vector2(-actions.size.x / 2, rect.size.y * 0.5 + 4 * zoom)).clamp(Vector2.ZERO, (size - actions.size).max(Vector2.ZERO))
	actions.visible = selected_ids.size() == 1 and not dragging and not box_selecting
	if box_selecting:
		var rect := Rect2(box_start, box_end - box_start).abs()
		draw_rect(rect, Color(1, 1, 1, 0.08))
		draw_rect(rect, get_theme_color("selection_color", "SlotCanvas"), false)
