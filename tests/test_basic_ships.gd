extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://basic-ships/run.json"
	check(state.start_new_run(1, 42), "Start isolated basic-ship campaign.")
	var original_library: Array[Dictionary] = state.saved_ship_designs.duplicate(true)
	state.saved_ship_designs.clear()
	var fingerprints: Dictionary = {}
	for title: String in BUILTINS.designs():
		var design: Ship = BUILTINS.designs()[title]
		check(FleetRules.design_error(design).is_empty() and state.design_research_error(design).is_empty(), "%s is legal with Foundation research." % title)
		check(state.design_fits_build_area(design), "%s fits the starting build area." % title)
		var cells: Dictionary = {}
		for part in design.parts:
			for cell in part.get_occupied_cells():
				check(not cells.has(cell), "%s has no overlapping equipment." % title)
				cells[cell] = true
		check(cells.size() == design.tiles.size(), "%s has no unassembled material." % title)
		var reached := {design.get_tile_cells()[0]: true}
		var pending: Array[Vector2i] = [design.get_tile_cells()[0]]
		while not pending.is_empty():
			var cell: Vector2i = pending.pop_back()
			for offset in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var neighbor: Vector2i = cell + offset
				if design.tiles.has(neighbor) and not reached.has(neighbor):
					reached[neighbor] = true
					pending.append(neighbor)
		check(reached.size() == design.tiles.size(), "%s has a connected material footprint." % title)
		var fingerprint := FleetRules.fingerprint(design)
		check(not fingerprints.has(fingerprint), "Basic ships have distinct layouts.")
		fingerprints[fingerprint] = true
		check(state.load_saved_ship_design(title) and FleetRules.fingerprint(state.ship) == fingerprint, "%s loads through the actual design library API." % title)
		check(not state.save_current_ship_design(title).is_empty() and not state.delete_saved_ship_design(title), "Built-in templates require saving an editable copy.")
		check(state.start_new_run(1, 42) and state.purchase_ship(design, title), "%s constructs at the starting port." % title)
		var owned: FleetShip = state.fleet.back()
		check(FleetRules.fingerprint(owned.design) == fingerprint and owned.units.size() == design.parts.size(), "Construction preserves every component.")
		check(state.load_run_checkpoint() and FleetRules.fingerprint(state.fleet.back().design) == fingerprint, "Purchased hull survives campaign reload.")
		print("%s: %d cells, %d capacity, %s materials" % [title, design.tiles.size(), FleetRules.design_capacity(design), state.get_design_material_costs(design)])
	check(state.get_visible_ship_designs("surv").size() == 1, "Library search finds the Surveyor template.")
	# An existing player design called Scout takes priority over the new template.
	state.saved_ship_designs.clear()
	state.saved_ship_designs.append({"name": "Scout", "ship": BUILTINS.drone().to_design_data()})
	var matches: Array = state.get_visible_ship_designs("Scout")
	check(matches.size() == 1 and not matches[0].get("builtin", false) and state.load_saved_ship_design("Scout")
		and FleetRules.fingerprint(state.ship) == FleetRules.fingerprint(BUILTINS.drone()), "Existing same-name player designs remain visible and load unchanged.")
	state.saved_ship_designs.clear()
	await test_library_ui()
	state.saved_ship_designs = original_library
	if "--capture" in OS.get_cmdline_user_args():
		await capture()
	print("Basic ship tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var viewport := control.get_viewport()
	if viewport is Window and viewport != root:
		point += Vector2(viewport.position)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	for _frame in range(3):
		await process_frame

func test_library_ui() -> void:
	root.gui_embed_subwindows = true
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = Vector2i(640, 360)
	var map: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	map.panel_tabs.current_tab = 1
	await process_frame
	await process_frame
	var dialog: PopupPanel = map.build_area.load_design_dialog
	dialog.open_library("LOAD")
	for _frame in range(3):
		await process_frame
	check(dialog.choices.size() == 5 and dialog.page_label.text == "1 / 2", "All basic templates are reachable through the paged minimum-resolution library.")
	for choice in dialog.choices:
		check(choice.builtin, "Library rows retain built-in protection.")
	await click(dialog.forward_button)
	check(dialog.page == 1 and dialog.page_label.text == "2 / 2", "Library pagination responds to actual mouse input.")
	check(Rect2i(Vector2i.ZERO, root.size).encloses(Rect2i(dialog.position, dialog.size)), "The library fits wholly inside 640x360 after refreshing and changing pages.")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/basic-ships/library.png")
	dialog.search.text = "Surveyor"
	dialog._refresh_rows()
	for _frame in range(3):
		await process_frame
	var row: Control = dialog.rows.get_child(dialog.rows.get_child_count() - 1)
	var load_button: Button = row.find_children("*", "Button", true, false)[0]
	await click(load_button)
	check(not dialog.visible and root.get_node("GameState").current_ship_design_name == "Surveyor", "Surveyor loads by clicking its library row.")
	map.free()
	current_scene = null

func capture() -> void:
	root.size = Vector2i(960, 360)
	var sheet := Control.new()
	sheet.theme = load("res://themes/ui_theme.tres")
	root.add_child(sheet)
	var i := 0
	for title in ["Scout", "Escort", "Surveyor", "Hauler"]:
		var label := Label.new()
		label.text = title
		label.position = Vector2(i * 240 + 80, 25)
		sheet.add_child(label)
		var preview: Control = load("res://scripts/ship_design_preview.gd").new()
		preview.position = Vector2(i * 240 + 10, 65)
		preview.size = Vector2(220, 250)
		sheet.add_child(preview)
		preview.set_ship(BUILTINS.designs()[title])
		i += 1
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/basic-ships/designs.png")
	sheet.free()
