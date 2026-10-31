extends Control

const Transfer = preload("res://scripts/hangar_equipment_transfer.gd")
var texture: Texture2D
var item: Dictionary
var data: Dictionary
var target_slot := ""
var bounds := Rect2(-Vector2(24, 36), Vector2(48, 72))
var sprite_rect := Rect2()
var title: Label

func _ready() -> void:
	SurfaceArt.apply(self)
	add_to_group("equipment_drag_preview")
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = TEXTURE_FILTER_NEAREST
	title = Label.new()
	title.text = item.name
	title.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(title)
	_process(0)

func _process(_delta: float) -> void:
	target_slot = ""
	bounds = Rect2(-Vector2(24, 36), Vector2(48, 72))
	var canvas: Control = get_tree().get_first_node_in_group("hangar_fitting_canvas")
	if is_instance_valid(canvas):
		var reference: Dictionary = {}
		for slot: Dictionary in canvas._slots:
			if canvas.slot_buttons[slot.id].equipment_uid == data.uid:
				reference = slot
				break
			if reference.is_empty() and SlotCatalog.compatible(slot, item):
				reference = slot
		if not reference.is_empty():
			var mount_bounds: Rect2 = get_global_transform().affine_inverse() * (canvas.get_global_transform() * canvas.slot_rect(reference))
			bounds = Rect2(-mount_bounds.size * 0.5, mount_bounds.size)
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if is_instance_valid(canvas) and is_instance_valid(hovered) and (hovered == canvas or canvas.is_ancestor_of(hovered)):
		var slot_id: String = hovered.get_meta("hangar_slot", "")
		if slot_id.is_empty() and hovered == canvas:
			slot_id = canvas._slot_at(canvas.get_local_mouse_position())
		if Transfer.can_fit(canvas.owned_id, slot_id, data):
			for slot: Dictionary in canvas._slots:
				if slot.id == slot_id:
					target_slot = slot_id
					# Convert the authored mount through canvas transforms, exactly as fitted art.
					bounds = get_global_transform().affine_inverse() * (canvas.get_global_transform() * canvas.slot_rect(slot))
					break
	if texture != null:
		sprite_rect = SlotCatalog.fitted_art_rect(texture, bounds, item.get("art_mount", []))
	title.visible = target_slot.is_empty() or texture == null
	title.position = Vector2(bounds.get_center().x - title.size.x * 0.5, bounds.end.y + 4)
	queue_redraw()

func _draw() -> void:
	if texture != null:
		draw_texture_rect(texture, sprite_rect, false)
	else:
		draw_rect(bounds, Color(1, 1, 1, 0.6), false)
