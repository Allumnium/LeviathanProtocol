extends SceneTree

var failures := 0
var checks := 0
var state: Node
var screen: Control
var mouse := Vector2.ZERO

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func settle() -> void:
	for i in range(4):
		await process_frame

func button(position: Vector2, pressed: bool, double_click := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.double_click = double_click
	root.push_input(event, true)

func motion(position: Vector2, pressed := false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = position - mouse
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	mouse = position
	root.push_input(event, true)

func drag(start: Vector2, finish: Vector2) -> void:
	motion(start)
	button(start, true)
	await process_frame
	motion(finish, true)
	await process_frame
	button(finish, false)
	await settle()

func capture(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/ui-polish/" + name + ".png")

func star_layout(field: Control) -> Array:
	var result: Array = []
	for star in field._area_stars:
		result.append([star.world_offset, star.depth, star.radius, star.color, star.phase,
			star.speed, star.animation_frame_offset, star.animation_speed, star.is_sparkle])
	return result

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/ui-polish"))
	root.size = Vector2i(1280, 720)
	var ui_theme: Theme = load("res://themes/ui_theme.tres")
	var resource_sample := ResourceText.create("3 RP/day | 20 CR | -5 cr\nRepair | SHIELD | Shields\n[b]Literal text[/b]")
	resource_sample.theme = ui_theme
	resource_sample.size = Vector2(180, 90)
	root.add_child(resource_sample)
	await settle()
	check(not resource_sample.get_parsed_text().contains("RP") and not resource_sample.get_parsed_text().contains("CR")
		and not resource_sample.get_parsed_text().contains("cr") and resource_sample.get_parsed_text().contains("[b]Literal text[/b]"),
		"Resource text replaces whole unit tokens, preserves numbers and never interprets names as markup")
	check(not resource_sample.get_parsed_text().to_lower().contains("repair")
		and not resource_sample.get_parsed_text().to_lower().contains("shield")
		and ResourceText.REPAIR.resource_path == "res://assets/ui/icons/icon_repair.png"
		and ResourceText.SHIELD.resource_path == "res://assets/ui/icons/icon_shield.png",
		"Repair and singular/plural shield words render the supplied inline icons")
	for font_size in [10, 13, 18]:
		resource_sample.add_theme_font_size_override("normal_font_size", font_size)
		await settle()
		check(resource_sample.icon_size == font_size and resource_sample.texture_filter == Control.TEXTURE_FILTER_NEAREST,
			"Inline resource images follow font size with nearest-neighbor filtering: %d" % font_size)
		for entry: Array in [["RP", ResourceText.SCIENCE], ["CR", ResourceText.CREDITS], ["Repair", ResourceText.REPAIR], ["Shield", ResourceText.SHIELD]]:
			resource_sample.set_content(entry[0])
			await settle()
			var texture: Texture2D = entry[1]
			var expected_width: float = font_size * float(texture.get_width()) / texture.get_height()
			check(absf(resource_sample.get_content_width() - expected_width) <= 1.0,
				"Rendered inline %s preserves source aspect at text height %d" % [entry[0], font_size])
	resource_sample.set_content("4 passengers")
	check(resource_sample.get_parsed_text() == "4 passengers", "Changing content removes stale resource icons")
	resource_sample.set_content("Shield Generator\nShields 40 | shield recharge")
	check(resource_sample.get_parsed_text().begins_with("Shield Generator\n")
		and not resource_sample.get_parsed_text().contains("Shields")
		and not resource_sample.get_parsed_text().contains("shield recharge")
		and not ResourceText.has_icons("Shield Generator")
		and SlotCatalog.find_equipment("shield_generator").name == "Shield Generator",
		"Shield Generator keeps its full equipment name while shield stats/effects use icons")
	resource_sample.queue_free()
	var button_style := ui_theme.get_stylebox("normal", "Button") as StyleBoxFlat
	var hover_style := ui_theme.get_stylebox("hover", "TacticalButton") as StyleBoxFlat
	var pressed_style := ui_theme.get_stylebox("pressed", "TacticalButton") as StyleBoxFlat
	check(button_style != null and button_style.bg_color.a == 1.0
		and button_style.border_color != hover_style.border_color
		and hover_style.border_width_left > button_style.border_width_left
		and pressed_style.content_margin_top > button_style.content_margin_top,
		"Tactical buttons have distinct hover and pressed feedback")
	var panel_style := ui_theme.get_stylebox("panel", "PanelContainer") as StyleBoxTexture
	check(panel_style != null and panel_style.texture.atlas.resource_path == "res://assets/ui/Panel_StoreItem.png"
		and panel_style.texture_margin_right == 8 and panel_style.texture.atlas.get_width() == 300,
		"Panel containers use supplied nine-sliced chamfered artwork")
	for panel_type in ["Panel", "PopupPanel", "CompactPanel", "CompactPopup", "ResearchPanel", "RoutePanel"]:
		check(ui_theme.get_stylebox("panel", panel_type) == panel_style,
			"Panel surface shares the same chamfered theme: " + panel_type)
	check(ui_theme.get_stylebox("normal", "LineEdit") != null
		and ui_theme.get_stylebox("normal", "TextEdit") != null,
		"Single-line and multiline text boxes use shared themed surfaces")
	check(ui_theme.get_icon("checked", "CheckBox").resource_path == "res://assets/ui/Checkbox_On.png"
		and ui_theme.get_icon("unchecked", "CheckBox").resource_path == "res://assets/ui/Checkbox_Off.png"
		and ui_theme.get_icon("checked", "CheckBox").get_width() == 16,
		"Checkboxes use supplied on/off artwork at compact bitmap size")
	var save_dialog: PopupPanel = load("res://scenes/save_design_dialog.tscn").instantiate()
	check(save_dialog.theme == ui_theme
		and save_dialog.get_node("Contents/ShipNameInput") is LineEdit,
		"Ship-name editor field inherits the shared UI theme")
	save_dialog.free()
	state = root.get_node("GameState")
	state.run_save_path = "user://ui-polish.json"
	check(state.start_new_run(1, 151), "Start isolated UI fixture")
	var settings: PopupPanel = load("res://scenes/settings_dialog.tscn").instantiate()
	root.add_child(settings)
	check(settings.battle_auto_pan_button is TextureButton and settings.battle_auto_zoom_button is TextureButton
		and settings.find_child("ReducedMotionButton", true, false) == null,
		"Settings uses an artwork switch and does not expose Reduced motion")
	for slider_type in ["HSlider", "VSlider"]:
		check(ui_theme.get_stylebox("slider", slider_type).texture.resource_path == "res://assets/ui/Slider1_bg.png"
			and ui_theme.get_stylebox("grabber_area", slider_type).texture.atlas.resource_path == "res://assets/ui/Slider1.png"
			and ui_theme.get_icon("grabber", slider_type).resource_path == "res://assets/ui/processed/slider_handle.png"
			and ui_theme.get_icon("grabber", slider_type).get_size() == Vector2(8, 16),
			"Shared sliders use supplied track, foreground and compact handle: " + slider_type)
	var slider_fill := ui_theme.get_stylebox("grabber_area", "HSlider") as StyleBoxTexture
	var fill_image := slider_fill.texture.get_image()
	check(fill_image.get_pixel(0, fill_image.get_height() / 2).a == 1,
		"Slider foreground has no transparent left inset")
	var handle_image := ui_theme.get_icon("grabber", "HSlider").get_image()
	check(handle_image.get_pixel(0, 0).a == 1 and handle_image.get_pixel(7, 15).a == 1,
		"Compact slider handle has crisp opaque edges without baked glow")
	var camera_preference: bool = state.battle_auto_pan
	var zoom_preference: bool = state.battle_auto_zoom
	settings.battle_auto_pan_button.button_pressed = not camera_preference
	check(state.battle_auto_pan == not camera_preference and state.battle_auto_zoom == zoom_preference,
		"Settings switch updates and saves boolean preferences")
	settings.battle_auto_pan_button.button_pressed = camera_preference
	settings.battle_auto_zoom_button.button_pressed = not zoom_preference
	check(state.battle_auto_zoom == not zoom_preference and state.battle_auto_pan == camera_preference,
		"Auto-zoom preference changes independently from auto-pan")
	settings.battle_auto_zoom_button.button_pressed = zoom_preference
	settings.popup_centered()
	await settle()
	check(settings.size == Vector2i(304, 246) and settings.content_scale_factor == 1.0
		and root.gui_embed_subwindows and settings.get_visible_rect().size == Vector2(settings.size),
		"Settings uses a compact embedded modal at the same pixel scale as the main UI")
	check(settings.music_slider.get_parent().get_child(0).get_theme_font("font") == ui_theme.default_font,
		"Settings text inherits the same shared bitmap font")
	var music_volume: float = settings.music_slider.value
	var audio: Node = root.get_node("AudioManager")
	var old_preferences := ConfigFile.new()
	check(old_preferences.save("user://tutorial-default.cfg") == OK, "Create pre-tutorial settings fixture")
	state.tutorials_enabled = false
	audio.load_settings("user://tutorial-default.cfg")
	check(state.tutorials_enabled, "Tutorials default to enabled when older settings omit the preference")
	settings._refresh_context()
	check(settings.tutorials_button.button_pressed
		and settings.tutorials_button.texture_normal == ui_theme.get_icon("off", "SettingsSwitch")
		and settings.tutorials_button.texture_pressed == ui_theme.get_icon("on", "SettingsSwitch"),
		"Enable Tutorials uses the shared on/off artwork and reflects its default")
	settings.tutorials_button.button_pressed = false
	check(not state.tutorials_enabled, "Tutorial switch updates the session preference")
	state.tutorials_enabled = true
	audio.load_settings()
	check(not state.tutorials_enabled, "Disabled tutorials persist after preferences reload")
	settings.tutorials_button.button_pressed = true
	state.tutorials_enabled = false
	audio.load_settings()
	check(state.tutorials_enabled, "Enabled tutorials persist after preferences reload")
	settings._refresh_context()
	await settle()
	check(settings.get_node("Contents/ContentArea").get_global_rect().encloses(
		settings.tutorials_button.get_global_rect()), "Tutorial switch fits inside settings content")
	check(audio.save_settings("user://settings-no-motion.cfg"), "Save settings without removed motion preference")
	var saved_settings := ConfigFile.new()
	check(saved_settings.load("user://settings-no-motion.cfg") == OK
		and not saved_settings.has_section_key("accessibility", "reduced_motion")
		and state.get("reduced_motion") == null,
		"Reduced motion is absent from saved settings and runtime state")
	var slider: HSlider = settings.music_slider
	var handle_width: float = slider.get_theme_icon("grabber").get_width()
	for fraction in [0.0, 0.5, 1.0]:
		var position: Vector2 = slider.global_position + Vector2(
			handle_width / 2 + (slider.size.x - handle_width) * fraction, slider.size.y / 2)
		var motion_event := InputEventMouseMotion.new()
		motion_event.position = position
		settings.push_input(motion_event, true)
		for pressed in [true, false]:
			var click_event := InputEventMouseButton.new()
			click_event.position = position
			click_event.button_index = MOUSE_BUTTON_LEFT
			click_event.pressed = pressed
			settings.push_input(click_event, true)
			await process_frame
		await settle()
		check(absf(slider.value - fraction * 100) <= 1,
			"Themed slider retains clickable minimum, midpoint and maximum: %s / %s" % [slider.value, fraction * 100])
		check(absf(audio.get_bus_volume_percent(audio.MUSIC_BUS) - slider.value) <= 1,
			"Themed slider continues updating the music bus")
	var drag_start: Vector2 = slider.global_position + Vector2(slider.size.x - handle_width / 2, slider.size.y / 2)
	var drag_finish: Vector2 = slider.global_position + Vector2(handle_width / 2 + (slider.size.x - handle_width) * 0.25, slider.size.y / 2)
	var drag_press := InputEventMouseButton.new()
	drag_press.position = drag_start
	drag_press.button_index = MOUSE_BUTTON_LEFT
	drag_press.pressed = true
	settings.push_input(drag_press, true)
	await process_frame
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.position = drag_finish
	drag_motion.relative = drag_finish - drag_start
	drag_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	settings.push_input(drag_motion, true)
	await process_frame
	drag_press.position = drag_finish
	drag_press.pressed = false
	settings.push_input(drag_press, true)
	await settle()
	check(absf(slider.value - 25) <= 1, "Supplied handle retains native slider dragging")
	slider.value = music_volume
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720)]:
		root.size = resolution
		await settle()
		settings.popup_centered()
		await settle()
		for audio_slider: HSlider in [settings.music_slider, settings.ambience_slider, settings.effects_slider]:
			check(audio_slider.get_theme_stylebox("slider") == ui_theme.get_stylebox("slider", "HSlider")
				and audio_slider.size.y >= audio_slider.get_theme_icon("grabber").get_height(),
				"Settings audio sliders inherit artwork and fit their handles")
			var row_label: Label = audio_slider.get_parent().get_child(0)
			check(absf(audio_slider.get_global_rect().get_center().y - row_label.get_global_rect().get_center().y) <= 1,
				"Compact audio slider and row label align vertically")
		await capture("settings-sliders-%d" % resolution.x)
	check(settings.battle_auto_pan_button.texture_pressed == ui_theme.get_icon("on", "SettingsSwitch")
		and settings.battle_auto_pan_button.texture_normal == ui_theme.get_icon("off", "SettingsSwitch"),
		"Settings switch inherits the supplied on/off artwork from the shared theme")
	await capture("settings-switch")
	var settings_close: TextureButton = settings.get_node("CloseX")
	check(settings_close.stretch_mode == TextureButton.STRETCH_KEEP_ASPECT_CENTERED,
		"Close-button artwork preserves aspect in normal, hovered and pressed states")
	settings_close._on_mouse_entered()
	await capture("settings-close-hover")
	settings_close.toggle_mode = true
	settings_close.set_pressed_no_signal(true)
	settings_close._on_button_down()
	await capture("settings-close-pressed")
	settings_close.set_pressed_no_signal(false)
	settings_close.toggle_mode = false
	settings_close._on_mouse_exited()
	settings.hide()
	settings.queue_free()
	var data: Dictionary = state.hangar_snapshot()
	data.credits = 5000
	check(state._commit_hangar(data) and state.buy_ship("transport"), "Buy escort")
	check(state.move_ships({state.fleet.back().id: Vector2(2, 1)}),
		"Purchased fixture escort stays outside the starter group selection")
	screen = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	await settle()
	check(screen.active_tab == "MAP", "Map opens first")
	screen.tabs.get_child(1).pressed.emit()
	await settle()
	check(screen.active_tab == "FLEET", "Fleet tab opens the formation view")
	check(screen.formation_view.exhaust_elapsed == 0, "Docked Fleet does not advance travel thrust")
	check(root.snap_2d_transforms_to_pixel and root.snap_2d_vertices_to_pixel,
		"Active viewport snaps UI positions and vertices to pixels")
	var credits_icon: TextureRect = screen.find_child("CreditsIcon", true, false)
	var science_icon: TextureRect = screen.find_child("ScienceIcon", true, false)
	check(credits_icon != null and credits_icon.texture.resource_path == "res://assets/credits.png"
		and science_icon != null and screen.header.text == str(state.credits)
		and screen.research_status.text == "0 / 20 RP",
		"Header uses the credits icon and explicit research status")
	check(absf(science_icon.global_position.y + science_icon.size.y / 2.0
		- screen.research_status.global_position.y - screen.research_status.size.y / 2.0) <= 1.0,
		"Science icon and research status align vertically")
	check(screen.tabs.get_index() == 0 and screen.header.get_parent() == screen.header_wallet,
		"Tabs are left aligned and credits sit in the right-hand wallet")
	for entry: Array in [[screen.roster_panel, "left_panel_d.png"], [screen.details_panel, "right_panel_d.png"],
			[screen.find_child("CommandFooter", true, false), "bottom_bar_d.png"]]:
		check(SurfaceArt.diffuse(entry[0].art).resource_path.ends_with("/" + entry[1]),
			"Management frame uses supplied " + entry[1])
	check(screen.research_progress.visible and screen.research_progress.value == 0,
		"Shared research bar is visible from the start")
	screen.set_process(false)
	screen.research_pulse_time = 0.0
	screen._process(0.5)
	check(is_zero_approx(screen.research_pulse.get_shader_parameter("white_mix")),
		"An unfunded research bar does not prompt for a choice")
	screen._process(0.5)
	check(is_zero_approx(screen.research_pulse.get_shader_parameter("white_mix")),
		"Research prompt returns to normal once per second")
	# Advance the screen explicitly so periodic saves cannot race failed-save fixtures.
	var focused: Dictionary = state.hangar_snapshot()
	focused.research.research_points = 1.5
	check(state._commit_hangar(focused), "Save fractional header research progress")
	await settle()
	var required := HangarResearch.threshold(state.run_progress_snapshot())
	check(screen.research_status.text == "1 / 20 RP"
		and screen.research_progress.visible and screen.research_progress.value == 1.5
		and screen.research_progress.max_value == required and not screen.research_progress.show_percentage,
		"Header shows shared research progress without a focused project")
	check(screen.research_rate.text == "+1/day" and screen.research_progress.min_value == -1,
		"Research progress has a UI-only negative minimum and adjacent daily production")
	var progress_snapshot: Dictionary = state.hangar_snapshot()
	screen.research_progress.value = 0
	check(screen.research_progress.get_as_ratio() > 0 and state.hangar_snapshot() == progress_snapshot,
		"Zero progress retains a thin visible fill without changing game state")
	screen.research_progress.value = 1.5
	check(is_zero_approx(screen.research_pulse.get_shader_parameter("white_mix")),
		"Partial research progress keeps the choice prompt inactive")
	var progress_fill := screen.research_progress.get_theme_stylebox("fill") as StyleBoxTexture
	check(progress_fill.texture.atlas.resource_path == "res://assets/ui/Progress_CharacterAttribute.png",
		"Research bar uses the supplied progress artwork")
	check(progress_fill.get_minimum_size().x == 0,
		"Progress artwork has no minimum fill width that inflates low research percentages")
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		var research_column: Control = screen.find_child("HeaderResearch", true, false)
		var gear: TextureButton = screen.find_child("SettingsButton", true, false)
		check(screen.tabs.global_position.x == 8
			and screen.tabs.get_global_rect().end.x <= research_column.global_position.x
			and screen.research_button.get_global_rect().end.x <= screen.header_wallet.global_position.x
			and gear.get_global_rect().end.x <= screen.size.x,
			"Left tabs and right research/wallet fit inside the command header at every resolution")
		var header_rect: Rect2 = screen.command_header.get_global_rect()
		var speed_rect: Rect2 = screen.travel_controls.get_global_rect()
		check(absf(speed_rect.get_center().x - header_rect.get_center().x) <= 1
			and header_rect.encloses(speed_rect)
			and screen.tabs.get_global_rect().end.x <= speed_rect.position.x
			and speed_rect.end.x <= screen.research_button.global_position.x,
			"Speed controls stay centered and never overlap either header wing")
		var art_scale: float = screen.command_header.background.scale.x
		var upper_recess := Rect2(header_rect.position + Vector2(244, 6) * art_scale, Vector2(200, 28) * art_scale)
		check(upper_recess.grow(1).encloses(speed_rect),
			"Scaled time controls fit inside the topmost center recess")
		check(screen.tabs.global_position.y <= header_rect.position.y + 14 * art_scale
			and screen.research_button.global_position.y <= header_rect.position.y + 14 * art_scale,
			"Compact navigation and research sit close to the top rail")
		check(screen.departure_button.get_parent() == screen.command_header.course
			and screen.command_header.course.position.y > screen.command_header.middle.position.y,
			"Course action occupies the lower center recess instead of the footer")
		check(SurfaceArt.diffuse(screen.command_header.art).resource_path.ends_with("/top_bar_d.png")
			and screen.command_header.texture_filter == Control.TEXTURE_FILTER_NEAREST,
			"Command header uses supplied top_bar artwork with crisp filtering")
		for frame: Control in [screen.command_header, screen.roster_panel, screen.details_panel,
				screen.find_child("CommandFooter", true, false)]:
			var art: CanvasTexture = frame.art
			check(art != null and art.normal_texture != null and art.specular_texture != null
				and frame.background.material.shader == SurfaceArt.SHADER and frame.material == null,
				"UI frame uses cached mapped lighting without lighting child controls")
			check(is_equal_approx(frame.background.scale.x, frame.background.scale.y)
				and (frame.size - art.get_size() * frame.background.scale).abs().x <= 2
				and (frame.size - art.get_size() * frame.background.scale).abs().y <= 2,
				"Whole UI frame keeps its original aspect ratio: %s %s source %s" % [frame.name, frame.size, art.get_size()])
			check(screen.get_global_rect().encloses(frame.get_global_rect()),
				"Aspect-sized frames never expand beyond the screen")
		check(is_zero_approx(screen.command_header.global_position.y)
			and is_zero_approx(screen.roster_panel.global_position.x)
			and is_equal_approx(screen.details_panel.get_global_rect().end.x, screen.size.x)
			and is_equal_approx(screen.find_child("CommandFooter", true, false).get_global_rect().end.y, screen.size.y),
			"Management frames align flush to their nearest viewport edge")
		check(screen.roster_panel.size.x >= 156 and screen.details_panel.size.x >= 157,
			"Edge-aligned side panels use the reclaimed space for larger artwork")
		for frame: Control in [screen.command_header, screen.roster_panel, screen.details_panel,
				screen.find_child("CommandFooter", true, false)]:
			var extent: Vector2 = frame.art.get_size() * frame.background.scale
			var art_rect := Rect2(frame.global_position + frame.background.position - extent * 0.5, extent)
			var edge: Vector2 = frame.get_parent().edge
			check((edge == Vector2.UP and is_zero_approx(art_rect.position.y))
				or (edge == Vector2.DOWN and is_equal_approx(art_rect.end.y, screen.size.y))
				or (edge == Vector2.LEFT and is_zero_approx(art_rect.position.x))
				or (edge == Vector2.RIGHT and is_equal_approx(art_rect.end.x, screen.size.x)),
				"Uniformly scaled artwork itself meets the viewport edge despite pixel rounding")
		check(absf(screen.research_button.get_global_rect().end.x + 4 - screen.header_wallet.global_position.x) <= 1,
			"Research is right aligned immediately before credits")
		check(screen.research_button.get_global_rect().encloses(research_column.get_global_rect())
			and research_column.get_global_rect().encloses(screen.research_progress.get_global_rect()),
			"Research icon, text and progress fit inside the clickable tab")
		check(screen.research_progress.global_position.x == research_column.global_position.x
			and screen.research_rate.global_position.x >= screen.research_progress.get_global_rect().end.x
			and research_column.get_global_rect().encloses(screen.research_rate.get_global_rect()),
			"Progress is left aligned with the daily rate on its right inside the tab")
		var first_tab: Button = screen.tabs.get_child(0)
		for tab: Button in screen.tabs.get_children():
			check(tab.size == first_tab.size and tab.size.x >= 72
				and absf(tab.size.x / tab.size.y - 353.0 / 134.0) < 0.1,
				"Every tab shares a natural-aspect wide button size")
		check(screen.research_status.get_theme_font_size("font_size") == 10 and science_icon.size == Vector2(12, 12)
			and screen.research_progress.size.x <= ceilf(research_column.size.x * 0.5),
			"Compact research icon/text and half-width progress leave room for wide tabs")
		check(screen.header.get_global_rect().end.x <= gear.global_position.x,
			"Credits remain immediately to the left of Settings")
		await capture("research-header-%d" % resolution.x)
	root.size = Vector2i(640, 360)
	await settle()
	var short_research_text: String = screen.research_status.text
	screen.research_status.text = "Advanced Fleet Synchronization"
	screen._resize_research_label()
	await settle()
	check(screen.tabs.size.x == 224 and screen.header_wallet.get_global_rect().end.x <= screen.size.x
		and screen.research_button.get_global_rect().encloses(screen.research_status.get_global_rect())
		and screen.research_button.size.y <= 48,
		"Long research titles wrap without narrowing tabs or pushing the wallet offscreen")
	await capture("research-header-long-640")
	screen.research_status.text = short_research_text
	screen._resize_research_label()
	root.size = Vector2i(1280, 720)
	await settle()
	check(screen.research_button.size.y <= 34, "Research button returns to compact height after a long name")
	check(screen.roster.find_child("BuyEquipment", true, false) == null
		and screen.roster.find_child("BuyShips", true, false) != null, "Fleet offers Buy Ships")
	screen.formation_view.camera = Vector2(25, -12)
	screen.formation_view.zoom = 1.3
	var roster_escort_id: int = state.fleet[1].id
	var escort: HangarShip = state.owned_ship(roster_escort_id)
	var escort_point: Vector2 = screen.formation_view.global_position + screen.formation_view.ship_rect(escort).get_center()
	check(screen.roster.find_child("Ship%d" % roster_escort_id, true, false) == null,
		"Fleet side panel no longer lists ships; the formation sprites are the roster")
	await drag(escort_point, escort_point)
	check(screen.active_tab == "FLEET" and screen.selected_ship_id == roster_escort_id and screen.ship_editor_open,
		"Single-click on a Fleet sprite opens its editor")
	check(screen.formation_view.find_children("*", "Button", true, false).is_empty(),
		"Selected formation ships have no floating Equip or Salvage buttons")
	check(screen.active_tab == "FLEET" and screen.selected_ship_id == roster_escort_id
		and screen.canvas.owned_id == roster_escort_id and screen.selected_slot.is_empty(),
		"Native Fleet sprite click opens the matching ship editor")
	screen.ship_editor.find_child("CloseX", true, false).pressed.emit()
	await settle()
	check(screen.formation_view.camera == Vector2(25, -12) and is_equal_approx(screen.formation_view.zoom, 1.3),
		"Closing the ship editor preserves Fleet pan and zoom")
	screen._open_ship_editor(state.fleet[0].id)
	await settle()
	check(screen.roster.find_child("BuyEquipment", true, false) == null
		and screen.refit_panel != null,
		"Fleet editor shows loadout refits instead of an equipment shop")
	screen._close_ship_editor()
	await settle()
	screen.roster.find_child("BuyShips", true, false).pressed.emit()
	await settle()
	var before_purchase: int = state.fleet.size()
	for offer: HBoxContainer in screen.shop_rows.get_children():
		var purchase: Button = offer.get_child(1)
		if not purchase.disabled:
			var row_center := purchase.get_global_rect().get_center()
			await drag(row_center, row_center)
			check(state.fleet.size() == before_purchase, "Clicking a ship offer does not purchase")
			purchase.pressed.emit()
			check(state.fleet.size() == before_purchase, "Ship inspection row has no purchase callback")
			check(not screen.inspected_item.is_empty() and screen.inspection != null,
				"Ship offer opens inspection in the side panel")
			var buy: TextureButton = purchase.find_child("BuyIcon", true, false)
			check(buy != null and buy.size == Vector2(32, 32) and purchase.size.y < 52,
				"Ship offers have a double-size green buy button and compact row")
			await drag(buy.get_global_rect().get_center(), buy.get_global_rect().get_center())
			break
	await settle()
	check(screen.buy_open and state.fleet.size() == before_purchase + 1, "Ship purchases keep the shop open")
	await capture("ships-shop")
	screen.roster.find_child("BuyShips", true, false).pressed.emit()
	await settle()
	screen.tabs.get_child(1).pressed.emit()
	await settle()
	var selected_squadron := HangarSquadrons.for_ship(state.squadrons, state.fleet[0].id)
	check(not screen.buy_open and screen.details.get_child(0).text == "%s #%d x%d" % [
		selected_squadron.name, selected_squadron.id, selected_squadron.members.size()],
		"Closing the ship shop restores squadron commands in Fleet")
	var offer_fixture: Dictionary = state.hangar_snapshot()
	state._allocate_research(offer_fixture.research, 20)
	check(state._commit_hangar(offer_fixture), "Fund native card selection")
	await settle()
	screen._maybe_show_research_choices()
	await settle()
	check(is_instance_valid(screen.research_dialog) and screen.research_dialog.buttons.size() == 3,
		"Filled research bar opens three upgrade cards over the current view")
	await capture("research-cards")
	screen.research_dialog._close()
	await settle()
	screen.tabs.get_child(1).pressed.emit()
	await settle()
	var board: Control = screen.formation_view
	board.camera = Vector2(20, -15)
	board.zoom = 1.2
	board.queue_redraw()
	await settle()
	var first: Vector2 = board.point(state.fleet[0])
	var second: Vector2 = board.point(state.fleet[1])
	check(board.ship_rect(state.fleet[1]).size.is_equal_approx(board.ship_rect(state.fleet[0]).size * 0.25),
		"Fleet escort renders at quarter flagship width and height")
	check(board._hit(second + Vector2(15, 0) * board.zoom) == 0,
		"Escort hit target no longer covers its old full-size bounds")
	var origin := board.global_position
	var before_layout: Dictionary = state.hangar_snapshot()
	var display_before: Dictionary = board.display_positions.duplicate()
	await drag(origin + first - Vector2(40, 50), origin + second + Vector2(40, 50))
	board = screen.formation_view
	check(not screen.ship_editor_open and SaveValidation.same(before_layout, state.hangar_snapshot()),
		"Dragging management space never edits tactical formation")
	check(board.camera == Vector2(20, -15) and is_equal_approx(board.zoom, 1.2), "Selection preserves camera")
	await capture("orderly-fleet")
	var saved: Dictionary = state.hangar_snapshot()
	check(state.load_run_checkpoint(), "Reload tactical formation")
	check(state.hangar_snapshot().ships == saved.ships, "Inspection preserves saved tactical positions")
	await settle()
	board = screen.formation_view
	check(board.display_positions == display_before, "Continue preserves orderly management escorts")
	var empty: Vector2 = board.global_position + Vector2(20, 120)
	await drag(empty, empty)
	check(screen.selected_ship_id == 0 and screen.formation_view.selected_ids.is_empty(), "Empty-space click deselects")
	check(screen.find_child("FleetRepairAll", true, false).get_meta("resource_text", "").begins_with("REPAIR ALL"), "Empty selection offers repair all")
	var fleet_totals: ResourceText = screen.details.find_child("FleetTotals", true, false)
	check(not fleet_totals.get_parsed_text().contains("RP") and fleet_totals.icon_size == ui_theme.default_font_size,
		"Fleet science renders an inline icon at the surrounding font size")
	var repair_label: ResourceText = screen.find_child("FleetRepairAll", true, false).find_child("ResourceText", true, false)
	check(repair_label != null and not repair_label.get_parsed_text().contains("cr")
		and repair_label.icon_size == screen.find_child("FleetRepairAll", true, false).get_theme_font_size("font_size"),
		"Repair cost renders a text-sized credits icon instead of cr")
	check(fleet_totals != null and fleet_totals.source_text == "DPS 10.8\nShield 40\nHull 1390 / 1390\n1 RP / day\nCargo 0 / 20",
		"Empty selection shows summed fleet combat stats and research, without zero capacities: " + fleet_totals.source_text)
	var summary_ship := HangarShip.new()
	check(summary_ship.initialize_chassis("transport", 999), "Initialize fleet-summary fixture")
	for equipment: String in ["cargo_hold", "passenger_cabin", "research_lab", "shield_generator", "mini_turret"]:
		var item := SlotCatalog.find_equipment(equipment)
		var part := ShipPart.new(0, 0, Vector2i.ZERO, [], ShipPartStats.new())
		part.definition_id = equipment
		part.type = int(item.part_type)
		part.rank = int(item.rank)
		part.stats = SlotCatalog.stats_for(equipment, int(item.rank))
		summary_ship._append_mount(equipment, Vector2.ZERO, part)
	state.fleet.append(summary_ship)
	screen._show_details()
	fleet_totals = screen.details.find_child("FleetTotals", true, false)
	var fixture_summary := summary_ship.hangar_summary()
	check(fleet_totals.source_text == "DPS %.1f\nShield %.0f\nHull 1310 / 1310\n10 RP / day\nCargo 0 / 30\nPassengers 0 / 4" % [
		10.8 + fixture_summary.dps, 40 + fixture_summary.shields],
		"Fleet totals include operational weapons, shields, labs, cargo and passenger capacity: " + fleet_totals.source_text)
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720)]:
		root.size = resolution
		await settle()
		check(screen.details_panel.get_global_rect().encloses(fleet_totals.get_global_rect()),
			"Fleet summary with capacities fits the detail panel")
	root.size = Vector2i(1280, 720)
	await settle()
	await capture("fleet-totals")
	summary_ship.hull_hp -= 15
	screen._show_details()
	fleet_totals = screen.details.find_child("FleetTotals", true, false)
	check(fleet_totals.source_text == "DPS %.1f\nShield %.0f\nHull 1295 / 1310\n10 RP / day\nCargo 0 / 30\nPassengers 0 / 4" % [
		10.8 + fixture_summary.dps, 40 + fixture_summary.shields],
		"Damaged hull contributes exact current/max while all fitted equipment and capacity stay operational: " + fleet_totals.source_text)
	summary_ship.hull_hp = -1
	screen._show_details()
	fleet_totals = screen.details.find_child("FleetTotals", true, false)
	check(fleet_totals.source_text == "DPS 10.8\nShield 40\nHull 1390 / 1390\n1 RP / day\nCargo 0 / 20",
		"Destroyed ships contribute no operational fleet totals")
	state.fleet.erase(summary_ship)
	screen._show_details()
	state.fleet[0].hull_hp -= 10
	state.fleet[1].hull_hp -= 15
	check(state.save_run_checkpoint(), "Damage fixture")
	screen._refresh()
	await settle()
	var credits: int = state.credits
	check(state.fleet_repair_cost() == 25, "Repair-all quote sums hull damage")
	var save_path: String = state.run_save_path
	var blocker := FileAccess.open("user://blocked-save", FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	state.run_save_path = "user://blocked-save/run.json"
	var damaged: Dictionary = state.hangar_snapshot()
	check(not state.repair_all_ships() and state.hangar_snapshot() == damaged, "Failed repair-all save restores credits and every ship")
	state.run_save_path = save_path
	state.credits = 0
	check(not state.repair_all_ships() and state.fleet_repair_cost() == 25, "Unaffordable repair all cannot partially repair")
	state.credits = credits
	screen.find_child("FleetRepairAll", true, false).pressed.emit()
	await settle()
	check(state.credits == credits - 25 and state.fleet_repair_cost() == 0, "Repair all repairs fleet and charges once")
	check(screen.find_child("FleetRepairAll", true, false).disabled, "Full fleet disables repair all")
	var escort_id: int = state.fleet[1].id
	screen._confirm_salvage(escort_id)
	await settle()
	check(state.owned_ship(escort_id) != null and screen.shop != null, "Salvage waits for confirmation")
	await capture("salvage-confirm")
	screen.shop.find_child("CloseX", true, false).pressed.emit()
	await settle()
	check(state.owned_ship(escort_id) != null, "X cancels salvage")
	screen._confirm_salvage(escort_id)
	await settle()
	for candidate in screen.shop.find_children("*", "Button", true, false):
		if candidate.text == "SALVAGE":
			candidate.pressed.emit()
			break
	await settle()
	check(state.owned_ship(escort_id) == null and screen.shop == null, "Confirm salvages escort")
	screen._confirm_salvage(1)
	check(screen.shop == null, "Flagship cannot be salvaged")
	var item := SlotCatalog.find_equipment("mini_turret")
	var texture := SlotCatalog.equipment_texture(item)
	var bounds := Rect2(10, 20, 80, 80)
	var fitted := SlotCatalog.fitted_art_rect(texture, bounds, item.art_mount)
	check((fitted.position + Vector2(62, 65) * fitted.size.x / 124).is_equal_approx(bounds.get_center()), "Turret circular base aligns to mount center")
	check(is_equal_approx(fitted.size.x / 124 * 82, bounds.size.x), "Turret base diameter matches mount")
	board = screen.formation_view
	var starfield: Control = board.starfield
	var star = starfield._stars[0]
	var star_position: Vector2 = starfield._get_star_position(star)
	starfield._process(0.1)
	check(starfield._get_star_position(star).is_equal_approx(star_position), "Space stars stay stationary")
	var click := InputEventMouseButton.new()
	click.position = star_position
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	starfield._gui_input(click)
	check(star.click_flash_remaining > 0, "Stars respond to clicks")
	var layout := star_layout(starfield)
	check(layout.size() == 220, "Area has a stable pool independent of visible star count")
	for action in range(3):
		screen._refresh()
		await settle()
		check(star_layout(screen.formation_view.starfield) == layout, "UI refresh preserves every generated star")
	screen.active_tab = "FLEET"
	screen.ship_editor_open = true
	screen.selected_ship_id = 1
	screen._refresh()
	await settle()
	check(star_layout(screen.canvas.starfield) == layout, "Ships uses the same area layout")
	root.size = Vector2i(640, 360)
	await settle()
	check(star_layout(screen.canvas.starfield) == layout, "Resize preserves the area pool")
	root.size = Vector2i(1280, 720)
	await settle()
	check(star_layout(screen.canvas.starfield) == layout, "Resize back restores the same stars")
	screen.canvas.starfield.set_area(state.run_seed, state.current_node_id + 1)
	check(star_layout(screen.canvas.starfield) != layout, "Another map node has its own layout")
	screen.canvas.starfield.set_area(state.run_seed, state.current_node_id)
	check(star_layout(screen.canvas.starfield) == layout, "Returning to a node recreates its original layout")
	check(state.load_run_checkpoint(), "Reload node checkpoint")
	screen.queue_free()
	await settle()
	screen = load("res://scenes/game_map.tscn").instantiate()
	screen.active_tab = "FLEET"
	root.add_child(screen)
	current_scene = screen
	await settle()
	check(star_layout(screen.formation_view.starfield) == layout, "Reopening screen after Continue recreates the area")
	screen.active_tab = "MAP"
	screen._refresh()
	await settle()
	var graph: Control = screen.graph
	check(star_layout(graph.starfield) == layout, "Map uses the same node seed")
	check(not screen.get_theme_color("background_color", "SlotCanvas").r > 0.03, "Space background stays dark")
	var target: int = state.get_reachable_nodes(state.current_node_id)[0]
	var expedition = state.expedition_simulation
	var expedition_position: Vector2 = expedition.state.position_nu
	screen._begin_travel(target)
	check(not screen.traveling and current_scene == screen
		and expedition.state.position_nu.is_equal_approx(expedition_position),
		"Legacy graph travel cannot replace the continuous Fleet travel view")
	check(screen.travel_controls != null and screen.travel_controls.is_visible_in_tree(),
		"Fleet travel controls remain available while inspecting the existing map")
	var generation: int = state.hangar_generation
	screen._on_expedition_destination_selected("refuel_station_1")
	screen._process(0.25)
	check(expedition.state.destination_location_id == "refuel_station_1"
		and expedition.state.position_nu.distance_to(expedition_position) > 0
		and current_scene == screen,
		"Course selection moves the fleet in place without a map-scene transition")
	check(state.hangar_generation > generation, "Expedition course is checkpointed atomically")
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await settle()
	check(menu.space_background.modulate.a == 1, "Menu starts with its background image visible")
	menu._on_start_run_requested(1, "flagship_science")
	await create_timer(0.5).timeout
	check(menu.space_background.modulate.a > 0 and menu.space_background.modulate.a < 1,
		"Background fades gradually during the star warp")
	await create_timer(0.6).timeout
	check(is_zero_approx(menu.space_background.modulate.a),
		"Background is fully transparent after one second of warp")
	await create_timer(3.1).timeout
	check(current_scene != menu and state.fleet[0].chassis_id == "flagship_science",
		"Warp completes and enters the new run with the menu's selected flagship")
	print("UI POLISH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
