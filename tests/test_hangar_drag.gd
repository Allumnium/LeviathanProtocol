extends SceneTree

const Transfer = preload("res://scripts/hangar_equipment_transfer.gd")
var checks := 0
var failures := 0
var state: Node
var screen: Control
var ship_id := 0
var items: Dictionary = {}
var last_mouse := Vector2.ZERO

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/cargo-art"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/unequip-panel"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/inline-sale"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/art-only"))
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	state = root.get_node("GameState")
	state.run_save_path = "user://drag-hangar.json"
	check(state.start_new_run(1, 42), "Start drag-and-drop fixture")
	var data: Dictionary = state.hangar_snapshot()
	data.credits = 5000
	data.research.research_ids.append_array(["applied_energy", "civil_hospitality"])
	check(state._commit_hangar(data), "Fund researched physical inventory for starter Transport")
	ship_id = state.fleet[1].id
	for id in ["double_laser", "laser", "shield_generator", "research_lab", "hull_plate", "cargo_hold", "passenger_cabin"]:
		check(state.buy_equipment(id), "Purchase physical " + id)
		items[id] = str(state.next_equipment_id - 1)
	check(state.buy_equipment("double_laser"), "Stock can contain two distinct copies")
	items["second_laser"] = str(state.next_equipment_id - 1)
	screen = load("res://scenes/game_map.tscn").instantiate()
	screen.active_tab = "SHIPS"
	root.add_child(screen)
	current_scene = screen
	screen.selected_ship_id = ship_id
	screen._queue_refresh()
	await settle()
	check(screen.stock.visible_uids.size() == 8, "Stock shows uninstalled owned instances")
	check(screen.roster.find_child("Ship%d" % ship_id, true, false).button_pressed, "Roster marks the ship being equipped")
	check_callouts(false)
	for mount: Button in screen.canvas.slot_buttons.values():
		check(not mount is OptionButton, "Slot has no equipment dropdown")
	await filter_checks()
	var initial_cargo_row: Button = await prepare_stock("cargo_hold")
	var before_label_drop: Dictionary = state.hangar_snapshot()
	await drag(initial_cargo_row.get_global_rect().get_center(), screen.canvas.slot_callouts.hold.get_global_rect().get_center())
	check(state.hangar_snapshot() == before_label_drop and state.equipment_location(items.cargo_hold).is_empty(), "Dropping on a side label cannot fit equipment")
	await fit_stock("cargo_hold", "hold")
	if failures:
		quit(1)
		return
	check(state.owned_ship(ship_id).hangar_summary().cargo == 10, "Equipped hold updates cargo capacity")
	var cargo_button: Button = screen.canvas.slot_buttons.hold
	check(cargo_button.equipment_texture != null and cargo_button.text.is_empty(), "Fitted Cargo Bay renders its sprite instead of a text button")
	var hold: Dictionary = state.owned_ship(ship_id).chassis.slots.filter(func(slot: Dictionary) -> bool: return slot.id == "hold")[0]
	var hold_rect: Rect2 = screen.canvas.slot_rect(hold)
	check(cargo_button.position.is_equal_approx(hold_rect.position) and cargo_button.size.is_equal_approx(hold_rect.size), "Cargo drag target snaps to the full XL slot")
	var sprite_rect := SlotCatalog.fitted_art_rect(cargo_button.equipment_texture, hold_rect)
	check(hold_rect.encloses(sprite_rect) and sprite_rect.get_center().is_equal_approx(hold_rect.get_center()), "Sprite stays centered inside the slot")
	check(is_equal_approx(sprite_rect.size.x / sprite_rect.size.y, cargo_button.equipment_texture.get_size().x / cargo_button.equipment_texture.get_size().y), "Cargo sprite keeps its original proportions")
	var cargo_glow: TextureRect = screen.canvas.slot_glows.hold
	check(cargo_glow.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and cargo_glow.get_rect().is_equal_approx(sprite_rect),
		"Equipment hover glow shares fitted sprite bounds without intercepting input")
	motion(cargo_button.get_global_rect().get_center(), false)
	await settle()
	check(cargo_glow.visible and cargo_glow.material.get_shader_parameter("glow_color") == Color.WHITE,
		"Hovering fitted equipment shows a white silhouette glow")
	var label_start: Vector2 = screen.canvas.slot_callouts.hold.get_global_rect().get_center()
	motion(label_start, false)
	await settle()
	check(not cargo_glow.visible, "Leaving fitted equipment hides its glow")
	mouse_button(label_start, true)
	await process_frame
	motion(label_start + Vector2(20, 0), true)
	await process_frame
	check(not root.gui_is_dragging(), "Side label cannot start an equipment drag")
	mouse_button(label_start + Vector2(20, 0), false)
	await settle()
	check(state.owned_ship(ship_id).mounts.hold.uid == items.cargo_hold, "Dragging a side label cannot unequip its part")
	var art_before: Rect2 = screen.canvas.image_rect
	await click(screen.canvas.slot_buttons.hold)
	check(screen.slot_info.visible and not screen.stats_grid.visible and screen.slot_info.get_parsed_text().contains("Cargo Hold")
		and screen.slot_info.get_parsed_text().contains("10 cargo") and screen.slot_info.source_text.contains("XL Civic")
		and not screen.slot_info.source_text.contains("HP"), "Art click shows only full part name, size/type and effect, never component health")
	check(screen.canvas.image_rect == art_before, "Selecting a part never shifts the ship or mount geometry")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/art-only/cargo-details.png")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/cargo-art/fitted.png")
	await drag(cargo_button.get_global_rect().get_center(), screen.details_panel.get_global_rect().position + Vector2(2, 2))
	check(not state.owned_ship(ship_id).equipment_art.has("hold") and state.equipment_location(items.cargo_hold).is_empty(), "Dragging fitted cargo art back to stock removes the installed sprite")
	check(screen.stats_grid.visible and not screen.slot_info.visible, "Unequipping the selected part restores ship details")
	await click(screen.canvas.slot_buttons.hold)
	check(not screen.canvas.slot_glows.has("hold"), "Empty mounts have no equipment hover glow")
	check(screen.selected_slot.is_empty() and screen.stats_grid.visible, "An empty mount has no part details and keeps ship statistics")
	await fit_stock("cargo_hold", "hold")
	check(state.buy_chassis("drone"), "Buy general M passenger host")
	var transport_id := ship_id
	var drone_id: int = state.fleet[-1].id
	ship_id = drone_id
	screen.selected_ship_id = drone_id
	screen._queue_refresh()
	await settle()
	await fit_stock("passenger_cabin", "center")
	check(state.owned_ship(ship_id).hangar_summary().passengers == 4, "Equipped cabin updates passenger capacity")
	var inventory_count: int = state.equipment_inventory.size()
	await fit_stock("double_laser", "center")
	check(state.equipment_location(items.passenger_cabin).is_empty() and state.equipment_inventory.size() == inventory_count, "Replacement returns the old instance without creating copies")
	check(state.owned_ship(ship_id).hangar_summary().passengers == 0 and state.owned_ship(ship_id).hangar_summary().dps > 0, "Replacement updates both capacities and DPS")
	check(state.buy_chassis("corsair"), "Buy compatible M combat transfer host")
	var corsair_id: int = state.fleet[-1].id
	ship_id = corsair_id
	screen.selected_ship_id = corsair_id
	screen._queue_refresh()
	await settle()
	check(state.fit_equipment(corsair_id, "port", items.double_laser), "Transfer weapon to compatible combat host")
	await settle()
	await drag(screen.canvas.slot_buttons.port.get_global_rect().get_center(), screen.canvas.slot_buttons.starboard.get_global_rect().get_center())
	check(not state.owned_ship(ship_id).mounts.has("port") and state.owned_ship(ship_id).mounts.starboard.uid == items.double_laser, "Native drag moves installed equipment between slots")
	await fit_stock("shield_generator", "port")
	check(state.owned_ship(ship_id).hangar_summary().shields > 0, "Shields update after fitting")
	motion(screen.canvas.slot_buttons.port.get_global_rect().get_center(), false)
	await settle()
	var fallback_label: ResourceText = screen.canvas.slot_callouts.port.get_node("EquipmentName")
	check(fallback_label.get_theme_color("font_shadow_color") == Color.WHITE,
		"Hovering equipment without artwork highlights its floating name")
	motion(screen.canvas.slot_callouts.port.get_global_rect().get_center(), false)
	await settle()
	check(fallback_label.get_theme_color("font_shadow_color").a == 0,
		"Leaving artwork-free equipment clears its name glow")
	await drag(screen.canvas.slot_buttons.port.get_global_rect().get_center(), screen.stock.scroll.get_global_rect().get_center())
	check(not state.owned_ship(ship_id).mounts.has("port") and state.equipment_location(items.shield_generator).is_empty(), "Native drag back into stock unequips the instance")
	check(state.owned_ship(ship_id).hangar_summary().shields == 0, "Unequipping updates shields")
	ship_id = transport_id
	screen.selected_ship_id = transport_id
	screen._queue_refresh()
	await settle()
	var integrity: float = state.owned_ship(ship_id).hull_max
	await fit_stock("hull_plate", "aft")
	check(state.owned_ship(ship_id).hangar_summary().integrity_max > integrity, "Defensive equipment updates integrity")
	check(state.buy_equipment("mini_turret"), "Buy turret for anchored drag-scale checks")
	items["mini_turret"] = str(state.next_equipment_id - 1)
	await settle()
	await fit_stock("mini_turret", "fore")
	await drag(screen.canvas.slot_buttons.fore.get_global_rect().get_center(), screen.details_panel.get_global_rect().get_center())
	await camera_checks()
	await invalid_drop_checks()
	await layout_checks()
	check(state.load_run_checkpoint() and state.owned_ship(corsair_id).mounts.starboard.uid == items.double_laser, "Drag transactions survive checkpoint reload")
	check(state.owned_ship(ship_id).equipment_art.has("hold"), "Fitted equipment art rebuilds on checkpoint reload")
	await settle()
	await sale_checks()
	screen.queue_free()
	await settle()
	await create_timer(0.5).timeout
	print("HANGAR DRAG: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func click(control: Control) -> void:
	var position := control.get_global_rect().get_center()
	motion(position, false)
	mouse_button(position, true)
	await process_frame
	mouse_button(position, false)
	await settle()

func camera_button(position: Vector2, code: MouseButton, pressed: bool) -> void:
	motion(position, false)
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = code
	event.pressed = pressed
	root.push_input(event, true)
	if pressed and code in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var release := event.duplicate() as InputEventMouseButton
		release.pressed = false
		root.push_input(release, true)

func camera_checks() -> void:
	var before: Dictionary = state.hangar_snapshot()
	var board: Control = screen.canvas
	var pointer: Vector2 = board.global_position + board.size * 0.5
	var local_pointer: Vector2 = board.get_global_transform().affine_inverse() * pointer
	var normalized: Vector2 = (local_pointer - board.image_rect.position) / board.image_rect.size
	var card_rect: Rect2 = board.slot_callouts.fore.get_global_rect()
	var stars: Control = board.starfield
	var star_transform := stars.get_global_transform()
	var star_position: Vector2 = stars._get_star_position(stars._stars[0])
	camera_button(pointer, MOUSE_BUTTON_WHEEL_UP, true)
	await settle()
	check(is_equal_approx(board.zoom, 1.2), "Mouse wheel zooms the equipment assignment view")
	check(((local_pointer - board.image_rect.position) / board.image_rect.size).is_equal_approx(normalized), "Zoom anchors the ship point under the pointer")
	check(board.slot_callouts.fore.get_global_rect() == card_rect, "Equipment cards stay fixed and readable while zooming")
	check(stars.get_global_transform() == star_transform and stars._get_star_position(stars._stars[0]).is_equal_approx(star_position), "Fitting zoom leaves deterministic stars stationary")
	var image_before: Rect2 = board.image_rect
	camera_button(pointer, MOUSE_BUTTON_MIDDLE, true)
	motion(pointer + Vector2(12, 9), false)
	camera_button(pointer + Vector2(12, 9), MOUSE_BUTTON_MIDDLE, false)
	await settle()
	check(board.image_rect.position.is_equal_approx(image_before.position + Vector2(12, 9)), "Middle mouse pans ship and mount targets")
	check(not board.panning and board.slot_callouts.fore.get_global_rect() == card_rect, "Releasing pan preserves fixed card positions")
	var camera: Vector2 = board.camera
	var zoom: float = board.zoom
	await fit_stock("mini_turret", "fore")
	check(screen.canvas.camera.is_equal_approx(camera) and is_equal_approx(screen.canvas.zoom, zoom), "Refitting preserves ship camera")
	await drag(screen.canvas.slot_buttons.fore.get_global_rect().get_center(), screen.details_panel.get_global_rect().get_center())
	check(screen.canvas.camera.is_equal_approx(camera) and is_equal_approx(screen.canvas.zoom, zoom), "Unequipping preserves camera and scaled floating art")
	screen.active_tab = "MAP"
	screen._refresh()
	await settle()
	screen.active_tab = "SHIPS"
	screen._refresh()
	await settle()
	check(screen.canvas.camera.is_equal_approx(camera) and is_equal_approx(screen.canvas.zoom, zoom), "Tab changes preserve the fitting camera")
	screen.selected_ship_id = state.fleet[0].id
	screen._refresh()
	await settle()
	check(screen.canvas.camera == Vector2.ZERO and is_equal_approx(screen.canvas.zoom, 1.0), "Another ship starts with its own fitting camera")
	screen.selected_ship_id = ship_id
	screen._refresh()
	await settle()
	check(screen.canvas.camera.is_equal_approx(camera) and is_equal_approx(screen.canvas.zoom, zoom), "Returning to a ship restores its individual camera")
	screen._open_shop()
	await settle()
	board = screen.canvas
	pointer = board.global_position + board.size * 0.5
	motion(pointer, false)
	await settle()
	camera_button(pointer, MOUSE_BUTTON_WHEEL_UP, true)
	await settle()
	check(is_equal_approx(board.zoom, zoom), "Shop overlay prevents zooming the fitting canvas behind it")
	screen._open_shop()
	await settle()
	board = screen.canvas
	pointer = screen.stock.scroll.get_global_rect().get_center()
	camera_button(pointer, MOUSE_BUTTON_WHEEL_UP, true)
	await settle()
	check(is_equal_approx(board.zoom, zoom), "Stock wheel input does not zoom the fitting canvas")
	check(state.hangar_snapshot() == before, "Camera gestures and fit/unequip round trip preserve checkpoint contents")
	board = screen.canvas
	var row: Button = await prepare_stock("mini_turret")
	var start := row.get_global_rect().position + Vector2(row.size.x * 0.5, 8)
	motion(start, false)
	await process_frame
	mouse_button(start, true)
	await process_frame
	motion(start + Vector2(18, 0), true)
	await settle()
	check(root.gui_is_dragging(), "Native equipment drag starts after shop and stock camera-isolation checks")
	pointer = board.global_position + Vector2(board.size.x * 0.5, 2)
	motion(pointer, true)
	await settle()
	var preview: Control = get_first_node_in_group("equipment_drag_preview")
	var old_size: Vector2 = preview.sprite_rect.size
	camera_button(pointer, MOUSE_BUTTON_WHEEL_UP, true)
	await settle()
	check(preview.sprite_rect.size.is_equal_approx(old_size * 1.2), "Floating sprite tracks zoom changes during an active drag")
	mouse_button(pointer, false)
	await settle()
	check_callouts(false)
	board = screen.canvas
	for index in range(25):
		camera_button(pointer, MOUSE_BUTTON_WHEEL_UP, true)
	await settle()
	check(is_equal_approx(board.zoom, 4.0), "Fitting zoom stops at its upper limit")
	for index in range(40):
		camera_button(pointer, MOUSE_BUTTON_WHEEL_DOWN, true)
	await settle()
	check(is_equal_approx(board.zoom, 0.4), "Fitting zoom stops at its lower limit")
	board.camera = Vector2.ZERO
	board.zoom = 1.0
	board._update_view()
	screen._refresh()
	await settle()

func sale_checks() -> void:
	await prepare_stock("second_laser")
	var uid: String = items.second_laser
	var controls: Dictionary = screen.stock.sale_controls[uid]
	var original_position: Vector2 = controls.sell.get_global_rect().get_center()
	var before: Dictionary = state.hangar_snapshot()
	await click(controls.sell)
	check(screen.stock.pending_sale == uid and controls.summary.text == "Sell?" and controls.cancel.visible, "Coin click opens inline sale confirmation")
	check(controls.sell.action == "confirm" and controls.sell.get_global_rect().get_center().is_equal_approx(original_position), "Checkmark replaces the coin in exactly the same position")
	check(state.hangar_snapshot() == before and not root.gui_is_dragging(), "First click neither sells nor starts a drag")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/inline-sale/confirmation.png")
	await click(controls.cancel)
	check(screen.stock.pending_sale.is_empty() and controls.summary.text == controls.text and controls.sell.action == "sell", "Cancel restores the card's second row")
	check(state.hangar_snapshot() == before, "Cancel preserves inventory and credits")
	await click(controls.sell)
	screen.stock._change()
	await settle()
	check(screen.stock.pending_sale.is_empty(), "Filtering cancels pending sales")
	controls = screen.stock.sale_controls[uid]
	await click(controls.sell)
	var save_path: String = state.run_save_path
	state.run_save_path = "user://blocked-save/run.json"
	await click(controls.sell)
	check(state.hangar_snapshot() == before and screen.stock.pending_sale == uid and not controls.sell.disabled, "Failed sale save leaves the item and credits intact and permits retry/cancel")
	state.run_save_path = save_path
	screen.feedback.text = ""
	var instance: Dictionary = state.equipment_inventory[uid]
	var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
	var expected: int = state.credits + floori(float(item.price) * 0.5)
	await click(controls.sell)
	check(not state.equipment_inventory.has(uid) and state.credits == expected, "Checkmark sells exactly that physical instance for half catalog price")
	check(not screen.stock.row_buttons.has(uid) and screen.stock.filters.get_preferences() == screen.stock_preferences, "Sale refresh removes the card and preserves filters")
	check(not state.sell_equipment(uid) and state.credits == expected, "Sold item cannot pay twice")

func filter_checks() -> void:
	screen.stock.filters.set_preferences({"categories": ["offense"], "sizes": ["S", "M"]})
	screen.stock._change()
	check(screen.stock.visible_uids.size() == 3, "Category filter includes selected small and medium weapons")
	screen.stock.filters.size_range.set_range(1, 1, true)
	await settle()
	check(screen.stock.visible_uids.size() == 2, "Inclusive size range combines with category")
	screen.stock.filters.size_range.set_range(0, 1, true)
	await settle()
	check(screen.stock.visible_uids.size() == 3, "Inclusive range includes both small and medium")
	await click(screen.stock.filters.categories.defense)
	check(screen.stock.visible_uids.size() == 5, "Multiple category checkboxes can be selected together")
	screen.stock.filters.categories.offense.button_pressed = false
	check(screen.stock.visible_uids.size() == 2 and items.hull_plate in screen.stock.visible_uids and items.shield_generator in screen.stock.visible_uids, "Unchecking one category preserves other choices")
	screen.stock.filters.categories.defense.button_pressed = false
	check(screen.stock.visible_uids.is_empty(), "No checked categories shows no matches")
	screen.stock.filters.set_preferences({"sizes": []})
	screen.stock._change()
	check(screen.stock.filters.get_preferences().sizes == SlotCatalog.SIZES,
		"Empty historical size preferences normalize to the full inclusive range")
	screen.stock.filters.set_preferences({})
	screen.stock._change()
	var previous_price := -1
	var previous_uid := -1
	for uid: String in screen.stock.visible_uids:
		var instance: Dictionary = state.equipment_inventory[uid]
		var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
		check(int(item.price) >= previous_price, "Stock is always ordered by ascending credit price")
		if int(item.price) == previous_price:
			check(int(uid) > previous_uid, "Equal-price stock uses stable instance-ID ties")
		previous_price = int(item.price)
		previous_uid = int(uid)
	screen.stock.filters.set_preferences({"categories": ["offense", "defense"], "sizes": ["M"]})
	screen.stock._change()
	var preferences: Dictionary = screen.stock.filters.get_preferences()
	var order: Array = screen.stock.visible_uids.duplicate()
	var data: Dictionary = state.hangar_snapshot()
	data.ships[0].hull_hp -= 1
	check(state._commit_hangar(data), "Damage hull while preserving stock instances")
	await settle()
	check(screen.stock.filters.get_preferences() == preferences, "Checkbox preferences survive state refresh")
	check(screen.stock.visible_uids == order, "Persistent hull damage does not change catalog-price ordering")
	for uid: String in screen.stock.visible_uids:
		var item := SlotCatalog.find_equipment(state.equipment_inventory[uid].equipment_id, int(state.equipment_inventory[uid].rank))
		check(screen.stock.sale_controls[uid].summary.text == "%s %s" % [item.size, item.type.capitalize()],
			"Stock summary contains only size/type without HP or condition")

func prepare_stock(key: String) -> Button:
	var instance: Dictionary = state.equipment_inventory[items[key]]
	var item := SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank))
	screen.stock.filters.set_preferences({"categories": [item.type], "sizes": [item.size]})
	screen.stock._change()
	screen.stock.scroll.scroll_vertical = 0
	await settle()
	if key == "cargo_hold":
		var thumbnail: TextureRect = screen.stock.row_buttons[items[key]].find_child("EquipmentThumbnail", true, false)
		check(thumbnail != null and SurfaceArt.diffuse(thumbnail.texture).resource_path == "res://assets/equipment/cargo_xl_d.png", "Cargo stock row includes the supplied art thumbnail")
	return screen.stock.row_buttons[items[key]]

