extends Control

const Transfer = preload("res://scripts/hangar_equipment_transfer.gd")
const DragButton = preload("res://scripts/hangar_drag_button.gd")
const GLOW = preload("res://shaders/ship_selection.gdshader")
const Exhaust = preload("res://scripts/ship_exhaust.gd")
var exhaust_elapsed := 0.0
signal slot_selected(id: String)
signal instance_selected(slot_id: String, uid: String)
var selected_slot := ""
var slot_buttons: Dictionary[String, Button] = {}
var slot_callouts: Dictionary[String, Control] = {}
var slot_glows: Dictionary[String, TextureRect] = {}
var image_rect := Rect2()
var owned_id := 0
var _slots: Array = []
var _texture: Texture2D
var starfield: Control
var camera := Vector2.ZERO
var zoom := 1.0
var panning := false
var _base_image_rect := Rect2()
# Until the player pans or zooms, frame the art's opaque bounds instead of the
# padded 512px source square.
var auto_fit := true
static var _used_rects: Dictionary = {}

const MIN_ZOOM := 0.4
const MAX_ZOOM := 4.0

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		if panning:
			panning = false
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and panning:
		auto_fit = false
		camera -= event.relative / zoom
		_update_view()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouse or not get_global_rect().has_point(event.position):
		return
	var hovered := get_viewport().gui_get_hovered_control()
	if is_instance_valid(hovered) and hovered != self and not is_ancestor_of(hovered):
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var pointer: Vector2 = get_global_transform().affine_inverse() * event.position
			var world := camera + (pointer - size * 0.5) / zoom
			auto_fit = false
			zoom = clampf(zoom * (1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.2), MIN_ZOOM, MAX_ZOOM)
			camera = world - (pointer - size * 0.5) / zoom
			_update_view()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			panning = true
			get_viewport().set_input_as_handled()

func _ready() -> void:
	SurfaceArt.apply(self)
	add_to_group("hangar_fitting_canvas")
	clip_contents = true
	focus_mode = FOCUS_NONE
	starfield = load("res://scripts/main_menu_starfield.gd").new()
	starfield.stationary = true
	starfield.show_behind_parent = true
	starfield.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(starfield)
	starfield.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	resized.connect(_layout_slots)

func _gui_input(event: InputEvent) -> void:
	starfield._gui_input(event)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not get_viewport().gui_is_dragging():
		selected_slot = ""
		slot_selected.emit("")
		queue_redraw()

func set_owned(owned: HangarShip) -> void:
	owned_id = owned.id
	_slots = owned.chassis.slots
	_texture = owned.art_texture
	for child: Control in slot_buttons.values() + slot_callouts.values() + slot_glows.values():
		child.queue_free()
	slot_buttons.clear()
	slot_callouts.clear()
	slot_glows.clear()
	for slot: Dictionary in _slots:
		var button: Button = DragButton.new()
		button.theme_type_variation = &"CompactButton"
		button.focus_mode = FOCUS_NONE
		button.clip_text = true
		button.name = slot.id
		button.set_meta("hangar_slot", slot.id)
		var instance: Dictionary = owned.mounts.get(slot.id, {})
		button.equipment_uid = instance.get("uid", "")
		button.equipment_texture = owned.equipment_art.get(slot.id)
		button.text = ""
		var empty := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(state, empty)
		button.accepts = func(data: Variant) -> bool: return Transfer.can_fit(owned_id, slot.id, data)
		button.received = func(data: Dictionary) -> void: instance_selected.emit(slot.id, data.uid)
		button.pressed.connect(func() -> void:
			selected_slot = slot.id
			slot_selected.emit(slot.id)
			queue_redraw())
		add_child(button)
		slot_buttons[slot.id] = button
		if button.equipment_texture != null:
			var glow := TextureRect.new()
			glow.name = "EquipmentGlow_" + slot.id
			glow.texture = SurfaceArt.diffuse(button.equipment_texture)
			glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			glow.mouse_filter = MOUSE_FILTER_IGNORE
			glow.visible = false
			var glow_material := ShaderMaterial.new()
			glow_material.shader = GLOW
			glow_material.set_shader_parameter("glow_color", get_theme_color("selection_color", "SlotCanvas"))
			glow.material = glow_material
			add_child(glow)
			slot_glows[slot.id] = glow
			button.mouse_entered.connect(func() -> void:
				glow.visible = not get_viewport().gui_is_dragging())
			button.mouse_exited.connect(func() -> void: glow.hide())
		var card := Control.new()
		card.name = "Callout_" + slot.id
		card.focus_mode = FOCUS_NONE
		card.mouse_filter = MOUSE_FILTER_STOP
		card.self_modulate = button.self_modulate
		card.visible = not instance.is_empty()
		add_child(card)
		var label := ResourceText.new()
		label.name = "EquipmentName"
		label.theme_type_variation = &"MountCalloutText"
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_contents = false
		label.set_content("" if instance.is_empty() else SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank)).name)
		label.mouse_filter = MOUSE_FILTER_IGNORE
		card.add_child(label)
		if not instance.is_empty() and button.equipment_texture == null:
			button.mouse_entered.connect(func() -> void:
				label.add_theme_color_override("font_shadow_color", get_theme_color("selection_color", "SlotCanvas")))
			button.mouse_exited.connect(func() -> void:
				label.remove_theme_color_override("font_shadow_color"))
		slot_callouts[slot.id] = card
	_layout_slots()

