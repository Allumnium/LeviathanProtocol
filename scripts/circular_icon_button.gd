extends TextureButton


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(_update_tint)
	mouse_exited.connect(_update_tint)
	button_down.connect(_update_tint)
	button_up.connect(_update_tint)


func _update_tint() -> void:
	self_modulate = Color(1.25, 1.25, 1.25) if is_hovered() and not is_pressed() else Color.WHITE
