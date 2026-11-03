extends PanelContainer

var art: Texture2D
var horizontal := false
var background := Sprite2D.new()
var padding := StyleBoxEmpty.new()
var source_padding := Vector4()

func _ready() -> void:
	var style := get_theme_stylebox("panel")
	art = SurfaceArt.texture(get_theme_icon("frame").resource_path)
	source_padding = Vector4(style.content_margin_left, style.content_margin_top,
		style.content_margin_right, style.content_margin_bottom)
	add_theme_stylebox_override("panel", padding)
	background.texture = art
	background.show_behind_parent = true
	add_child(background)
	SurfaceArt.apply(background)
	texture_filter = TEXTURE_FILTER_NEAREST
	resized.connect(_resize_art, CONNECT_DEFERRED)
	_resize_art()

func _resize_art() -> void:
	if art == null:
		return
	if horizontal:
		custom_minimum_size.y = size.x * art.get_height() / art.get_width()
	background.position = size * 0.5
	background.scale = Vector2.ONE * minf(size.x / art.get_width(), size.y / art.get_height())
	var remaining := size - art.get_size() * background.scale
	if horizontal:
		background.position.y += remaining.y * 0.5
	elif theme_type_variation == &"CommandLeftPanel":
		background.position.x -= remaining.x * 0.5
	else:
		background.position.x += remaining.x * 0.5
	padding.content_margin_left = ceilf(source_padding.x * background.scale.x)
	padding.content_margin_top = ceilf(source_padding.y * background.scale.y)
	padding.content_margin_right = ceilf(source_padding.z * background.scale.x)
	padding.content_margin_bottom = ceilf(source_padding.w * background.scale.y)
