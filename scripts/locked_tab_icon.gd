extends Control

@export var lock_message := ""
var _flash_tween: Tween
@onready var icon: TextureRect = $Icon


func _ready() -> void:
	tooltip_text = lock_message
	gui_input.connect(_on_gui_input)


func _on_gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if (
		mouse_event != null
		and mouse_event.pressed
		and mouse_event.button_index == MOUSE_BUTTON_LEFT
	):
		_flash_twice()
		accept_event()


func _flash_twice() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	icon.modulate = Color.WHITE
	_flash_tween = create_tween()
	for flash_index in range(2):
		_flash_tween.tween_property(icon, "modulate", Color(1.0, 1.0, 1.0, 0.15), 0.08)
		_flash_tween.tween_property(icon, "modulate", Color.WHITE, 0.08)


func _make_custom_tooltip(for_text: String) -> Object:
	var label := Label.new()
	label.text = for_text
	return label
