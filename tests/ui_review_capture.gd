extends SceneTree

var output := "res://.local/ui-review/before"
var state: Node

func _initialize() -> void:
	call_deferred("run")

func mount(path: String) -> Control:
	if current_scene != null:
		current_scene.free()
	var scene: Control = load(path).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	return scene

func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := "%s/%dx%d" % [output, root.size.x, root.size.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.get_texture().get_image().save_png(folder + "/" + name + ".png")
	var metadata: Array = []
	collect(current_scene, metadata)
	var file := FileAccess.open(folder + "/" + name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata, "  "))
	print("Captured ", folder, "/", name)

func collect(node: Node, entries: Array) -> void:
	if node is Control and node.is_visible_in_tree() and (node is Label or node is BaseButton or node is LineEdit):
		var entry := {"path": str(node.get_path()), "size": [node.size.x, node.size.y], "position": [node.global_position.x, node.global_position.y], "focus": node.focus_mode}
		if node is Label or node is Button:
			entry["text"] = node.text
			entry["font"] = node.get_theme_font("font").get_font_name()
			entry["font_size"] = node.get_theme_font_size("font_size")
		entries.append(entry)
	for child in node.get_children():
		collect(child, entries)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="):
			output = argument.trim_prefix("--review-output=")
	root.mode = Window.MODE_WINDOWED
	root.gui_embed_subwindows = true
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	state = root.get_node("GameState")
	state.run_save_path = "user://ui-review/run.json"
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await process_frame
		var menu := await mount("res://scenes/main_menu.tscn")
		await shot("menu")
		menu._on_play_pressed()
		await shot("setup")
		menu._on_setup_back_requested()
		menu._on_settings_pressed()
		await shot("settings")
		menu.settings_dialog.hide()
		state.start_new_run(1, 42)
		for entry in state.story_archive():
			state.story_flags["seen/" + entry.id] = true
		state.load_saved_ship_design("Drone")
		var map := await mount("res://scenes/game_map.tscn")
		await shot("fleet")
		var fleet: Control = map.panel_tabs.get_node("Fleet")
		var owned: FleetShip = state.fleet[0]
		fleet.board.selected = owned
		fleet.board.selected_ships.assign([owned])
		fleet.board.selection_changed.emit()
		await shot("fleet-selected")
		fleet._construct_slot(0)
		await shot("construction-review")
		fleet.action_review.queue_free()
		await process_frame
		state.set_ship_reserve(owned, true)
		await process_frame
		await process_frame
		await shot("fleet-reserved-hidden")
		fleet._open_reserve()
		await shot("reserve-modal")
		fleet.reserve_modal.queue_free()
		await process_frame
		state.set_ship_reserve(owned, false)
		await process_frame
		await process_frame
		fleet.board.selected = owned
		fleet.board.selected_ships.assign([owned])
		var health: float = owned.units[0].hp
		owned.units[0].hp -= 0.5
		state.fleet_changed.emit()
		await shot("fleet-repair-actions")
		fleet.ship_actions.find_child("RepairAction", true, false).pressed.emit()
		await shot("repair-review")
		fleet.action_review.queue_free()
		await process_frame
		owned.units[0].hp = health
		state.fleet_changed.emit()
		map.panel_tabs.current_tab = 1
		await shot("builder")
		map.build_area._on_load_design_pressed()
		await shot("library")
		map.build_area.load_design_dialog.search.text = "no matching blueprint"
		map.build_area.load_design_dialog.search.text_changed.emit("no matching blueprint")
		await shot("library-empty")
		state.save_current_ship_design("Long Blueprint Name For A Passenger Expedition Revision 123456789")
		map.build_area.load_design_dialog.search.text = "Long Blueprint"
		map.build_area.load_design_dialog.search.text_changed.emit("Long Blueprint")
		await shot("library-long-name")
		map.build_area.load_design_dialog.close_library()
		map.panel_tabs.current_tab = 2
		await shot("research")
		map.panel_tabs.get_node("Upgrades").grouped_view._select("civil_hospitality")
		await shot("research-details")
		map.panel_tabs.get_node("Upgrades").grouped_view.tree_canvas.fit_view()
		map.panel_tabs.current_tab = 3
		await shot("archive")
		map.panel_tabs.current_tab = 0
		map._on_map_pressed()
		map._show_route_preview(state.get_reachable_nodes(0)[0])
		await shot("map")
		map.graph_modal.hide()
		map._on_how_to_play_pressed()
		await shot("help")
		map.how_to_play_dialog.hide()
		await mount("res://scenes/ship_designer.tscn")
		await shot("designer")
		state.set_destination(state.get_reachable_nodes(0)[0])
		var battle := await mount("res://scenes/auto_battle.tscn")
		battle.set_physics_process(false)
		await shot("battle")
		battle.simulation.phase = BattleSimulation.Phase.WITHDRAWN
		battle._finish_battle(false)
		await shot("report")
	print("UI review capture complete")
	if OS.get_cmdline_user_args().has("--review-hold"):
		await create_timer(45).timeout
	current_scene.free()
	await process_frame
	await process_frame
	quit()
