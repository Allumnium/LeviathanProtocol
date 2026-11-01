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
	check(settings.battle_auto_camera_button is TextureButton
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
	var camera_preference: bool = state.battle_auto_camera
	settings.battle_auto_camera_button.button_pressed = not camera_preference
	check(state.battle_auto_camera == not camera_preference,
		"Settings switch updates and saves boolean preferences")
	settings.battle_auto_camera_button.button_pressed = camera_preference
	settings.popup_centered()
	await settle()
	check(settings.size == Vector2i(304, 186) and settings.content_scale_factor == 1.0
		and root.gui_embed_subwindows and settings.get_visible_rect().size == Vector2(settings.size),
		"Settings uses a compact embedded modal at the same pixel scale as the main UI")
	check(settings.music_slider.get_parent().get_child(0).get_theme_font("font") == ui_theme.default_font,
		"Settings text inherits the same shared bitmap font")
	var music_volume: float = settings.music_slider.value
	var audio: Node = root.get_node("AudioManager")
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
	check(settings.battle_auto_camera_button.texture_pressed == ui_theme.get_icon("on", "SettingsSwitch")
		and settings.battle_auto_camera_button.texture_normal == ui_theme.get_icon("off", "SettingsSwitch"),
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
	check(state._commit_hangar(data) and state.buy_chassis("transport"), "Buy escort")
	screen = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	await settle()
	check(screen.active_tab == "FLEET", "Fleet opens first")
	check(root.snap_2d_transforms_to_pixel and root.snap_2d_vertices_to_pixel,
		"Active viewport snaps UI positions and vertices to pixels")
	var credits_icon: TextureRect = screen.find_child("CreditsIcon", true, false)
	var science_icon: TextureRect = screen.find_child("ScienceIcon", true, false)
	check(credits_icon != null and credits_icon.texture.resource_path == "res://assets/credits.png"
		and science_icon != null and screen.header.text == str(state.credits)
		and screen.research_status.text == "Choose Research",
		"Header uses the credits icon and explicit research status")
	check(absf(science_icon.global_position.y + science_icon.size.y / 2.0
		- screen.research_status.global_position.y - screen.research_status.size.y / 2.0) <= 1.0,
		"Science icon and research status align vertically")
	check(screen.tabs.get_index() == 0 and screen.header.get_parent() == screen.header_wallet,
		"Tabs are left aligned and credits sit in the right-hand wallet")
	check(not screen.research_progress.visible and screen.research_progress.value == 0,
		"No focus hides and clears research progress")
	screen.set_process(false)
	screen.research_pulse_time = 0.0
	screen._process(0.5)
	check(is_equal_approx(screen.research_pulse.get_shader_parameter("white_mix"), 0.08),
		"Research prompt gently fades toward white halfway through its one-second cycle")
	screen._process(0.5)
	check(is_zero_approx(screen.research_pulse.get_shader_parameter("white_mix")),
		"Research prompt returns to normal once per second")
	screen.set_process(true)
	check(state.set_research_focus("applied_energy"), "Set focused research for header")
	var focused: Dictionary = state.hangar_snapshot()
	focused.research.research_progress["applied_energy"] = 1.5
	check(state._commit_hangar(focused), "Save fractional header research progress")
	await settle()
	var required := ResearchFocusRules.cost("applied_energy", state.run_progress_snapshot())
	check(screen.research_status.text == GameDefinitions.find("research", "applied_energy").display_name
		and screen.research_progress.visible and screen.research_progress.value == 1.5
		and screen.research_progress.max_value == required and not screen.research_progress.show_percentage,
		"Header shows technology name and actual fractional project progress in a bar")
	check(screen.research_rate.text == "+1/day" and screen.research_progress.min_value == -1,
		"Research progress has a UI-only negative minimum and adjacent daily production")
	var progress_snapshot: Dictionary = state.hangar_snapshot()
	screen.research_progress.value = 0
	check(screen.research_progress.get_as_ratio() > 0 and state.hangar_snapshot() == progress_snapshot,
		"Zero progress retains a thin visible fill without changing game state")
	screen.research_progress.value = 1.5
	check(is_zero_approx(screen.research_pulse.get_shader_parameter("white_mix")),
		"Selecting a research focus stops the prompt pulse immediately")
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
			"Left tabs, center research and right wallet fit at every resolution")
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
			check(tab.size == first_tab.size and tab.size.x >= 80
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
	check(screen.tabs.size.x == 248 and screen.header_wallet.get_global_rect().end.x <= screen.size.x
		and screen.research_button.get_global_rect().encloses(screen.research_status.get_global_rect())
		and screen.research_button.size.y <= 44,
		"Long research titles wrap without narrowing tabs or pushing the wallet offscreen")
	await capture("research-header-long-640")
	screen.research_status.text = short_research_text
	screen._resize_research_label()
	root.size = Vector2i(1280, 720)
	await settle()
	check(screen.research_button.size.y <= 34, "Research button returns to compact height after a long name")
	check(screen.roster.find_child("BuyEquipment", true, false) == null
		and screen.roster.find_child("BuyChassis", true, false) != null, "Fleet has only Buy Chassis")
	screen.formation_view.camera = Vector2(25, -12)
	screen.formation_view.zoom = 1.3
	var roster_escort_id: int = state.fleet[1].id
	var roster_button: Button = screen.roster.find_child("Ship%d" % roster_escort_id, true, false)
	await drag(roster_button.get_global_rect().get_center(), roster_button.get_global_rect().get_center())
	check(screen.active_tab == "FLEET" and screen.selected_ship_id == roster_escort_id,
		"Single-click Fleet roster selects the escort without opening the editor")
	check(screen.formation_view.find_children("*", "Button", true, false).is_empty(),
		"Selected formation ships have no floating Equip or Salvage buttons")
	roster_button = screen.roster.find_child("Ship%d" % roster_escort_id, true, false)
	var roster_point := roster_button.get_global_rect().get_center()
	motion(roster_point)
	button(roster_point, true, true)
	await process_frame
	button(roster_point, false)
	await settle()
	check(screen.active_tab == "SHIPS" and screen.selected_ship_id == roster_escort_id
		and screen.canvas.owned_id == roster_escort_id and screen.selected_slot.is_empty(),
		"Native Fleet roster double-click opens the matching ship editor")
	check(screen.roster.find_child("Ship%d" % roster_escort_id, true, false).button_pressed,
		"Editor roster marks the double-clicked ship")
	screen.tabs.get_child(0).pressed.emit()
	await settle()
	check(screen.formation_view.camera == Vector2(25, -12) and is_equal_approx(screen.formation_view.zoom, 1.3),
		"Returning from roster double-click preserves formation pan and zoom")
	screen.roster.find_child("Ship%d" % state.fleet[0].id, true, false).pressed.emit()
	await settle()
	screen.tabs.get_child(1).pressed.emit()
	await settle()
	check(screen.roster.find_child("BuyChassis", true, false) == null, "Ships has only Buy Equipment")
	screen.roster.find_child("BuyEquipment", true, false).pressed.emit()
	await settle()
	check(screen.stock != null and screen.stock.get_parent() == screen.details
		and screen.buy_mode == "EQUIPMENT", "Ships equipment shop shows shared stock in the right panel")
	var range_control: Control = screen.stock.filters.size_range
	var range_origin: Vector2 = range_control.global_position
	await drag(range_origin + Vector2(range_control._handle_center(0), 10),
		range_origin + Vector2(range_control._handle_x(1), 10))
	check(screen.stock.filters.get_preferences().sizes == ["M", "L", "XL"]
		and screen.shop_filters.get_preferences() == screen.stock.filters.get_preferences(),
		"Dragging the lower size handle selects an inclusive range and synchronizes shop")
	await drag(range_origin + Vector2(range_control._handle_center(1), 10),
		range_origin + Vector2(range_control._handle_x(1), 10))
	check(screen.stock.filters.get_preferences().sizes == ["M"],
		"Range handles can meet on one inclusive size")
	await drag(range_origin + Vector2(range_control._handle_center(0), 10),
		range_origin + Vector2(range_control._handle_x(0), 10))
	check(screen.stock.filters.get_preferences().sizes == ["S", "M"],
		"Both handles remain selectable when the range has one size")
	await drag(range_origin + Vector2(range_control._handle_center(0), 10),
		range_origin + Vector2(range_control._handle_x(3), 10))
	check(screen.stock.filters.get_preferences().sizes == ["M"],
		"Dragging an endpoint beyond the other handle never crosses it")
	await drag(range_origin + Vector2(range_control._handle_center(1), 10),
		range_origin + Vector2(range_control.size.x + 12, 10))
	check(screen.stock.filters.get_preferences().sizes == ["M", "L", "XL"]
		and range_control.dragging_handle == -1,
		"Releasing outside the range clamps to the final stop and ends dragging")
	screen.stock.filters.set_preferences({"sizes": ["S", "L"]})
	screen.stock._change()
	check(screen.stock.filters.get_preferences().sizes == ["S", "M", "L"],
		"Disjoint historical size preferences normalize to their inclusive span")
	screen.stock.filters.set_preferences({})
	screen.stock._change()
	await settle()
	var before_purchase: int = state.equipment_inventory.size()
	for purchase: Button in screen.shop_rows.get_children():
		if not purchase.disabled:
			var row_center := purchase.get_global_rect().get_center()
			await drag(row_center, row_center)
			check(state.equipment_inventory.size() == before_purchase,
				"Clicking the equipment shop row does not purchase")
			purchase.pressed.emit()
			check(state.equipment_inventory.size() == before_purchase,
				"Equipment inspection row has no purchase callback")
			check(not screen.inspected_item.is_empty() and screen.inspection != null and not screen.stock.visible,
				"Equipment row opens inspection while retaining hidden stock")
			var buy: TextureButton = purchase.find_child("BuyIcon", true, false)
			check(buy != null and buy.size == Vector2(32, 32) and purchase.size.y < 52,
				"Equipment has a double-size green buy button and compact row")
			await drag(buy.get_global_rect().get_center(), buy.get_global_rect().get_center())
			break
	await settle()
	check(screen.stock != null and screen.buy_open and state.equipment_inventory.size() == before_purchase + 1,
		"Equipment purchases refresh stock while keeping the shop open")
	await capture("fleet-equipment-shop")
	screen.roster.find_child("BuyEquipment", true, false).pressed.emit()
	await settle()
	screen.tabs.get_child(0).pressed.emit()
	await settle()
	check(screen.stock == null and screen.details.get_child(0).text == state.fleet[0].display_name,
		"Closing Fleet equipment shop restores ship details")
	await drag(screen.research_status.get_global_rect().get_center(), screen.research_status.get_global_rect().get_center())
	check(screen.active_tab == "RESEARCH" and screen.research_button.button_pressed,
		"Clicking embedded research content activates its tab")
	await settle()
	var research: Control = screen.research_panel
	research.tree_canvas.camera_position = Vector2(320, 180)
	research.tree_canvas.camera_zoom = 1.4
	research.tree_canvas._update_camera()
	research.card_buttons["laboratory_ii"].pressed.emit()
	await settle()
	check(screen.research_panel.tree_canvas.camera_position == Vector2(320, 180)
		and screen.research_panel.tree_canvas.camera_zoom == 1.4,
		"Selecting research preserves pan and zoom")
	var research_card: Button = research.card_buttons["laboratory_ii"]
	research.tree_canvas.camera_position = research.tree_canvas.positions["laboratory_ii"] + research.tree_canvas.CARD_SIZE * 0.5
	research.tree_canvas._update_camera()
	var research_camera: Vector2 = research.tree_canvas.camera_position
	await settle()
	var card_center := research_card.get_global_rect().get_center()
	motion(card_center)
	button(card_center, true, true)
	button(card_center, false)
	await settle()
	check(state.research_focus == "laboratory_ii", "Native double-click sets the research focus")
	var focus_snapshot: Dictionary = state.hangar_snapshot()
	screen.research_panel._activate("laboratory_ii")
	screen.research_panel._activate("laboratory_iii")
	check(state.hangar_snapshot() == focus_snapshot, "Double-click cannot refocus the same technology or bypass prerequisites")
	var focus_blocker := FileAccess.open("user://focus-save-blocked", FileAccess.WRITE)
	focus_blocker.store_string("not a directory")
	focus_blocker.close()
	var focus_save_path: String = state.run_save_path
	state.run_save_path = "user://focus-save-blocked/run.json"
	screen.research_panel._activate("applied_energy")
	await settle()
	check(state.hangar_snapshot() == focus_snapshot and not screen.feedback.text.is_empty(),
		"Failed double-click focus save rolls back state and displays the existing failure notification")
	state.run_save_path = focus_save_path
	screen.research_panel._select("laboratory_ii")
	check(screen.research_panel.tree_canvas.camera_position == research_camera
		and screen.research_panel.tree_canvas.camera_zoom == 1.4
		and screen.research_panel.selected_id == "laboratory_ii",
		"Research focus refresh preserves camera and selection")
	screen.tabs.get_child(0).pressed.emit()
	await settle()
	screen.research_button.pressed.emit()
	await settle()
	check(screen.research_panel.tree_canvas.camera_position == research_camera
		and screen.research_panel.tree_canvas.camera_zoom == 1.4,
		"Returning to Research preserves the user's view")
	await capture("research-view-preserved")
	screen.tabs.get_child(0).pressed.emit()
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
	await drag(origin + first - Vector2(40, 50), origin + second + Vector2(40, 50))
	board = screen.formation_view
	check(board.selected_ids.size() == 2 and screen.selected_ship_id == 0, "Native box select selects both ships")
	check(board.camera == Vector2(20, -15) and is_equal_approx(board.zoom, 1.2), "Selection preserves camera")
	await capture("group-selected")
	var before_a: Vector2 = state.fleet[0].formation
	var before_b: Vector2 = state.fleet[1].formation
	var background_position: Vector2 = board.starfield._get_star_position(board.starfield._stars[0])
	var start: Vector2 = board.global_position + board.point(state.fleet[0])
	check(board._hit(board.point(state.fleet[0])) == state.fleet[0].id, "Ship center is a native hit target")
	await drag(start, start + Vector2(40, 20))
	board = screen.formation_view
	check(not state.fleet[0].formation.is_equal_approx(before_a), "Native group drag moves ships")
	check((state.fleet[1].formation - state.fleet[0].formation).is_equal_approx(before_b - before_a), "Group drag preserves spacing")
	check(board.selected_ids.size() == 2 and board.camera == Vector2(20, -15) and is_equal_approx(board.zoom, 1.2), "Move retains selection, pan and zoom")
	check(board.starfield._get_star_position(board.starfield._stars[0]).is_equal_approx(background_position), "Moving ships does not reshuffle stationary stars")
	var saved: Dictionary = state.hangar_snapshot()
	check(state.load_run_checkpoint(), "Load moved formation")
	check(state.hangar_snapshot().ships == saved.ships, "Group positions persist")
	saved = state.hangar_snapshot()
	var blocker := FileAccess.open("user://blocked-save", FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	var save_path: String = state.run_save_path
	state.run_save_path = "user://blocked-save/run.json"
	check(not state.move_ships({1: Vector2.ZERO}), "Group move reports failed save")
	check(state.hangar_snapshot() == saved, "Failed group save preserves whole fleet")
	state.run_save_path = save_path
	check(not state.move_ships({1: Vector2(6, 0)}) and state.hangar_snapshot() == saved, "Out-of-bounds group move is rejected atomically")
	await settle()
	board = screen.formation_view
	var empty: Vector2 = board.global_position + Vector2(20, 20)
	await drag(empty, empty)
	check(screen.selected_ship_id == 0 and screen.formation_view.selected_ids.is_empty(), "Empty-space click deselects")
	check(screen.details.get_child(1).get_meta("resource_text", "").begins_with("REPAIR ALL"), "Empty selection offers repair all")
	var fleet_totals: ResourceText = screen.details.find_child("FleetTotals", true, false)
	check(not fleet_totals.get_parsed_text().contains("RP") and fleet_totals.icon_size == ui_theme.default_font_size,
		"Fleet science renders an inline icon at the surrounding font size")
	var repair_label: ResourceText = screen.details.get_child(1).find_child("ResourceText", true, false)
	check(repair_label != null and not repair_label.get_parsed_text().contains("cr")
		and repair_label.icon_size == screen.details.get_child(1).get_theme_font_size("font_size"),
		"Repair cost renders a text-sized credits icon instead of cr")
	check(fleet_totals != null and fleet_totals.source_text == "DPS 7.2\nShield 40\nHull 960 / 960\n1 RP / day",
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
	check(fleet_totals.source_text == "DPS %.1f\nShield %.0f\nHull 1180 / 1180\n2 RP / day\nCargo capacity 10\nPassenger capacity 4" % [
		7.2 + fixture_summary.dps, 40 + fixture_summary.shields],
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
	check(fleet_totals.source_text == "DPS %.1f\nShield %.0f\nHull 1165 / 1180\n2 RP / day\nCargo capacity 10\nPassenger capacity 4" % [
		7.2 + fixture_summary.dps, 40 + fixture_summary.shields],
		"Damaged hull contributes exact current/max while all fitted equipment and capacity stay operational: " + fleet_totals.source_text)
	summary_ship.hull_hp = -1
	screen._show_details()
	fleet_totals = screen.details.find_child("FleetTotals", true, false)
	check(fleet_totals.source_text == "DPS 7.2\nShield 40\nHull 960 / 960\n1 RP / day",
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
	state.run_save_path = "user://blocked-save/run.json"
	var damaged: Dictionary = state.hangar_snapshot()
	check(not state.repair_all_ships() and state.hangar_snapshot() == damaged, "Failed repair-all save restores credits and every ship")
	state.run_save_path = save_path
	state.credits = 0
	check(not state.repair_all_ships() and state.fleet_repair_cost() == 25, "Unaffordable repair all cannot partially repair")
	state.credits = credits
	screen.details.get_child(1).pressed.emit()
	await settle()
	check(state.credits == credits - 25 and state.fleet_repair_cost() == 0, "Repair all repairs fleet and charges once")
	check(screen.details.get_child(1).disabled, "Full fleet disables repair all")
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
	screen.active_tab = "SHIPS"
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
	graph.start_travel(target)
	check(graph._travel_duration >= 2 and graph._travel_duration <= 3, "Distance-scaled travel takes 2-3 seconds")
	graph.set_process(false)
	graph._process(graph._travel_duration * 0.25)
	check(graph._ship_world_position.is_equal_approx(graph._travel_start.lerp(graph._travel_end, 0.25)), "Travel flies linearly at a steady speed")
	graph._traveling = false
	graph.set_process(true)
	screen._begin_travel(target)
	check(screen.traveling and graph._traveling, "Actual Travel starts flight before changing scene")
	var generation: int = state.hangar_generation
	screen._begin_travel(target)
	check(state.hangar_generation == generation, "Double travel cannot settle twice")
	await create_timer(0.6).timeout
	check(is_instance_valid(graph) and graph._travel_elapsed > 0 and graph._traveling, "Flight remains visible en route")
	await capture("map-flight")
	await create_timer(3.0).timeout
	check(current_scene != screen or not screen.traveling, "Flight finishes and resumes destination")
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
