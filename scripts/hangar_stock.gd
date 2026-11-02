extends VBoxContainer

const Transfer = preload("res://scripts/hangar_equipment_transfer.gd")
const DragButton = preload("res://scripts/hangar_drag_button.gd")
const ActionButton = preload("res://scripts/equipment_action_button.gd")
const EquipmentFilters = preload("res://scripts/hangar_equipment_filters.gd")
signal changed_preferences(value: Dictionary)
signal equipment_stored(ok: bool)
signal equipment_sold(ok: bool)
signal equipment_selected(uid: String)
var pending_sale := ""
var sale_controls: Dictionary = {}
var preferences: Dictionary = {}
var filters: EquipmentFilters
var rows: VBoxContainer
var scroll: ScrollContainer
var visible_uids: Array[String] = []
var row_buttons: Dictionary = {}
var unequip_hint: Label
var unequip_mode := false
var drop_panel: Control
var _hidden_content: Array[CanvasItem] = []

func _ready() -> void:
	var title := Label.new()
	title.text = "STOCK"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	var heading := HBoxContainer.new()
	add_child(heading)
	heading.add_child(title)
	filters = EquipmentFilters.new()
	filters.set_preferences(preferences)
	add_child(filters)
	scroll = ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(rows)
	filters.changed.connect(func(_value: Dictionary) -> void: _change())
	_render()
	unequip_hint = Label.new()
	unequip_hint.name = "UnequipTarget"
	unequip_hint.text = "Drop here to unequip"
	unequip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unequip_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	unequip_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unequip_hint.size_flags_vertical = SIZE_EXPAND_FILL
	unequip_hint.mouse_filter = MOUSE_FILTER_IGNORE
	unequip_hint.hide()
	add_child(unequip_hint)
	# Include the frame and padding, as well as the stock content, in the target.
	drop_panel = get_parent_control().get_parent_control()
	drop_panel.set_drag_forwarding(Callable(), _can_drop_data, _drop_data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN and is_instance_valid(unequip_hint):
		var data: Variant = get_viewport().gui_get_drag_data()
		if Transfer.valid(data) and not GameState.equipment_location(data.uid).is_empty():
			_set_unequip_mode(true)
	elif what == NOTIFICATION_DRAG_END and is_instance_valid(unequip_hint):
		_set_unequip_mode(false)

func _exit_tree() -> void:
	if is_instance_valid(drop_panel):
		drop_panel.set_drag_forwarding(Callable(), Callable(), Callable())

func _set_unequip_mode(active: bool) -> void:
	unequip_mode = active
	if active:
		_hidden_content.clear()
		for child: CanvasItem in get_children():
			if child != unequip_hint and child.visible:
				_hidden_content.append(child)
				child.hide()
	else:
		for child: CanvasItem in _hidden_content:
			if is_instance_valid(child):
				child.show()
		_hidden_content.clear()
	unequip_hint.visible = active

func _change() -> void:
	preferences = filters.get_preferences()
	changed_preferences.emit(preferences.duplicate(true))
	_render()

func _render() -> void:
	pending_sale = ""
	sale_controls.clear()
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	visible_uids.clear()
	row_buttons.clear()
	var grants := GameState.research_grants()
	var candidates: Array[Dictionary] = []
	for instance: Dictionary in GameState.equipment_inventory.values():
		if not GameState.equipment_location(instance.uid).is_empty():
			continue
		var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
		if not filters.matches(item):
			continue
		candidates.append({"instance": instance, "item": item})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.item.price) == int(b.item.price):
			return int(a.instance.uid) < int(b.instance.uid)
		return int(a.item.price) < int(b.item.price))
	for entry: Dictionary in candidates:
		var instance: Dictionary = entry.instance
		var item: Dictionary = entry.item
		visible_uids.append(instance.uid)
		var row: Button = DragButton.new()
		row.equipment_uid = instance.uid
		row.equipment_texture = SlotCatalog.equipment_texture(item)
		row.theme_type_variation = &"CompactButton"
		row.focus_mode = FOCUS_NONE
		row.custom_minimum_size.y = 42
		row.clip_contents = true
		row.disabled = item.id in HangarResearch.DEFERRED_PURCHASES or not SlotCatalog.unlocked(item, grants)
		row.set_meta("inspect_equipment", instance.uid)
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not get_viewport().gui_is_dragging():
				equipment_selected.emit(instance.uid))
		rows.add_child(row)
		row_buttons[instance.uid] = row
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 0)
		content.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(content)
		content.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		content.offset_left = 6
		content.offset_right = -6
		content.offset_top = 4
		if row.equipment_texture != null:
			var thumbnail := TextureRect.new()
			thumbnail.name = "EquipmentThumbnail"
			thumbnail.texture = row.equipment_texture
			SurfaceArt.apply(thumbnail)
			thumbnail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			thumbnail.position = Vector2(4, 4)
			thumbnail.size = Vector2(28, 34)
			thumbnail.mouse_filter = MOUSE_FILTER_IGNORE
			row.add_child(thumbnail)
			content.offset_left = 38
		var name_label := ResourceText.create(item.name)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.custom_minimum_size.y = name_label.get_theme_font_size("normal_font_size") + 2
		name_label.clip_contents = true
		name_label.mouse_filter = MOUSE_FILTER_IGNORE
		content.add_child(name_label)
		var second_line := HBoxContainer.new()
		second_line.name = "Actions"
		second_line.add_theme_constant_override("separation", 2)
		second_line.mouse_filter = MOUSE_FILTER_PASS
		content.add_child(second_line)
		var summary := Label.new()
		summary.text = "%s %s" % [item.size, item.type.capitalize()]
		summary.size_flags_horizontal = SIZE_EXPAND_FILL
		summary.clip_text = true
		summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		summary.mouse_filter = MOUSE_FILTER_IGNORE
		second_line.add_child(summary)
		var cancel: Button = ActionButton.new()
		cancel.name = "CancelSale"
		cancel.action = "cancel"
		second_line.add_child(cancel)
		cancel.hide()
		cancel.pressed.connect(func() -> void: _set_pending_sale(""))
		AudioManager.connect_ui_button(cancel)
		var sell: Button = ActionButton.new()
		sell.name = "SellAction"
		sell.disabled = not GameState.can_use_shipyard()
		second_line.add_child(sell)
		sell.pressed.connect(func() -> void:
			if pending_sale != instance.uid:
				AudioManager.play_ui_sfx(&"question")
				_set_pending_sale(instance.uid)
			else:
				sell.disabled = true
				var ok: bool = GameState.sell_equipment(instance.uid)
				if not ok:
					sell.disabled = false
				else:
					AudioManager.play_ui_sfx(&"accept")
				equipment_sold.emit(ok))
		sale_controls[instance.uid] = {"summary": summary, "text": summary.text, "cancel": cancel, "sell": sell}
	if candidates.is_empty():
		var empty := Label.new()
		empty.text = "No stock" if filters.is_unfiltered() else "No matches"
		rows.add_child(empty)

func _set_pending_sale(uid: String) -> void:
	pending_sale = uid
	for id: String in sale_controls:
		var controls: Dictionary = sale_controls[id]
		controls.summary.text = "Sell?" if id == uid else controls.text
		controls.cancel.visible = id == uid
		controls.sell.action = "confirm" if id == uid else "sell"

func refresh_service_access() -> void:
	_set_pending_sale("")
	for controls: Dictionary in sale_controls.values():
		controls.sell.disabled = not GameState.can_use_shipyard()

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return Transfer.can_store(data)

func _drop_data(_position: Vector2, data: Variant) -> void:
	if Transfer.can_store(data):
		equipment_stored.emit(Transfer.store(data))
