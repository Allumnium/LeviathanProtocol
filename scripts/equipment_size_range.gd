extends Control

signal changed

var lower := 0
var upper := 3
var dragging_handle := -1

func _init() -> void:
	custom_minimum_size = Vector2(108, 38)
	size_flags_horizontal = SIZE_EXPAND_FILL
	focus_mode = FOCUS_NONE
	mouse_default_cursor_shape = CURSOR_POINTING_HAND

func _ready() -> void:
	resized.connect(queue_redraw)

func set_range(first: int, last: int, notify := false) -> void:
	var next_lower := clampi(first, 0, 3)
	var next_upper := clampi(last, next_lower, 3)
	if lower == next_lower and upper == next_upper:
		return
	lower = next_lower
	upper = next_upper
	queue_redraw()
	if notify:
		changed.emit()

func _handle_x(index: int) -> float:
	return roundf(8 + (size.x - 16) * index / 3.0)

func _handle_center(handle: int) -> float:
	var x := _handle_x(lower if handle == 0 else upper)
	return x + (-4 if handle == 0 else 4) if lower == upper else x

func _draw() -> void:
	var track := Rect2(8, 8, maxf(1, size.x - 16), 6)
	draw_style_box(get_theme_stylebox("slider", "HSlider"), track)
	draw_style_box(get_theme_stylebox("grabber_area", "HSlider"),
		Rect2(_handle_x(lower), 8, maxf(1, _handle_x(upper) - _handle_x(lower)), 6))
	var handle := get_theme_icon("grabber", "HSlider")
	for index in range(2):
		draw_texture(handle, Vector2(_handle_center(index) - handle.get_width() / 2.0, 3).round())
	var font := get_theme_font("font", "Label")
	var font_size := get_theme_font_size("font_size", "EquipmentLabel")
	for index in range(4):
		var title: String = SlotCatalog.SIZES[index]
		var text_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(_handle_x(index) - text_width / 2, 34).round(), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, get_theme_color("font_color", "Label"))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var distance_lower := absf(event.position.x - _handle_center(0))
			var distance_upper := absf(event.position.x - _handle_center(1))
			dragging_handle = 0 if distance_lower < distance_upper else 1
			if lower == upper:
				dragging_handle = 0 if event.position.x < _handle_x(lower) else 1
			_move_handle(event.position.x)
		else:
			dragging_handle = -1
		accept_event()
	elif event is InputEventMouseMotion and dragging_handle >= 0:
		_move_handle(event.position.x)
		accept_event()

func _move_handle(x: float) -> void:
	var index := clampi(roundi((x - 8) / maxf(1, size.x - 16) * 3), 0, 3)
	set_range(mini(index, upper) if dragging_handle == 0 else lower,
		maxi(index, lower) if dragging_handle == 1 else upper, true)
