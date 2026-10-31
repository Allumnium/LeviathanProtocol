class_name SlotShipCanvas
extends Control

signal slot_selected(id: String)
signal equipment_selected(slot_id: String, equipment_id: String, rank: int)
var design: SlotShipDesign
var grants := {}
var selected_slot := ""
var slot_buttons: Dictionary[String, OptionButton] = {}
var image_rect := Rect2()
var _texture: Texture2D
var _slots: Array = []

func _ready() -> void:
	clip_contents = true
	focus_mode = FOCUS_NONE
	resized.connect(_layout_slots)
	theme_changed.connect(queue_redraw)

func set_design(next: SlotShipDesign, research: Dictionary) -> void:
	design = next
	grants = research
	var chassis := SlotCatalog.find_chassis(design.chassis_id)
	_texture = load(chassis.art)
	_slots = chassis.slots
	for child in slot_buttons.values():
		remove_child(child)
		child.queue_free()
	slot_buttons.clear()
	for slot: Dictionary in _slots:
		var button := OptionButton.new()
		button.focus_mode = FOCUS_NONE
		button.theme_type_variation = &"CompactButton"
		button.fit_to_longest_item = false
		button.clip_text = true
		button.custom_minimum_size = Vector2(48, 24)
		add_child(button)
		slot_buttons[slot.id] = button
		button.add_item("Empty")
		button.set_item_metadata(0, {"id": "", "rank": 1})
		for item in SlotCatalog.equipment():
			if not SlotCatalog.compatible(slot, item):
				continue
			var index := button.item_count
			var available := SlotCatalog.unlocked(item, grants)
			button.add_item(item.name + (" (Research)" if not available else ""))
			button.set_item_metadata(index, {"id": item.id, "rank": item.rank})
			button.set_item_disabled(index, not available)
		var fitted: Dictionary = design.equipment.get(slot.id, {})
		if not fitted.is_empty():
			var old_item := SlotCatalog.find_equipment(fitted.id, fitted.rank)
			if old_item.get("retired", false):
				button.add_item(old_item.name + " (Retired)")
				button.set_item_metadata(button.item_count - 1, fitted)
				button.set_item_disabled(button.item_count - 1, true)
		for index in range(button.item_count):
			var item: Dictionary = button.get_item_metadata(index)
			if item.id == fitted.get("id", "") and item.rank == fitted.get("rank", 1):
				button.select(index)
		# The full names remain in the popup; compact text keeps mounts separate.
		button.text = _short_name(fitted)
		button.pressed.connect(func() -> void:
			selected_slot = slot.id
			slot_selected.emit(slot.id)
			queue_redraw())
		button.item_selected.connect(func(index: int) -> void:
			var item: Dictionary = button.get_item_metadata(index)
			equipment_selected.emit(slot.id, item.id, item.rank))
	_layout_slots()

func _short_name(fitted: Dictionary) -> String:
	if fitted.is_empty():
		return "--"
	var item := SlotCatalog.find_equipment(fitted.id, fitted.rank)
	var words: PackedStringArray = item.name.split(" ")
	if words.size() == 1:
		return item.name.left(3).to_upper()
	var result := ""
	for word in words:
		result += word.left(1).to_upper()
	return result.left(3)

func _layout_slots() -> void:
	var side := maxf(1, minf(size.x - 24, size.y - 24))
	image_rect = Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side)
	for slot: Dictionary in _slots:
		var rect := slot_rect(slot)
		var button := slot_buttons[slot.id]
		button.size = Vector2(48, 24)
		button.position = (rect.get_center() - button.size * 0.5).round()
	queue_redraw()

func slot_rect(slot: Dictionary) -> Rect2:
	var factor := image_rect.size.x / 512.0
	return Rect2(image_rect.position + Vector2(slot.rect[0], slot.rect[1]) * factor, Vector2(slot.rect[2], slot.rect[3]) * factor)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), get_theme_color("background_color", "SlotCanvas"))
	if _texture == null:
		return
	draw_texture_rect(_texture, image_rect, false)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for slot: Dictionary in _slots:
		var rect := slot_rect(slot)
		var color := get_theme_color(slot.type + "_color", "SlotCanvas")
		draw_rect(rect.grow(2), color, false, 2 if slot.id == selected_slot else 1)
		var badge := slot.size as String
		var position := slot_buttons[slot.id].position + Vector2(0, -3)
		draw_string_outline(font, position, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color.BLACK)
		draw_string(font, position, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
