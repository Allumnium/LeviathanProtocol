extends Container

var left := HBoxContainer.new()
var middle := HBoxContainer.new()
var right := HBoxContainer.new()
var middle_rect := Rect2()

func _init() -> void:
	name = "CommandHeader"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_PASS
	left.name = "HeaderLeft"
	middle.name = "HeaderMiddle"
	right.name = "HeaderRight"
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	right.alignment = BoxContainer.ALIGNMENT_END
	for section: HBoxContainer in [left, middle, right]:
		add_child(section)

func _get_minimum_size() -> Vector2:
	var height := 50.0
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
		middle_rect = Rect2(start, 0, width, size.y)
		fit_child_in_rect(left, Rect2(8, 6, start - 8, size.y - 12))
		fit_child_in_rect(middle, Rect2(start, 6, width, size.y - 12))
		fit_child_in_rect(right, Rect2(start + width, 6, size.x - start - width - 8, size.y - 12))
		queue_redraw()

func _draw() -> void:
	get_theme_stylebox("left", "CommandHeader").draw(get_canvas_item(), Rect2(0, 0, middle_rect.position.x, size.y))
	get_theme_stylebox("middle", "CommandHeader").draw(get_canvas_item(), middle_rect)
	get_theme_stylebox("right", "CommandHeader").draw(get_canvas_item(),
			Rect2(middle_rect.end.x, 0, size.x - middle_rect.end.x, size.y))
