extends RefCounted

const HULL: Texture2D = preload("res://assets/ui/Progress_Cp.png")
const HULL_BACK: Texture2D = preload("res://assets/ui/Progress_Cp_Bg.png")
const SHIELD: Texture2D = preload("res://assets/ui/ProgressLv.png")
const SHIELD_BACK: Texture2D = preload("res://assets/ui/ProgressLv_bg.png")

static func configure(bar: TextureProgressBar, shield := false) -> void:
	var front := SHIELD if shield else HULL
	var back := SHIELD_BACK if shield else HULL_BACK
	# Transparent margins give the fill its original inset inside the full track.
	var inset := back.get_size() - front.get_size()
	var padded := AtlasTexture.new()
	padded.atlas = front
	padded.margin = Rect2((inset * 0.5).floor(), inset)
	bar.texture_progress = padded
	bar.texture_under = back
	bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bar.nine_patch_stretch = true
	bar.custom_minimum_size = Vector2(0, 10)
	bar.step = 0.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func draw_hull(target: CanvasItem, rect: Rect2, ratio: float) -> void:
	target.draw_texture_rect(HULL_BACK, rect, false)
	var scale := rect.size / HULL_BACK.get_size()
	var inset := ((HULL_BACK.get_size() - HULL.get_size()) * 0.5).floor()
	var source := Rect2(Vector2.ZERO, HULL.get_size() * Vector2(clampf(ratio, 0, 1), 1))
	if source.has_area():
		target.draw_texture_rect_region(HULL, Rect2(rect.position + inset * scale, source.size * scale), source)