func _layout_slots() -> void:
	if _slots.is_empty():
		return
	var left: Array[Dictionary] = []
	var right: Array[Dictionary] = []
	var middle: Array[Dictionary] = []
	for slot: Dictionary in _slots:
		var x := float(slot.rect[0]) + float(slot.rect[2]) * 0.5
		if x < 246:
			left.append(slot)
		elif x > 266:
			right.append(slot)
		else:
			middle.append(slot)
	for slot: Dictionary in middle:
		if left.size() <= right.size():
			left.append(slot)
		else:
			right.append(slot)
	var left_width := _rail_width(left)
	var right_width := _rail_width(right)
	var side := maxf(1, minf(size.x - left_width - right_width - 16, size.y - 16))
	_base_image_rect = Rect2(Vector2(left_width + (size.x - left_width - right_width - side) * 0.5, (size.y - side) * 0.5), Vector2.ONE * side)
	if auto_fit and _texture != null:
		var used := _art_used_rect()
		if used.size.x > 0.0 and used.size.y > 0.0:
			var fit_x := side * 0.96 / (used.size.x * side)
			var fit_y := (size.y - 16) * 0.96 / (used.size.y * side)
			zoom = clampf(minf(fit_x, fit_y), 1.0, MAX_ZOOM)
			var art_center := _base_image_rect.position + (used.position + used.size * 0.5) * side
			var frame_center := _base_image_rect.get_center()
			camera = art_center - size * 0.5 - (frame_center - size * 0.5) / zoom
	_layout_rail(left, 0, left_width)
	_layout_rail(right, size.x - right_width, right_width)
	_update_view()

static var _obtainable: Dictionary = {}

# Equipment a player can actually own in the active game; retired and deferred
# items never reach a mount, so they do not reserve callout width.
static func _obtainable_ids() -> Dictionary:
	if _obtainable.is_empty():
		for node: Dictionary in HangarResearch.catalog():
			for id: String in node.grants.equipment_ids:
				if id not in HangarResearch.DEFERRED_PURCHASES:
					_obtainable[id] = true
	return _obtainable

func _art_used_rect() -> Rect2:
	if _texture == null:
		return Rect2(0, 0, 1, 1)
	var diffuse := SurfaceArt.diffuse(_texture)
	var key := diffuse.resource_path if not diffuse.resource_path.is_empty() else str(diffuse.get_instance_id())
	if not _used_rects.has(key):
		var image := diffuse.get_image()
		var used := Rect2(image.get_used_rect())
		_used_rects[key] = Rect2(used.position / Vector2(image.get_size()), used.size / Vector2(image.get_size()))
	return _used_rects[key]

func _update_view() -> void:
	image_rect = Rect2(size * 0.5 + (_base_image_rect.position - size * 0.5 - camera) * zoom, _base_image_rect.size * zoom)
	queue_redraw()
	_place_slots()

# Opaque chassis art on screen; callouts must stay clear of this, not of the
# transparent padding around it.
func art_rect() -> Rect2:
	var used := _art_used_rect()
	return Rect2(image_rect.position + used.position * image_rect.size, used.size * image_rect.size)

func _place_slots() -> void:
	for slot: Dictionary in _slots:
		var rect := slot_rect(slot)
		slot_buttons[slot.id].position = rect.position
		slot_buttons[slot.id].size = rect.size
		if slot_glows.has(slot.id):
			var owned: HangarShip = GameState.owned_ship(owned_id)
			var glow: TextureRect = slot_glows[slot.id]
			var glow_rect := SlotCatalog.fitted_art_rect(slot_buttons[slot.id].equipment_texture, rect,
				owned.equipment_art_mounts.get(slot.id, []))
			glow.position = glow_rect.position
			glow.size = glow_rect.size
	queue_redraw()

