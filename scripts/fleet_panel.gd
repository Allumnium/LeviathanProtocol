extends Control

signal selected_design_changed
signal selected_ship_changed
var selected_design: Ship
var selected_title := ""
var choices: Array[Dictionary] = []
var board := preload("res://scripts/formation_board.gd").new()
var picker := PopupPanel.new()
var search := LineEdit.new()
var previous_runs := CheckBox.new()
var rows := VBoxContainer.new()
var page := 0
var page_label := Label.new()
var back := Button.new()
var forward := Button.new()
var design_title := Label.new()
var design_preview := preload("res://scripts/ship_design_preview.gd").new()

func _ready() -> void:
	var contents := VBoxContainer.new()
	contents.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	contents.add_theme_constant_override("separation", 8)
	add_child(contents)
	var header := HBoxContainer.new()
	contents.add_child(header)
	design_preview.custom_minimum_size = Vector2(52, 40)
	header.add_child(design_preview)
	design_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	design_title.add_theme_font_size_override("font_size", 10)
	design_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(design_title)
	var browse := Button.new()
	browse.text = "SEARCH"
	browse.add_theme_font_size_override("font_size", 9)
	browse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	compact_button(browse)
	header.add_child(browse)
	browse.pressed.connect(func() -> void:
		search.text = ""
		page = 0
		_refresh_rows()
		picker.popup_centered(Vector2i(480, 290))
		search.grab_focus())
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(board)
	board.selection_changed.connect(func() -> void: selected_ship_changed.emit())
	_build_picker()
	GameState.design_library_changed.connect(_refresh_choices)
	_refresh_choices()

func _build_picker() -> void:
	picker.theme = preload("res://themes/ui_theme.tres")
	add_child(picker)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	picker.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	search.placeholder_text = "Search saved ships"
	search.add_theme_font_size_override("font_size", 10)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(search)
	var close := Button.new()
	close.text = "CLOSE"
	close.add_theme_font_size_override("font_size", 9)
	compact_button(close)
	close.pressed.connect(picker.hide)
	top.add_child(close)
	previous_runs.text = "Include previous runs"
	previous_runs.add_theme_font_size_override("font_size", 9)
	style_checkbox(previous_runs)
	previous_runs.toggled.connect(GameState.set_include_previous_designs)
	box.add_child(previous_runs)
	rows.custom_minimum_size = Vector2(440, 184)
	box.add_child(rows)
	var pager := HBoxContainer.new()
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(pager)
	back.icon = _arrow_icon(false)
	forward.icon = _arrow_icon(true)
	for button in [back, forward]:
		compact_button(button)
	back.pressed.connect(func() -> void: page -= 1; _refresh_rows())
	forward.pressed.connect(func() -> void: page += 1; _refresh_rows())
	pager.add_child(back)
	page_label.add_theme_font_size_override("font_size", 10)
	pager.add_child(page_label)
	pager.add_child(forward)
	search.text_changed.connect(func(_text: String) -> void: page = 0; _refresh_rows())

func _refresh_choices() -> void:
	choices.clear()
	previous_runs.set_pressed_no_signal(GameState.include_previous_run_designs)
	for entry in GameState.get_visible_ship_designs():
		var blueprint := Ship.new()
		if blueprint.load_design_data(entry.ship):
			choices.append({"name": entry.name, "design": blueprint})
	selected_design = null
	for choice in choices:
		if choice.name == selected_title:
			selected_design = choice.design
	if selected_design == null:
		selected_title = "" if choices.is_empty() else choices[0].name
		selected_design = null if choices.is_empty() else choices[0].design
	_update_selection()
	_refresh_rows()

func _update_selection() -> void:
	design_title.text = selected_title if selected_design != null else "No saved designs"
	design_preview.set_ship(selected_design)
	selected_design_changed.emit()

