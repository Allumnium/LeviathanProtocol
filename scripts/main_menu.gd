extends Control

const MAP_SCENE_PATH := "res://scenes/game_map.tscn"
const BOLD_GAME_FONT: FontFile = preload("res://assets/fonts/GameFont_bold.ttf")

var settings_dialog: PopupPanel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color.BLACK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center_container := CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center_container)

	var menu_buttons := VBoxContainer.new()
	menu_buttons.add_theme_constant_override("separation", 12)
	center_container.add_child(menu_buttons)

	var play_button := Button.new()
	play_button.text = "Play"
	play_button.custom_minimum_size = Vector2(180, 48)
	play_button.pressed.connect(_on_play_pressed)
	menu_buttons.add_child(play_button)

	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.custom_minimum_size = Vector2(180, 48)
	settings_button.pressed.connect(_on_settings_pressed)
	menu_buttons.add_child(settings_button)

	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.custom_minimum_size = Vector2(180, 48)
	quit_button.pressed.connect(_on_quit_pressed)
	menu_buttons.add_child(quit_button)

	settings_dialog = _create_modal("Settings", "", "OK", Vector2i(360, 180))


func _on_play_pressed() -> void:
	GameState.start_new_run()
	var error := get_tree().change_scene_to_file(MAP_SCENE_PATH)
	if error != OK:
		push_error("Could not open the game map scene. Error code: %s" % error)


func _on_settings_pressed() -> void:
	settings_dialog.popup_centered()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _create_modal(
	title_text: String,
	body_text: String,
	button_text: String,
	popup_size: Vector2i
) -> PopupPanel:
	var modal := PopupPanel.new()
	modal.borderless = true
	modal.transient = true
	modal.exclusive = true
	modal.unresizable = true
	modal.size = popup_size
	add_child(modal)

	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 8)
	modal.add_child(contents)

	var title_label := Label.new()
	title_label.text = title_text
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", BOLD_GAME_FONT)
	contents.add_child(title_label)

	if body_text.is_empty():
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		contents.add_child(spacer)
	else:
		var body_label := Label.new()
		body_label.text = body_text
		body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		contents.add_child(body_label)

	var button_center := CenterContainer.new()
	button_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_child(button_center)

	var modal_button := Button.new()
	modal_button.text = button_text
	modal_button.custom_minimum_size = Vector2(100, 44)
	modal_button.pressed.connect(modal.hide)
	button_center.add_child(modal_button)

	return modal
