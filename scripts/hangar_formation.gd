extends Control

signal ship_selected(id: int)
signal ship_opened(id: int)
signal action_failed(message: String)
const GLOW = preload("res://shaders/ship_selection.gdshader")
const Exhaust = preload("res://scripts/ship_exhaust.gd")
const PlaceholderAssets = preload("res://scripts/placeholders.gd")
const STATION_ART := "res://assets/environment/space_station_large_d.png"
const STATION_REVOLUTION_SECONDS := 30.0
var station: Sprite2D
var surface_material: ShaderMaterial
var station_angle := 0.0
var exhaust_elapsed := 0.0
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
var glows: Dictionary = {}
var starfield: Control
var hit_images: Dictionary = {}
var travel_distance_nu := 0.0
var _last_travel_distance_nu := 0.0

func _ready() -> void:
	surface_material = SurfaceArt.apply(self)
	clip_contents = true
	focus_mode = FOCUS_NONE
	starfield = load("res://scripts/main_menu_starfield.gd").new()
	starfield.stationary = true
	starfield.set_area(GameState.run_seed, 0)
	starfield.show_behind_parent = true
	starfield.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(starfield)
	starfield.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	station = Sprite2D.new()
	station.name = "DockedStation"
	station.show_behind_parent = true
	station.texture = SurfaceArt.texture(STATION_ART)
	station.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var station_material := SurfaceArt.apply(station)
	station_material.set_shader_parameter("emission_energy", 0.25)
	add_child(station)
	_update_station()
	if travel_distance_nu > 0.0:
		starfield.call("scroll_stationary", travel_distance_nu * 0.002)
	if selected_ids.is_empty() and selected_id > 0:
		selected_ids.append(selected_id)
	_expand_squadrons()
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
	resized.connect(queue_redraw)

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

func _expand_squadrons() -> void:
	var expanded: Array[int] = []
	var groups := {}
	for id: int in selected_ids:
		var group := HangarSquadrons.for_ship(GameState.squadrons, id)
		if group.is_empty():
			continue
		groups[int(group.id)] = true
		for member: int in group.members:
			if member not in expanded:
				expanded.append(member)
	selected_ids = expanded
	selected_id = selected_ids[0] if groups.size() == 1 else 0

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
			if hit > 0 and event.double_click:
				ship_opened.emit(hit)
				return
			if hit > 0:
				AudioManager.play_ui_sfx(&"select_tab")
				if hit not in selected_ids:
					selected_ids.assign([hit])
				_expand_squadrons()
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
					if not GameState.move_ships(positions):
						action_failed.emit(GameState.last_save_error if not GameState.last_save_error.is_empty() else "Formation move failed.")
				drag_delta = Vector2.ZERO
			elif box_selecting:
				box_selecting = false
				var rect := Rect2(box_start, box_end - box_start).abs()
				if rect.size.length() > 4:
					for owned: HangarShip in GameState.fleet:
						if rect.has_point(point(owned)):
							selected_ids.append(owned.id)
				_expand_squadrons()
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

func _process(delta: float) -> void:
	if is_visible_in_tree():
		exhaust_elapsed += delta
		station_angle = fmod(station_angle + TAU * delta / STATION_REVOLUTION_SECONDS, TAU)
		_update_station()
		if starfield != null and travel_distance_nu > _last_travel_distance_nu:
			starfield.call("scroll_stationary",
					(travel_distance_nu - _last_travel_distance_nu) * 0.002)
			_last_travel_distance_nu = travel_distance_nu
		queue_redraw()

func _update_station() -> void:
	if station == null:
		return
	var simulation = GameState.expedition_simulation
	station.visible = simulation != null and simulation.state != null \
			and not simulation.state.docked_location_id.is_empty()
	var light := Vector4.ZERO
	if station.visible:
		station.position = size * 0.5 + (Vector2(-2.8, -1.6) * 52 - camera) * zoom
		station.scale = Vector2.ONE * 220.0 * zoom / station.texture.get_width()
		station.rotation = station_angle
		var transform := get_global_transform_with_canvas()
		var origin := transform * station.position
		light = Vector4(origin.x, origin.y, 420.0 * zoom * transform.x.length(), 1.2)
	surface_material.set_shader_parameter("station_light", light)

func _draw_location() -> void:
	var simulation = GameState.expedition_simulation
	if simulation == null or simulation.state == null:
		return
	var state = simulation.state
	var texture: Texture2D
	if state.docked_location_id.is_empty() and state.destination_location_id.is_empty() and not state.visited_location_ids.is_empty():
		var here: Dictionary = simulation.locations.get(state.visited_location_ids.back(), {})
		if not here.is_empty() and state.position_nu.distance_to(Vector2(here.position[0], here.position[1])) < 0.01:
			texture = PlaceholderAssets.art()
	if texture == null:
		return
	# Small pixel art: keep an integer scale and sit it beside, not over, the fleet.
	var extent := Vector2.ONE * 40.0 * zoom
	var center := size * 0.5 + (Vector2(-2.3, -2.3) * 52 - camera) * zoom
	draw_texture_rect(texture, Rect2((center - extent * 0.5).round(), extent), false, Color(1, 1, 1, 0.85))

func _draw() -> void:
	_draw_location()
	for owned: HangarShip in GameState.fleet:
		var rect := ship_rect(owned)
		Exhaust.draw(self, owned, rect, exhaust_elapsed)
		draw_texture_rect(owned.art_texture, rect, false)
		owned.draw_fitted_equipment(self, rect)
		if glows.has(owned.id):
			var glow: TextureRect = glows[owned.id]
			glow.position = rect.position
			glow.size = rect.size
			glow.visible = owned.id in selected_ids
	if box_selecting:
		var rect := Rect2(box_start, box_end - box_start).abs()
		draw_rect(rect, Color(1, 1, 1, 0.08))
		draw_rect(rect, get_theme_color("selection_color", "SlotCanvas"), false)
