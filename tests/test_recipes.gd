extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var equipment: Array = GameDefinitions.entries("equipment")
	_check(MaterialRecipe.validate_registry(equipment).is_empty(), "All base/rank recipes have exactly the permitted opposite-branch collisions.")
	var signatures: Dictionary = {}
	var count := 0
	for definition: Dictionary in equipment:
		var recipes: Array = [definition.recipe]
		for rank: Dictionary in definition.ranks:
			if int(rank.rank) > 1:
				recipes.append(rank.recipe)
		for recipe: String in recipes:
			count += 1
			var cells := MaterialRecipe.parse(recipe)
			var key := MaterialRecipe.signature(cells)
			signatures[key] = true
			for turns in range(4):
				for flip in range(2):
					var transformed := MaterialRecipe.transformed(cells, turns, flip == 1)
					_check(MaterialRecipe.signature(transformed) == key and transformed.size() == cells.size(), "Material labels and counts survive all eight transforms.")
	_check(count == 58 and signatures.size() == 46, "56 base recipes plus two additional lab ranks have 46 unique canonical signatures.")
	_check(MaterialRecipe.signature(MaterialRecipe.parse("OC/.T")) != MaterialRecipe.signature(MaterialRecipe.parse("OT/.C")), "Equal shapes with different material positions remain distinct unless a real symmetry maps them.")
	var invalid := equipment.duplicate(true)
	invalid[2].recipe = "O"
	_check(not MaterialRecipe.validate_registry(invalid).is_empty(), "Reject accidental cross-equipment recipe collisions.")
	invalid = equipment.duplicate(true)
	invalid[16].recipe = "CCCC"
	_check(not MaterialRecipe.validate_registry(invalid).is_empty(), "Reject loss of an intended exclusive recipe pair.")
	var registry := GameDefinitions.snapshot()
	registry.equipment[7].ranks.append({"rank": 2, "recipe": "CCT/CTT/CTT"})
	_check(not GameDefinitions.validate(registry).is_empty(), "Reject duplicate physical lab ranks.")
	registry = GameDefinitions.snapshot()
	registry.equipment[7].ranks.append({"rank": 1, "recipe": "CCT/CTT"})
	_check(not GameDefinitions.validate(registry).is_empty(), "Reject a duplicate rank I declaration as well.")
	var holed_pattern := ShipPartPattern.new(ShipPart.Type.REPAIR_STATION, ShipPart.Category.CORE,
		[Vector2i.ZERO, Vector2i.RIGHT, Vector2i.ONE], "Hole fixture", null, ShipPartStats.new(), true,
		[ShipPart.Category.CORE, ShipPart.Category.DEFENSE, ShipPart.Category.DEFENSE])
	var holed_design := Ship.new()
	holed_design.set_tile_at(Vector2i.ZERO, ShipPart.Category.CORE)
	holed_design.set_tile_at(Vector2i.RIGHT, ShipPart.Category.DEFENSE)
	holed_design.set_tile_at(Vector2i.ONE, ShipPart.Category.DEFENSE)
	preload("res://scripts/builtin_ships.gd")._add_part(holed_design, ShipPart.Type.MINI_TURRET, Vector2i.DOWN)
	_check(not MaterialRecipe.loose_matches(holed_design, [holed_pattern]).is_empty(), "A period outside the footprint may contain unrelated assembled equipment.")
	_check(MaterialRecipe.loose_matches(holed_design, [holed_pattern], {Vector2i.ZERO: true}).is_empty(), "In-flight assembly locks prevent overlapping preview matches.")

	for pattern in ShipPartPattern.get_catalog():
		var pattern_cells: Dictionary = {}
		for index in range(pattern.cell_offsets.size()):
			pattern_cells[pattern.cell_offsets[index]] = pattern.tile_categories[index]
		var definition := GameDefinitions.equipment(pattern.part_type)
		var recipe: String = definition.recipe
		for physical: Dictionary in definition.ranks:
			if int(physical.rank) == pattern.rank:
				recipe = physical.recipe
		_check(MaterialRecipe.signature(pattern_cells) == MaterialRecipe.signature(MaterialRecipe.parse(recipe)), "Live material patterns match their authoritative recipe.")
		for turns in range(4 if pattern.can_rotate else 1):
			for flip in range(2):
				var design := Ship.new()
				var offsets := pattern.get_offsets_for_transform(turns, flip == 1)
				for index in range(offsets.size()):
					design.set_tile_at(offsets[index], pattern.tile_categories[index])
				var part := ShipPart.new(pattern.part_type, pattern.category, Vector2i.ZERO, offsets, pattern.stats,
					pattern.get_hidden_tile_offsets_for_transform(turns, flip == 1), turns, flip == 1, pattern.rank)
				design.add_part(part)
				var data := design.to_design_data()
				var restored := Ship.new()
				_check(restored.load_design_data(JSON.parse_string(JSON.stringify(data))), "Every legal live recipe orientation reloads.")
				_check(restored.parts[0].definition_id == pattern.definition_id and restored.parts[0].quarter_turns == turns
					and restored.parts[0].horizontally_flipped == (flip == 1), "Assembled identity and facing survive even symmetric footprints.")
				_check(restored.parts[0].facing(pattern) == MaterialRecipe.direction(Vector2i.RIGHT, turns, flip == 1), "Weapon facing follows the recipe transform.")
				_check(restored.parts[0].hidden_tile_offsets == part.hidden_tile_offsets, "Exhaust cells retain their transformed footprint.")
				var matches := MaterialRecipe.loose_matches(design, [pattern])
				_check(matches.is_empty(), "Preview never consumes an assembled component.")
				design.clear_parts()
				matches = MaterialRecipe.loose_matches(design, [pattern])
				_check(not matches.is_empty(), "The same physical material can match once explicitly disassembled.")
				var before := design.to_design_data()
				MaterialRecipe.loose_matches(design, [pattern])
				_check(before == design.to_design_data(), "Preview is read-only.")

	var serialized := preload("res://scripts/builtin_ships.gd").drone().to_design_data()
	var original_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	for field in ["definition_id", "rank", "quarter_turns", "horizontally_flipped"]:
		var forged := serialized.duplicate(true)
		forged.parts[0][field] = {"definition_id": "laser", "rank": 2, "quarter_turns": 9, "horizontally_flipped": 1}[field]
		_check(not Ship.new().load_design_data(forged), "Reject forged identity, rank or orientation metadata.")
	Engine.print_error_messages = original_errors

	await _test_editor()
	print("Recipe tests finished: %d failures; %d recipes; %d signatures" % [failures, count, signatures.size()])
	quit(0 if failures == 0 else 1)

