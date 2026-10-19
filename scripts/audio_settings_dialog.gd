extends RefCounted

const BOLD_GAME_FONT: FontFile = preload("res://assets/fonts/GameFont_bold.ttf")
const DIALOG_SIZE := Vector2i(360, 280)


static func create_dialog() -> PopupPanel:
	var modal := PopupPanel.new()
	modal.borderless = true
	modal.transient = true
	modal.exclusive = true
	modal.unresizable = true
	modal.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	modal.content_scale_size = DIALOG_SIZE
	modal.size = DIALOG_SIZE * 2

	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 10)
	modal.add_child(contents)

	var title_label := Label.new()
	title_label.text = "Settings"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", BOLD_GAME_FONT)
	contents.add_child(title_label)

	_add_volume_row(contents, "Music", &"Music")
	_add_volume_row(contents, "Ambience", &"Ambience")
	_add_volume_row(contents, "Effects", &"SFX")

	var button_center := CenterContainer.new()
	button_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_child(button_center)

	var close_button := Button.new()
	close_button.text = "OK"
	close_button.custom_minimum_size = Vector2(100, 44)
	close_button.pressed.connect(modal.hide)
	button_center.add_child(close_button)

	return modal


static func _add_volume_row(contents: VBoxContainer, label_text: String, bus_name: StringName) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 32
	row.add_theme_constant_override("separation", 8)
	contents.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 100
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = AudioManager.get_bus_volume_percent(bus_name)
	slider.value_changed.connect(
		func(value: float) -> void:
			AudioManager.set_bus_volume_percent(bus_name, value)
	)
	row.add_child(slider)
