extends Control

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const AUTO_BATTLE_SCENE_PATH := "res://scenes/auto_battle.tscn"
const BUILD_BUTTON_TEXTURE: Texture2D = preload("res://assets/ui/buttons/circular_button.png")
const BUILD_BUTTON_HIGHLIGHT_TEXTURE: Texture2D = preload(
	"res://assets/ui/buttons/circular_button_highlighted.png"
)
const BOLD_GAME_FONT: FontFile = preload("res://assets/fonts/GameFont_bold.ttf")

var deploy_button: Button
var graph_modal: Control
var graph_view: GraphView
var settings_dialog: PopupPanel
var how_to_play_dialog: PopupPanel
var victory_dialog: PopupPanel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color.BLACK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 8)
	add_child(layout)

	_build_top_bar(layout)
	_build_upper_area(layout)
	_build_graph_modal()
	_build_dialogs()

	if GameState.current_node_id == GameState.FINAL_NODE_ID:
		victory_dialog.popup_centered()


func _build_top_bar(layout: VBoxContainer) -> void:
	var top_bar := PanelContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 56)
	top_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(top_bar)

	var bar_contents := HBoxContainer.new()
	bar_contents.add_theme_constant_override("separation", 8)
	top_bar.add_child(bar_contents)

	var stats_space := Control.new()
	stats_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_contents.add_child(stats_space)

	var how_to_play_button := Button.new()
	how_to_play_button.text = "How to Play"
	how_to_play_button.pressed.connect(_on_how_to_play_pressed)
	bar_contents.add_child(how_to_play_button)

	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.pressed.connect(_on_settings_pressed)
	bar_contents.add_child(settings_button)


func _build_upper_area(layout: VBoxContainer) -> void:
	var upper_area := HBoxContainer.new()
	upper_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upper_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upper_area.size_flags_stretch_ratio = 2.0
	upper_area.add_theme_constant_override("separation", 8)
	layout.add_child(upper_area)

	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upper_area.add_child(left_panel)

	var left_panel_contents := VBoxContainer.new()
	left_panel_contents.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_panel_contents)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var build_page := Control.new()
	build_page.name = "Build"
	_build_build_buttons(build_page)
	tabs.add_child(build_page)
	for tab_name in ["Upgrades", "Archive"]:
		var tab_page := Control.new()
		tab_page.name = tab_name
		tabs.add_child(tab_page)
	tabs.current_tab = 0
	left_panel_contents.add_child(tabs)

	var details_panel := PanelContainer.new()
	details_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upper_area.add_child(details_panel)

	var details_contents := VBoxContainer.new()
	details_contents.add_theme_constant_override("separation", 8)
	details_panel.add_child(details_contents)

	var details_space := Control.new()
	details_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_contents.add_child(details_space)

	deploy_button = Button.new()
	deploy_button.text = "Deploy"
	deploy_button.custom_minimum_size = Vector2(0, 48)
	deploy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deploy_button.pressed.connect(_on_deploy_pressed)
	details_contents.add_child(deploy_button)


func _build_build_buttons(build_page: Control) -> void:
	var button_column := VBoxContainer.new()
	button_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button_column.add_theme_constant_override("separation", 8)
	build_page.add_child(button_column)

	for _index in range(3):
		var build_button := TextureButton.new()
		build_button.ignore_texture_size = true
		build_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		build_button.texture_normal = BUILD_BUTTON_TEXTURE
		build_button.texture_hover = BUILD_BUTTON_HIGHLIGHT_TEXTURE
		build_button.texture_pressed = BUILD_BUTTON_TEXTURE
		build_button.custom_minimum_size = Vector2(64, 64)
		build_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		build_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		button_column.add_child(build_button)


func _build_graph_modal() -> void:
	graph_modal = Control.new()
	graph_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	graph_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	graph_modal.visible = false
	add_child(graph_modal)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.72)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(_on_graph_modal_backdrop_input)
	graph_modal.add_child(backdrop)

	var center_container := CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph_modal.add_child(center_container)

	var graph_panel := PanelContainer.new()
	graph_panel.custom_minimum_size = Vector2(960, 360)
	center_container.add_child(graph_panel)

	graph_view = GraphView.new()
	graph_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_view.destination_selected.connect(_on_destination_selected)
	graph_panel.add_child(graph_view)


func _build_dialogs() -> void:
	settings_dialog = _create_modal("Settings", "", "OK", Vector2i(360, 180))
	how_to_play_dialog = _create_modal(
		"How to Play",
		"Press Deploy, then select a reachable node.",
		"OK",
		Vector2i(460, 220)
	)
	victory_dialog = _create_modal(
		"Victory",
		"",
		"Accept",
		Vector2i(360, 180),
		_on_victory_accepted
	)


func _create_modal(
	title_text: String,
	body_text: String,
	button_text: String,
	popup_size: Vector2i,
	accept_callback: Callable = Callable()
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
	modal_button.pressed.connect(_on_modal_action_pressed.bind(modal, accept_callback))
	button_center.add_child(modal_button)

	return modal


func _on_modal_action_pressed(modal: PopupPanel, accept_callback: Callable) -> void:
	modal.hide()
	if accept_callback.is_valid():
		accept_callback.call()


func _on_destination_selected(node_id: int) -> void:
	if not GameState.set_destination(node_id):
		push_error("The selected destination is not reachable from the current room.")
		return
	graph_modal.hide()

	var error := get_tree().change_scene_to_file(AUTO_BATTLE_SCENE_PATH)
	if error != OK:
		GameState.cancel_battle()
		graph_modal.show()
		push_error("Could not open the auto-battle scene. Error code: %s" % error)


func _on_deploy_pressed() -> void:
	graph_view.set_current_node(GameState.current_node_id)
	graph_modal.show()


func _on_graph_modal_backdrop_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		graph_modal.hide()


func _unhandled_key_input(event: InputEvent) -> void:
	if not graph_modal.visible:
		return

	var key_event := event as InputEventKey
	if key_event == null:
		return
	if not key_event.pressed or key_event.echo or key_event.keycode != KEY_ESCAPE:
		return

	graph_modal.hide()
	get_viewport().set_input_as_handled()


func _on_settings_pressed() -> void:
	settings_dialog.popup_centered()


func _on_how_to_play_pressed() -> void:
	how_to_play_dialog.popup_centered()


func _on_victory_accepted() -> void:
	var error := get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	if error != OK:
		push_error("Could not return to the main menu. Error code: %s" % error)
