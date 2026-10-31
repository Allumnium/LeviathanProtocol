class_name HexMaterialPalette
extends Resource

# Artwork can be supplied here without changing the editor or saved designs.
# Single-tile textures are centered on the owner's 64x55 flat-topped hexes.
@export var offense: Texture2D
@export var defense: Texture2D
@export var tech: Texture2D
@export var civic: Texture2D
const TILE_SIZE := Vector2i(64, 55)
const RADIUS := 32.0
const COLORS := [Color("323c45"), Color("53646e"), Color("d65c49"), Color("388bc1"), Color("6baf59"), Color("a873c8")]
static var _fallbacks: Dictionary = {}

func material_texture(category: int) -> Texture2D:
	var art: Texture2D = [offense, defense, tech, civic][category]
	return art if art else fallback(category + 2)

static func fallback(source: int) -> Texture2D:
	if not _fallbacks.has(source):
		var image := Image.create(TILE_SIZE.x, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
		var shape := polygon(Vector2i.ZERO)
		for y in range(TILE_SIZE.y):
			for x in range(TILE_SIZE.x):
				var point := Vector2(x + 0.5, y + 0.5) - Vector2(TILE_SIZE) * 0.5
				if Geometry2D.is_point_in_polygon(point, shape):
					var edge := Geometry2D.is_point_in_polygon(point / 0.89, shape)
					image.set_pixel(x, y, COLORS[source] if edge else COLORS[source].darkened(0.35))
		_fallbacks[source] = ImageTexture.create_from_image(image)
	return _fallbacks[source]

func make_tileset() -> TileSet:
	var result := TileSet.new()
	result.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	result.tile_layout = TileSet.TILE_LAYOUT_STAIRS_DOWN
	result.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	result.tile_size = TILE_SIZE
	for source in range(6):
		var atlas := TileSetAtlasSource.new()
		atlas.texture = fallback(source) if source < 2 else material_texture(source - 2)
		atlas.texture_region_size = Vector2i(atlas.texture.get_size())
		atlas.create_tile(Vector2i.ZERO)
		result.add_source(atlas, source)
	return result

static func polygon(cell: Vector2i) -> PackedVector2Array:
	var result := HexGrid.polygon(cell, RADIUS)
	for index in range(result.size()):
		result[index] = native_point(result[index])
	return result

static func center(cell: Vector2i) -> Vector2:
	return native_point(HexGrid.center(cell, RADIUS))

static func native_point(point: Vector2) -> Vector2:
	# Axial topology stays unchanged; only its presentation turns 30 degrees.
	var rotated := point.rotated(PI / 6)
	return Vector2(rotated.x, rotated.y * TILE_SIZE.y / (HexGrid.ROOT_THREE * RADIUS))

static func outlines(cells: Array[Vector2i]) -> Array[PackedVector2Array]:
	var result := HexGrid.boundaries(cells, RADIUS)
	for boundary in result:
		for index in range(boundary.size()):
			boundary[index] = native_point(boundary[index])
	return result
