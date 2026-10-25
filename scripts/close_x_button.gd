extends Control

signal pressed


func _ready() -> void:
	$Button.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	pressed.emit()