func _test_editor() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://recipes/run.json"
	_check(state.start_new_run(1, 42), "Start isolated recipe editor fixture.")
	state.current_research_ids.append("applied_energy")
	for pattern in ShipPartPattern.get_catalog():
		state.discover_part(pattern.part_type)
	var map: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await process_frame
	await process_frame
	var builder: Control = map.build_area
	builder.auto_assemble = false
	state.ship.clear()
	state.ship.set_tile_at(Vector2i(0, 0), ShipPart.Category.OFFENSE)
	builder._evaluate_part_patterns()
	_check(state.ship.parts.is_empty(), "Manual mode leaves loose tiles unconsumed.")
	builder._refresh_assembly_menu()
	_check(not builder.recipe_matches.is_empty() and builder.assembly_menu != null, "Assembly menu exposes loose recipe previews.")
	builder._preview_recipe(100)
	_check(builder.recipe_preview_outlines.size() == 1, "Hover preview outlines actual material cells.")
	builder._clear_recipe_preview()
	await builder._assembly_action(100)
	_check(state.ship.parts.size() == 1, "Explicit match assembly stores the selected equipment identity.")
	var first: ShipPart = state.ship.parts[0]
	state.ship.set_tile_at(Vector2i(1, 0), ShipPart.Category.OFFENSE)
	state.ship.set_tile_at(Vector2i(2, 0), ShipPart.Category.OFFENSE)
	builder.auto_assemble = true
	builder._evaluate_part_patterns()
	_check(state.ship.parts.has(first) and first.type == ShipPart.Type.MINI_TURRET, "Larger overlapping layouts cannot morph an already assembled turret.")
	await builder._assembly_action(2)
	_check(not builder.auto_assemble and state.ship.parts.is_empty() and state.ship.tiles.size() == 3, "Explicit disassembly keeps material and disables automatic reassembly.")
	builder._refresh_assembly_menu()
	_check(builder.recipe_matches[0].pattern.part_type == ShipPart.Type.LASER, "Larger loose matches appear before single-cell matches.")
	await builder._assembly_action(100)
	_check(state.ship.parts.size() == 1 and state.ship.parts[0].type == ShipPart.Type.LASER, "Explicit larger recipe assembly uses only loose material.")
	var assembled: ShipPart = state.ship.parts[0]
	_check(builder._move_ship_by(Vector2i(1, 1)) and state.ship.parts.has(assembled) and assembled.origin == Vector2i(1, 1), "Whole-ship movement preserves assembled identity and facing.")
	builder._undo()
	_check(state.ship.parts.size() == 1 and state.ship.parts[0].origin == Vector2i.ZERO, "Undo restores assembled metadata, not an automatic reinterpretation.")
	builder._redo()
	_check(state.ship.parts[0].origin == Vector2i(1, 1), "Redo preserves assembled metadata.")
	state.ship.clear()
	state.discovered_part_types.erase(ShipPart.Type.ARMOR_BLOCK)
	for cell in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
		state.ship.set_tile_at(cell, ShipPart.Category.DEFENSE)
	builder._evaluate_part_patterns()
	builder._refresh_assembly_menu()
	_check(builder.recipe_matches[0].pattern.part_type == ShipPart.Type.ARMOR_BLOCK, "Undiscovered larger loose matches can be selected explicitly.")
	await builder._assembly_action(100)
	_check(state.active_part_transformations == 0 and state.ship.parts.size() == 1
		and state.ship.parts[0].type == ShipPart.Type.ARMOR_BLOCK, "Discovery completion commits the chosen identity in manual mode.")
	builder._undo()
	_check(state.ship.parts.is_empty() and state.ship.tiles.size() == 4, "Undo of animated assembly returns loose material.")
	# Paint sequentially: the first three cells have already become plates.
	state.ship.clear()
	state.discover_part(ShipPart.Type.ARMOR_BLOCK)
	state.discover_part(ShipPart.Type.SINGLE_PLATE)
	builder.auto_assemble = true
	for cell in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN]:
		state.ship.set_tile_at(cell, ShipPart.Category.DEFENSE)
		builder._evaluate_part_patterns()
	_check(state.ship.parts.size() == 3, "Three separately painted blue cells remain usable plates.")
	var plates: Dictionary = builder._history_state()
	state.ship.set_tile_at(Vector2i.ONE, ShipPart.Category.DEFENSE)
	builder._evaluate_part_patterns()
	builder._record_change(plates)
	_check(state.ship.parts.size() == 1 and state.ship.parts[0].type == ShipPart.Type.ARMOR_BLOCK
		and state.ship.tiles.size() == 4 and builder._part_sprites.size() == 1,
		"Painting the fourth blue cell combines plates into one armor block and removes plate sprites.")
	builder._undo()
	_check(state.ship.parts.size() == 3 and state.ship.tiles.size() == 3, "Undo restores the three plates before the fourth stroke.")
	builder._redo()
	_check(state.ship.parts.size() == 1 and state.ship.parts[0].type == ShipPart.Type.ARMOR_BLOCK, "Redo restores the assembled armor.")
	# Manual assembly must offer the same combination without changing it early.
	state.ship.clear()
	builder.auto_assemble = false
	for cell in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
		preload("res://scripts/builtin_ships.gd")._add_part(state.ship, ShipPart.Type.SINGLE_PLATE, cell)
	builder._evaluate_part_patterns()
	builder._refresh_assembly_menu()
	_check(state.ship.parts.size() == 4 and builder.recipe_matches[0].pattern.part_type == ShipPart.Type.ARMOR_BLOCK,
		"Manual mode offers armor from four plates without auto-converting them.")
	await builder._assembly_action(100)
	_check(state.ship.parts.size() == 1 and state.ship.parts[0].type == ShipPart.Type.ARMOR_BLOCK, "Manual armor assembly also consumes existing plates.")
	map.queue_free()
	current_scene = null
	await process_frame
