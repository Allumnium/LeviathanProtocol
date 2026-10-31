class_name HexRecipePreview
extends Control

var layout := {}
var _layer: TileMapLayer
var _overlay: Node2D
var equipment_name := ""
var palette: HexMaterialPalette = preload("res://themes/hex_material_palette.tres")

func _ready() -> void:
	_layer = TileMapLayer.new()
	_layer.tile_set = palette.make_tileset()
	_layer.collision_enabled = false
	_layer.navigation_enabled = false
	add_child(_layer)
	_overlay = Node2D.new()
	add_child(_overlay)
	_overlay.draw.connect(_draw_equipment)
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(_rebuild)
	_rebuild()

func set_recipe(recipe: Dictionary, turns := 0, flipped := false, label := "") -> void:
	layout = HexRecipe.cells(recipe, turns, flipped)
	equipment_name = label
	_rebuild()

func _rebuild() -> void:
	if not is_instance_valid(_layer):
		return
	_layer.clear()
	_overlay.queue_redraw()
	if layout.is_empty():
		return
	var bounds := Rect2()
	var first := true
	for cell: Vector2i in layout:
		_layer.set_cell(cell, layout[cell] + 2, Vector2i.ZERO)
		for point in HexMaterialPalette.polygon(cell):
			bounds = Rect2(point, Vector2.ZERO) if first else bounds.expand(point)
			first = false
	var factor := maxf(0.05, minf((size.x - 24) / bounds.size.x, (size.y - 24) / bounds.size.y))
	_layer.scale = Vector2.ONE * minf(factor, 2)
	_layer.position = size * 0.5 - (bounds.get_center() + _layer.map_to_local(Vector2i.ZERO)) * _layer.scale

func _draw_equipment() -> void:
	if equipment_name.is_empty():
		return
	var cells: Array[Vector2i] = []
	cells.assign(layout.keys())
	var view := Transform2D(0, _layer.scale, 0, _layer.position + _layer.map_to_local(Vector2i.ZERO) * _layer.scale)
	HexEquipmentDrawing.draw_group(_overlay, self, cells, view, equipment_name)
