extends Button

var action := "sell":
	set(value):
		action = value
		queue_redraw()
const CREDIT_ICON = preload("res://assets/credits.png")

func _ready() -> void:
	focus_mode = FOCUS_NONE
	theme_type_variation = &"CompactButton"
	custom_minimum_size = Vector2(18, 18)
	mouse_filter = MOUSE_FILTER_STOP

func _draw() -> void:
	var center := size * 0.5
	var color := get_theme_color("font_color", "Label")
	if action == "sell":
		draw_texture_rect(CREDIT_ICON, Rect2(center - Vector2.ONE * 7, Vector2.ONE * 14), false)
	elif action == "confirm":
		draw_polyline(PackedVector2Array([center + Vector2(-5, 0), center + Vector2(-1, 4), center + Vector2(5, -4)]), color, 2, true)
	else:
		draw_line(center - Vector2(4, 4), center + Vector2(4, 4), color, 2, true)
		draw_line(center + Vector2(-4, 4), center + Vector2(4, -4), color, 2, true)