func fit_stock(key: String, slot: String) -> void:
	var row: Button = await prepare_stock(key)
	var before: int = state.credits
	var target: Button = screen.canvas.slot_buttons[slot]
	await drag(row.get_global_rect().get_center(), target.get_global_rect().get_center())
	check(state.owned_ship(ship_id).mounts.get(slot, {}).get("uid") == items[key], "Native stock drag fits " + key)
	check(state.credits == before and items[key] not in screen.stock.visible_uids, "Fitting is free and removes exactly the fitted stock row")
	check(screen.slot_info.visible and not screen.stats_grid.visible and screen.slot_info.source_text.contains(SlotCatalog.find_equipment(state.equipment_inventory[items[key]].equipment_id).name)
		and not screen.slot_info.get_parsed_text().replace("Shield Generator", "").to_lower().contains("shield")
		and not screen.slot_info.get_parsed_text().to_lower().contains("repair"), "Selecting fitted equipment replaces ship stats with icon-rendered part details")
	var empty_space: Vector2 = screen.canvas.global_position + Vector2(screen.canvas.size.x * 0.5, 2)
	motion(empty_space, false)
	mouse_button(empty_space, true)
	mouse_button(empty_space, false)
	await settle()
	check(screen.selected_slot.is_empty() and screen.stats_grid.visible and not screen.slot_info.visible, "Empty-space click restores ship details")
	var summary: Dictionary = state.owned_ship(ship_id).hangar_summary()
	var rendered := text_under(screen.stats_grid)
	for expected in ["Hull %d / %d" % [roundi(summary.integrity), roundi(summary.integrity_max)]]:
		check(rendered.contains(expected), "Visible stats refresh after a real mouse drop")
	check(rendered.contains("DPS ") == (summary.dps > 0), "DPS details appear only for positive mounted DPS")
	check(screen.stats_grid.bars.has("shields") == (summary.shields > 0), "Shield bar appears only with positive shield capacity")
	if summary.dps > 0:
		check(rendered.contains("DPS %d" % roundi(summary.dps)), "Positive DPS shows rounded mounted value")
	if summary.shields > 0:
		check(rendered.contains("Shields %d" % roundi(summary.shields)), "Positive shields show rounded capacity")
	for capacity: String in ["cargo", "passengers"]:
		var title := "Cargo" if capacity == "cargo" else "Passengers"
		check(rendered.contains(title + "\n") == (summary[capacity] > 0), "Show %s only with operational capacity" % capacity)
		if summary[capacity] > 0:
			check(rendered.contains("%s\n%d" % [title, summary[capacity]]), "Positive %s capacity shows exact value" % capacity)