func _rail_width(slots: Array[Dictionary]) -> float:
	var width := 76.0
	var names := {}
	var catalog := SlotCatalog.equipment()
	var obtainable := _obtainable_ids()
	var owned: HangarShip = GameState.owned_ship(owned_id)
	for slot: Dictionary in slots:
		if owned != null and owned.mounts.has(slot.id):
			var fitted: Dictionary = owned.mounts[slot.id]
			names[SlotCatalog.find_equipment(fitted.equipment_id, int(fitted.rank)).name] = true
		for item: Dictionary in catalog:
			if obtainable.has(item.id) and SlotCatalog.compatible(slot, item):
				names[item.name] = true
	# Reserve full-name space for this chassis so fitting never changes ship scale.
	var label: ResourceText = slot_callouts[slots[0].id].get_node("EquipmentName") if not slots.is_empty() else null
	for name: String in names:
		width = maxf(width, label.get_theme_font("normal_font").get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("normal_font_size")).x + 20)
	return ceilf(width)

func _layout_rail(slots: Array[Dictionary], x: float, width: float) -> void:
	slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.rect[1]) < float(b.rect[1]))
	var height := 24.0
	var gap := minf(12, maxf(2, (size.y - height * slots.size()) / maxf(1, slots.size() - 1)))
	var y := maxf(0, (size.y - height * slots.size() - gap * (slots.size() - 1)) * 0.5)
	for slot: Dictionary in slots:
		var card: Control = slot_callouts[slot.id]
		card.set_meta("left_rail", x == 0)
		card.position = Vector2(x, y)
		card.size = Vector2(width, height)
		var label: ResourceText = card.get_node("EquipmentName")
		label.position = Vector2(10, 0)
		label.size = Vector2(width - 20, height)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if x == 0 else HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		y += height + gap

func slot_rect(slot: Dictionary) -> Rect2:
	return Rect2(image_rect.position + Vector2(slot.rect[0], slot.rect[1]) * image_rect.size.x / 512,
		Vector2(slot.rect[2], slot.rect[3]) * image_rect.size.x / 512)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_DRAG_BEGIN, NOTIFICATION_DRAG_END]:
		for id: String in slot_glows:
			slot_glows[id].visible = what == NOTIFICATION_DRAG_END and slot_buttons[id].is_hovered()
		queue_redraw()

func _connector_points(card: Control, rect: Rect2) -> PackedVector2Array:
	var left_side: bool = card.get_meta("left_rail")
	var anchor := Vector2(card.get_rect().end.x if left_side else card.position.x, card.get_rect().get_center().y)
	var mount_edge := Vector2(rect.position.x if left_side else rect.end.x, rect.get_center().y)
	var bend := Vector2(anchor.x + 6 if left_side else anchor.x - 6, anchor.y)
	var screen_transform := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var inverse := screen_transform.affine_inverse()
	var points := PackedVector2Array()
	for point: Vector2 in [anchor, bend, mount_edge]:
		points.append(inverse * ((screen_transform * point).floor() + Vector2(0.5, 0.5)))
	return points

func _process(delta: float) -> void:
	if is_visible_in_tree():
		exhaust_elapsed += delta
		queue_redraw()

func _draw() -> void:
	if _texture == null:
		return
	var owned: HangarShip = GameState.owned_ship(owned_id)
	if owned != null:
		Exhaust.draw(self, owned, image_rect, exhaust_elapsed)
	draw_texture_rect(_texture, image_rect, false)
	if owned != null:
		owned.draw_fitted_equipment(self, image_rect)
	var data: Variant = get_viewport().gui_get_drag_data()
	var dragging := Transfer.valid(data)
	var grants: Dictionary = GameState.research_grants() if dragging else {}
	for slot: Dictionary in _slots:
		var rect := slot_rect(slot)
		var color := get_theme_color(slot.type + "_color", "SlotCanvas")
		if dragging:
			color = get_theme_color("drop_valid_color" if Transfer.can_fit(owned_id, slot.id, data, grants) else "drop_invalid_color", "SlotCanvas")
			draw_rect(rect.grow(3), Color(color, 0.18))
			draw_rect(rect.grow(2), color, false, 2)
		var card: Control = slot_callouts[slot.id]
		card.visible = not slot_buttons[slot.id].equipment_uid.is_empty()
		if not card.visible:
			continue
		# Negative width keeps the unfiltered line one screen pixel at every UI scale.
		draw_polyline(_connector_points(card, rect), get_theme_color("connector_color", "SlotCanvas"), -1, false)

func _slot_at(position: Vector2) -> String:
	for slot: Dictionary in _slots:
		if slot_rect(slot).has_point(position):
			return slot.id
	return ""

func _can_drop_data(position: Vector2, data: Variant) -> bool:
	return Transfer.can_fit(owned_id, _slot_at(position), data)

func _drop_data(position: Vector2, data: Variant) -> void:
	if _can_drop_data(position, data):
		instance_selected.emit(_slot_at(position), data.uid)