func _refresh_rows() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var filtered: Array[Dictionary] = []
	for choice in choices:
		if search.text.strip_edges().is_empty() or choice.name.to_lower().contains(search.text.strip_edges().to_lower()):
			filtered.append(choice)
	var pages := maxi(1, ceili(filtered.size() / 4.0))
	page = clampi(page, 0, pages - 1)
	page_label.text = "%d / %d" % [page + 1, pages]
	back.disabled = page == 0
	forward.disabled = page == pages - 1
	if filtered.is_empty():
		var empty := Label.new()
		empty.text = "No matching saved designs"
		empty.add_theme_font_size_override("font_size", 10)
		rows.add_child(empty)
	for choice in filtered.slice(page * 4, page * 4 + 4):
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 42
		rows.add_child(row)
		var preview := preload("res://scripts/ship_design_preview.gd").new()
		preview.custom_minimum_size = Vector2(48, 40)
		preview.set_ship(choice.design)
		row.add_child(preview)
		var details := Label.new()
		var stats: ShipStats = choice.design.get_stats()
		details.text = "%s\n%d cr · Hull %.0f · DPS %.1f · Thrust %.0f" % [choice.name, choice.design.cost, stats.integrity, stats.dps, stats.thrust]
		details.add_theme_font_size_override("font_size", 8)
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(details)
		var select := Button.new()
		select.text = "SELECT"
		select.add_theme_font_size_override("font_size", 9)
		select.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		compact_button(select)
		select.pressed.connect(func() -> void:
			selected_design = choice.design
			selected_title = choice.name
			_update_selection()
			picker.hide())
		row.add_child(select)
		var remove := Button.new()
		remove.icon = trash_icon()
		remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		remove.tooltip_text = "Delete saved design"
		remove.visible = choice.name != "Drone"
		compact_button(remove)
		remove.pressed.connect(func() -> void: GameState.delete_saved_ship_design(choice.name))
		row.add_child(remove)

static func compact_button(button: Button) -> void:
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 30)
	button.add_theme_font_override("font", preload("res://assets/fonts/GameFont_bold.ttf"))
	var theme := preload("res://themes/ui_theme.tres")
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style: StyleBox = theme.get_stylebox(state, "Button").duplicate()
		# Small icon buttons use the square frame; the wide action sprite has 32px end caps.
		if button.text.is_empty() and button.icon != null and style is StyleBoxTexture:
			style.texture = preload("res://assets/ui/panels/simple_panel.png")
			style.texture_margin_left = 12
			style.texture_margin_right = 12
			style.texture_margin_top = 12
			style.texture_margin_bottom = 12
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		button.add_theme_stylebox_override(state, style)

static func style_checkbox(checkbox: CheckBox) -> void:
	for checked in [false, true]:
		var image := Image.new()
		var mark := '<path d="M3 7 L6 10 L11 3" fill="none" stroke="#cfdee4" stroke-width="2"/>' if checked else ""
		image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14"><rect x="1" y="1" width="12" height="12" rx="1" fill="#172128" stroke="#8ea5b2"/>%s</svg>' % mark)
		checkbox.add_theme_icon_override("checked" if checked else "unchecked", ImageTexture.create_from_image(image))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var style := StyleBoxEmpty.new()
		style.set_content_margin_all(2)
		checkbox.add_theme_stylebox_override(state, style)

static func _arrow_icon(right: bool) -> Texture2D:
	var image := Image.new()
	var path := "M4 2 L9 7 L4 12" if right else "M9 2 L4 7 L9 12"
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14"><path d="%s" fill="none" stroke="#cfdee4" stroke-width="2"/></svg>' % path)
	return ImageTexture.create_from_image(image)

static func trash_icon() -> Texture2D:
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="16"><path d="M2 4h10M5 4V2h4v2M3 5l1 9h6l1-9M6 6v6M8 6v6" fill="none" stroke="#ed7272" stroke-width="1.5" stroke-linejoin="round"/></svg>')
	return ImageTexture.create_from_image(image)