func drag(start: Vector2, finish: Vector2) -> void:
	var original_art: Rect2 = screen.canvas.image_rect
	motion(start, false)
	await process_frame
	mouse_button(start, true)
	await process_frame
	motion(start + Vector2(18, 0), true)
	await process_frame
	check(root.gui_is_dragging(), "Mouse motion starts a native Godot drag")
	var data: Dictionary = root.gui_get_drag_data()
	var installed: bool = not state.equipment_location(data.uid).is_empty()
	await settle()
	check_callouts(true)
	check(screen.canvas.image_rect == original_art, "Showing empty cards during a drag does not rescale the ship")
	var floating_point: Vector2 = screen.canvas.global_position + Vector2(screen.canvas.size.x * 0.5, 2)
	motion(floating_point, true)
	await settle()
	var floating: Control = get_first_node_in_group("equipment_drag_preview")
	var item: Dictionary = SlotCatalog.find_equipment(state.equipment_inventory[data.uid].equipment_id, int(state.equipment_inventory[data.uid].rank))
	var reference: Dictionary = {}
	for slot: Dictionary in screen.canvas._slots:
		if screen.canvas.slot_buttons[slot.id].equipment_uid == data.uid:
			reference = slot
			break
		if reference.is_empty() and SlotCatalog.compatible(slot, item):
			reference = slot
	if not reference.is_empty() and floating.texture != null:
		var mount_bounds: Rect2 = screen.canvas.get_global_transform() * screen.canvas.slot_rect(reference)
		var expected_art := SlotCatalog.fitted_art_rect(floating.texture, mount_bounds, item.get("art_mount", []))
		var actual_art: Rect2 = floating.get_global_transform() * floating.sprite_rect
		check(actual_art.size.distance_to(expected_art.size) < 0.001, "Floating sprite matches fitted ship scale, including mount anchors")
		check(floating.target_slot.is_empty(), "Floating scale check is outside all mount targets")
	check(screen.stock.unequip_mode == installed, "Only installed-equipment drags replace stock with the unequip target")
	if installed:
		await settle()
		check(screen.stock.unequip_hint.visible and not screen.stock.filters.visible and not screen.stock.scroll.visible, "Unequip drag hides the normal stock content")
		check(screen.stock.unequip_hint.get_global_rect().get_center().distance_to(screen.details_panel.get_global_rect().get_center()) < 3, "Unequip instruction is centered in the right panel")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/unequip-panel/active.png")
	motion(finish, true)
	await settle()
	var target_id: String = screen.canvas._slot_at(screen.canvas.get_global_transform().affine_inverse() * finish)
	var preview_size := Vector2.ZERO
	if Transfer.can_fit(screen.canvas.owned_id, target_id, data):
		var preview: Control = get_first_node_in_group("equipment_drag_preview")
		check(preview != null and preview.target_slot == target_id, "Drag preview recognizes the hovered art mount")
		var target_slot: Dictionary = screen.canvas._slots.filter(func(slot: Dictionary) -> bool: return slot.id == target_id)[0]
		var actual: Rect2 = preview.get_global_transform() * preview.bounds
		var expected: Rect2 = screen.canvas.get_global_transform() * screen.canvas.slot_rect(target_slot)
		preview_size = expected.size
		check(actual.position.is_equal_approx(expected.position) and actual.size.is_equal_approx(expected.size), "Drag preview matches the actual fitted mount bounds before release")
	if DisplayServer.get_name() != "headless" and root.gui_is_dragging() and root.gui_get_drag_data().get("uid") == items.cargo_hold:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/cargo-art/drag.png")
	mouse_button(finish, false)
	await settle()
	if preview_size != Vector2.ZERO and state.owned_ship(ship_id).mounts.get(target_id, {}).get("uid") == data.uid:
		var fitted_slot: Dictionary = screen.canvas._slots.filter(func(slot: Dictionary) -> bool: return slot.id == target_id)[0]
		check(screen.canvas.slot_rect(fitted_slot).size.distance_to(preview_size) < 0.001, "Fitted size stays equal to its preview after inventory refresh")
	check(not screen.stock.unequip_mode and screen.stock.filters.visible and screen.stock.scroll.visible and not screen.stock.unequip_hint.visible, "Stock content returns after completed or cancelled drags")
	check_callouts(false)
	check(screen.canvas.image_rect == original_art, "Hiding empty cards after release does not rescale the ship")

