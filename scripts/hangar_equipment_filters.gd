extends VBoxContainer

signal changed(preferences: Dictionary)

const CATEGORIES := SlotCatalog.TYPES
var categories: Dictionary = {}
var sizes: Dictionary = {}

func _init() -> void:
	for options: Array in [CATEGORIES, SlotCatalog.SIZES]:
		var row := HFlowContainer.new()
		add_child(row)
		var controls: Dictionary = categories if options == CATEGORIES else sizes
		for option: String in options:
			var checkbox := CheckBox.new()
			checkbox.text = option.capitalize() if options == CATEGORIES else option
			checkbox.focus_mode = FOCUS_NONE
			checkbox.button_pressed = true
			row.add_child(checkbox)
			controls[option] = checkbox
			checkbox.toggled.connect(func(_pressed: bool) -> void: changed.emit(get_preferences()))

func set_preferences(value: Dictionary) -> void:
	for category: String in categories:
		categories[category].set_pressed_no_signal(category in value.get("categories", CATEGORIES))
	for size: String in sizes:
		sizes[size].set_pressed_no_signal(size in value.get("sizes", SlotCatalog.SIZES))

func get_preferences() -> Dictionary:
	var value := {"categories": [], "sizes": []}
	for category: String in categories:
		if categories[category].button_pressed:
			value.categories.append(category)
	for size: String in sizes:
		if sizes[size].button_pressed:
			value.sizes.append(size)
	return value

func matches(item: Dictionary) -> bool:
	return categories[item.type].button_pressed and sizes[item.size].button_pressed

func is_unfiltered() -> bool:
	return categories.values().all(func(control: CheckBox) -> bool: return control.button_pressed) \
		and sizes.values().all(func(control: CheckBox) -> bool: return control.button_pressed)
