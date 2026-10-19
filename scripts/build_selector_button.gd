extends TextureButton

@export var selected_texture: Texture2D
@export var unselected_icon_modulate := Color(0.8, 0.8, 0.8, 1.0)

@onready var icon: TextureRect = $Icon

var _unselected_texture: Texture2D
var _highlighted_texture: Texture2D
var _pressed_texture: Texture2D


func _ready() -> void:
	_unselected_texture = texture_normal
	_highlighted_texture = texture_hover
	_pressed_texture = texture_pressed
	toggled.connect(_on_toggled)
	_on_toggled(button_pressed)


func _on_toggled(is_selected: bool) -> void:
	texture_normal = selected_texture if is_selected else _unselected_texture
	texture_hover = selected_texture if is_selected else _highlighted_texture
	texture_pressed = selected_texture if is_selected else _pressed_texture
	icon.modulate = Color.WHITE if is_selected else unselected_icon_modulate
