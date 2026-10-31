extends Control

const CLOSE_BUTTON = preload("res://scenes/close_x_button.tscn")
var library := HexDesignLibrary.new()
var designs: Dictionary[String, HexShipDesign] = {}
var build_area: HexBuildArea
var chassis_picker: OptionButton
var build_tab_button: Button
var archive_tab_button: Button
var panel_tabs: TabContainer
var build_controls: VBoxContainer
var archive_details: VBoxContainer
var archive_progress: VBoxContainer
var stats_contents: VBoxContainer
var back_button: Button
var undo_button: Button
var redo_button: Button
var save_button: Button
var load_button: Button
var name_input: LineEdit
var status: Label
var command_label: Label
var selected_label: Label
var bonus_label: Label
var integrity_label: Label
var material_buttons: Array[Button] = []
var material_labels: Array[Label] = []
var archive_material_labels: Array[Label] = []
var archive_list: ItemList
var recipe_preview: HexRecipePreview
var archive_title: Label
var archive_stats: Label
var assembly_picker: OptionButton
var assemble_button: Button
var load_popup: PopupPanel
var load_list: ItemList
var matcher: HexRecipeMatcher
var patterns: Array[ShipPartPattern] = []
var _by_key := {}
var _draft_names := {}
var _undo := {}
var _redo := {}
var _before := {}
var _pending: Array[Dictionary] = []
var _selected_cell := Vector2i(2147483647, 2147483647)
var _refresh_queued := false

func _ready() -> void:
	AudioManager.play_build_music()
	patterns = ShipPartPattern.get_catalog()
	patterns.sort_custom(func(a: ShipPartPattern, b: ShipPartPattern) -> bool:
		return a.display_name < b.display_name if a.display_name != b.display_name else a.rank < b.rank)
	for pattern in patterns:
		_by_key[HexRecipe.key(pattern.definition_id, pattern.rank)] = pattern
	# The command center is fixed chassis equipment, not a buildable recipe.
	patterns.assign(patterns.filter(func(pattern: ShipPartPattern) -> bool: return pattern.definition_id != "command_center"))
	matcher = HexRecipeMatcher.new(patterns)
	_build_ui()
	theme_changed.connect(_size_context_labels)
	_size_context_labels()
	if not library.load_library():
		status.text = library.last_error
		status.show()
	_switch_chassis(3)
	archive_list.select(0)
	_show_recipe(0)
	_select_tab(0)

func _label(parent: Node, text := "") -> Label:
	var result := Label.new()
	result.text = text
	result.clip_text = true
	result.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(result)
	return result

