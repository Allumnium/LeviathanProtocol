class_name ShipLibraryDialog
extends PopupPanel

signal design_selected(design_name: String, design: Ship)

const PREVIEW = preload("res://scripts/ship_design_preview.gd")
const MATERIAL_ICONS: Array[Texture2D] = [
	preload("res://assets/ui/icons/red_square.png"),
	preload("res://assets/ui/icons/blue_square.png"),
	preload("res://assets/ui/icons/green_square.png"),
	preload("res://assets/core.png"),
]
const CREDIT_ICON: Texture2D = preload("res://assets/credits.png")
const ROW_STYLE: StyleBox = preload("res://assets/ui/panels/compact_panel_nine_patch.tres")
const PAGE_SIZE := 3

@onready var title_label: Label = $Contents/Title
@onready var search: LineEdit = $Contents/SearchRow/Search
@onready var close_button: Control = $CloseX
@onready var previous_runs: CheckBox = $Contents/Pager/PreviousRuns
@onready var rows: VBoxContainer = $Contents/ScrollContainer/SavedDesignRows
@onready var empty_label: Label = $Contents/ScrollContainer/SavedDesignRows/EmptyDesignsLabel
@onready var back_button: Button = $Contents/Pager/PreviousPageButton
@onready var page_label: Label = $Contents/Pager/PageLabel
@onready var forward_button: Button = $Contents/Pager/ForwardButton
@onready var status_label: Label = $Contents/StatusLabel

var action_text := "SELECT"
var page := 0
var choices: Array[Dictionary] = []
var selection_validator: Callable
var _allow_close := false


func _ready() -> void:
	close_button.connect("pressed", close_library)
	popup_hide.connect(_on_popup_hide)
	search.text_changed.connect(func(_text: String) -> void:
		page = 0
		_refresh_rows())
	previous_runs.toggled.connect(GameState.set_include_previous_designs)
	GameState.tile_inventory_changed.connect(refresh_library)
	back_button.pressed.connect(func() -> void:
		page -= 1
		_refresh_rows())
	forward_button.pressed.connect(func() -> void:
		page += 1
		_refresh_rows())
	GameState.design_library_changed.connect(refresh_library)
	_style_checkbox(previous_runs)
	for button in [back_button, forward_button]:
		_style_pager_button(button)
	refresh_library()


func open_library(new_action_text: String, validator: Callable = Callable()) -> void:
	_allow_close = false
	action_text = new_action_text.to_upper()
	selection_validator = validator
	title_label.text = "%s SHIP DESIGN" % action_text
	title_label.visible = action_text != "SELECT"
	search.text = ""
	status_label.text = ""
	status_label.visible = false
	page = 0
	refresh_library()
	popup_centered(Vector2i(480, 255))
	search.grab_focus()


func close_library() -> void:
	_allow_close = true
	hide()


func _on_popup_hide() -> void:
	if _allow_close:
		_allow_close = false
		return
	call_deferred("_restore_after_unintended_close")


func _restore_after_unintended_close() -> void:
	if is_inside_tree() and not visible:
		popup_centered(Vector2i(480, 255))


func refresh_library() -> void:
	if not is_node_ready():
		return
	choices.clear()
	previous_runs.set_pressed_no_signal(GameState.include_previous_run_designs)
	for entry in GameState.get_visible_ship_designs():
		var blueprint := Ship.new()
		if blueprint.load_design_data(entry.ship):
			choices.append({"name": entry.name, "design": blueprint})
	_refresh_rows()


func _refresh_rows() -> void:
	for child in rows.get_children():
		if child != empty_label:
			child.queue_free()
	var filtered: Array[Dictionary] = []
	var query := search.text.strip_edges().to_lower()
	for choice in choices:
		if query.is_empty() or str(choice.name).to_lower().contains(query):
			filtered.append(choice)
	var page_count := maxi(1, ceili(filtered.size() / float(PAGE_SIZE)))
	page = clampi(page, 0, page_count - 1)
	page_label.text = "%d / %d" % [page + 1, page_count]
	back_button.visible = page_count > 1
	page_label.visible = page_count > 1
	forward_button.visible = page_count > 1
	back_button.disabled = page == 0
	forward_button.disabled = page == page_count - 1
	empty_label.visible = filtered.is_empty()
	for choice in filtered.slice(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE):
		rows.add_child(_create_row(choice))


