extends Container

var left := HBoxContainer.new()
var middle := HBoxContainer.new()
var right := HBoxContainer.new()
var course := HBoxContainer.new()
var middle_rect := Rect2()
var art: Texture2D
var background := Sprite2D.new()

func _ready() -> void:
	art = SurfaceArt.texture(get_theme_icon("frame", "CommandHeader").resource_path)
	background.texture = art
	background.show_behind_parent = true
	add_child(background)
	SurfaceArt.apply(background)
	resized.connect(update_minimum_size, CONNECT_DEFERRED)
	update_minimum_size()

func _init() -> void:
	name = "CommandHeader"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_PASS
	left.name = "HeaderLeft"
	middle.name = "HeaderMiddle"
	right.name = "HeaderRight"
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	course.alignment = BoxContainer.ALIGNMENT_CENTER
	right.alignment = BoxContainer.ALIGNMENT_END
	for section: HBoxContainer in [left, middle, right, course]:
		add_child(section)

func _get_minimum_size() -> Vector2:
	var height := size.x * art.get_height() / art.get_width() if art != null else 50.0
	for section: HBoxContainer in [left, middle, right]:
		height = maxf(height, section.get_combined_minimum_size().y + 12)
	return Vector2(left.get_combined_minimum_size().x + middle.get_combined_minimum_size().x
			+ right.get_combined_minimum_size().x + 16, height)

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var left_min := left.get_combined_minimum_size().x
		var right_min := right.get_combined_minimum_size().x
		var middle_min := middle.get_combined_minimum_size().x
		var width := maxf(middle_min, minf(244, size.x - 16 - 2 * maxf(left_min, right_min)))
		var start := clampf(floorf((size.x - width) * 0.5), left_min + 8, size.x - right_min - width - 8)
		var art_scale := size.x / 688.0
		var wing_height := maxf(left.get_combined_minimum_size().y, right.get_combined_minimum_size().y)
		middle_rect = Rect2(start, 7 * art_scale, width, 23 * art_scale)
		fit_child_in_rect(left, Rect2(8, 12 * art_scale, start - 8, wing_height))
		fit_child_in_rect(middle, middle_rect)
		fit_child_in_rect(right, Rect2(start + width, 12 * art_scale, size.x - start - width - 8, wing_height))
		var course_width := maxf(course.get_combined_minimum_size().x, 144 * art_scale)
		fit_child_in_rect(course, Rect2((size.x - course_width) * 0.5, 40 * art_scale, course_width, 34 * art_scale))
		if art != null:
			background.position = size * 0.5
			background.scale = Vector2.ONE * minf(size.x / art.get_width(), size.y / art.get_height())
			background.position.y = art.get_height() * background.scale.y * 0.5
