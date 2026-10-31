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
	check(screen.canvas != null, "Actual game opens physical hangar")
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
		var placed: Array[Rect2] = []
		for id in buttons:
			var button: OptionButton = buttons[id]
			check(button.focus_mode == Control.FOCUS_NONE and button.tooltip_text.is_empty(), "Mount has no focus box or tooltip")
			var rect := button.get_global_rect()
			check(screen.canvas.get_global_rect().encloses(rect), "Mount stays in canvas")
			check(not placed.any(func(other: Rect2) -> bool: return rect.intersects(other)), "Mount controls never overlap")
			placed.append(rect)
			for index in range(1, button.item_count):
				var uid: String = button.get_item_metadata(index).uid
				check(state.equipment_inventory.has(uid), "Dropdown offers only owned instances")
		check(screen.get_global_rect().encloses(screen.details.get_global_rect()), "Details fit screen")
		check(screen.get_global_rect().encloses(screen.roster.get_global_rect()), "Roster fits screen")
	root.size = Vector2i(1280, 720)
	await settle()
	check(state.buy_equipment("mini_turret"), "Buy gear through actual state")
	await settle()
	var uid := str(state.next_equipment_id - 1)
	var button: OptionButton = screen.canvas.slot_buttons.aft_port
	var index := -1
	for item in range(button.item_count):
		if button.get_item_metadata(item).uid == uid:
			index = item
	check(index >= 0, "New purchase appears in actual dropdown")
	button.get_popup().index_pressed.emit(index)
	await settle()
	check(state.owned_ship(1).mounts.aft_port.uid == uid, "Native dropdown equips physical item")
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
			for mount: OptionButton in screen.canvas.slot_buttons.values():
				var rect := mount.get_global_rect()
				check(screen.canvas.get_global_rect().encloses(rect), chassis.name + " mount in canvas")
				check(not rectangles.any(func(other: Rect2) -> bool: return rect.intersects(other)), chassis.name + " mounts do not overlap")
				rectangles.append(rect)
		check(state.salvage_hangar_ship(screen.selected_ship_id), "Immediate fixture salvage")
		await settle()
	root.size = Vector2i(1280, 720)
	await settle()
	screen._open_shop()
	await settle()
	check(screen.shop.visible, "Shop opens")
	var close: TextureButton = screen.shop.find_child("CloseX", true, false)
	check(close.texture_normal != null, "Shared close artwork")
	check(screen.shop.get_global_rect().encloses(close.get_global_rect()), "Shared X lies within modal")
	close.pressed.emit()
	await settle()
	check(screen.shop == null, "X closes shop")
	screen._open_stock()
	await settle()
	check(screen.shop.visible, "Stock opens")
	screen.shop.find_child("CloseX", true, false).pressed.emit()
	await settle()
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
	for title in ["RESEARCH", "FORMATION", "MAP", "HANGAR"]:
		screen.active_tab = title
		screen._refresh()
		await settle()
		check(screen.center.get_child_count() > 0, title + " is connected")
		if title == "RESEARCH":
			check(labels_under(screen.roster).contains("6.5 RP/day") and labels_under(screen.roster).contains("1 x Lab III"), "Native production panel explains ranked lab output")
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
