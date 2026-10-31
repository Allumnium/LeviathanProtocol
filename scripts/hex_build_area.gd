class_name HexBuildArea
extends Control

signal design_changed
signal cell_selected(cell: Vector2i)
signal stroke_started
signal stroke_finished
signal material_changed(cell: Vector2i)

@export var palette: HexMaterialPalette = preload("res://themes/hex_material_palette.tres")
var design: HexShipDesign
var selected_material := 0
var radius := 12.0
var pan := Vector2.ZERO
var unrestricted_blueprints := true
var grid_layer: TileMapLayer
var placed_layer: TileMapLayer
var _pan_root: Node2D
var _overlay: Node2D
var _origin := Vector2.ZERO
var _chassis: ChassisDefinition
var _painting := false
var _erasing := false
var _panning := false
var _last_cell := Vector2i(2147483647, 2147483647)

func _ready() -> void:
	clip_contents = true
	focus_mode = FOCUS_NONE
	_pan_root = Node2D.new()
	add_child(_pan_root)
	var tileset := palette.make_tileset()
	for field in ["grid_layer", "placed_layer"]:
		var layer := TileMapLayer.new()
		layer.name = "GridLayer" if field == "grid_layer" else "PlacedLayer"
		layer.tile_set = tileset
		layer.collision_enabled = false
		layer.navigation_enabled = false
		_pan_root.add_child(layer)
		set(field, layer)
	_origin = grid_layer.map_to_local(Vector2i.ZERO)
	grid_layer.position = -_origin
	placed_layer.position = -_origin
	_overlay = Node2D.new()
	add_child(_overlay)
	_overlay.draw.connect(_draw_equipment)
	resized.connect(fit_view)
	mouse_exited.connect(_stop_painting)
	refresh()
	fit_view()

func set_design(blueprint: HexShipDesign) -> void:
	_stop_painting()
	design = blueprint
	_chassis = blueprint.chassis() if blueprint else null
	refresh()
	fit_view()

func refresh() -> void:
	if not is_instance_valid(grid_layer):
		return
	grid_layer.clear()
	placed_layer.clear()
	if _chassis:
		for cell in _chassis.hull:
			grid_layer.set_cell(cell, 0 if _chassis.region_at(cell).is_empty() else 1, Vector2i.ZERO)
		for cell: Vector2i in design.tiles:
			placed_layer.set_cell(cell, design.tiles[cell] + 2, Vector2i.ZERO)
	_overlay.queue_redraw()
	queue_redraw()

func fit_view() -> void:
	if _chassis == null or size.x <= 0 or size.y <= 0 or not is_instance_valid(grid_layer):
		return
	var bounds := Rect2()
	var first := true
	for cell in _chassis.hull:
		for point in HexMaterialPalette.polygon(cell):
			bounds = Rect2(point, Vector2.ZERO) if first else bounds.expand(point)
			first = false
	var factor := maxf(0.05, minf((size.x - 24) / bounds.size.x, (size.y - 24) / bounds.size.y))
	radius = HexMaterialPalette.RADIUS * factor
	pan = size * 0.5 - bounds.get_center() * factor
	_apply_view()

func _apply_view() -> void:
	if is_instance_valid(_pan_root):
		_pan_root.position = pan
		_pan_root.scale = Vector2.ONE * radius / HexMaterialPalette.RADIUS
		_overlay.queue_redraw()

func cell_at(point: Vector2) -> Vector2i:
	return grid_layer.local_to_map((point - pan) * HexMaterialPalette.RADIUS / radius + _origin)

func cell_position(cell: Vector2i) -> Vector2:
	return pan + (grid_layer.map_to_local(cell) - _origin) * radius / HexMaterialPalette.RADIUS

func _stop_painting() -> void:
	var was_painting := _painting
	_painting = false
	_erasing = false
	_panning = false
	_last_cell = Vector2i(2147483647, 2147483647)
	if was_painting:
		stroke_finished.emit()

func _gui_input(event: InputEvent) -> void:
	if design == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var point: Vector2 = event.position
			var next := clampf(radius * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 2, 64)
			pan = point - (point - pan) * next / radius
			radius = next
			_apply_view()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				get_viewport().gui_release_focus()
				_stop_painting()
				_painting = true
				_erasing = event.button_index == MOUSE_BUTTON_RIGHT
				stroke_started.emit()
				_paint(event.position)
			else:
				_stop_painting()
		accept_event()
	elif event is InputEventMouseMotion:
		if _panning:
			pan += event.relative
			_apply_view()
		elif _painting:
			_paint(event.position)
		accept_event()

func _paint(point: Vector2) -> void:
	var cell := cell_at(point)
	if cell == _last_cell:
		return
	var previous := _last_cell
	_last_cell = cell
	if previous.x != 2147483647:
		var steps := HexGrid.distance(previous, cell)
		for index in range(1, steps):
			var between := HexGrid.center(previous, 1).lerp(HexGrid.center(cell, 1), float(index) / steps)
			_paint_cell(HexGrid.at_point(between, 1))
	_paint_cell(cell)

func _paint_cell(cell: Vector2i) -> void:
	if not _chassis.has_cell(cell):
		return
	cell_selected.emit(cell)
	var old: int = design.tiles.get(cell, -1)
	if (_erasing and old < 0) or (not _erasing and old == selected_material):
		return
	var changed := design.remove_tile(cell) if _erasing else design.set_tile(cell, selected_material)
	if changed:
		if _erasing:
			placed_layer.erase_cell(cell)
		else:
			placed_layer.set_cell(cell, selected_material + 2, Vector2i.ZERO)
		material_changed.emit(cell)
		design_changed.emit()
		_overlay.queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("090e12"))

func _draw_equipment() -> void:
	if _chassis == null:
		return
	var view := Transform2D(0, Vector2.ONE * radius / HexMaterialPalette.RADIUS, 0, pan)
	for region in _chassis.regions:
		var cells: Array[Vector2i] = []
		cells.assign(region.cells)
		for outline in HexMaterialPalette.outlines(cells):
			for index in range(outline.size()):
				outline[index] = view * outline[index]
			outline.append(outline[0])
			_overlay.draw_polyline(outline, Color("8ba2ad80"), 1)
	for builtin in _chassis.builtins:
		HexEquipmentDrawing.draw_group(_overlay, self, builtin.cells, view, HexEquipmentDrawing.title(builtin.equipment_id, builtin.rank))
	for component in design.components:
		var cells: Array[Vector2i] = []
		cells.assign(HexShipDesign.component_cells(component).keys())
		HexEquipmentDrawing.draw_group(_overlay, self, cells, view, HexEquipmentDrawing.title(component.equipment_id, component.rank))