func check_callouts(dragging: bool) -> void:
	for id: String in screen.canvas.slot_callouts:
		var occupied: bool = not screen.canvas.slot_buttons[id].equipment_uid.is_empty()
		check(screen.canvas.slot_callouts[id].visible == occupied, "Only occupied mount cards are visible, including during drags: %s" % dragging)

func motion(position: Vector2, down: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = position - last_mouse
	last_mouse = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	root.push_input(event, true)

func mouse_button(position: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	root.push_input(event, true)

func invalid_drop_checks() -> void:
	var row: Button = await prepare_stock("second_laser")
	var before: Dictionary = state.hangar_snapshot()
	await drag(row.get_global_rect().get_center(), screen.canvas.slot_buttons.fore.get_global_rect().get_center())
	check(state.hangar_snapshot() == before, "Wrong-size native drop does not mutate ownership or credits")
	row = await prepare_stock("second_laser")
	await drag(row.get_global_rect().get_center(), Vector2(40, 20))
	check(state.hangar_snapshot() == before, "Cancelled drag leaves the checkpoint unchanged")
	var stale := Transfer.payload(items.second_laser)
	stale.run_id = "old-run"
	check(not screen.canvas.slot_buttons.port._can_drop_data(Vector2.ZERO, stale), "Reject stale drag data from another run")
	var data := before.duplicate(true)
	data.equipment[items.cargo_hold]["load"] = {"kind": "cargo", "quantity": 10, "unit_value": 3, "origin": 0}
	check(state._commit_hangar(data), "Loaded equipment fixture")
	await settle()
	check(not Transfer.can_store(Transfer.payload(items.cargo_hold)), "Occupied hold cannot be warehoused")
	var hull: Dictionary = state.hangar_snapshot()
	for ship: Dictionary in hull.ships:
		if ship.id == ship_id:
			ship.hull_hp -= 1
	check(state._commit_hangar(hull), "Damaged hull fixture")
	await settle()
	check(state.owned_ship(ship_id).hangar_summary().cargo == 10 and HangarTrade.has_load(state.equipment_inventory[items.cargo_hold]),
		"Damaged hull keeps fitted cargo capacity and occupied load operational")
	check(not Transfer.can_store(Transfer.payload(items.cargo_hold)), "Hull damage never bypasses loaded-equipment restrictions")
	hull = state.hangar_snapshot()
	hull.equipment[items.cargo_hold]["load"] = {}
	check(state._commit_hangar(hull), "Delivered hold fixture for failed-save rollback")
	var blocked := FileAccess.open("user://blocked-save", FileAccess.WRITE)
	blocked.store_string("not a directory")
	blocked.close()
	var save_path: String = state.run_save_path
	state.run_save_path = "user://blocked-save/run.json"
	before = state.hangar_snapshot()
	screen.canvas.slot_buttons.hold._drop_data(Vector2.ZERO, Transfer.payload(items.cargo_hold))
	check(state.hangar_snapshot() == before, "Failed-save drop rolls back the entire transaction")
	state.run_save_path = save_path

func layout_checks() -> void:
	screen.feedback.text = ""
	screen.stock.filters.set_preferences({})
	screen.stock._change()
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		var turret_row: Button = await prepare_stock("mini_turret")
		var pointer: Vector2 = screen.canvas.global_position + Vector2(screen.canvas.size.x * 0.5, 2)
		camera_button(pointer, MOUSE_BUTTON_WHEEL_UP, true)
		await settle()
		await drag(turret_row.get_global_rect().get_center(), Vector2(40, 20))
		camera_button(pointer, MOUSE_BUTTON_WHEEL_DOWN, true)
		await settle()
		check(screen.get_global_rect().encloses(screen.stock.get_global_rect()), "Stock remains on screen")
		check(screen.get_global_rect().encloses(screen.stats_grid.get_global_rect()), "Ship stats remain on screen")
		var bottom: Control = screen.stats_grid.get_parent()
		var art_before: Rect2 = screen.canvas.image_rect
		check(bottom.custom_minimum_size.y == 128 and bottom.get_rect().size.y == 128, "Ship/part detail area keeps fixed height at every resolution")
		for key: String in screen.stats_grid.bars:
			check(bottom.get_global_rect().encloses(screen.stats_grid.bars[key].get_global_rect()), "Every stat bar fits fixed bottom area")
		await click(screen.canvas.slot_buttons.hold)
		check(screen.canvas.image_rect == art_before and bottom.get_rect().size.y == 128
			and not screen.stats_grid.visible and screen.slot_info.visible and not screen.slot_info.source_text.contains("HP"),
			"Selected equipment replaces all bars without shifting fitting art or bottom geometry")
		await click(screen.canvas.slot_buttons.fore)
		check(screen.canvas.image_rect == art_before and screen.stats_grid.visible, "Empty mount restores bars without shifting fitting geometry")
		check(not screen.stock.get_global_rect().intersects(screen.canvas.get_global_rect()), "Stock and ship have separate drag areas")
		var summary: Dictionary = state.owned_ship(ship_id).hangar_summary()
		check(screen.stats_grid.bars.size() == 3 + int(summary.shields > 0)
			and screen.stats_grid.get_child_count() == 3 + int(summary.shields > 0) + int(summary.dps > 0) + int(summary.cargo > 0) + int(summary.passengers > 0),
			"Shields, DPS, cargo and passengers appear independently only with positive values")
		for uid: String in screen.stock.sale_controls:
			var controls: Dictionary = screen.stock.sale_controls[uid]
			var card: Button = screen.stock.row_buttons[uid]
			check(card.get_global_rect().encloses(controls.sell.get_global_rect()), "Sell icon stays inside its card at every tested resolution")
			check(controls.sell.focus_mode == Control.FOCUS_NONE and controls.sell.tooltip_text.is_empty(), "Sell icon has no keyboard focus or tooltip")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/drag-hangar/hangar-%dx%d.png" % [resolution.x, resolution.y])

func text_under(node: Node) -> String:
	var result: String = node.source_text if node is ResourceText else (node.text if node is Label else "")
	for child in node.get_children():
		result += "\n" + text_under(child)
	return result
