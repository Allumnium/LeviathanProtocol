extends CanvasLayer

# Overworld <-> battle transition: a bright flash, horizontal shutters closing
# to black with an optional caption, then the scene change. The next scene
# calls reveal() to open from black.
const SHUTTERS := 8
static var pending_reveal := false

var _bars: Array[ColorRect] = []
var _flash: ColorRect
var _caption: Label

static func cover_and_change(host: Node, scene_path: String, caption := "", flash := true) -> void:
	var fade = load("res://scripts/scene_fade.gd").new()
	host.get_tree().root.add_child(fade)
	fade._build(caption)
	fade._close(scene_path, flash)

static func reveal(host: Node) -> void:
	if not pending_reveal:
		return
	pending_reveal = false
	var fade = load("res://scripts/scene_fade.gd").new()
	host.add_child(fade)
	fade._build("")
	fade._open()

func _build(caption: String) -> void:
	layer = 120
	var viewport := get_viewport().get_visible_rect().size
	for index in range(SHUTTERS):
		var bar := ColorRect.new()
		bar.color = Color(0.0, 0.01, 0.02)
		bar.mouse_filter = Control.MOUSE_FILTER_STOP
		bar.position = Vector2(0, viewport.y * index / SHUTTERS)
		bar.size = Vector2(viewport.x, ceilf(viewport.y / SHUTTERS) + 1)
		add_child(bar)
		_bars.append(bar)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.size = viewport
	add_child(_flash)
	_caption = Label.new()
	_caption.text = caption
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.size = viewport
	_caption.modulate.a = 0.0
	_caption.add_theme_font_size_override("font_size", 32)
	add_child(_caption)

func _close(scene_path: String, flash: bool) -> void:
	for bar in _bars:
		bar.scale.x = 0.0
	var tween := create_tween()
	if flash:
		tween.tween_property(_flash, "color:a", 0.85, 0.06)
		tween.tween_property(_flash, "color:a", 0.0, 0.12)
		tween.tween_property(_flash, "color:a", 0.6, 0.06)
		tween.tween_property(_flash, "color:a", 0.0, 0.12)
	tween.set_parallel(true)
	for index in range(_bars.size()):
		var bar := _bars[index]
		if index % 2 == 1:
			bar.pivot_offset = Vector2(bar.size.x, 0)
		tween.tween_property(bar, "scale:x", 1.0, 0.45).set_delay(0.03 * index).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	if not _caption.text.is_empty():
		tween.tween_property(_caption, "modulate:a", 1.0, 0.2)
		tween.tween_interval(0.5)
	tween.tween_callback(func() -> void:
		pending_reveal = true
		var error := get_tree().change_scene_to_file(scene_path)
		if error != OK:
			push_error("Could not change scene to %s: %s" % [scene_path, error])
		queue_free())

func _open() -> void:
	var tween := create_tween().set_parallel(true)
	for index in range(_bars.size()):
		var bar := _bars[index]
		if index % 2 == 0:
			bar.pivot_offset = Vector2(bar.size.x, 0)
		tween.tween_property(bar, "scale:x", 0.0, 0.4).set_delay(0.03 * index).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
