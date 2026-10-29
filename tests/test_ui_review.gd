extends SceneTree

var failures := 0
var state: Node

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	await process_frame
	await process_frame

func tooltip_offenders(node: Node) -> Array[String]:
	var result: Array[String] = []
	if node is Control and not node.tooltip_text.is_empty() and node.name != &"Lock":
		result.append(str(node.get_path()))
	for child in node.get_children():
		result.append_array(tooltip_offenders(child))
	return result

func mount(path: String) -> Control:
	if current_scene != null:
		current_scene.free()
	var scene: Control = load(path).instantiate()
	root.add_child(scene)
	current_scene = scene
	await settle()
	check(tooltip_offenders(scene).is_empty(), "Only the conditional Ship Designer lock has a tooltip: %s" % [str(tooltip_offenders(scene))])
	return scene

# Dispatch genuine Godot GUI events, including hit testing and focus routing.
func click(control: Control, viewport: Viewport = root) -> void:
	var point := control.get_global_rect().get_center()
	if viewport is Window and viewport != root:
		point += Vector2(viewport.position)
		viewport = root
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		viewport.push_input(event, true)
	await settle()

func key(code: Key, viewport: Viewport = root, ctrl := false) -> void:
	viewport = root # Embedded windows receive their focused input through the host.
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.ctrl_pressed = ctrl
		event.pressed = pressed
		viewport.push_input(event, true)
	await settle()

