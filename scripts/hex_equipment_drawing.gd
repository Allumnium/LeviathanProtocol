class_name HexEquipmentDrawing
extends RefCounted

# Hex equipment presentation deliberately has no sprite/art dependencies.
static func title(id: String, rank := 1) -> String:
	var definition := GameDefinitions.find("equipment", id)
	var name: String = definition.get("display_name", id.capitalize())
	return name + (" %d" % rank if id == "research_lab" else "")

static func draw_group(target: CanvasItem, themed: Control, cells: Array[Vector2i], view: Transform2D, name: String, minimum_label_width := 0.0) -> void:
	if cells.is_empty():
		return
	var color := themed.get_theme_color("group_outline_color", "HexEquipmentLabel")
	var center := Vector2.ZERO
	var bounds := Rect2()
	var first := true
	for cell in cells:
		center += view * HexMaterialPalette.center(cell)
		for point in HexMaterialPalette.polygon(cell):
			var next := view * point
			bounds = Rect2(next, Vector2.ZERO) if first else bounds.expand(next)
			first = false
	center /= cells.size()
	for boundary in HexMaterialPalette.outlines(cells):
		for index in range(boundary.size()):
			boundary[index] = view * boundary[index]
		boundary.append(boundary[0])
		target.draw_polyline(boundary, color, 2, true)
	if bounds.size.x < minimum_label_width:
		return # Battle overview: retain outlines; show names when zoomed in.
	# An explicit font lookup on the custom variation can resolve Godot's Label
	# fallback before Theme.default_font. Use the shared default intentionally so
	# changing that one theme property changes every equipment name as well.
	var font := themed.get_theme_default_font()
	var font_size := themed.get_theme_font_size("font_size", "HexEquipmentLabel")
	var line_height := font.get_height(font_size)
	var width := maxf(bounds.size.x - 6, 1)
	for word in name.split(" "):
		width = maxf(width, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var lines: Array[String] = []
	var line := ""
	for word in name.split(" "):
		var candidate := word if line.is_empty() else line + " " + word
		if not line.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			lines.append(line)
			line = word
		else:
			line = candidate
	if not line.is_empty():
		lines.append(line)
	var text_color := themed.get_theme_color("font_color", "HexEquipmentLabel")
	var shadow := themed.get_theme_color("font_outline_color", "HexEquipmentLabel")
	for index in range(lines.size()):
		var position := Vector2(center.x - width * 0.5, center.y - line_height * lines.size() * 0.5 + font.get_ascent(font_size) + index * line_height)
		target.draw_string_outline(font, position, lines[index], HORIZONTAL_ALIGNMENT_CENTER, width, font_size, 3, shadow)
		target.draw_string(font, position, lines[index], HORIZONTAL_ALIGNMENT_CENTER, width, font_size, text_color)
