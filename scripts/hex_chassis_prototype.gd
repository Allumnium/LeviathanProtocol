extends Control

# Isolated integration scene. It never reads or writes campaign/archive saves.
var board: HexBuildArea
var designs: Dictionary[String, HexShipDesign] = {}
var details: Label
var chassis_picker: OptionButton

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	var columns := VBoxContainer.new()
	margin.add_child(columns)
	var header := HBoxContainer.new()
	columns.add_child(header)
	chassis_picker = OptionButton.new()
	chassis_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(chassis_picker)
	for entry in ChassisCatalog.entries():
		var design := HexShipDesign.new()
		design.initialize(entry.id)
		designs[entry.id] = design
		chassis_picker.add_item(entry.display_name)
		chassis_picker.set_item_metadata(chassis_picker.item_count - 1, entry.id)
	chassis_picker.item_selected.connect(_select)
	var materials := HBoxContainer.new()
	header.add_child(materials)
	for category in range(4):
		var button := Button.new()
		button.text = ["O", "D", "T", "C"][category]
		button.custom_minimum_size = Vector2(32, 28)
		materials.add_child(button)
		button.pressed.connect(func() -> void: board.selected_material = category)
	board = HexBuildArea.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(board)
	details = Label.new()
	details.custom_minimum_size.y = 24
	columns.add_child(details)
	board.cell_selected.connect(_selected_cell)
	_select(3)
	chassis_picker.select(3)

func _select(index: int) -> void:
	board.set_design(designs[str(chassis_picker.get_item_metadata(index))])
	var chassis := board.design.chassis()
	details.text = "%s  %d CP" % ["Flagship" if chassis.flagship else "Command", chassis.command_points if chassis.flagship else chassis.command_cost]

func _selected_cell(cell: Vector2i) -> void:
	var chassis := board.design.chassis()
	var region := chassis.region_at(cell)
	if region.is_empty():
		details.text = "Chassis"
		return
	var bonuses := chassis.modifiers_at(cell)
	details.text = "Armor +%d%%  Range +%d%%" % [roundi(bonuses.get("armor_integrity", 0) * 100), roundi(bonuses.get("weapon_range", 0) * 100)]
