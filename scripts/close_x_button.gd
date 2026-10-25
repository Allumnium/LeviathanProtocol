extends TextureButton

const NORMAL_TINT := Color.WHITE
const HOVER_TINT := Color(1.25, 1.25, 1.25, 1.0)
const PRESSED_TINT := Color(0.48, 0.52, 0.58, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	# Always use the complete rectangular control as the hit target. The icon has
	# transparent pixels around its X, which must not create holes in the button.
	texture_click_mask = null
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	pressed.connect(_close_containing_modal)
	_place_in_top_right()
	# Most dialogs add a full-size Contents control after this shared button.
	# GUI hit testing follows sibling order, so defer until the complete scene is
	# assembled and keep the X above that overlapping content.
	_ensure_above_siblings.call_deferred()


func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(point)


func _process(_delta: float) -> void:
	_place_in_top_right()


func _ensure_above_siblings() -> void:
	if is_inside_tree():
		move_to_front()
		_place_in_top_right()


func _place_in_top_right() -> void:
	var parent_control := get_parent() as Control
	var parent_window := get_parent() as Window
	if parent_control == null and parent_window == null:
		return
	var parent_size := (
		parent_control.size if parent_control != null else Vector2(parent_window.size)
	)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(24, 24)
	position = Vector2(parent_size.x - size.x - 6.0, 6.0)


func _on_mouse_entered() -> void:
	self_modulate = HOVER_TINT


func _on_mouse_exited() -> void:
	self_modulate = NORMAL_TINT


func _on_button_down() -> void:
	self_modulate = PRESSED_TINT


func _on_button_up() -> void:
	self_modulate = HOVER_TINT if is_hovered() else NORMAL_TINT


func _close_containing_modal() -> void:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is Popup or ancestor is Window:
			ancestor.hide()
			return
		if ancestor is Control:
			var ancestor_name := str(ancestor.name).to_lower()
			if (
				"modal" in ancestor_name
				or "dialog" in ancestor_name
				or "overlay" in ancestor_name
			):
				ancestor.hide()
				return
		ancestor = ancestor.get_parent()
