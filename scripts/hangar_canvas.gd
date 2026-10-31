extends SlotShipCanvas

signal instance_selected(slot_id: String, uid: String)

func _layout_slots() -> void:
	super._layout_slots()
	var placed: Array[Rect2] = []
	for slot: Dictionary in _slots:
		var button := slot_buttons[slot.id]
		var origin := button.position
		for offset in [0, 28, -28, 56, -56, 84, -84]:
			var rect := Rect2(origin + Vector2(0, offset), button.size)
			if rect.position.y < 14 or rect.end.y > size.y - 4:
				continue
			if not placed.any(func(other: Rect2) -> bool: return rect.grow(2).intersects(other)):
				button.position = rect.position
				placed.append(rect)
				break

func _draw() -> void:
	super._draw()
	for slot: Dictionary in _slots:
		var button := slot_buttons[slot.id]
		var origin := slot_rect(slot).get_center()
		if button.get_rect().get_center().distance_to(origin) > 16:
			draw_line(origin, button.get_rect().get_center(), get_theme_color(slot.type + "_color", "SlotCanvas"), 1)

func set_owned(owned: HangarShip) -> void:
	var view := SlotShipDesign.new()
	view.initialize(owned.chassis_id)
	for key in owned.mounts:
		var instance: Dictionary = owned.mounts[key]
		view.equipment[key] = {"id": instance.equipment_id, "rank": instance.rank}
	set_design(view, GameState.research_grants())
	for slot: Dictionary in owned.chassis.slots:
		var button := slot_buttons[slot.id]
		button.clear()
		button.add_item("Empty")
		button.set_item_metadata(0, {"id": "", "rank": 1, "uid": ""})
		for instance: Dictionary in GameState.equipment_inventory.values():
			var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
			if not SlotCatalog.compatible(slot, item):
				continue
			var location: Dictionary = GameState.equipment_location(instance.uid)
			var suffix := "Stock" if location.is_empty() else GameState.owned_ship(int(location.ship_id)).display_name
			button.add_item("%s #%s | %s | %.0f%%" % [item.name, instance.uid, suffix, 100 * instance.hp / item.hit_points])
			var index := button.item_count - 1
			button.set_item_metadata(index, {"id": item.id, "rank": int(item.rank), "uid": instance.uid})
			if item.id in HangarResearch.DEFERRED_PURCHASES:
				button.set_item_disabled(index, true)
				button.set_item_text(index, item.name + " (Deferred)")
			if owned.mounts.get(slot.id, {}).get("uid", "") == instance.uid:
				button.select(index)
		button.text = _short_name(view.equipment.get(slot.id, {}))
		button.item_selected.connect(func(index: int) -> void: instance_selected.emit(slot.id, button.get_item_metadata(index).uid))