func _button(parent: Node, text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.theme_type_variation = &"CompactButton"
	result.custom_minimum_size.y = 28
	result.size_flags_horizontal = SIZE_EXPAND_FILL
	result.focus_mode = FOCUS_NONE
	parent.add_child(result)
	result.pressed.connect(action)
	return result

func _panel(parent: Node, minimum: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CompactPanel"
	panel.custom_minimum_size.x = minimum
	parent.add_child(panel)
	var contents := VBoxContainer.new()
	contents.size_flags_vertical = SIZE_EXPAND_FILL
	panel.add_child(contents)
	return contents

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("090e12")
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	var layout := VBoxContainer.new()
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	build_tab_button = _button(header, "SHIP BUILDER", _select_tab.bind(0))
	archive_tab_button = _button(header, "ARCHIVE", _select_tab.bind(1))
	var group := ButtonGroup.new()
	for button in [build_tab_button, archive_tab_button]:
		button.toggle_mode = true
		button.button_group = group
	back_button = _button(header, "MAIN MENU", _back)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = SIZE_EXPAND_FILL
	layout.add_child(columns)
	var left := _panel(columns, 140)
	build_controls = VBoxContainer.new()
	left.add_child(build_controls)
	_label(build_controls, "CHASSIS")
	chassis_picker = OptionButton.new()
	chassis_picker.fit_to_longest_item = false
	chassis_picker.custom_minimum_size.y = 28
	chassis_picker.focus_mode = FOCUS_NONE
	build_controls.add_child(chassis_picker)
	for entry in ChassisCatalog.entries():
		var design := HexShipDesign.new()
		design.initialize(entry.id)
		designs[entry.id] = design
		_undo[entry.id] = []
		_redo[entry.id] = []
		_draft_names[entry.id] = entry.display_name
		chassis_picker.add_item(entry.display_name)
		chassis_picker.set_item_metadata(chassis_picker.item_count - 1, entry.id)
	chassis_picker.item_selected.connect(_switch_chassis)
	command_label = _label(build_controls)
	var materials := GridContainer.new()
	materials.columns = 2
	build_controls.add_child(materials)
	var material_group := ButtonGroup.new()
	for category in range(4):
		var button := _button(materials, ["O", "D", "T", "C"][category], _select_material.bind(category))
		button.icon = preload("res://themes/hex_material_palette.tres").material_texture(category)
		button.expand_icon = true
		button.toggle_mode = true
		button.button_group = material_group
		material_buttons.append(button)
	_select_material(0)
	var history := HBoxContainer.new()
	build_controls.add_child(history)
	undo_button = _button(history, "UNDO", undo)
	redo_button = _button(history, "REDO", redo)
	_button(build_controls, "FIT VIEW", func() -> void: build_area.fit_view())
	name_input = LineEdit.new()
	name_input.max_length = 32
	name_input.placeholder_text = "Design name"
	build_controls.add_child(name_input)
	name_input.text_submitted.connect(func(_name: String) -> void: save_design())
	var files := HBoxContainer.new()
	build_controls.add_child(files)
	save_button = _button(files, "SAVE", save_design)
	load_button = _button(files, "LOAD", _open_library)
	archive_details = VBoxContainer.new()
	archive_details.size_flags_vertical = SIZE_EXPAND_FILL
	left.add_child(archive_details)
	_label(archive_details, "EQUIPMENT")
	archive_list = ItemList.new()
	archive_list.custom_minimum_size.x = 108
	archive_list.size_flags_vertical = SIZE_EXPAND_FILL
	archive_list.focus_mode = FOCUS_NONE
	archive_details.add_child(archive_list)
	for pattern in patterns:
		archive_list.add_item(_pattern_name(pattern))
	archive_list.item_selected.connect(_show_recipe)
	var center := _panel(columns, 0)
	center.get_parent().size_flags_horizontal = SIZE_EXPAND_FILL
	panel_tabs = TabContainer.new()
	panel_tabs.tabs_visible = false
	panel_tabs.size_flags_vertical = SIZE_EXPAND_FILL
	center.add_child(panel_tabs)
	build_area = HexBuildArea.new()
	build_area.name = "Build"
	panel_tabs.add_child(build_area)
	build_area.stroke_started.connect(_begin_stroke)
	build_area.stroke_finished.connect(_finish_stroke)
	build_area.material_changed.connect(_material_changed)
	build_area.design_changed.connect(_queue_refresh)
	build_area.cell_selected.connect(_select_cell)
	var archive := VBoxContainer.new()
	archive.name = "Archive"
	panel_tabs.add_child(archive)
	archive_title = _label(archive)
	archive_title.hide()
	archive_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	recipe_preview = HexRecipePreview.new()
	recipe_preview.size_flags_vertical = SIZE_EXPAND_FILL
	archive.add_child(recipe_preview)
	var right := _panel(columns, 148)
	stats_contents = VBoxContainer.new()
	right.add_child(stats_contents)
	integrity_label = _label(stats_contents)
	_label(stats_contents, "MATERIALS")
	material_labels = _material_counts(stats_contents)
	_label(stats_contents, "SELECTED")
	selected_label = _label(stats_contents)
	selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selected_label.custom_minimum_size.x = 110
	bonus_label = _label(stats_contents)
	bonus_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	assembly_picker = OptionButton.new()
	assembly_picker.fit_to_longest_item = false
	assembly_picker.focus_mode = FOCUS_NONE
	stats_contents.add_child(assembly_picker)
	assemble_button = _button(stats_contents, "ASSEMBLE", _assemble_selected)
	archive_progress = VBoxContainer.new()
	right.add_child(archive_progress)
	_label(archive_progress, "MATERIALS")
	archive_material_labels = _material_counts(archive_progress)
	archive_stats = _label(archive_progress)
	status = _label(layout)
	status.custom_minimum_size.y = 16
	_build_library_popup()

func _material_counts(parent: Node) -> Array[Label]:
	var grid := GridContainer.new()
	grid.columns = 2
	parent.add_child(grid)
	var result: Array[Label] = []
	for category in range(4):
		var row := HBoxContainer.new()
		row.size_flags_horizontal = SIZE_EXPAND_FILL
		grid.add_child(row)
		var icon := TextureRect.new()
		icon.texture = preload("res://themes/hex_material_palette.tres").material_texture(category)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(20, 22)
		row.add_child(icon)
		result.append(_label(row, "0"))
	return result

func _size_context_labels() -> void:
	# Autowrapped clipped Labels otherwise report a one-pixel minimum height.
	# Measure from the inherited theme so swapping its font still works.
	for label: Label in [selected_label, bonus_label]:
		var line_height := label.get_theme_font("font").get_height(label.get_theme_font_size("font_size"))
		var spacing := maxi(label.get_theme_constant("line_spacing"), 0)
		label.custom_minimum_size = Vector2(110, ceilf((line_height + spacing) * 2) + 2)

func _build_library_popup() -> void:
	load_popup = PopupPanel.new()
	load_popup.name = "LoadDesignDialog"
	load_popup.theme = theme
	load_popup.exclusive = true
	load_popup.size = Vector2i(320, 240)
	add_child(load_popup)
	var contents := VBoxContainer.new()
	load_popup.add_child(contents)
	contents.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	contents.offset_left = 12
	contents.offset_top = 12
	contents.offset_right = -12
	contents.offset_bottom = -12
	_label(contents, "LOAD DESIGN")
	load_list = ItemList.new()
	load_list.size_flags_vertical = SIZE_EXPAND_FILL
	load_list.focus_mode = FOCUS_NONE
	contents.add_child(load_list)
	_button(contents, "LOAD", _load_selected)
	var close := CLOSE_BUTTON.instantiate()
	load_popup.add_child(close)
	close.pressed.connect(load_popup.hide)

func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _pattern_name(pattern: ShipPartPattern) -> String:
	return pattern.display_name + (" %d" % pattern.rank if pattern.definition_id == "research_lab" else "")

func _select_material(category: int) -> void:
	get_viewport().gui_release_focus()
	if build_area:
		build_area.selected_material = category
	material_buttons[category].button_pressed = true

func _select_tab(index: int) -> void:
	build_area._stop_painting()
	panel_tabs.current_tab = index
	build_controls.visible = index == 0
	stats_contents.visible = index == 0
	archive_details.visible = index == 1
	archive_progress.visible = index == 1
	build_tab_button.button_pressed = index == 0
	archive_tab_button.button_pressed = index == 1

func _switch_chassis(index: int) -> void:
	build_area._stop_painting()
	if build_area.design:
		_draft_names[build_area.design.chassis_id] = name_input.text
	var id := str(chassis_picker.get_item_metadata(index))
	build_area.set_design(designs[id])
	chassis_picker.select(index)
	name_input.text = _draft_names[id]
	_selected_cell = Vector2i(2147483647, 2147483647)
	_pending.clear()
	_refresh()

func _begin_stroke() -> void:
	_before = build_area.design.to_data()

func _finish_stroke() -> void:
	if _before.is_empty() or build_area.design == null:
		return
	if _before != build_area.design.to_data():
		_record_undo(_before)
	_before = {}
	_queue_refresh()

func _record_undo(before: Dictionary) -> void:
	var id := build_area.design.chassis_id
	_undo[id].append(before)
	if _undo[id].size() > 128:
		_undo[id].pop_front()
	_redo[id].clear()

func undo() -> void:
	build_area._stop_painting()
	_restore_history(_undo, _redo)

func redo() -> void:
	build_area._stop_painting()
	_restore_history(_redo, _undo)

func _restore_history(from: Dictionary, to: Dictionary) -> void:
	var id := build_area.design.chassis_id
	if from[id].is_empty():
		return
	var previous: Dictionary = from[id].back()
	var current := build_area.design.to_data()
	if build_area.design.load_data(previous):
		from[id].pop_back()
		to[id].append(current)
		_pending.clear()
		build_area.refresh()
		_refresh()

func _material_changed(cell: Vector2i) -> void:
	_pending = matcher.assemble_unique(build_area.design, cell)
	_selected_cell = cell

func _select_cell(cell: Vector2i) -> void:
	_selected_cell = cell
	_pending = matcher.choices(build_area.design, cell)
	_queue_refresh()

func _queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		_refresh.call_deferred()

func _refresh() -> void:
	_refresh_queued = false
	var design := build_area.design
	if design == null:
		return
	var chassis := design.chassis()
	command_label.text = "%d CP / Flagship" % chassis.command_points if chassis.flagship else "%d CP cost" % chassis.command_cost
	integrity_label.text = "Integrity %d" % chassis.integrity
	var counts := [0, 0, 0, 0]
	for category: int in design.tiles.values():
		counts[category] += 1
	for index in range(4):
		material_labels[index].text = str(counts[index])
	undo_button.disabled = _undo[design.chassis_id].is_empty()
	redo_button.disabled = _redo[design.chassis_id].is_empty()
	selected_label.text = ""
	bonus_label.text = ""
	for builtin in chassis.builtins:
		if _selected_cell in builtin.cells:
			selected_label.text = _equipment_name(builtin.equipment_id, builtin.rank)
	for component in design.components:
		if HexShipDesign.component_cells(component).has(_selected_cell):
			selected_label.text = _equipment_name(component.equipment_id, component.rank)
	if not chassis.region_at(_selected_cell).is_empty():
		var bonuses := chassis.modifiers_at(_selected_cell)
		bonus_label.text = "Armor +%d%%\nRange +%d%%" % [roundi(bonuses.get("armor_integrity", 0) * 100), roundi(bonuses.get("weapon_range", 0) * 100)]
	assembly_picker.clear()
	for candidate in _pending:
		assembly_picker.add_item(_equipment_name(candidate.equipment_id, candidate.rank))
	assembly_picker.visible = not _pending.is_empty()
	assemble_button.visible = not _pending.is_empty()
	load_button.disabled = library.designs.is_empty()

func _equipment_name(id: String, rank: int) -> String:
	var pattern: ShipPartPattern = _by_key.get(HexRecipe.key(id, rank))
	return _pattern_name(pattern) if pattern else id.capitalize()

func _assemble_selected() -> void:
	if _pending.is_empty() or assembly_picker.selected < 0:
		return
	var before := build_area.design.to_data()
	var selected := _pending[assembly_picker.selected]
	if build_area.design.assemble(selected.equipment_id, selected.rank, selected.origin, selected.turns, selected.flipped):
		_record_undo(before)
		_pending.clear()
		build_area.refresh()
		_refresh()

func save_design() -> void:
	build_area._stop_painting()
	var ok := library.save_design(name_input.text, build_area.design)
	status.text = "Saved" if ok else library.last_error
	status.show()
	_refresh()

func _open_library() -> void:
	build_area._stop_painting()
	load_list.clear()
	var names := library.designs.keys()
	names.sort()
	for name: String in names:
		load_list.add_item(name)
	if not names.is_empty():
		load_list.select(0)
	load_popup.popup_centered()

func _load_selected() -> void:
	var selected := load_list.get_selected_items()
	if not selected.is_empty():
		load_design(load_list.get_item_text(selected[0]))

func load_design(name: String) -> bool:
	var design := library.get_design(name)
	if design == null:
		return false
	build_area._stop_painting()
	var id := design.chassis_id
	_undo[id].append(designs[id].to_data())
	_redo[id].clear()
	designs[id] = design
	for index in range(chassis_picker.item_count):
		if chassis_picker.get_item_metadata(index) == id:
			_switch_chassis(index)
	_draft_names[id] = name
	name_input.text = name
	load_popup.hide()
	status.text = ""
	return true

func _show_recipe(_index: int) -> void:
	_update_recipe()

func _update_recipe() -> void:
	var selected := archive_list.get_selected_items()
	if selected.is_empty():
		return
	var pattern := patterns[selected[0]]
	var recipe := HexRecipe.find(pattern.definition_id, pattern.rank)
	archive_title.text = _pattern_name(pattern)
	recipe_preview.set_recipe(recipe, 0, false, _pattern_name(pattern))
	var counts := [0, 0, 0, 0]
	for cell: Array in recipe.cells:
		counts[int(cell[2])] += 1
	for index in range(4):
		archive_material_labels[index].text = str(counts[index])
	var lines: Array[String] = []
	lines.append("Integrity %.1f" % (recipe.cells.size() + pattern.stats.integrity / 3.0))
	if pattern.stats.shields > 0:
		lines.append("Shields %d" % pattern.stats.shields)
	if pattern.stats.thrust > 0:
		lines.append("Thrust %d" % pattern.stats.thrust)
	var dps := 0.0
	for weapon in pattern.stats.weapons:
		dps += weapon.get_dps()
	if dps > 0:
		lines.append("DPS %.1f" % dps)
	archive_stats.text = "\n".join(lines)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or panel_tabs.current_tab != 0 or load_popup.visible:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if event.ctrl_pressed and event.keycode == KEY_Z:
		redo() if event.shift_pressed else undo()
	elif event.ctrl_pressed and event.keycode == KEY_Y:
		redo()
	elif not event.ctrl_pressed and event.keycode >= KEY_1 and event.keycode <= KEY_4:
		_select_material(event.keycode - KEY_1)
	else:
		return
	get_viewport().set_input_as_handled()
