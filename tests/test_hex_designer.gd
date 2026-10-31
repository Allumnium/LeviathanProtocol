extends SceneTree

var failures := 0
var checks := 0
var designer: Control

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame in range(3):
		await process_frame

func pointer(point: Vector2, button := MOUSE_BUTTON_LEFT, pressed := true) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = pressed
	root.push_input(event, true)

func click_point(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	pointer(point, button, true)
	pointer(point, button, false)
	await settle()

func click(control: Control) -> void:
	await click_point(control.get_global_rect().get_center())

func paint(cell: Vector2i) -> void:
	await click_point(designer.build_area.global_position + designer.build_area.cell_position(cell))

func capture(name: String) -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/ui-review/hex-designer-%s.png" % name)

func run() -> void:
	root.size = Vector2i(640, 360)
	root.gui_embed_subwindows = true
	var state := root.get_node("GameState")
	var legacy_before: Dictionary = state.ship.to_design_data()
	designer = load("res://scenes/hex_ship_designer.tscn").instantiate()
	root.add_child(designer)
	current_scene = designer
	await settle()
	check(designer.get_script().resource_path == "res://scripts/hex_ship_designer.gd", "Archived hex Designer remains readable without being the active editor.")
	designer.library.path = "user://hex_designer_ui/library.json"
	designer.library.load_library()
	var board: HexBuildArea = designer.build_area
	check(board.grid_layer.tile_set.tile_shape == TileSet.TILE_SHAPE_HEXAGON and board.grid_layer.tile_set.tile_layout == TileSet.TILE_LAYOUT_STAIRS_DOWN and board.grid_layer.tile_set.tile_offset_axis == TileSet.TILE_OFFSET_AXIS_VERTICAL, "Designer uses native flat-topped hex TileMapLayers with axial layout.")
	var art_paths := ["solid_red_tiles.png", "solid_blue_tiles.png", "Green_tech_tiles.png", "solid_purple_tiles.png"]
	for category in range(4):
		var texture := board.palette.material_texture(category)
		check(texture.resource_path == "res://assets/" + art_paths[category] and texture.get_size() == Vector2(64, 55), "Palette uses the owner's actual material image in the correct category.")
		var source: TileSetAtlasSource = board.placed_layer.tile_set.get_source(category + 2)
		check(source.texture == texture, "Material art is shared by native tile rendering and palette UI.")
	for q in range(-8, 9):
		for r in range(-8, 9):
			var cell := Vector2i(q, r)
			check(board.cell_at(board.cell_position(cell)) == cell, "Native picking matches saved axial coordinates, including negative rows.")
			check((board.grid_layer.map_to_local(cell) - board.grid_layer.map_to_local(Vector2i.ZERO)).distance_to(HexMaterialPalette.center(cell)) < 0.001, "Equipment outlines and labels share the exact native flat-hex cell geometry.")
	check(board.size.x > 230 and board.size.y > 200, "Native canvas remains usable at minimum resolution.")
	await click(designer.material_buttons[1])
	var worst := 0
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var start := Time.get_ticks_usec()
		await paint(cell)
		worst = maxi(worst, Time.get_ticks_usec() - start)
	check(worst < 500000, "Placement/assembly plus frames returns within 500ms: %d us" % worst)
	check(board.design.components.size() == 1 and board.design.components[0].equipment_id == "armor_block", "Four blue hexes assemble Armor, consuming the four smaller plates.")
	check(designer.material_labels[1].text == "4" and designer.material_labels[1].size.x >= 18, "Material totals are correct and have enough width to remain legible.")
	check(designer.selected_label.text == "Armor" or "Armor" in designer.selected_label.text, "Clicking equipment shows its identity inline.")
	check("+15%" in designer.bonus_label.text and "+30%" in designer.bonus_label.text, "Selected region displays both bonuses without a tooltip.")
	var line_height: float = designer.bonus_label.get_theme_font("font").get_height(designer.bonus_label.get_theme_font_size("font_size"))
	check(designer.bonus_label.size.y >= line_height * 2 and designer.selected_label.size.y >= line_height, "Context labels reserve enough space to render their equipment name and both bonus lines.")
	check(designer.bonus_label.get_visible_line_count() >= 2, "Both Armor and Range bonus lines are visible with theme line spacing included.")
	await click(designer.undo_button)
	check(board.design.tiles.size() == 3 and board.design.components.size() == 3, "Undo restores materials and pre-upgrade component identities together.")
	await click(designer.redo_button)
	check(board.design.components.size() == 1 and board.design.components[0].equipment_id == "armor_block", "Redo restores the assembled component.")
	await paint(Vector2i(-1, 0))
	await paint(Vector2i(-1, 3))
	check(board.design.tiles.size() == 4, "Structural gap and built-ins remain immutable through actual pointer input.")
	await click(designer.material_buttons[3])
	for cell in [Vector2i(-6, 0), Vector2i(-5, 0), Vector2i(-4, 0), Vector2i(-6, 1), Vector2i(-5, 1), Vector2i(-4, 1)]:
		await paint(cell)
	check(board.design.components.any(func(part: Dictionary) -> bool: return part.equipment_id == "passenger_cabin"), "Six Civic hexes form a cabin even after smaller recipes assemble.")
	await click(designer.material_buttons[1])
	var start := Vector2i(0, -2)
	var finish := Vector2i(3, -2)
	pointer(board.global_position + board.cell_position(start))
	var motion := InputEventMouseMotion.new()
	motion.position = board.global_position + board.cell_position(finish)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	pointer(motion.position, MOUSE_BUTTON_LEFT, false)
	await settle()
	check(board.design.tiles.has(Vector2i(1, -2)) and board.design.tiles.has(Vector2i(2, -2)), "Fast paint drags fill intervening hexes.")
	await click(designer.undo_button)
	check(not board.design.tiles.has(start) and not board.design.tiles.has(finish), "A complete drag stroke undoes as one action.")
	var shared := HexRecipe.cells(HexRecipe.find("focusing_lens"), 0, false, Vector2i(0, -2))
	for cell: Vector2i in shared:
		await click(designer.material_buttons[shared[cell]])
		await paint(cell)
	check(designer.assembly_picker.visible and designer.assemble_button.visible, "Shared branch recipes expose an inline equipment choice.")
	for index in range(designer._pending.size()):
		if designer._pending[index].equipment_id == "ion_emitter":
			designer.assembly_picker.select(index)
	await click(designer.assemble_button)
	check(board.design.components.any(func(component: Dictionary) -> bool: return component.equipment_id == "ion_emitter"), "Assemble button preserves the player's explicit branch choice.")
	designer.name_input.text = "Hex UI test"
	await click(designer.save_button)
	check(designer.library.designs.has("Hex UI test"), "Save button persists a versioned hex design.")
	var saved := board.design.to_data()
	await click(designer.load_button)
	check(designer.load_popup.visible, "Load opens the small standard-X library.")
	await click_point(Vector2(designer.load_popup.position) + Vector2(designer.load_popup.size.x - 18, 18))
	check(not designer.load_popup.visible, "The shared top-right X closes the library through native pointer input.")
	check(designer.load_design("Hex UI test") and board.design.to_data() == saved, "Loading restores chassis, materials and equipment identities.")
	await settle()
	check(state.ship.to_design_data() == legacy_before, "Creative hex edits never mutate the legacy campaign ship or research state.")
	await click(designer.material_buttons[1])
	await paint(Vector2i(0, 0))
	check(board.design.to_data() == saved, "Selecting an already-painted material preserves the existing fitted component.")
	await capture("build")
	await click(designer.archive_tab_button)
	check(designer.panel_tabs.current_tab == 1 and designer.archive_details.visible and designer.archive_progress.visible, "Archive keeps the themed three-panel workspace.")
	check(designer.patterns.all(func(pattern: ShipPartPattern) -> bool: return pattern.definition_id != "command_center"), "Archive does not offer a recipe for the uneditable built-in command center.")
	var before: Dictionary = designer.recipe_preview.layout.duplicate()
	for index in range(designer.patterns.size()):
		if designer.patterns[index].definition_id == "thruster":
			designer.archive_list.select(index)
			designer._show_recipe(index)
			check(designer.recipe_preview.equipment_name == "Thruster" and not "archive_art" in designer, "Hex Archive uses an outlined named group without legacy equipment sprites.")
			break
	check(not designer.has_method("_rotate_recipe") and not designer.has_method("_flip_recipe"), "Orientation-free equipment has no Archive rotation controls.")
	await capture("archive")
	await click(designer.build_tab_button)
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		await settle()
		check(designer.get_rect().size.x <= root.get_visible_rect().size.x + 1, "Designer stays within the viewport at larger sizes.")
		await paint(Vector2i(0, 0))
		check(designer.selected_label.text.contains("Armor"), "Native hex picking still selects equipment after viewport resizing.")
		await capture("%d" % size.x)
	check(root.gui_get_focus_owner() == null, "Pointer and canvas controls do not leave keyboard focus outlines.")
	designer.queue_free()
	current_scene = null
	await settle()
	print("Hex Designer: %d checks, %d failures; worst placement %d us" % [checks, failures, worst])
	quit(1 if failures else 0)
