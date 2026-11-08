extends "res://tests/test_content_transactions.gd"

var completed_native := false

func click_base(button: BaseButton) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = motion.position
		event.global_position = motion.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await settle()

func menu_continue() -> void:
	var id: String = state.run_id
	var credits: int = state.credits
	var equipment: Dictionary = state.equipment_inventory.duplicate(true)
	var frozen_hash: String = state.run_session.content.content_hash
	Content.load_all(["res://packs"])
	check(state.missile_quote().price == 17 and Content.db() == state.run_session.content, "Installed reload leaves the displayed active quote frozen")
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await settle()
	check(Content.db() == Content.installed() and Loadouts.default_for("fighter").id == "interceptor"
		and menu.continue_button.is_visible_in_tree() and not menu.continue_button.disabled, "Main menu previews installed content and offers the stored run")
	await click(menu.play_button)
	check(menu.game_setup.visible, "New Run pointer opens setup")
	var warning: Label = menu.game_setup.find_child("CheckpointWarning", true, false)
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		check(warning.is_visible_in_tree() and warning.text == "Other runs are kept."
			and menu.game_setup.setup_modal.get_global_rect().encloses(warning.get_global_rect()), "New-run preservation notice fits at " + str(resolution))
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("user://p3-setup-%d.png" % resolution.x) == OK, "Capture new-run setup")
	await click_base(menu.game_setup.back_button)
	check(not menu.game_setup.visible and menu.continue_button.is_visible_in_tree(), "Shared X returns to the run's Continue action")
	await click(menu.continue_button)
	await settle()
	check(is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/game_map.tscn",
		"Actual Continue pointer opens the production management scene")
	current_scene.set_process(false)
	check(state.run_id == id and state.credits == credits and state.equipment_inventory == equipment
		and state.run_session.content.content_hash == frozen_hash and state.missile_quote().price == 17,
		"Continue restores frozen prices, fitted UIDs and committed pointer purchases despite installed changes: id=%s credits=%d inventory=%s hash=%s price=%d" % [state.run_id == id, state.credits, state.equipment_inventory == equipment, state.run_session.content.content_hash == frozen_hash, state.missile_quote().price])
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://p3-continued.png") == OK, "Capture resumed frozen run")
	current_scene.queue_free()
	await settle()
	completed_native = true

func removed_art_native() -> void:
	var folder := "user://native_removed/gone"
	DirAccess.make_dir_recursive_absolute(folder + "/defs")
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.CYAN)
	check(image.save_png(folder + "/ship.png") == OK, "Create isolated removable native art")
	FileAccess.open(folder + "/pack.json", FileAccess.WRITE).store_string(JSON.stringify({"id": "gone", "name": "Missing art fixture", "kind": "content", "version": "1.0.0", "depends": [{"id": "core", "version": ">=1.0"}]}))
	FileAccess.open(folder + "/defs/patch.json", FileAccess.WRITE).store_string(JSON.stringify({"def": "patch", "id": "drone", "target_def": "chassis", "target": "core:drone", "set": {"art": "gone:ship.png"}}))
	var installed := Content.load_all(["res://packs", "user://native_removed"])
	check(installed.problems.items.is_empty() and state.start_new_run(1, 3741), "Freeze a native run using pack-relative chassis art")
	DirAccess.remove_absolute(folder + "/ship.png")
	check(state.load_run_checkpoint(), "Continue after removing the source image")
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	screen.active_tab = "FLEET"
	root.size = Vector2i(1280, 720)
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	await settle()
	check(state.fleet[3].art_texture == preload("res://scripts/placeholders.gd").art()
		and screen.formation_view.is_visible_in_tree() and state.fleet[3].is_alive()
		and state.squadrons.all(func(group: Dictionary) -> bool: return group.id is int), "Living ships with removed art and integer flag identities remain on the actual Fleet canvas")
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://p3-missing-art.png") == OK, "Capture the existing pink marker on restored fleet ships")
	screen.queue_free()
	await settle()
	completed_native = true

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = ""
	check(DisplayServer.get_name() != "headless", "Run core UI check requires native rendering")
	if DisplayServer.get_name() != "headless":
		if not "--art-only" in OS.get_cmdline_user_args():
			await native_interface()
			await menu_continue()
		await removed_art_native()
	check(completed_native, "Native transaction/setup/Continue section completed")
	print("RUN CORE NATIVE COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
