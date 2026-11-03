extends RefCounted

static func decorate(button: Button, kind: String) -> void:
	button.text = ""
	button.custom_minimum_size = Vector2(20, 20)
	button.toggle_mode = true
	button.draw.connect(func() -> void:
		var origin := (button.size - Vector2(12, 12)) * 0.5
		var color := button.get_theme_color("font_disabled_color" if button.disabled else "font_color")
		if kind == "pause":
			for x: float in [0.0, 8.0]:
				button.draw_rect(Rect2(origin + Vector2(x, 0), Vector2(4, 12)), color)
		else:
			var width := 6.0 if kind == "fast" else 10.0
			for x: float in ([0.0, 6.0] if kind == "fast" else [1.0]):
				button.draw_colored_polygon(PackedVector2Array([
					origin + Vector2(x, 0), origin + Vector2(x + width, 6),
					origin + Vector2(x, 12)]), color))
