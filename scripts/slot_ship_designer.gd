extends Control

var library := SlotDesignLibrary.new()
var design := SlotShipDesign.new()
var drafts: Dictionary[String, SlotShipDesign] = {}
var canvas: SlotShipCanvas
var chassis_picker: OptionButton
var name_input: LineEdit
var details: Label
var status: Label
var load_popup: PopupPanel
var load_list: ItemList
var save_button: Button
var load_button: Button
var _selected := ""
var _names := {}

func _ready() -> void:
	AudioManager.play_build_music()
	for item in SlotCatalog.chassis():
		var draft := SlotShipDesign.new()
		draft.initialize(item.id)
		drafts[item.id] = draft
		_names[item.id] = item.name
	_build_ui()
	GameState.research_changed.connect(_research_changed)
	if not library.load_library():
		status.text = library.last_error
	_switch_chassis(0)

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = &"CompactButton"
	button.focus_mode = FOCUS_NONE
	button.custom_minimum_size.y = 28
	parent.add_child(button)
	button.pressed.connect(action)
	return button

func _label(parent: Node, text := "") -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = get_theme_color("background_color", "SlotDesigner")
	background.mouse_filter = MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var layout := VBoxContainer.new()
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	_label(header, "SHIP DESIGNER")
	chassis_picker = OptionButton.new()
	chassis_picker.size_flags_horizontal = SIZE_EXPAND_FILL
	chassis_picker.focus_mode = FOCUS_NONE
	header.add_child(chassis_picker)
	for item in SlotCatalog.chassis():
		chassis_picker.add_item(item.name)
		chassis_picker.set_item_metadata(chassis_picker.item_count - 1, item.id)
	chassis_picker.item_selected.connect(_switch_chassis)
	_button(header, "MAIN MENU", func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	layout.add_child(body)
	canvas = SlotShipCanvas.new()
	canvas.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(canvas)
	canvas.slot_selected.connect(_select_slot)
	canvas.equipment_selected.connect(_equip)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CompactPanel"
	panel.custom_minimum_size.x = 154
	body.add_child(panel)
	var info := VBoxContainer.new()
	panel.add_child(info)
	_label(info, "EQUIPMENT")
	details = _label(info, "Select a slot.")
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.custom_minimum_size.x = 138
	details.size_flags_vertical = SIZE_EXPAND_FILL
	var footer := HBoxContainer.new()
	layout.add_child(footer)
	name_input = LineEdit.new()
	name_input.max_length = 32
	name_input.placeholder_text = "Design name"
	name_input.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(name_input)
	save_button = _button(footer, "SAVE", save_design)
	load_button = _button(footer, "LOAD", _open_library)
	status = _label(layout)
	status.clip_text = true
	status.custom_minimum_size.y = 16
	load_popup = PopupPanel.new()
	load_popup.exclusive = true
	load_popup.size = Vector2i(320, 240)
	add_child(load_popup)
	var content := VBoxContainer.new()
	load_popup.add_child(content)
	content.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	content.offset_left = 12
	content.offset_top = 12
	content.offset_right = -12
	content.offset_bottom = -12
	_label(content, "LOAD DESIGN")
	load_list = ItemList.new()
	load_list.size_flags_vertical = SIZE_EXPAND_FILL
	load_list.focus_mode = FOCUS_NONE
	content.add_child(load_list)
	_button(content, "LOAD", func() -> void:
		if not load_list.get_selected_items().is_empty():
			load_design(load_list.get_item_text(load_list.get_selected_items()[0])))
	var close := preload("res://scenes/close_x_button.tscn").instantiate()
	load_popup.add_child(close)
	close.pressed.connect(load_popup.hide)

func _switch_chassis(index: int) -> void:
	if not design.chassis_id.is_empty():
		_names[design.chassis_id] = name_input.text
	design = drafts[chassis_picker.get_item_metadata(index)]
	chassis_picker.select(index)
	name_input.text = _names[design.chassis_id]
	_selected = ""
	canvas.selected_slot = ""
	_research_changed()

func _research_changed() -> void:
	if design.chassis_id.is_empty():
		return
	canvas.set_design(design, GameState.research_grants())
	_select_slot(_selected)
	status.text = design.authorization_error(GameState.research_grants())

func _select_slot(id: String) -> void:
	_selected = id
	var slot := design.slot(id)
	if slot.is_empty():
		details.text = "Select a slot."
		return
	var lines: Array[String] = [slot.type.capitalize() + " / " + slot.size]
	var fitted: Dictionary = design.equipment.get(id, {})
	if not fitted.is_empty():
		var item := SlotCatalog.find_equipment(fitted.id, fitted.rank)
		lines.append(item.name)
		if not SlotCatalog.unlocked(item, GameState.research_grants()):
			lines.append("Research required.")
		for pattern in ShipPartPattern.get_catalog():
			if pattern.definition_id == item.id and pattern.rank == item.rank:
				if pattern.stats.shields > 0:
					lines.append("Shield %s" % pattern.stats.shields)
				if pattern.stats.thrust > 0:
					lines.append("Thrust %s" % pattern.stats.thrust)
				if pattern.stats.weapons.size() > 0:
					var dps := 0.0
					for weapon in pattern.stats.weapons:
						dps += weapon.get_dps()
					lines.append("DPS %s" % dps)
				break
	else:
		lines.append("Empty")
	details.text = "\n\n".join(lines)

func _equip(slot_id: String, equipment_id: String, rank: int) -> void:
	if not design.equip(slot_id, equipment_id, rank, GameState.research_grants()):
		status.text = "Requires matching type, size and research."
		canvas.set_design(design, GameState.research_grants())
		return
	_selected = slot_id
	canvas.selected_slot = slot_id
	_research_changed()

func save_design() -> void:
	status.text = "Saved." if library.save_design(name_input.text, design) else library.last_error

func _open_library() -> void:
	load_list.clear()
	if not library.load_library():
		status.text = library.last_error
		return
	var names: Array = library.designs.keys()
	names.sort()
	for name: String in names:
		load_list.add_item(name)
	if not names.is_empty():
		load_list.select(0)
	load_popup.popup_centered()

func load_design(name: String) -> bool:
	var next := library.get_design(name)
	if next == null:
		return false
	drafts[next.chassis_id] = next
	for index in range(chassis_picker.item_count):
		if chassis_picker.get_item_metadata(index) == next.chassis_id:
			_switch_chassis(index)
	_names[next.chassis_id] = name
	name_input.text = name
	load_popup.hide()
	return true
