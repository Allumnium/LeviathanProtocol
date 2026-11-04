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
		var icon_size := CREDIT_ICON.get_size() * (14.0 / maxf(CREDIT_ICON.get_width(), CREDIT_ICON.get_height()))
		draw_texture_rect(CREDIT_ICON, Rect2(center - icon_size * 0.5, icon_size), false)
	elif action == "confirm":
		draw_polyline(PackedVector2Array([center + Vector2(-5, 0), center + Vector2(-1, 4), center + Vector2(5, -4)]), color, 2, true)
	else:
		draw_line(center - Vector2(4, 4), center + Vector2(4, 4), color, 2, true)
		draw_line(center + Vector2(-4, 4), center + Vector2(4, -4), color, 2, true)
