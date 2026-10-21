class_name StatDisplayRow
extends VBoxContainer

const POINTS_PER_SEGMENT := 5.0
const SEGMENT_BORDER_SIZE := 1.0
const SEGMENT_SIZE := Vector2(6.0, 8.0)
const SEGMENT_SEPARATION := 1
const SEGMENT_BORDER_COLOR := Color(0.22, 0.3, 0.32, 1.0)
const SEGMENT_EMPTY_COLOR := Color(0.05, 0.08, 0.09, 1.0)
const SEGMENT_POSITIVE_COLOR := Color(0.28, 0.76, 0.7, 1.0)
const SEGMENT_NEGATIVE_COLOR := Color(0.88, 0.31, 0.27, 1.0)


func _init(
	stat_name: String = "",
	value: float = 0.0,
	formatted_value: String = "",
	font_size: int = 11
) -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 1)

	var title_row := HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = stat_name
	name_label.add_theme_font_size_override("font_size", font_size)
	title_row.add_child(name_label)

	var value_label := Label.new()
	value_label.text = formatted_value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.add_theme_font_size_override("font_size", font_size)
	title_row.add_child(value_label)
	add_child(title_row)

	var segments := HFlowContainer.new()
	segments.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	segments.add_theme_constant_override("h_separation", SEGMENT_SEPARATION)
	segments.add_theme_constant_override("v_separation", SEGMENT_SEPARATION)
	segments.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var magnitude := absf(value)
	var segment_count := int(ceil(magnitude / POINTS_PER_SEGMENT))
	for index in range(segment_count):
		var segment_value := minf(magnitude - index * POINTS_PER_SEGMENT, POINTS_PER_SEGMENT)
		segments.add_child(
			_create_segment(
				segment_value / POINTS_PER_SEGMENT,
				SEGMENT_NEGATIVE_COLOR if value < 0.0 else SEGMENT_POSITIVE_COLOR
			)
		)
	add_child(segments)


func _create_segment(fill_fraction: float, fill_color: Color) -> ColorRect:
	var border := ColorRect.new()
	border.custom_minimum_size = SEGMENT_SIZE
	border.color = SEGMENT_BORDER_COLOR
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var empty := ColorRect.new()
	empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty.offset_left = SEGMENT_BORDER_SIZE
	empty.offset_top = SEGMENT_BORDER_SIZE
	empty.offset_right = -SEGMENT_BORDER_SIZE
	empty.offset_bottom = -SEGMENT_BORDER_SIZE
	empty.color = SEGMENT_EMPTY_COLOR
	empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_child(empty)

	var fill := ColorRect.new()
	fill.anchor_right = clampf(fill_fraction, 0.0, 1.0)
	fill.anchor_bottom = 1.0
	fill.color = fill_color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty.add_child(fill)
	return border
