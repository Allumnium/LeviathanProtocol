extends Container

const DURATION := 0.18
var frame: Control
var edge := Vector2.LEFT
var progress := 1.0
var relevant := false
var initialized := false
var motion: Tween

static func wrap(parent: Node, content: Control, direction: Vector2) -> Container:
	var shell := load("res://scripts/panel_slide.gd").new() as Container
	shell.frame = content
	shell.edge = direction
	shell.size_flags_horizontal = content.size_flags_horizontal
	shell.size_flags_vertical = content.size_flags_vertical
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shell)
	shell.add_child(content)
	content.minimum_size_changed.connect(shell.update_minimum_size)
	return shell

func _get_minimum_size() -> Vector2:
	return frame.get_combined_minimum_size() if is_instance_valid(frame) else Vector2.ZERO

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN and is_instance_valid(frame):
		fit_child_in_rect(frame, Rect2(Vector2.ZERO, size))
		var screen := get_viewport_rect().size
		var distance := size.x + global_position.x if edge == Vector2.LEFT else screen.x - global_position.x
		if edge == Vector2.UP:
			distance = size.y + global_position.y
		elif edge == Vector2.DOWN:
			distance = screen.y - global_position.y
		frame.position += edge * distance * progress

func _process(_delta: float) -> void:
	var needed := _has_content(frame, true)
	if initialized and needed == relevant:
		return
	initialized = true
	relevant = needed
	if motion != null:
		motion.kill()
	if needed:
		frame.show()
		AudioManager.play_ui_sfx(&"panel_open")
	motion = create_tween()
	motion.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	motion.tween_method(_move, progress, 0.0 if needed else 1.0, DURATION)
	if not needed:
		motion.tween_callback(frame.hide)

func _move(value: float) -> void:
	progress = value
	queue_sort()

func _has_content(node: Node, root := false) -> bool:
	if not root and node is CanvasItem and not node.visible:
		return false
	if node is Label and not node.text.strip_edges().is_empty():
		return true
	if node is ResourceText and not node.source_text.strip_edges().is_empty():
		return true
	if node is BaseButton:
		return true
	if node is TextureRect and node.texture != null:
		return true
	for child in node.get_children():
		if _has_content(child):
			return true
	return false
