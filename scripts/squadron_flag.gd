extends RefCounted

const SIZE := Vector2(22, 18)

static func rect(bounds: Rect2) -> Rect2:
	return Rect2(Vector2(bounds.position.x - SIZE.x - 5, bounds.get_center().y - SIZE.y * 0.5), SIZE)

static func draw(canvas: CanvasItem, area: Rect2, label: String, selected: bool, enemy := false) -> void:
	var color := Color("ed8975") if enemy else Color("8cd4e8")
	canvas.draw_rect(area.grow(2), Color("162431") if selected else Color("070d15"))
	if selected:
		canvas.draw_rect(area.grow(2), color, false)
	var p := area.position
	canvas.draw_line(p + Vector2(2, 1), p + Vector2(2, 17), color, 1)
	canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(3, 1), p + Vector2(21, 1), p + Vector2(17, 7), p + Vector2(21, 13), p + Vector2(3, 13)]), color)
	canvas.draw_string(ThemeDB.fallback_font, p + Vector2(5, 11), label, HORIZONTAL_ALIGNMENT_LEFT, 15, 9, Color("070d15"))
