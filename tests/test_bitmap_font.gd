extends SceneTree

var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	# The original full-cell UV for 'o' began directly under '_' in the atlas.
	# Require a transparent sampling gutter without changing logical advance.
	var font: FontFile = load("res://assets/fonts/starhull-fonts/Starhull/Starhull.fnt")
	var glyph := font.get_glyph_index(13, "o".unicode_at(0), 0)
	var uv := font.get_glyph_uv_rect(0, Vector2i(13, 0), glyph)
	check(uv.position.y >= 57 and uv.size.y <= 6, "Lowercase o samples only its own ink, away from the underscore above it (%s; glyph %d)." % [uv, glyph])
	check(font.get_string_size("ooo o", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x == 28,
		"Tight glyph UVs preserve original letter/space advances.")
	check(font.get_height(13) == 13, "Original font line height is unchanged.")
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	for resolution in [Vector2i(640,360), Vector2i(1240,835), Vector2i(1920,1080)]:
		root.size = resolution
		var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
		root.add_child(menu)
		current_scene = menu
		menu._on_play_pressed()
		menu.game_setup.get_node("CenterContainer/SetupModal/Contents/CheckpointWarning").show()
		for difficulty in [GameState.Difficulty.EASY, GameState.Difficulty.MEDIUM, GameState.Difficulty.HARD]:
			menu.game_setup.selected_difficulty = difficulty
			menu.game_setup._update_difficulty_display()
			for frame in range(3):
				await process_frame
			check(menu.game_setup.difficulty_details.get_theme_font("font") == font, "Setup inherits Starhull from the shared theme.")
			check(menu.game_setup.setup_modal.get_global_rect().encloses(menu.game_setup.difficulty_details.get_global_rect()), "Difficulty details fit the setup window.")
			check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(menu.game_setup.setup_modal.get_global_rect()), "Setup fits %s with the checkpoint warning." % resolution)
			if "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/mission-font/after"))
				root.get_texture().get_image().save_png("res://.local/mission-font/after/setup-%dx%d-%d.png" % [resolution.x,resolution.y,difficulty])
		menu.free()
		current_scene = null
	print("Bitmap font/setup tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
