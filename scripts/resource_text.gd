class_name ResourceText
extends RichTextLabel

const SCIENCE: Texture2D = preload("res://assets/science.png")
const CREDITS: Texture2D = preload("res://assets/credits.png")
const REPAIR: Texture2D = preload("res://assets/ui/icons/icon_repair.png")
const SHIELD: Texture2D = preload("res://assets/ui/icons/icon_shield.png")
const ICON_PATTERN := "(?i)\\b(RP|CR|repair|shields?(?!\\s+Generator\\b))\\b"

static func has_icons(value: String) -> bool:
	var tokens := RegEx.new()
	tokens.compile(ICON_PATTERN)
	return tokens.search(value) != null

var source_text := ""
var icon_size := 0

func _init() -> void:
	bbcode_enabled = false
	fit_content = true
	scroll_active = false
	selection_enabled = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = Control.TEXTURE_FILTER_NEAREST
	theme_type_variation = &"ResourceText"

func _ready() -> void:
	if source_text.is_empty() and not text.is_empty():
		source_text = text
	_render()
	theme_changed.connect(_render)

func set_content(value: String) -> void:
	source_text = value
	if is_inside_tree():
		_render()

func _render() -> void:
	clear()
	var tokens := RegEx.new()
	tokens.compile(ICON_PATTERN)
	var cursor := 0
	icon_size = get_theme_font_size("normal_font_size")
	for token: RegExMatch in tokens.search_all(source_text):
		add_text(source_text.substr(cursor, token.get_start() - cursor))
		var icons := {"RP": SCIENCE, "CR": CREDITS, "REPAIR": REPAIR, "SHIELD": SHIELD, "SHIELDS": SHIELD}
		add_image(icons[token.get_string().to_upper()],
			0, icon_size, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		cursor = token.get_end()
	add_text(source_text.substr(cursor))

static func create(value: String) -> ResourceText:
	var label := ResourceText.new()
	label.set_content(value)
	return label

static func button_content(button: Button, value: String) -> void:
	button.set_meta("resource_text", value)
	var label := create(value)
	label.name = "ResourceText"
	button.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var update := func() -> void:
		var font_size := button.get_theme_font_size("font_size")
		if label.get_theme_font_size("normal_font_size") != font_size:
			label.add_theme_font_size_override("normal_font_size", font_size)
		if label.get_theme_font("normal_font") != button.get_theme_font("font"):
			label.add_theme_font_override("normal_font", button.get_theme_font("font"))
		var state := "disabled" if button.disabled else ("pressed" if button.is_pressed() else ("hover" if button.is_hovered() else "normal"))
		var color_key := {"normal": "font_color", "hover": "font_hover_color", "pressed": "font_pressed_color", "disabled": "font_disabled_color"}
		label.self_modulate = button.get_theme_color(color_key[state])
		var style := button.get_theme_stylebox(state)
		label.offset_left = style.content_margin_left
		label.offset_right = -style.content_margin_right
		label.offset_top = style.content_margin_top
		label.offset_bottom = -style.content_margin_bottom
		var width := button.get_theme_font("font").get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		button.custom_minimum_size.x = ceilf(width + style.content_margin_left + style.content_margin_right)
	button.draw.connect(update)
	label.add_theme_color_override("default_color", Color.WHITE)