func _run() -> void:
	root.size = Vector2i(640, 360)
	root.gui_embed_subwindows = true
	state = root.get_node("GameState")
	state.run_save_path = "user://ui-review-tests/run.json"
	for action in [&"ui_focus_next", &"ui_focus_prev", &"ui_left", &"ui_right", &"ui_up", &"ui_down"]:
		check(InputMap.action_get_events(action).is_empty(), "Default UI navigation action %s has no keys." % action)
	var menu := await mount("res://scenes/main_menu.tscn")
	check(not menu.continue_button.visible, "Fresh profile has no misleading Continue action.")
	await click(menu.play_button)
	check(menu.game_setup.visible, "Pointer opens new-run setup.")
	await key(KEY_TAB)
	check(not root.gui_get_focus_owner() is BaseButton, "Tab does not focus UI buttons.")
	await key(KEY_ESCAPE)
	check(not menu.game_setup.visible, "Escape dismisses setup.")
	await click(menu.settings_button)
	check(menu.settings_dialog.visible, "Settings opens through pointer input.")
	await click(menu.settings_dialog.reduced_motion_button, menu.settings_dialog)
	check(state.reduced_motion, "Reduced-motion control updates the preference.")
	state.reduced_motion = false
	root.get_node("AudioManager").load_settings()
	check(state.reduced_motion, "Reduced-motion preference survives reload.")
	await key(KEY_ESCAPE, menu.settings_dialog)
	check(not menu.settings_dialog.visible, "Escape dismisses the settings popup.")
	await click(menu.play_button)
	await click(menu.game_setup.start_button)
	check(current_scene.scene_file_path == "res://scenes/game_map.tscn", "New Run completes through setup using the reduced-motion transition.")
	await key(KEY_ESCAPE)
	check(state.start_new_run(1, 42), "Create isolated checkpoint for UI journeys.")
	for entry in state.story_archive():
		state.story_flags["seen/" + entry.id] = true
	state.load_saved_ship_design("Drone")
	var map := await mount("res://scenes/game_map.tscn")
	var fleet: Control = map.panel_tabs.get_node("Fleet")
	var ui_theme: Theme = map.theme
	var original_font := ui_theme.default_font
	ui_theme.default_font = ThemeDB.fallback_font
	await settle()
	for control in [fleet.slot_widgets[0].label, map.deploy_button, fleet.reserve_button, map.panel_tab_buttons[0], map.build_area.save_design_button]:
		check(control.get_theme_font("font") == ui_theme.default_font, "Changing the theme font reaches %s without a control override." % control.name)
	ui_theme.default_font = original_font
	await settle()
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		check(fleet.slot_widgets.size() == 3 and map.fleet_controls.find_children("*", "ScrollContainer", true, false).is_empty(), "Three general ship slots require no scrolling at %s." % resolution)
		var panel: Control = map.fleet_controls.get_parent()
		for widget: Dictionary in fleet.slot_widgets:
			check(panel.get_global_rect().encloses(widget.button.get_global_rect()), "Every slot is completely inside the left panel at %s." % resolution)
		check(map.fleet_controls.find_child("FleetServices", true, false) == null and not map.sector_name_label.visible, "No Port/Story controls or Act/row label remain.")
		check(fleet.slot_widgets[0].label.get_theme_font("font").get_font_name() == "Starhull", "Ship slot names retain Starhull.")
	root.size = Vector2i(640, 360)
	await settle()
	check(not fleet.summary_host.find_children("*", "Button", true, false).any(func(button: Button) -> bool: return button.text in ["RESERVE", "DEPLOY", "REPAIR", "SELECT"]), "Fleet summary contains no repeated per-ship actions.")
	var selected_owned: FleetShip = state.fleet[0]
	await click(fleet.board.previews[selected_owned])
	check(fleet.ship_actions.visible and fleet.board.selected_ships == [selected_owned], "Clicking a hull shows its single-ship toolbar.")
	var formation: Vector2 = selected_owned.formation
	var deployed_count: int = state.get_deployed_fleet().size()
	await click(fleet.ship_actions.find_child("ReserveAction", true, false))
	check(not state.is_ship_deployed(selected_owned) and state.get_deployed_fleet().size() == deployed_count - 1 and selected_owned.formation == formation and not fleet.board.dragging, "Reserve acts only on the selected hull and does not drag it.")
	check(not fleet.board.previews.has(selected_owned) and not fleet.ship_actions.visible, "Reserved hull is absent from formation rendering and selection.")
	await click(fleet.reserve_button)
	check(is_instance_valid(fleet.reserve_modal), "Reserve button opens a small management modal.")
	await click(fleet.reserve_modal.find_child("ReserveShip%d" % selected_owned.id, true, false).get_node("DeployReserve"))
	check(state.is_ship_deployed(selected_owned) and state.get_deployed_fleet().size() == deployed_count and fleet.board.previews.has(selected_owned), "Deploying from Reserve restores the hull to formation.")
	await key(KEY_ESCAPE)
	await click(fleet.board.previews[selected_owned])
	fleet.board.selected_ships.append(state.fleet[1])
	fleet.board.selection_changed.emit()
	await settle()
	check(not fleet.ship_actions.visible, "Group selection hides single-ship actions.")
	fleet.board.selected_ships.clear()
	fleet.board.selection_changed.emit()
	await settle()
	check(not fleet.ship_actions.visible, "Empty selection hides single-ship actions.")
	await click(fleet.board.previews[selected_owned])
	var original_hp: float = selected_owned.units[0].hp
	selected_owned.units[0].hp -= 0.5
	state.fleet_changed.emit()
	await settle()
	check(fleet.ship_actions.find_child("RepairAction", true, false) != null, "Damaged selected hull offers Repair beside it.")
	var credits_before_repair: int = state.credits
	await click(fleet.ship_actions.find_child("RepairAction", true, false))
	check(is_instance_valid(fleet.action_review) and state.is_modal_ui_open(), "Repair click opens a priced review instead of hover text.")
	await key(KEY_ESCAPE)
	check(state.credits == credits_before_repair and selected_owned.units[0].hp == original_hp - 0.5, "Cancelling repair preserves funds and damage.")
	await click(fleet.ship_actions.find_child("RepairAction", true, false))
	var repair_price: int = state.repair_quote(selected_owned).credits
	await click(fleet.action_review.find_child("ConfirmAction", true, false))
	check(not selected_owned.needs_repair() and state.credits == credits_before_repair - repair_price, "Confirmed repair restores only the selected hull and charges its quote once.")
	var owned_count: int = state.fleet.size()
	var construction_price: int = state.get_construction_credit_cost(fleet.slots[0].design)
	var credits_before_construction: int = state.credits
	await click(fleet.slot_widgets[0].construct)
	check(is_instance_valid(fleet.action_review) and state.fleet.size() == owned_count, "Plus opens a construction quote before spending.")
	await key(KEY_ESCAPE)
	check(state.fleet.size() == owned_count and state.credits == credits_before_construction, "Cancelling construction spends nothing.")
	await click(fleet.slot_widgets[0].construct)
	var good_path: String = state.run_save_path
	var blocker := FileAccess.open("user://ui-review-tests/blocker", FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	state.run_save_path = "user://ui-review-tests/blocker/run.json"
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	await click(fleet.action_review.find_child("ConfirmAction", true, false))
	Engine.print_error_messages = printed
	check(state.fleet.size() == owned_count and state.credits == credits_before_construction and fleet.action_review.find_child("ActionStatus", true, false).visible, "Failed construction save preserves funds and ships and reports the error inline.")
	state.run_save_path = good_path
	var fleet_edit_started := Time.get_ticks_usec()
	await click(fleet.action_review.find_child("ConfirmAction", true, false))
	var fleet_add_usec := Time.get_ticks_usec() - fleet_edit_started
	check(state.fleet.size() == owned_count + 1 and state.credits == credits_before_construction - construction_price, "Confirmed construction creates and charges one physical ship.")
	check(fleet_add_usec < 600000, "Fleet add, including deferred UI refresh, stays below 600 ms (%d us)." % fleet_add_usec)
	fleet.board.selected_ships.assign([state.fleet.back()])
	fleet.board.selection_changed.emit()
	await settle()
	fleet_edit_started = Time.get_ticks_usec()
	await click(fleet.ship_actions.find_child("SalvageAction", true, false))
	var fleet_remove_usec := Time.get_ticks_usec() - fleet_edit_started
	check(state.fleet.size() == owned_count and state.credits == credits_before_construction - construction_price, "Dismantling removes one physical hull without refunding credits.")
	check(fleet_remove_usec < 600000, "Fleet removal, including deferred UI refresh, stays below 600 ms (%d us)." % fleet_remove_usec)
	await click(map.settings_button)
	await click(map.settings_dialog.quit_to_menu_button, map.settings_dialog)
	await key(KEY_TAB, map.settings_dialog)
	check(not map.settings_dialog.gui_get_focus_owner() is BaseButton, "Tab does not cycle through confirmation buttons.")
	await key(KEY_ESCAPE, map.settings_dialog)
	check(map.settings_dialog.visible and not map.settings_dialog.quit_confirmation_overlay.visible, "First Escape cancels Quit without closing Settings (popup %s, confirmation %s)." % [map.settings_dialog.visible, map.settings_dialog.quit_confirmation_overlay.visible])
	await key(KEY_ESCAPE, map.settings_dialog)
	await click(map.how_to_play_button)
	var body: Label = map.how_to_play_dialog.find_child("Body", true, false)
	var scroll: ScrollContainer = body.get_parent()
	check(body.size.y > scroll.size.y and scroll.size.y < 320, "Long help stays inside a usable scrolling viewport.")
	await key(KEY_ESCAPE, map.how_to_play_dialog)
	check(not map.how_to_play_dialog.visible and not state.is_modal_ui_open(), "Closing Help clears the modal input gate.")
	await click(map.map_button)
	await click(map.panel_tab_buttons[1])
	check(map.panel_tabs.current_tab == 0, "Clicks outside the map modal cannot switch background tabs.")
	await key(KEY_ESCAPE)
	await click(map.panel_tab_buttons[1])
	check(map.panel_tabs.current_tab == 1, "Pointer selects builder tab.")
	var builder: Control = map.build_area
	await key(KEY_L, root, true)
	var library: PopupPanel = builder.load_design_dialog
	check(library.visible and library.gui_get_focus_owner() == library.search, "Ctrl+L opens library with search focus.")
	var source: int = builder._selected_source_id
	var typed := InputEventKey.new()
	typed.keycode = KEY_1
	typed.unicode = 49
	typed.pressed = true
	root.push_input(typed, true)
	await settle()
	check(library.search.text == "1" and builder._selected_source_id == source and library.empty_label.visible, "Search consumes typing, reports empty results, and suppresses canvas shortcuts.")
	await key(KEY_ESCAPE, library)
	await settle()
	check(not library.visible, "Library stays closed after Escape instead of reopening.")
	check(state.save_current_ship_design("A Very Long Blueprint Name For A Passenger Expedition Revision 123456789").is_empty(), "Create long-name layout fixture.")
	await key(KEY_L, root, true)
	library.search.text = "A Very Long"
	library.search.text_changed.emit("A Very Long")
	await settle()
	var row: PanelContainer = library.rows.get_child(library.rows.get_child_count() - 1)
	check(row.size.x <= library.size.x and row.get_global_rect().end.x <= library.size.x, "Long blueprint names keep row actions inside the popup.")
	await key(KEY_ESCAPE, library)
	# Exercise a real canvas placement and its keyboard history, measuring the
	# formerly multi-second mutation independently of rendering frame pacing.
	await key(KEY_ESCAPE)
	await key(KEY_2)
	var cell := Vector2i(8, 8)
	var point: Vector2 = builder.placed_layer.to_global(builder.placed_layer.map_to_local(cell))
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	var started := Time.get_ticks_usec()
	root.push_input(event, true)
	var elapsed := Time.get_ticks_usec() - started
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await settle()
	check(state.ship.tiles.has(cell), "Canvas hit testing places a material block.")
	check(elapsed < 500000, "One placement returns within 500 ms (measured %d us)." % elapsed)
	await key(KEY_Z, root, true)
	check(not state.ship.tiles.has(cell), "Ctrl+Z undoes the placement.")
	await key(KEY_Y, root, true)
	check(state.ship.tiles.has(cell), "Ctrl+Y restores the placement.")
	await click(map.map_button)
	map._show_route_preview(state.get_reachable_nodes(0)[0])
	await settle()
	check(not map.route_travel_button.disabled, "Ready fleet can travel to a reachable node.")
	await key(KEY_ESCAPE)
	check(not map.graph_modal.visible, "Escape closes the map modal.")
	var credits: int = state.credits
	check(not state.has_method("purchase_material") and not is_instance_valid(map.campaign_overlay), "No material shop or automatic story/service popup appears.")
	state.research_points = 20
	state.research_changed.emit()
	await click(map.panel_tab_buttons[2])
	var research: Control = map.panel_tabs.get_node("Upgrades").grouped_view
	research.tree_canvas.camera_position = research.tree_canvas.positions.civil_hospitality + research.tree_canvas.CARD_SIZE * 0.5
	research.tree_canvas._update_camera()
	await settle()
	await click(research.card_buttons.civil_hospitality)
	check(is_instance_valid(research.focus_button), "Selecting a research node exposes its inline focus action.")
	await click(research.focus_button)
	check(state.research_points == 0 and state.current_research_ids.has("civil_hospitality"), "Reviewed research spends the quoted RP once and unlocks its grants.")
	state.credits = -48
	await click(map.panel_tab_buttons[0])
	for field in ["red_tiles_available", "blue_tiles_available", "green_tiles_available", "core_tiles_available"]:
		state.set(field, 100)
	state.tile_inventory_changed.emit()
	await settle()
	await click(fleet.slot_widgets[0].construct)
	check(not fleet.action_review.find_child("ConfirmAction", true, false).disabled, "Debt permits construction paid entirely with owned materials.")
	await key(KEY_ESCAPE)
	for field in ["red_tiles_available", "blue_tiles_available", "green_tiles_available", "core_tiles_available"]:
		state.set(field, 0)
	state.tile_inventory_changed.emit()
	await settle()
	await click(fleet.slot_widgets[0].construct)
	check(fleet.action_review.find_child("ConfirmAction", true, false).disabled, "Debt blocks a positive-credit shortage quote before spending.")
	await key(KEY_ESCAPE)
	# Menu recovery uses the same checkpoint store and scene path as players.
	menu = await mount("res://scenes/main_menu.tscn")
	check(menu.continue_button.visible and not menu.continue_button.disabled, "Valid checkpoint exposes Continue.")
	await click(menu.continue_button)
	check(current_scene.scene_file_path == "res://scenes/game_map.tscn" and state.credits == credits, "Continue restores persisted accounting, discarding unsaved edits.")
	check(state.save_run_checkpoint(), "Create backup at a stable preparation boundary.")
	var damaged := FileAccess.open(state.run_save_path, FileAccess.WRITE)
	damaged.store_string("corrupt main file")
	damaged.close()
	menu = await mount("res://scenes/main_menu.tscn")
	await click(menu.continue_button)
	check(current_scene.scene_file_path == "res://scenes/game_map.tscn" and state.credits == credits, "Continue recovers a valid backup through the menu.")
	check(state.set_destination(state.get_reachable_nodes(0)[0]), "Freeze an interrupted deployment.")
	var identity: String = state.battle_identity()
	menu = await mount("res://scenes/main_menu.tscn")
	await click(menu.continue_button)
	check(current_scene.scene_file_path == "res://scenes/auto_battle.tscn" and state.battle_identity() == identity, "Interrupted Continue reopens the same frozen encounter.")
	current_scene.set_physics_process(false)
	var battle: Control = current_scene
	await click(battle.pause_button)
	check(battle.pause_button.button_pressed, "Pointer pauses combat.")
	await click(battle.fast_forward_button)
	check(not battle.pause_button.button_pressed and state.battle_fast_forward, "Fast-forward releases Pause without conflicting toggles.")
	await click(battle.withdraw_button)
	check(battle.withdraw_button.disabled, "Retreat rejects duplicate input.")
	for tick in range(400):
		battle.simulation.advance(1.0 / 30.0)
		if battle.simulation.phase != BattleSimulation.Phase.COMBAT:
			break
	check(battle.simulation.phase == BattleSimulation.Phase.WITHDRAWN, "Retreat command reaches the withdrawn outcome.")
	battle._finish_battle(false)
	await settle()
	check(battle._report_open and not battle.destroy_neutral_targets.visible, "Outcome report takes priority over combat controls.")
	await key(KEY_ESCAPE)
	check(current_scene.scene_file_path == "res://scenes/game_map.tscn" and not state.battle_pending, "Dismissing the report returns to preparation after settlement.")
	# An interrupted loss must expose reserves rather than open an empty battle.
	state.run_save_path = "user://ui-review-tests/reserves.json"
	check(state.start_new_run(1, 42), "Create reserve-recovery fixture.")
	check(state.purchase_ship(preload("res://scripts/builtin_ships.gd").drone(), "Drone"), "Construct emergency reserve.")
	var reserve: FleetShip = state.fleet.back()
	check(state.set_ship_reserve(reserve, true), "Reserve the replacement.")
	check(state.set_destination(state.get_reachable_nodes(0)[0]), "Deploy armed ships.")
	for owned: FleetShip in state.get_deployed_fleet():
		owned.damage_cell(owned.units[owned.core_index].cells[0], 10000)
	check(state.save_run_checkpoint(), "Persist a lost deployment before interruption.")
	menu = await mount("res://scenes/main_menu.tscn")
	await click(menu.continue_button)
	check(current_scene.scene_file_path == "res://scenes/game_map.tscn" and state.emergency_roster_available() and state.fleet.size() == 1, "Continue removes lost hulls and exposes surviving reserves at preparation.")
	check(state.set_ship_reserve(state.fleet[0], false), "Activate surviving reserve.")
	check(state.set_destination(state.get_reachable_nodes(0)[0]), "Redeploy replacement.")
	var last: FleetShip = state.fleet[0]
	last.damage_cell(last.units[last.core_index].cells[0], 10000)
	check(state.save_run_checkpoint(), "Persist terminal interrupted loss.")
	menu = await mount("res://scenes/main_menu.tscn")
	await click(menu.continue_button)
	check(current_scene == menu and state.run_ended and menu.status_label.visible, "A terminal interrupted loss remains in the menu with an explanation.")
	state.run_save_path = "user://ui-review-tests/run.json"
	check(state.start_new_run(1, 43), "Restore valid checkpoint for failed-load UI test.")
	menu = await mount("res://scenes/main_menu.tscn")
	for suffix in ["", ".next", ".bak"]:
		var file := FileAccess.open(state.run_save_path + suffix, FileAccess.WRITE)
		file.store_string("invalid checkpoint")
		file.close()
	credits = state.credits
	await click(menu.continue_button)
	check(current_scene == menu and menu.status_label.visible and not menu.continue_button.disabled and state.credits == credits, "Failed Continue remains in menu with feedback and no live accounting changes.")
	menu = await mount("res://scenes/main_menu.tscn")
	check(not menu.continue_button.visible and menu.status_label.visible, "Unrecoverable save is explained before starting a replacement run.")
	current_scene.free()
	state.reduced_motion = false
	root.get_node("AudioManager").save_settings()
	await settle()
	print("UI review tests finished: %d failures; placement %d us; fleet add %d us; fleet remove %d us" % [failures, elapsed, fleet_add_usec, fleet_remove_usec])
	quit(0 if failures == 0 else 1)
