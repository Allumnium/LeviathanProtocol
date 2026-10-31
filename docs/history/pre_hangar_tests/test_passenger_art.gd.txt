extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func cabin_pattern() -> ShipPartPattern:
	for pattern in ShipPartPattern.get_catalog():
		if pattern.part_type == ShipPart.Type.PASSENGER_CABIN:
			return pattern
	return null

func design(turns := 0, flipped := false, legacy := false) -> Ship:
	var result := Ship.new()
	BUILTINS._add_part(result, ShipPart.Type.COMMAND_CENTER, Vector2i(-3, 0))
	var pattern := cabin_pattern()
	if legacy:
		var old_offsets: Array[Vector2i] = [Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)]
		pattern = ShipPartPattern.for_cells(pattern, old_offsets)
	var offsets := pattern.get_offsets_for_transform(turns, flipped)
	for index in range(offsets.size()):
		result.set_tile_at(offsets[index], pattern.tile_categories[index])
	var part := ShipPart.new(pattern.part_type, pattern.category, Vector2i.ZERO, offsets,
		pattern.stats, [], turns, flipped)
	check(result.add_part(part), "Add a cabin without overlapping another component.")
	return result

func run() -> void:
	var pattern := cabin_pattern()
	check(pattern.cell_offsets.size() == 6 and ShipStats.cell_bounds(pattern.cell_offsets).size == Vector2(3, 2), "Current cabin occupies exactly 3 by 2 cells.")
	check(pattern.tile_categories.all(func(category: int) -> bool: return category == ShipPart.Category.CORE), "All six cabin cells use Civic material.")
	check(pattern.preview_texture.resource_path == "res://assets/passenger_cabin.png", "The catalog and Archive use the supplied cabin artwork.")
	check(MaterialRecipe.validate_registry(GameDefinitions.entries("equipment")).is_empty(), "The revised cabin recipe has no canonical recipe collision.")
	for turns in range(4):
		for flipped in [false, true]:
			var blueprint := design(turns, flipped)
			var copy := Ship.new()
			check(copy.load_design_data(blueprint.to_design_data()), "All cabin orientations round-trip through design persistence.")
			var part: ShipPart = copy.parts[1]
			var texture := ShipPartPattern.texture_for_part(pattern, part)
			var original := pattern.preview_texture.get_size()
			check(texture.get_size() == (Vector2(original.y, original.x) if turns % 2 else original), "Cabin artwork rotates with its footprint rather than stretching.")
			var source := pattern.preview_texture.get_image()
			var rendered := texture.get_image()
			for sample in [Vector2i(16,16), Vector2i(64,32), Vector2i(145,105)]:
				var point: Vector2i = sample
				var extent := Vector2i(original)
				for turn in range(turns):
					point = Vector2i(extent.y - 1 - point.y, point.x)
					extent = Vector2i(extent.y, extent.x)
				if flipped:
					point.y = extent.y - 1 - point.y
				check(rendered.get_pixelv(point) == source.get_pixelv(sample), "Sprite pixels follow the cabin's saved rotation and reflection.")
			check(ShipPartPattern.texture_for_part(pattern, part) == texture, "Orientation textures are reused after their first creation.")
			var old := design(turns, flipped, true)
			var old_copy := Ship.new()
			check(old_copy.load_design_data(old.to_design_data()) and old_copy.parts[1].cell_offsets.size() == 4, "Legacy cabins keep their original occupied cells at every orientation.")
	var state := root.get_node("GameState")
	state.run_save_path = "user://passenger_art/run.json"
	check(state.start_new_run(1,42), "Start isolated cabin persistence fixture.")
	state.research_points = 20
	check(state.set_research_focus("civil_hospitality"), "Unlock cabins through current-run research.")
	state.credits = 10000
	check(state.purchase_ship(design(1, true, true), "Legacy cabin"), "Existing cabin blueprints remain constructible/loadable.")
	var owned: FleetShip = state.fleet.back()
	var id := owned.id
	owned.units[1].hp -= 0.25
	var hp: float = owned.units[1].hp
	var key := PassengerRules.component_id(id, 1)
	state.economy_state = PassengerRules.register_components(state.economy_state, state.fleet)
	state.economy_state.passengers.components[key].occupied = 3
	check(state.save_run_checkpoint() and state.load_run_checkpoint(), "An occupied damaged legacy cabin saves and reloads.")
	owned = state.fleet.back()
	check(owned.id == id and owned.units[1].hp == hp and owned.units[1].cells.size() == 4
		and PassengerRules.occupied(state.economy_state, id) == 3, "Reload preserves legacy hull identity, HP, geometry and passengers.")
	check(state.purchase_ship(design(), "New cabin"), "Construct the new six-cell cabin normally.")
	owned = state.fleet.back()
	check(owned.units[1].cells.size() == 6 and state.passenger_manifest().back().capacity == 4, "The 3x2 cabin retains four passenger places.")
	var map: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	state.discover_part(ShipPart.Type.PASSENGER_CABIN)
	map.panel_tabs.current_tab = 3
	await process_frame
	await process_frame
	var archive: Control = map.panel_tabs.get_node("Archive")
	var index: int = archive._part_patterns.find_custom(func(p: ShipPartPattern) -> bool: return p.part_type == ShipPart.Type.PASSENGER_CABIN)
	check(index >= 0 and archive._part_images[index].texture == pattern.preview_texture, "Archive cabin image uses the same supplied asset.")
	archive._on_part_button_pressed(index)
	state.ship = design(1, true)
	map.build_area._restore_loaded_ship_design()
	var assembled: ShipPart = state.ship.parts[1]
	var sprite: Sprite2D = map.build_area._part_sprites[assembled]
	check(sprite.texture == ShipPartPattern.texture_for_part(pattern, assembled), "The builder uses the correctly oriented cabin art.")
	var battle: Control = load("res://scripts/battle_visuals.gd").new()
	root.add_child(battle)
	var geometry: Dictionary = battle._get_owned_render_cache(owned)
	check(geometry.part_rects[1].size == Vector2(3,2) * owned.cell_size, "Battle geometry covers the new six-cell footprint.")
	check(battle._get_pattern_for_part(state.fleet[state.fleet.size()-2].units[1].part).cell_offsets.size() == 4, "Battle rendering resolves legacy cabin geometry separately.")
	battle.free()
	if "--capture" in OS.get_cmdline_user_args():
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280,720)
		root.content_scale_size = Vector2i(640,360)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/passenger-art/archive.png")
		map.panel_tabs.current_tab = 0
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/passenger-art/fleet.png")
		map.hide()
		var sheet := Control.new()
		root.add_child(sheet)
		for flipped in [false, true]:
			for turns in range(4):
				var label := Label.new()
				label.text = "%d%s" % [turns * 90, " mirrored" if flipped else ""]
				label.position = Vector2(turns * 160 + 8, (180 if flipped else 0) + 4)
				sheet.add_child(label)
				var preview: Control = load("res://scripts/ship_design_preview.gd").new()
				preview.position = Vector2(turns * 160 + 4, (180 if flipped else 0) + 24)
				preview.size = Vector2(152, 148)
				sheet.add_child(preview)
				preview.set_ship(design(turns, flipped))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/passenger-art/orientations.png")
		sheet.free()
	map.free()
	current_scene = null
	print("Passenger cabin art/footprint tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
