extends RefCounted

# Shared builders for the game's buttons, labels, dialogs and toasts so every
# screen uses the same theme variations, sounds and layering rules.
const DIALOG_Z := 40
const TOAST_Z := 35
const TOP_Z := 60
const PlaceholderAssets = preload("res://scripts/placeholders.gd")

static func label(text: String, variation: StringName = &"") -> Label:
	var result := Label.new()
	result.text = text
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not variation.is_empty():
		result.theme_type_variation = variation
	return result

static func button(text: String, action: Callable, sound: StringName = &"accept") -> Button:
	var result := Button.new()
	result.text = "" if ResourceText.has_icons(text) else text
	result.theme_type_variation = &"TacticalButton"
	result.focus_mode = Control.FOCUS_NONE
	result.custom_minimum_size.y = 30
	if not sound.is_empty():
		AudioManager.connect_ui_button(result, sound)
	result.pressed.connect(action)
	if ResourceText.has_icons(text):
		ResourceText.button_content(result, text)
	return result

static func close_button(action: Callable) -> TextureButton:
	var close: TextureButton = load("res://scenes/close_x_button.tscn").instantiate()
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	AudioManager.connect_ui_button(close)
	close.pressed.connect(action)
	return close

# Builds a centered modal dialog over `host`. Returns {root, panel, column,
# actions}; callers add buttons to `actions`. `art` may be a texture or a
# resource path (missing paths render the pink placeholder). A non-empty
# `on_close` adds the shared top-right X.
static func dialog(host: Control, node_name: String, title: String, text: String,
		art: Variant = null, on_close: Callable = Callable(), z := DIALOG_Z, width := 480.0) -> Dictionary:
	var root := Control.new()
	root.name = node_name
	root.add_to_group("modal_ui")
	root.z_index = z
	host.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	var panel := PanelContainer.new()
	panel.name = node_name + "Panel"
	panel.theme_type_variation = &"CompactPanel"
	panel.custom_minimum_size.x = minf(width, host.size.x - 48)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(panel)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)
	if art != null:
		var portrait := TextureRect.new()
		portrait.name = "DialogArt"
		portrait.texture = art if art is Texture2D else PlaceholderAssets.texture(str(art))
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.custom_minimum_size = Vector2(72, 72) if host.size.y >= 500 else Vector2(48, 48)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		body.add_child(portrait)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(column)
	if not title.is_empty():
		column.add_child(label(title.to_upper(), &"HeaderResearch"))
	if not text.is_empty():
		var description := label(text)
		description.name = "DialogText"
		description.custom_minimum_size.x = minf(width - 120.0, host.size.x - 160)
		column.add_child(description)
	var actions := VBoxContainer.new()
	actions.name = "DialogActions"
	column.add_child(actions)
	if on_close.is_valid():
		panel.add_child(close_button(on_close))
	return {"root": root, "panel": panel, "column": column, "actions": actions}

static func toast(host: Control, text: String, sound: StringName = &"") -> void:
	if text.is_empty():
		return
	var stack := host.get_node_or_null("Toasts") as VBoxContainer
	if stack == null:
		stack = VBoxContainer.new()
		stack.name = "Toasts"
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.z_index = TOAST_Z
		host.add_child(stack)
		stack.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		stack.offset_top = 52
		stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	if not sound.is_empty():
		AudioManager.play_ui_sfx(sound)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CompactPanel"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var line := label(text)
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(line)
	stack.add_child(card)
	while stack.get_child_count() > 3:
		var oldest := stack.get_child(0)
		stack.remove_child(oldest)
		oldest.queue_free()
	card.modulate.a = 0.0
	var tween := card.create_tween()
	tween.tween_property(card, "modulate:a", 1.0, 0.2)
	tween.tween_interval(3.0)
	tween.tween_property(card, "modulate:a", 0.0, 0.5)
	tween.tween_callback(card.queue_free)