func _create_row(choice: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 44)
	var row_style := ROW_STYLE.duplicate()
	row_style.set_content_margin_all(4)
	row.add_theme_stylebox_override("panel", row_style)
	var contents := HBoxContainer.new()
	contents.add_theme_constant_override("separation", 6)
	row.add_child(contents)
	var preview := PREVIEW.new()
	preview.custom_minimum_size = Vector2(50, 36)
	preview.set_ship(choice.design)
	contents.add_child(preview)
	var name_label := Label.new()
	name_label.text = str(choice.name).to_upper()
	name_label.custom_minimum_size.x = 90
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 9)
	contents.add_child(name_label)
	var costs := HBoxContainer.new()
	costs.add_theme_constant_override("separation", 3)
	costs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_child(costs)
	var counts := GameState.get_construction_material_costs(choice.design)
	for category in range(MATERIAL_ICONS.size()):
		if counts[category] > 0:
			_add_cost_item(costs, MATERIAL_ICONS[category], counts[category])
	var credit_cost := GameState.get_construction_credit_cost(choice.design)
	if credit_cost > 0:
		_add_cost_item(costs, CREDIT_ICON, credit_cost)
	var action := Button.new()
	action.text = action_text
	action.custom_minimum_size.x = 68
	_style_button(action)
	var validation_message := ""
	if selection_validator.is_valid():
		validation_message = str(selection_validator.call(choice.design))
	action.disabled = not validation_message.is_empty()
	action.pressed.connect(func() -> void:
		_allow_close = true
		design_selected.emit(choice.name, choice.design)
		hide())
	contents.add_child(action)
	var remove := Button.new()
	remove.icon = _trash_icon()
	remove.disabled = choice.name == "Drone"
	remove.modulate.a = 0.0 if remove.disabled else 1.0
	remove.mouse_filter = Control.MOUSE_FILTER_IGNORE if remove.disabled else Control.MOUSE_FILTER_STOP
	_style_button(remove)
	remove.pressed.connect(func() -> void:
		if not GameState.delete_saved_ship_design(choice.name):
			status_label.text = "Could not delete the saved design."
			status_label.visible = true)
	contents.add_child(remove)
	return row


func _add_cost_item(row: HBoxContainer, icon: Texture2D, amount: int) -> void:
	var texture := TextureRect.new()
	texture.custom_minimum_size = Vector2(10, 10)
	texture.texture = icon
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(texture)
	var label := Label.new()
	label.text = str(amount)
	label.add_theme_font_size_override("font_size", 8)
	row.add_child(label)


static func _style_button(button: Button) -> void:
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 30)
	button.add_theme_font_override("font", preload("res://assets/fonts/starhull-fonts/Starhull/Starhull.fnt"))


static func _style_pager_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(30, 26)
	button.add_theme_font_override("font", preload("res://assets/fonts/starhull-fonts/Starhull/Starhull.fnt"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxTexture.new()
		style.texture = preload("res://assets/ui/panels/simple_panel.png")
		style.texture_margin_left = 12
		style.texture_margin_right = 12
		style.texture_margin_top = 12
		style.texture_margin_bottom = 12
		style.set_content_margin_all(3)
		match state:
			"hover": style.modulate_color = Color(0.85, 0.95, 1.0)
			"pressed": style.modulate_color = Color(0.65, 0.78, 0.86)
			"disabled": style.modulate_color = Color(0.5, 0.55, 0.6)
			"focus": style.draw_center = false
		button.add_theme_stylebox_override(state, style)


static func _style_checkbox(checkbox: CheckBox) -> void:
	for checked in [false, true]:
		var image := Image.new()
		var mark := '<path d="M3 7 L6 10 L11 3" fill="none" stroke="#cfdee4" stroke-width="2"/>' if checked else ""
		image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14"><rect x="1" y="1" width="12" height="12" rx="1" fill="#172128" stroke="#8ea5b2"/>%s</svg>' % mark)
		var texture := ImageTexture.create_from_image(image)
		var prefix := "checked" if checked else "unchecked"
		for suffix in ["", "_disabled", "_pressed", "_hover"]:
			checkbox.add_theme_icon_override(prefix + suffix, texture)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var style := StyleBoxEmpty.new()
		style.set_content_margin_all(2)
		checkbox.add_theme_stylebox_override(state, style)


static func _trash_icon() -> Texture2D:
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="16"><path d="M2 4h10M5 4V2h4v2M3 5l1 9h6l1-9M6 6v6M8 6v6" fill="none" stroke="#ed7272" stroke-width="1.5" stroke-linejoin="round"/></svg>')
	return ImageTexture.create_from_image(image)
