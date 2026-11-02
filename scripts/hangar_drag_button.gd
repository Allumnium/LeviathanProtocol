extends Button

const Transfer = preload("res://scripts/hangar_equipment_transfer.gd")
var equipment_uid := ""
var accepts: Callable
var received: Callable
var equipment_texture: Texture2D

func _get_drag_data(_position: Vector2) -> Variant:
	if not GameState.can_use_shipyard() or equipment_uid.is_empty() or not GameState.equipment_inventory.has(equipment_uid):
		return null
	var item: Dictionary = SlotCatalog.find_equipment(GameState.equipment_inventory[equipment_uid].equipment_id, int(GameState.equipment_inventory[equipment_uid].rank))
	var preview: Control = preload("res://scripts/hangar_equipment_preview.gd").new()
	preview.name = "EquipmentDragPreview"
	preview.theme = preload("res://themes/ui_theme.tres")
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.texture = equipment_texture
	preview.item = item
	preview.data = Transfer.payload(equipment_uid)
	set_drag_preview(preview)
	return Transfer.payload(equipment_uid)

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return accepts.is_valid() and accepts.call(data)

func _drop_data(_position: Vector2, data: Variant) -> void:
	if _can_drop_data(_position, data) and received.is_valid():
		received.call(data)
