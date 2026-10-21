extends Control

const BOLD_FONT = preload("res://assets/fonts/GameFont_bold.ttf")

@onready var archive_rows: VBoxContainer = $ArchiveScroll/ArchiveRows

var _part_types: Array[int] = []
var _part_images: Array[TextureRect] = []


func _ready() -> void:
	GameState.discovered_parts_changed.connect(_refresh_discovery_masks)
	for pattern in ShipPartPattern.get_catalog():
		archive_rows.add_child(_create_entry(pattern))
	_refresh_discovery_masks()


func _create_entry(pattern: ShipPartPattern) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 104)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var contents := HBoxContainer.new()
	contents.add_theme_constant_override("separation", 8)
	row.add_child(contents)

	var image_center := CenterContainer.new()
	image_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	image_center.size_flags_stretch_ratio = 1.0
	contents.add_child(image_center)

	var image := TextureRect.new()
	image.custom_minimum_size = Vector2(80, 80)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture = pattern.preview_texture
	if image.texture == null:
		push_error("No Archive image is assigned for %s." % pattern.display_name)
	image_center.add_child(image)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.size_flags_stretch_ratio = 1.0
	details.add_theme_constant_override("separation", 4)
	contents.add_child(details)

	var name_label := Label.new()
	name_label.text = pattern.display_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_override("font", BOLD_FONT)
	details.add_child(name_label)

	var description_label := Label.new()
	description_label.text = "TODO"
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(description_label)

	_part_types.append(pattern.part_type)
	_part_images.append(image)
	return row


func _refresh_discovery_masks() -> void:
	for index in range(_part_images.size()):
		_part_images[index].modulate = (
			Color.WHITE
			if GameState.has_discovered_part(_part_types[index])
			else Color.BLACK
		)
