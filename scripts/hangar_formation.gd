extends Control

signal ship_selected(id: int)
signal squadron_selected(id: int)
const Flag = preload("res://scripts/squadron_flag.gd")
var selected_squadron_id := 0
signal action_failed(message: String)
const VIEW_SCALE := 52.0
var drag_origins: Dictionary[int, Vector2] = {}
var drag_moved := false
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
var display_positions: Dictionary[int, Vector2] = {}

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
	_load_formation()
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
	var position: Vector2 = display_positions.get(owned.id, Vector2.ZERO)
	return size * 0.5 + (position * VIEW_SCALE - camera) * zoom

func _load_formation() -> void:
	display_positions.clear()
	for owned: HangarShip in GameState.fleet:
		display_positions[owned.id] = owned.formation

func _start_drag(position: Vector2) -> void:
	dragging = GameState._can_refit()
	drag_start = position
	drag_moved = false
	drag_origins.clear()
	for id: int in selected_ids:
		drag_origins[id] = display_positions[id]

func _preview_drag(position: Vector2) -> void:
	if not drag_moved and position.distance_to(drag_start) < 3:
		return
	drag_moved = true
	var delta := (position - drag_start) / (VIEW_SCALE * zoom)
	var lower := Vector2(-INF, -INF)
	var upper := Vector2(INF, INF)
	var area := BattleSimulation.formation_area()
	for id: int in drag_origins:
		var radius := Vector2.ONE * GameState.owned_ship(id).get_stats().collision_radius / BattleSimulation.DEPLOYMENT_SCALE
		lower = lower.max(area.position + radius - drag_origins[id])
		upper = upper.min(area.end - radius - drag_origins[id])
	delta = delta.clamp(lower, upper)
	for id: int in drag_origins:
		display_positions[id] = drag_origins[id] + delta
	queue_redraw()

func _finish_drag() -> void:
	dragging = false
	if drag_moved:
		var positions := {}
		for id: int in drag_origins:
			positions[id] = display_positions[id]
		if not GameState.move_ships(positions):
			_load_formation()
			action_failed.emit(GameState.last_save_error if not GameState.last_save_error.is_empty() else "Formation unavailable.")
	drag_origins.clear()
	drag_moved = false
	queue_redraw()

func _world(position: Vector2) -> Vector2:
	return (camera + (position - size * 0.5) / zoom) / VIEW_SCALE

func ship_rect(owned: HangarShip) -> Rect2:
	var extent := BattleSimulation.Collision.hangar_rect(owned).size * VIEW_SCALE / BattleSimulation.DEPLOYMENT_SCALE * zoom
	return Rect2(point(owned) - extent * 0.5, extent)

func _hit(position: Vector2) -> int:
	for owned: HangarShip in GameState.fleet:
		var rect := ship_rect(owned)
		if rect.has_point(position):
			var pixel := (position - rect.position) / rect.size * owned.art_texture.get_size()
			if hit_images[owned.id].get_pixelv(Vector2i(pixel)).a > 0.1:
				return owned.id
	return 0

func flag_rect(group: Dictionary) -> Rect2:
	var bounds := ship_rect(GameState.owned_ship(int(group.members[0])))
	for id: int in group.members:
		bounds = bounds.merge(ship_rect(GameState.owned_ship(id)))
	return Flag.rect(bounds)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			if dragging:
				return
			var world: Vector2 = camera + (event.position - size * 0.5) / zoom
			zoom = clampf(zoom * (1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.2), 0.4, 2.5)
			camera = world - (event.position - size * 0.5) / zoom
			queue_redraw()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
			return
	if event is InputEventMouseMotion and dragging:
		_preview_drag(event.position)
		return
	if event is InputEventMouseMotion and panning:
		camera -= event.relative / zoom
		queue_redraw()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			for group: Dictionary in GameState.squadrons:
				if flag_rect(group).has_point(event.position):
					selected_squadron_id = int(group.id)
					selected_ids.assign(group.members)
					selected_id = int(group.members[0])
					_start_drag(event.position)
					squadron_selected.emit(int(group.id))
					return
			var hit := _hit(event.position)
			if hit > 0:
				selected_squadron_id = 0
				selected_id = hit
				selected_ids.assign([hit])
				_start_drag(event.position)
				ship_selected.emit(hit)
				return
			selected_ids.clear()
			selected_id = 0
			starfield._gui_input(event)
			ship_selected.emit(0)
		elif dragging:
			_preview_drag(event.position)
			_finish_drag()
		queue_redraw()

func _process(delta: float) -> void:
	if is_visible_in_tree():
		var simulation = GameState.expedition_simulation
		if simulation != null and simulation.state != null:
			exhaust_elapsed = simulation.state.simulation_seconds
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
		var simulation = GameState.expedition_simulation
		if simulation != null and simulation.state != null \
				and simulation.state.travel_state == ExpeditionState.TravelState.CRUISING \
				and simulation.state.pause_reasons.is_empty():
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

	for group: Dictionary in GameState.squadrons:
		Flag.draw(self, flag_rect(group), str(group.id), selected_squadron_id == int(group.id))
