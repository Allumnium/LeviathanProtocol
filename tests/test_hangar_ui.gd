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
	var result: String = node.source_text if node is ResourceText else (node.text if node is Label else "")
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
		check(not rect.intersects(board.art_rect()), "Side text never covers ship or slot art")
		check(not placed.any(func(other: Rect2) -> bool: return rect.intersects(other)), "Side callouts never overlap")
		placed.append(rect)
		var label: ResourceText = card.get_node("EquipmentName")
		check(label.horizontal_alignment == (HORIZONTAL_ALIGNMENT_RIGHT if card.get_meta("left_rail") else HORIZONTAL_ALIGNMENT_LEFT),
			"Equipment names align toward their ship-side connector")
		var instance: Dictionary = owned.mounts.get(id, {})
		var slot: Dictionary = owned.chassis.slots.filter(func(value: Dictionary) -> bool: return value.id == id)[0]
		var expected: String = "" if instance.is_empty() else SlotCatalog.find_equipment(instance.equipment_id, int(instance.rank)).name
		check(card.visible == not instance.is_empty(), "Empty mounts never show labels or connectors")
		check(label.source_text == expected and not label.clip_contents, "Callout uses the complete equipment name")
		check((instance.is_empty() or label.get_line_count() == 1) and not card.has_node("MountName"), "Occupied mount callouts have exactly one line, with no extra headings")
		check(board.get_theme_color("connector_color", "SlotCanvas") == Color.WHITE, "Every connector uses shared opaque white")
		var transform: Transform2D = board.get_viewport().get_final_transform() * board.get_global_transform_with_canvas()
		for point: Vector2 in board._connector_points(card, board.slot_rect(slot)):
			var pixel := transform * point - Vector2(0.5, 0.5)
			check(pixel.is_equal_approx(pixel.round()), "Connector vertices align to physical pixel centers")
		check(Rect2(Vector2.ZERO, card.size).encloses(label.get_rect()), "Equipment text stays within its card")
		check(card.focus_mode == Control.FOCUS_NONE and card.tooltip_text.is_empty(), "Callout has no keyboard focus or tooltip")
		check(not card is Button and not card.has_method("_get_drag_data"), "Side callout is display-only")
		check(not card is Panel and not card is PanelContainer,
			"Mount callout has no panel or frame")
		check(label.get_theme_color("default_color") == Color.WHITE,
			"Floating equipment names use opaque white text")
		check(label.get_theme_font_size("normal_font_size") == 10,
			"Floating equipment names use the smaller shared font size")

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
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/hangar/ui-menu.png")
		menu._on_play_pressed()
		await settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/hangar/ui-setup.png")
		menu._on_setup_back_requested()
		await settle()
	menu._on_continue_pressed()
	await settle()
	var screen: Control = current_scene
	await settle()
	check(screen.name == "Hangar" and screen.active_tab == "FLEET",
		"Continue opens the existing hangar screen on the Fleet travel page")
	check(screen.travel_controls != null, "Fleet page includes compact expedition controls")
	screen.selected_ship_id = 0
	screen.active_tab = "SHIPS"
	screen._refresh()
	await settle()
	check(screen.canvas != null, "Actual game opens physical hangar")
	var flagship_row: Button = screen.roster.find_child("Ship1", true, false)
	check(screen.selected_ship_id == state.fleet[0].id and state.fleet[0].flagship, "Ships selects the flagship when no ship is selected")
	check(flagship_row != null and flagship_row.text.is_empty() and flagship_row.get_parent().name == "ShipTiles",
		"Ships roster shows ship sprites instead of a text list")
	var audio := root.get_node("AudioManager")
	check(flagship_row.pressed.is_connected(Callable(audio, "play_ui_sfx").bind(&"select_tab")),
		"Ship roster selection uses the former tab sound")
	var tabs: HBoxContainer = screen.tabs
	check(tabs.get_parent() == screen.header_wallet.get_parent() and tabs.get_index() == 0,
		"Tabs align left in the shared header, with credits on the right")
	check(not screen.settings_dialog.visible, "Hangar Settings starts closed")
	var settings_button: TextureButton = screen.find_child("SettingsButton", true, false)
	check(settings_button.texture_normal.resource_path == "res://assets/ui/Btn_RandomName_n.png"
		and settings_button.texture_pressed.resource_path == "res://assets/ui/Btn_RandomName_p.png",
		"Settings uses the requested circular button artwork")
	settings_button.pressed.emit()
	await settle()
	check(screen.settings_dialog.visible and current_scene == screen and not state.run_id.is_empty(),
		"Gear opens Settings without leaving the run")
	var settings_close: TextureButton = screen.settings_dialog.get_node("CloseX")
	check(settings_close.position == Vector2(screen.settings_dialog.size.x - settings_close.size.x - 1, 1),
		"Settings close artwork sits one pixel from the top and right edges")
	settings_close.pressed.emit()
	await settle()
	check(not screen.settings_dialog.visible, "Shared close dismisses hangar Settings")
	for tab: Button in tabs.get_children():
		var normal_style := tab.get_theme_stylebox("normal") as StyleBoxTexture
		var pressed_style := tab.get_theme_stylebox("pressed") as StyleBoxTexture
		var hover_style := tab.get_theme_stylebox("hover") as StyleBoxTexture
		check(normal_style.texture.atlas.resource_path == "res://assets/ui/Btn_CharacterMenu_n.png"
			and pressed_style.texture.atlas.resource_path == "res://assets/ui/Btn_CharacterMenu_p.png"
			and hover_style.modulate_color.r > normal_style.modulate_color.r,
			"Tabs use CharacterMenu art and a lighter hover state: " + tab.text)
		check(tab.pressed.is_connected(Callable(audio, "play_ui_sfx").bind(&"accept")),
			"Tab switch uses the former ship-selection sound: " + tab.text)
	var science_icon: TextureRect = screen.find_child("ScienceIcon", true, false)
	check(science_icon != null and screen.header.text == str(state.credits), "Header shows credits and the science production icon")
	check(screen.research_status.text == "Choose Research", "Research tab prompts for a focus")
	check(absf(science_icon.global_position.y + science_icon.size.y / 2.0
		- screen.research_status.global_position.y - screen.research_status.size.y / 2.0) <= 1.0,
		"Research icon and status are vertically aligned")
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
		var named_row: Button = screen.roster.find_child("Ship1", true, false)
		check(screen.roster_panel.get_global_rect().encloses(named_row.get_global_rect()),
			"Flagship sprite tile fits the roster panel without canvas expansion")
		var buttons: Dictionary = screen.canvas.slot_buttons
		check_callouts(screen.canvas)
		check(screen.canvas.exhaust_elapsed > 0, "Ships view continuously animates preview thrust")
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
	var button: Button = screen.canvas.slot_buttons.port
	check(uid in screen.stock.visible_uids, "New purchase appears in stock")
	button._drop_data(Vector2.ZERO, preload("res://scripts/hangar_equipment_transfer.gd").payload(uid))
	await settle()
	check(state.owned_ship(1).mounts.port.uid == uid, "Drop target equips physical item")
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
	screen.roster.find_child("BuyEquipment", true, false).pressed.emit()
	await settle()
	check(screen.shop.visible, "Shop opens")
	check(str(screen.shop.find_child("ShopHeading", true, false).text).ends_with("Equipment"),
		"Equipment entry point names the station and its equipment shop")
	check(screen.shop.find_children("*", "Button", true, false).all(
		func(control: Button) -> bool: return control.text not in ["Equipment", "Ships"]),
		"Embedded shop has no internal mode buttons")
	check(screen.shop.find_children("*", "ScrollContainer", true, false).is_empty(),
		"Station shop never scrolls")
	var station: Dictionary = state.expedition_simulation.locations[state.expedition_simulation.state.docked_location_id]
	var grants: Dictionary = state.research_grants()
	var first_row: HBoxContainer = screen.shop_rows.get_child(0)
	check(first_row.get_child(1).get_meta("equipment_id") == station.featured[0],
		"Featured station stock is offered first")
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		screen._refresh()
		await settle()
		check(screen.shop.get_global_rect().is_equal_approx(screen.center.get_global_rect()), "Buy panel covers exactly the center area")
		var corner_close: TextureButton = screen.shop.find_child("CloseX", true, false)
		check(corner_close.position == Vector2(screen.shop.size.x - corner_close.size.x - 1, 1),
			"Shop close tracks the one-pixel top/right inset at every resolution")
		check(not screen.shop.is_in_group("modal_ui") and not screen.shop.get_global_rect().intersects(screen.details_panel.get_global_rect()), "Buy panel leaves stock and roster accessible without a modal backdrop")
		check(screen.find_child("ScienceIcon", true, false) != null
			and screen.research_status.text == "Choose Research",
			"Research status remains visible on every tab")
		check(screen.shop_rows.get_child_count() > 0, "Shop offers stock at every resolution")
		for row: HBoxContainer in screen.shop_rows.get_children():
			var purchase: Button = row.get_child(1)
			check(screen.shop.get_global_rect().grow(1).encloses(row.get_global_rect()),
				"Every offered item fits inside the shop without scrolling")
			check(row.find_child("ItemArt", true, false) != null, "Shop items show artwork or the placeholder")
			check(purchase.get_meta("equipment_id") in station.stock, "Shop offers only this station's stock")
			for label: Label in purchase.find_children("*", "Label", true, false):
				check(purchase.get_global_rect().encloses(label.get_global_rect()),
					"Purchase labels remain inside their row at every resolution")
			check((purchase.find_child("BuyIcon", true, false) != null) == not purchase.disabled,
				"Green plus appears only for purchasable equipment")
			check(purchase.find_child("PriceIcon", true, false) != null,
				"Shop price uses credits artwork")
			var unlocked := SlotCatalog.unlocked(SlotCatalog.find_equipment(purchase.get_meta("equipment_id"), purchase.get_meta("rank")), grants)
			check((purchase.find_child("ResearchRequiredIcon", true, false) != null) == not unlocked,
				"Locked equipment shows science artwork rather than Research text")
		for checkbox: CheckBox in screen.stock.filters.find_children("*", "CheckBox", true, false):
			check(screen.stock.filters.get_global_rect().encloses(checkbox.get_global_rect()), "Filter checkbox fits its panel at each supported resolution")
			check(checkbox.button_group == null and checkbox.focus_mode == Control.FOCUS_NONE, "Checkboxes are independent and excluded from focus cycling")
		if resolution == Vector2i(640, 360) and "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/hangar/ui-shop-640.png")
	root.size = Vector2i(1280, 720)
	await settle()
	screen.tabs.get_child(0).pressed.emit()
	await settle()
	check(screen.roster.find_child("BuyEquipment", true, false) == null, "Fleet offers only chassis buying")
	screen.roster.find_child("BuyChassis", true, false).pressed.emit()
	await settle()
	check(screen.buy_mode == "SHIPS" and screen.shop_rows.get_child_count() > 0, "Center panel lists purchasable chassis")
	check(str(screen.shop.find_child("ShopHeading", true, false).text).ends_with("Ships"),
		"Chassis entry point switches the open panel and heading")
	for row: HBoxContainer in screen.shop_rows.get_children():
		var purchase: Button = row.get_child(1)
		check((purchase.find_child("BuyIcon", true, false) != null) == not purchase.disabled
			and purchase.find_child("PriceIcon", true, false) != null,
			"Chassis price uses artwork and unavailable chassis has no plus")
		check(purchase.get_meta("inspect_chassis") in station.chassis_stock, "Chassis offers come from this station")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/hangar/ui-buy-ships.png")
	screen.tabs.get_child(1).pressed.emit()
	await settle()
	check(screen.roster.find_child("BuyChassis", true, false) == null, "Ships offers only equipment buying")
	screen.roster.find_child("BuyEquipment", true, false).pressed.emit()
	await settle()
	check(screen.shop.find_children("*", "LineEdit", true, false).is_empty()
		and screen.stock.find_children("*", "LineEdit", true, false).is_empty()
		and screen.shop.find_children("*", "OptionButton", true, false).is_empty()
		and screen.stock.find_children("*", "OptionButton", true, false).is_empty(),
		"Stock and Buy have no search or single-choice controls")
	var inventory_before: int = state.equipment_inventory.size()
	for row: HBoxContainer in screen.shop_rows.get_children():
		var purchase: Button = row.get_child(1)
		if not purchase.disabled:
			purchase.find_child("BuyIcon", true, false).pressed.emit()
			break
	await settle()
	check(state.equipment_inventory.size() == inventory_before + 1 and screen.buy_open and screen.shop != null, "Purchase updates stock while center shop stays open")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/hangar/ui-buy-equipment.png")
	screen.roster.find_child("BuyEquipment", true, false).pressed.emit()
	await settle()
	check(not screen.buy_open and screen.shop == null and screen.canvas != null, "Buy button toggles back to ship fitting")
	screen.roster.find_child("BuyEquipment", true, false).pressed.emit()
	await settle()
	var close: TextureButton = screen.shop.find_child("CloseX", true, false)
	check(close.texture_normal.atlas.resource_path == "res://assets/ui/Btn_ClosePanel_n.png"
		and close.texture_hover == close.texture_normal
		and close.texture_pressed.atlas.resource_path == "res://assets/ui/Btn_ClosePanel_p.png",
		"Shared close uses supplied normal, hover and pressed artwork")
	close._on_mouse_entered()
	check(close.self_modulate.r > 1.0, "Close button lightens on hover")
	close._on_mouse_exited()
	check(screen.shop.get_global_rect().encloses(close.get_global_rect()), "Shared X lies within modal")
	check(close.position == Vector2(screen.shop.size.x - close.size.x - 1, 1)
		and close.texture_normal.region == Rect2(64, 50, 117, 53),
		"Shop close removes source padding and sits one pixel from both edges")
	close.pressed.emit()
	await settle()
	check(screen.shop == null, "X closes shop")
	check(screen.stock != null and not screen.has_method("_open_stock"), "Stock selling has no Manage panel")
	var science_fixture: Dictionary = state.hangar_snapshot()
	science_fixture.research.research_ids.append("laboratory_ii")
	science_fixture.research.research_ids.append("laboratory_iii")
	science_fixture.research.story_flags["boss_i_defeated"] = true
	check(state._commit_hangar(science_fixture), "Late-game research UI fixture")
	check(state.buy_chassis("transport"), "Science chassis UI fixture")
	var science_ship: int = state.fleet[-1].id
	check(state.buy_equipment("research_lab", 2) and state.fit_equipment(science_ship, "port", str(state.next_equipment_id - 1)), "Lab II UI fixture")
	check(state.buy_equipment("research_lab", 3) and state.fit_equipment(science_ship, "hold", str(state.next_equipment_id - 1)), "Lab III UI fixture")
	await settle()
	screen.selected_ship_id = 1
	for title in ["RESEARCH", "FLEET", "MAP", "SHIPS"]:
		if title == "RESEARCH":
			screen.research_button.pressed.emit()
		for tab: Button in screen.tabs.get_children():
			if tab.text == title:
				tab.pressed.emit()
				break
		await settle()
		check(screen.center.get_child_count() > 0, title + " is connected")
		if title == "RESEARCH":
			check(labels_under(screen.roster).contains("6 RP/day") and labels_under(screen.roster).contains("1 x Lab III"), "Native production panel explains ranked lab output")
			screen.center.get_child(0)._select("laboratory_iii")
			await settle()
			check(labels_under(screen.details).contains("3 RP/day"), "Native research details show Lab III output")
		if title == "MAP":
			check(screen.center.get_child(0).get_script().resource_path == "res://scripts/expedition_map.gd", "Pannable expedition map shows the live voyage")
			screen._select_destination(state.get_reachable_nodes(0)[0])
			await settle()
		for tab: Button in screen.tabs.get_children():
			check(tab.button_pressed == (tab.text == title), "Active tab styling follows every refresh")
		check(screen.research_button.button_pressed == (title == "RESEARCH"), "Research tab reflects active screen")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await create_timer(0.15).timeout
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
		battle.set_process(false)
		for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.size = resolution
			await settle()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/hangar/ui-battle-%d.png" % resolution.x)
		battle.set_process(true)
	battle.simulation.phase = BattleSimulation.Phase.VICTORY
	battle._finish_battle(true)
	await settle()
	check(battle._report_open and not state.battle_pending, "Actual report and settlement")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.size = resolution
			await settle()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/hangar/ui-report-%d.png" % resolution.x)
	battle.queue_free()
	await settle()
	print("HANGAR UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
