extends VBoxContainer

signal changed(preferences: Dictionary)

const CATEGORIES := SlotCatalog.TYPES
var categories: Dictionary = {}
var size_range := preload("res://scripts/equipment_size_range.gd").new()

func _init() -> void:
	var categories_row := HFlowContainer.new()
	add_child(categories_row)
	for option: String in CATEGORIES:
		var checkbox := CheckBox.new()
		checkbox.text = option.capitalize()
		checkbox.focus_mode = FOCUS_NONE
		checkbox.button_pressed = true
		categories_row.add_child(checkbox)
		categories[option] = checkbox
		checkbox.toggled.connect(func(_pressed: bool) -> void: changed.emit(get_preferences()))
	var size_row := HFlowContainer.new()
	add_child(size_row)
	size_range.name = "SizeRange"
	size_row.add_child(size_range)
	size_range.changed.connect(func() -> void: changed.emit(get_preferences()))

func set_preferences(value: Dictionary) -> void:
	for category: String in categories:
		categories[category].set_pressed_no_signal(category in value.get("categories", CATEGORIES))
	var selected: Array = value.get("sizes", SlotCatalog.SIZES)
	var first := 3
	var last := 0
	for index in range(4):
		if SlotCatalog.SIZES[index] in selected:
			first = mini(first, index)
			last = maxi(last, index)
	size_range.set_range(first if first <= last else 0, last if first <= last else 3)

func get_preferences() -> Dictionary:
	var value := {"categories": [], "sizes": []}
	for category: String in categories:
		if categories[category].button_pressed:
			value.categories.append(category)
	for index in range(size_range.lower, size_range.upper + 1):
		value.sizes.append(SlotCatalog.SIZES[index])
	return value

func matches(item: Dictionary) -> bool:
	var index: int = SlotCatalog.SIZES.find(item.size)
	return categories[item.type].button_pressed and index >= size_range.lower and index <= size_range.upper

func is_unfiltered() -> bool:
	return categories.values().all(func(control: CheckBox) -> bool: return control.button_pressed) \
		and size_range.lower == 0 and size_range.upper == 3
