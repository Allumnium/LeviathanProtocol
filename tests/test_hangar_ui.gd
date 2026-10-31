extends SceneTree

var checks := 0
var failures := 0
var state: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func labels_under(node: Node) -> String:
	var result: String = node.text if node is Label else ""
	for child in node.get_children():
		result += "\n" + labels_under(child)
	return result

func check_callouts(board: Control) -> void:
	var placed: Array[Rect2] = []
	var owned: HangarShip = state.owned_ship(board.owned_id)
	for id: String in board.slot_callouts:
		var card: Control = board.slot_callouts[id]
		var rect := card.get_rect()
		check(Rect2(Vector2.ZERO, board.size).encloses(rect), "Side callout fits canvas")
		check(not rect.intersects(board.image_rect), "Side text never covers ship or slot art")
		check(not placed.any(func(other: Rect2) -> bool: return rect.intersects(other)), "Side callouts never overlap")
		placed.append(rect)
		var label: Label = card.get_node("EquipmentName")
		var instance: Dictionary = owned.mounts.get(id, {})
		var slot: Dictionary = owned.chassis.slots.filter(func(value: Dictionary) -> bool: return value.id == id)[0]
		var expected: String = board._empty_label(slot) if instance.is_empty() else SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank)).name
		check(label.text == expected and not label.clip_text, "Callout uses the complete equipment name")
		check(label.get_line_count() == 1 and not card.has_node("MountName"), "Mount callouts have exactly one line, with no extra headings")
		check(Rect2(Vector2.ZERO, card.size).encloses(label.get_rect()), "Equipment text stays within its card")
		check(card.focus_mode == Control.FOCUS_NONE and card.tooltip_text.is_empty(), "Callout has no keyboard focus or tooltip")
		check(not card is Button and not card.has_method("_get_drag_data"), "Side callout is display-only")

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	state = root.get_node("GameState")
	state.run_save_path = "user://hangar-ui.json"
	check(state.start_new_run(1, 151), "UI run starts")
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await settle()
	check(not menu.has_node("CenterContainer/MenuButtons/ShipDesignerButton"), "Main menu has no Designer")
	check(menu.continue_button.visible and not menu.continue_button.disabled, "Continue discovers physical checkpoint")
	menu._on_continue_pressed()
	await settle()
	var screen: Control = current_scene
	await settle()
	check(screen.active_tab == "FLEET", "Fleet is the first/default tab")
	screen.selected_ship_id = 0
	screen.active_tab = "SHIPS"
	screen._refresh()
	await settle()
	check(screen.canvas != null, "Actual game opens physical hangar")
	var flagship_row: Button = screen.roster.find_child("Ship1", true, false)
	check(screen.selected_ship_id == state.fleet[0].id and state.fleet[0].flagship, "Ships selects the flagship when no ship is selected")
	check(flagship_row.text == state.fleet[0].display_name and flagship_row.icon != null and flagship_row.icon.resource_path == "res://assets/flag.png", "Flagship row uses the supplied flag artwork instead of a generated icon")
	check(screen.find_child("ScienceIcon", true, false) == null and screen.header.text == str(state.credits), "Header shows credits without a research-point balance")
	var preview: Control = load("res://scripts/fleet_ship_preview.gd").new()
	preview.owned = state.fleet[0]
	preview.size = Vector2(64, 64)
	root.add_child(preview)
	await settle()
	check(preview.patterns.is_empty(), "Physical preview skips the retired square recipe catalog")
	preview.queue_free()
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		var buttons: Dictionary = screen.canvas.slot_buttons
		check_callouts(screen.canvas)
		var placed: Array[Rect2] = []
		for id in buttons:
			var button: Button = buttons[id]
			check(not button is OptionButton, "Mounts have no dropdowns")
			check(button.focus_mode == Control.FOCUS_NONE and button.tooltip_text.is_empty(), "Mount has no focus box or tooltip")
			var rect := button.get_global_rect()
			check(screen.canvas.get_global_rect().encloses(rect), "Mount stays in canvas")
			check(not placed.any(func(other: Rect2) -> bool: return rect.intersects(other)), "Mount controls never overlap")
			placed.append(rect)
		for uid: String in screen.stock.visible_uids:
			check(state.equipment_inventory.has(uid) and state.equipment_location(uid).is_empty(), "Stock offers owned uninstalled instances")
		check(screen.get_global_rect().encloses(screen.details.get_global_rect()), "Details fit screen")
		check(screen.get_global_rect().encloses(screen.roster.get_global_rect()), "Roster fits screen")
	root.size = Vector2i(1280, 720)
	await settle()
	check(state.buy_equipment("mini_turret"), "Buy gear through actual state")
	await settle()
	var uid := str(state.next_equipment_id - 1)
	var button: Button = screen.canvas.slot_buttons.aft_port
	check(uid in screen.stock.visible_uids, "New purchase appears in stock")
	button._drop_data(Vector2.ZERO, preload("res://scripts/hangar_equipment_transfer.gd").payload(uid))
	await settle()
	check(state.owned_ship(1).mounts.aft_port.uid == uid, "Drop target equips physical item")
	check(state.equipment_location("1").is_empty(), "Replaced physical item returns to stock")
	state.credits = 5000
	check(state.save_run_checkpoint(), "Fund chassis layout fixtures")
	for chassis in SlotCatalog.chassis():
		if int(chassis.command) > 0:
			continue
		check(state.buy_chassis(chassis.id), "Buy " + chassis.name + " for actual hangar review")
		screen.selected_ship_id = state.fleet[-1].id
		await settle()
		for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.size = resolution
			await settle()
			var rectangles: Array[Rect2] = []
			check_callouts(screen.canvas)
			for mount: Button in screen.canvas.slot_buttons.values():
				var rect := mount.get_global_rect()
				check(screen.canvas.get_global_rect().encloses(rect), chassis.name + " mount in canvas")
				check(not rectangles.any(func(other: Rect2) -> bool: return rect.intersects(other)), chassis.name + " mounts do not overlap")
				rectangles.append(rect)
		check(state.salvage_hangar_ship(screen.selected_ship_id), "Immediate fixture salvage")
		await settle()
	root.size = Vector2i(1280, 720)
	await settle()
	screen.selected_ship_id = 1
	screen._refresh()
	await settle()
	screen._open_shop()
	await settle()
	check(screen.shop.visible, "Shop opens")
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		check(screen.shop.get_global_rect().is_equal_approx(screen.center.get_global_rect()), "Buy panel covers exactly the center area")
		check(not screen.shop.is_in_group("modal_ui") and not screen.shop.get_global_rect().intersects(screen.details_panel.get_global_rect()), "Buy panel leaves stock and roster accessible without a modal backdrop")
		check(screen.find_child("ScienceIcon", true, false) == null, "No research-point resource appears in the header")
		for purchase: Button in screen.shop_rows.get_children():
			check(purchase.size.x <= screen.shop.size.x, "Purchase text fits center panel width")
		for filters: Control in [screen.stock.filters, screen.shop_filters]:
			for checkbox: CheckBox in filters.find_children("*", "CheckBox", true, false):
				check(filters.get_global_rect().encloses(checkbox.get_global_rect()), "Filter checkbox fits its panel at each supported resolution")
				check(checkbox.button_group == null and checkbox.focus_mode == Control.FOCUS_NONE, "Checkboxes are independent and excluded from focus cycling")
	screen._shop_ships()
	await settle()
	check(screen.buy_mode == "SHIPS" and screen.shop_rows.get_child_count() == 5, "Center panel lists purchasable chassis")
	check(not screen.shop_filters.visible, "Chassis buying has no equipment filters")
	var previous_chassis_price := -1
	for row: HBoxContainer in screen.shop_rows.get_children():
		var purchase: Button = row.get_child(1)
		var price := int(purchase.text.split(" | ")[1])
		check(price >= previous_chassis_price, "Chassis buying is always ordered by ascending credits")
		previous_chassis_price = price
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/hangar/ui-buy-ships.png")
	screen._shop_equipment()
	await settle()
	check(screen.shop_filters.visible and screen.shop_filters.categories.size() == 4
		and screen.shop_filters.sizes.size() == 4, "Equipment shop has a checkbox for each category and size")
	check(screen.shop.find_children("*", "LineEdit", true, false).is_empty()
		and screen.stock.find_children("*", "LineEdit", true, false).is_empty()
		and screen.shop.find_children("*", "OptionButton", true, false).is_empty()
		and screen.stock.find_children("*", "OptionButton", true, false).is_empty(),
		"Stock and Buy have no search or single-choice controls")
	var unfiltered_shop_count: int = screen.shop_rows.get_child_count()
	screen.shop_filters.set_preferences({"categories": ["offense"], "sizes": ["S"]})
	screen.shop_filters.changed.emit(screen.shop_filters.get_preferences())
	check(screen.shop_rows.get_child_count() > 0 and screen.shop_rows.get_child_count() < unfiltered_shop_count,
		"Shop category and size filters narrow equipment")
	for purchase: Button in screen.shop_rows.get_children():
		check(purchase.text.contains("Offense S"), "Shop lists only checked categories and sizes")
	check(screen.stock.filters.get_preferences() == screen.shop_filters.get_preferences(), "Buy checkboxes synchronize visible stock filters")
	screen.shop_filters.sizes.M.button_pressed = true
	screen.shop_filters.categories.defense.button_pressed = true
	check(screen.shop_rows.get_child_count() > 1 and screen.shop_rows.get_child_count() < unfiltered_shop_count, "Shop allows multiple categories and sizes at once")
	screen.stock.filters.categories.civic.button_pressed = true
	check(screen.stock.filters.get_preferences() == screen.shop_filters.get_preferences(), "Stock checkboxes synchronize visible Buy filters")
	var preferences: Dictionary = screen.shop_filters.get_preferences()
	screen._shop_ships()
	check(not screen.shop_filters.visible and screen.shop_rows.get_child_count() == 5, "Equipment checkbox choices never filter chassis")
	screen._refresh()
	await settle()
	check(screen.buy_mode == "SHIPS" and not screen.shop_filters.visible, "Chassis mode keeps equipment filters hidden after refresh")
	screen._shop_equipment()
	check(screen.shop_filters.get_preferences() == preferences, "Switching back to equipment restores checkbox selections")
	screen.shop_filters.set_preferences({"categories": []})
	screen.shop_filters.changed.emit(screen.shop_filters.get_preferences())
	check(screen.shop_rows.get_child_count() == 1 and screen.shop_rows.get_child(0) is Label, "Empty checkbox selection shows No matches")
	screen.shop_filters.set_preferences({})
	screen.shop_filters.changed.emit(screen.shop_filters.get_preferences())
	var previous_equipment_price := -1
	for purchase: Button in screen.shop_rows.get_children():
		var price := int(purchase.text.split(" | ")[1])
		check(price >= previous_equipment_price, "Equipment buying is always ordered by ascending credits")
		previous_equipment_price = price
	var inventory_before: int = state.equipment_inventory.size()
	for purchase: Button in screen.shop_rows.get_children():
		if not purchase.disabled:
			purchase.pressed.emit()
			break
	await settle()
	check(state.equipment_inventory.size() == inventory_before + 1 and screen.buy_open and screen.shop != null, "Purchase updates stock while center shop stays open")
	check(screen.shop_filters.is_unfiltered() and screen.stock.filters.is_unfiltered(), "Purchase preserves checkbox selections")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/hangar/ui-buy-equipment.png")
	screen.roster.find_child("BuyToggle", true, false).pressed.emit()
	await settle()
	check(not screen.buy_open and screen.shop == null and screen.canvas != null, "Buy button toggles back to ship fitting")
	screen.roster.find_child("BuyToggle", true, false).pressed.emit()
	await settle()
	var close: TextureButton = screen.shop.find_child("CloseX", true, false)
	check(close.texture_normal != null, "Shared close artwork")
	check(screen.shop.get_global_rect().encloses(close.get_global_rect()), "Shared X lies within modal")
	close.pressed.emit()
	await settle()
	check(screen.shop == null, "X closes shop")
	check(screen.stock != null and not screen.has_method("_open_stock"), "Stock selling has no Manage panel")
	var science_fixture: Dictionary = state.hangar_snapshot()
	science_fixture.research.research_ids.append("laboratory_ii")
	science_fixture.research.research_ids.append("laboratory_iii")
	science_fixture.research.story_flags["boss_i_defeated"] = true
	check(state._commit_hangar(science_fixture), "Late-game research UI fixture")
	check(state.buy_chassis("frigate"), "Science chassis UI fixture")
	var science_ship: int = state.fleet[-1].id
	check(state.buy_equipment("research_lab", 2) and state.fit_equipment(science_ship, "center", str(state.next_equipment_id - 1)), "Lab II UI fixture")
	check(state.buy_equipment("research_lab", 3) and state.fit_equipment(1, "hold", str(state.next_equipment_id - 1)), "Lab III UI fixture")
	await settle()
	screen.selected_ship_id = 1
	for title in ["RESEARCH", "FLEET", "MAP", "SHIPS"]:
		screen.active_tab = title
		screen._refresh()
		await settle()
		check(screen.center.get_child_count() > 0, title + " is connected")
		if title == "RESEARCH":
			check(labels_under(screen.roster).contains("6 RP/day") and labels_under(screen.roster).contains("1 x Lab III"), "Native production panel explains ranked lab output")
			screen.center.get_child(0)._select("laboratory_iii")
			await settle()
			check(labels_under(screen.details).contains("3 RP/day"), "Native research details show Lab III output")
		if title == "MAP":
			check(screen.center.get_child(0).get_script().resource_path == "res://scripts/graph_view.gd", "Pannable campaign map retained")
			screen._select_destination(state.get_reachable_nodes(0)[0])
			await settle()
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/hangar/ui-%s.png" % title.to_lower())
	var target: int = state.get_reachable_nodes(0)[0]
	check(state.travel_to(target), "UI travel")
	screen.queue_free()
	await settle()
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	await create_timer(0.5).timeout
	check(battle.simulation.player.owned_ship is HangarShip, "Actual battle uses physical ship")
	check(battle.visuals._part_patterns_by_type.is_empty() and battle.visuals._thruster_frames_by_type.is_empty(), "Physical battle skips square renderer initialization")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/hangar/ui-battle.png")
	battle.simulation.phase = BattleSimulation.Phase.VICTORY
	battle._finish_battle(true)
	await settle()
	check(battle._report_open and not state.battle_pending, "Actual report and settlement")
	battle.queue_free()
	await settle()
	print("HANGAR UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
