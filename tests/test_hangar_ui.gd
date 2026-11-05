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
	state.current_research_ids.append("applied_energy")
	check(state.save_run_checkpoint(), "Persist researched laser fixture before Continue")
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
	check(screen.name == "Hangar" and screen.active_tab == "MAP",
		"Continue opens the existing hangar screen on the Map home page")
	check(screen.travel_controls != null, "Fleet page includes compact expedition controls")
	screen.selected_ship_id = state.fleet[0].id
	screen.active_tab = "FLEET"
	screen.ship_editor_open = true
	screen._refresh()
	await settle()
	check(screen.canvas != null, "Actual game opens physical hangar")
	check(screen.selected_ship_id == state.fleet[0].id and state.fleet[0].flagship, "Fleet inspects the selected flagship")
	check(screen.formation_view != null and screen.ship_editor.is_visible_in_tree(),
		"Fleet sprites remain behind the ship editor")
	var audio := root.get_node("AudioManager")
	var tabs: HBoxContainer = screen.tabs
	check(tabs.get_parent() == screen.command_header.left
		and screen.header_wallet.get_parent() == screen.command_header.right
		and screen.travel_controls.get_parent() == screen.command_header.middle,
		"Command header puts tabs left, expedition speed controls in the recess and research/wallet right")
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
	check(screen.research_status.text == "0 / 20 RP", "Research header shows the shared bar")
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
		check(screen.get_global_rect().encloses(screen.ship_editor.get_node("ShipEditorPanel").get_global_rect()),
			"Fleet flagship editor stays inside the screen")
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
		check(screen.get_global_rect().encloses(screen.details.get_global_rect()), "Details fit screen")
		check(screen.get_global_rect().encloses(screen.roster.get_global_rect()), "Roster fits screen")
	root.size = Vector2i(1280, 720)
	await settle()
	var replaced_uid: String = state.owned_ship(1).mounts.port.uid
	screen.canvas.slot_selected.emit("port")
	await settle()
	screen.refit_panel.find_child("Part_laser", true, false).pressed.emit()
	await settle()
	check(state.owned_ship(1).mounts.port.equipment_id == "laser", "Clicking a mount and a part refits that mount")
	check(not state.equipment_inventory.has(replaced_uid), "Replaced part is scrapped; there is no stock")
	state.credits = 5000
	state.current_research_ids.append_array(["guided_munitions", "siege_i", "siege_ii"])
	state.research_branch_choices.force_projection = "siege"
	check(state.save_run_checkpoint(), "Fund ship layout fixtures")
	for chassis in SlotCatalog.chassis():
		if chassis.flagship:
			continue
		check(state.buy_ship(chassis.id), "Buy " + chassis.name + " for actual hangar review")
		screen.selected_ship_id = state.fleet[-1].id
		screen.ship_editor_open = true
		screen._refresh()
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
			var loadouts: Control = screen.refit_panel
			var scroll: ScrollContainer = loadouts.get_parent().get_parent()
			var last_action: Control = loadouts.get_child(loadouts.get_child_count() - 1)
			scroll.ensure_control_visible(last_action)
			await settle()
			check(loadouts != null and scroll.get_global_rect().grow(1).encloses(last_action.get_global_rect()),
				chassis.name + " refit choices remain reachable inside the aspect-sized panel")
			check(not scroll.get_h_scroll_bar().visible,
				"Ship actions never require horizontal scrolling")
			scroll.scroll_vertical = 0
			await settle()
			check(screen.formation_view != null, "Orderly Fleet stays available behind inspection")
		check(state.salvage_hangar_ship(screen.selected_ship_id), "Immediate fixture salvage")
		await settle()
	root.size = Vector2i(1280, 720)
	await settle()
	screen.selected_ship_id = 1
	screen.ship_editor_open = true
	screen._refresh()
	await settle()
	check(screen.roster.find_child("BuyEquipment", true, false) == null, "There is no equipment shop")
	screen._close_ship_editor()
	await settle()
	screen.roster.find_child("BuyShips", true, false).pressed.emit()
	await settle()
	check(screen.shop.visible, "Ship shop opens")
	check(str(screen.shop.find_child("ShopHeading", true, false).text).ends_with("Ships"),
		"Shop names the station and its ships")
	check(screen.shop.find_children("*", "ScrollContainer", true, false).is_empty(), "Station shop never scrolls")
	var station: Dictionary = state.expedition_simulation.locations[state.expedition_simulation.state.docked_location_id]
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		screen._refresh()
		await settle()
		check(screen.shop.get_global_rect().is_equal_approx(screen.center.get_global_rect()),
			"Buy panel covers exactly the center area: shop %s, center %s" % [screen.shop.get_global_rect(), screen.center.get_global_rect()])
		var corner_close: TextureButton = screen.shop.find_child("CloseX", true, false)
		check(corner_close.position == Vector2(screen.shop.size.x - corner_close.size.x - 1, 1),
			"Shop close tracks the one-pixel top/right inset at every resolution")
		check(not screen.shop.is_in_group("modal_ui") and not screen.shop.get_global_rect().intersects(screen.details_panel.get_global_rect()),
			"Buy panel leaves the side panels accessible without a modal backdrop")
		check(screen.find_child("ScienceIcon", true, false) != null and screen.research_status.text == "0 / 20 RP",
			"Research status remains visible on every tab")
		check(screen.shop_rows.get_child_count() > 0, "Shop offers ships at every resolution")
		for row: HBoxContainer in screen.shop_rows.get_children():
			var purchase: Button = row.get_child(1)
			check(screen.shop.get_global_rect().grow(1).encloses(row.get_global_rect()), "Every offer fits inside the shop without scrolling")
			check(purchase.get_meta("inspect_chassis") in station.chassis_stock, "Ship offers come from this station")
			check((purchase.find_child("BuyIcon", true, false) != null) == not purchase.disabled
				and purchase.find_child("PriceIcon", true, false) != null, "Ship price uses artwork and unavailable ships have no plus")
		if resolution == Vector2i(640, 360) and "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/hangar/ui-shop-640.png")
	root.size = Vector2i(1280, 720)
	await settle()
	var fleet_before: int = state.fleet.size()
	for row: HBoxContainer in screen.shop_rows.get_children():
		var purchase: Button = row.get_child(1)
		if not purchase.disabled:
			purchase.find_child("BuyIcon", true, false).pressed.emit()
			break
	await settle()
	check(state.fleet.size() == fleet_before + 1 and screen.buy_open and screen.shop != null, "Purchase adds a fitted ship while the shop stays open")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/hangar/ui-buy-ships.png")
	screen.roster.find_child("BuyShips", true, false).pressed.emit()
	await settle()
	check(not screen.buy_open and screen.shop == null and screen.canvas != null, "Buy button toggles back to ship fitting")
	screen.roster.find_child("BuyShips", true, false).pressed.emit()
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
	var science_fixture: Dictionary = state.hangar_snapshot()
	if not "laboratory_ii" in science_fixture.research.research_ids:
		science_fixture.research.research_ids.append("laboratory_ii")
	science_fixture.research.research_ids.append("laboratory_iii")
	science_fixture.research.story_flags["boss_i_defeated"] = true
	check(state._commit_hangar(science_fixture), "Late-game research UI fixture")
	check(state.buy_ship("transport"), "Science ship UI fixture")
	var science_ship: int = state.fleet[-1].id
	check(state.swap_part(science_ship, "port", "") and state.swap_part(science_ship, "starboard", ""),
		"Isolate ranked research UI fixture from preinstalled labs")
	check(state.swap_part(state.fleet[1].id, "port", "") and state.swap_part(state.fleet[1].id, "starboard", ""),
		"Isolate production from the starting Transport")
	check(not state.swap_part(science_ship, "port", "research_lab@2"), "Removed L lab is not offered")
	check(state.swap_part(science_ship, "hold", "research_lab@3"), "Lab (XL) UI fixture")
	await settle()
	screen.selected_ship_id = 1
	for title in ["FLEET", "MAP"]:
		for tab: Button in screen.tabs.get_children():
			if tab.text == title:
				tab.pressed.emit()
				break
		await settle()
		check(screen.center.get_child_count() > 0, title + " is connected")
		if title == "MAP":
			check(screen.center.get_child(0).get_script().resource_path == "res://scripts/expedition_map.gd", "Pannable expedition map shows the live voyage")
			screen._select_destination(state.get_reachable_nodes(0)[0])
			await settle()
		for tab: Button in screen.tabs.get_children():
			check(tab.button_pressed == (tab.text == title), "Active tab styling follows every refresh")
		check(not screen.research_button.toggle_mode, "Research control opens choices rather than switching tabs")
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
