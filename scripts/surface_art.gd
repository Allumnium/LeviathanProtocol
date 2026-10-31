class_name SurfaceArt
extends RefCounted

const SHADER = preload("res://shaders/surface_lighting.gdshader")
const MAX_FLASHES := 8
const MAX_PROJECTILE_LIGHTS := 16
static var _textures: Dictionary[String, Texture2D] = {}

static func texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var diffuse := load(path) as Texture2D
	if diffuse == null:
		push_error("Could not load surface diffuse: " + path)
		return null
	if not path.ends_with("_d.png"):
		_textures[path] = diffuse
		return diffuse
	var stem := path.trim_suffix("_d.png")
	for suffix in ["_n.png", "_o.png", "_p.png", "_s.png"]:
		if not ResourceLoader.exists(stem + suffix, "Texture2D"):
			push_error("Missing surface map: " + stem + suffix)
			return null
	var normal := load(stem + "_n.png") as Texture2D
	var height := load(stem + "_p.png") as Texture2D
	var specular := load(stem + "_s.png") as Texture2D
	var occlusion := load(stem + "_o.png") as Texture2D
	for map in [normal, height, specular, occlusion]:
		if map.get_size() != diffuse.get_size():
			push_error("Surface map dimensions do not match: " + stem)
			return null
	var surface := CanvasTexture.new()
	surface.diffuse_texture = diffuse
	# Auxiliary alpha channels retain height and occlusion without extra samplers.
	surface.normal_texture = _with_alpha(normal, height)
	surface.specular_texture = _with_alpha(specular, occlusion)
	surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_textures[path] = surface
	return surface

static func _with_alpha(rgb: Texture2D, alpha: Texture2D) -> ImageTexture:
	var image := rgb.get_image()
	var alpha_image := alpha.get_image()
	image.convert(Image.FORMAT_RGBA8)
	alpha_image.convert(Image.FORMAT_RGBA8)
	var pixels := image.get_data()
	var alpha_pixels := alpha_image.get_data()
	for offset in range(0, pixels.size(), 4):
		pixels[offset + 3] = alpha_pixels[offset]
	return ImageTexture.create_from_image(Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, pixels))

static func diffuse(texture_value: Texture2D) -> Texture2D:
	return texture_value.diffuse_texture if texture_value is CanvasTexture else texture_value

static func apply(target: CanvasItem) -> ShaderMaterial:
	var surface_material := ShaderMaterial.new()
	surface_material.shader = SHADER
	target.material = surface_material
	return surface_material
