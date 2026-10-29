extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _basic_stats(shields: float = 0.0) -> ShipStats:
	var stats := ShipStats.new()
	stats.integrity = 50.0
	stats.shields = shields
	stats.thrust = 25.0
	stats.weight = 11.0 # A finite-mass combat fixture under the shared movement law.
	stats.weapons.append(ShipWeaponStats.new("Test laser", 0.5, 5.0, 1))
	return stats


func _fleet(count: int, seed_value: int = 0) -> Array[RefCounted]:
	var result: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(count, 1.0, seed_value):
		result.append(alien)
	return result


func _run() -> void:
	var state := root.get_node("GameState")
	var archive_test_path := "user://archive_progress_suite_%d.json" % Time.get_ticks_usec()
	state.archive_progress_file_path = archive_test_path
	await _test_main_menu_setup_flow()
	_test_starter_drones()
	_test_weapon_range()
	_test_player_fleet()
	_test_thrust_movement()
	_test_ship_cost()
	_test_owned_fleet()
	_test_design_selection()
	_test_material_shortages()
	_test_run_loss()
	_test_build_area()
	_test_ship_design_storage()
	_test_archive_progress_storage()
	_test_settings_storage()
	_test_mini_turret_firing()
	_test_guaranteed_hits()
	_test_retreat_and_focus()
	_test_continuous_pursuit()
	_test_drop_distribution()
	_test_salvage()
	_test_stationary_salvage()
	_test_defeat()
	_test_combat_events()
	_test_balance()
	await _test_scene()
	for child in root.get_node("AudioManager").get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	await create_timer(0.1).timeout
	if FileAccess.file_exists(archive_test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(archive_test_path))
	print("Battle tests finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _test_main_menu_setup_flow() -> void:
	var menu: Variant = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	_check(menu.ship_designer_button != null and menu.ship_designer_button.text == "SHIP DESIGNER",
		"The main menu must provide a standalone Ship Designer button.")
	var settings_dialog := menu.settings_dialog as PopupPanel
	var settings_close := settings_dialog.get_node("CloseX") as TextureButton
	var auto_camera_button := settings_dialog.get_node(
		"Contents/ContentArea/BattleAutoCameraRow/BattleAutoCameraButton"
	) as Button
	_check(settings_dialog.exclusive,
		"Clicking outside the Settings popup must not dismiss it.")
	_check(
		settings_close.get_index() == settings_dialog.get_child_count() - 1
			and settings_close.size == Vector2(24, 24)
			and settings_close._has_point(Vector2(12, 23)),
		"The complete visible Settings X must remain above the popup contents and clickable."
	)
	_check(
		auto_camera_button != null
			and auto_camera_button.custom_minimum_size == Vector2(180, 40)
			and auto_camera_button.text in ["ON", "OFF"],
		"Battle auto-camera must use the same framed button presentation as difficulty."
	)
	menu.play_button.pressed.emit()
	var setup_close := menu.game_setup.back_button as TextureButton
	_check(
		menu.game_setup.visible and not menu.menu_ui.visible
			and is_zero_approx(menu.starfield._warp_progress),
		"Play must show mission setup before beginning the starfield warp."
	)
	_check(
		setup_close.get_index() == setup_close.get_parent().get_child_count() - 1
			and setup_close._has_point(Vector2(12, 23)),
		"The complete visible Mission Setup X must be above its contents and clickable."
	)
	_check(menu.game_setup.difficulty_button.text == "NORMAL", "Mission setup must default to Normal difficulty.")
	menu.game_setup.difficulty_button.pressed.emit()
	_check(menu.game_setup.difficulty_button.text == "HARD", "Difficulty must cycle from Normal to Hard.")
	menu.game_setup.difficulty_button.pressed.emit()
	_check(menu.game_setup.difficulty_button.text == "EASY", "Difficulty must cycle from Hard to Easy.")
	menu.game_setup.difficulty_button.pressed.emit()
	_check(menu.game_setup.difficulty_button.text == "NORMAL", "Difficulty must cycle from Easy to Normal.")
	menu.game_setup.back_button.pressed.emit()
	_check(
		not menu.game_setup.visible and menu.menu_ui.visible,
		"Backing out of mission setup must restore the title menu."
	)
	menu.play_button.pressed.emit()
	_check(
		menu.game_setup.visible and menu.game_setup.setup_modal.visible,
		"Reopening mission setup must restore its panel instead of leaving only the dark backdrop."
	)
	menu.game_setup.back_button.pressed.emit()
	root.remove_child(menu)
	menu.free()
	var standalone_designer: Variant = load("res://scenes/ship_designer.tscn").instantiate()
	root.add_child(standalone_designer)
	await process_frame
	_check(
		standalone_designer.build_tab_button != null
			and standalone_designer.build_tab_button.text == "SHIP BUILDER"
			and standalone_designer.archive_tab_button != null
			and standalone_designer.archive_tab_button.text == "ARCHIVE",
		"The standalone designer must provide Ship Builder and Archive workspace tabs."
	)
	standalone_designer.archive_tab_button.pressed.emit()
	_check(
		standalone_designer.panel_tabs.current_tab == 1
			and standalone_designer.archive_details.visible
			and standalone_designer.archive_progress.visible
			and not standalone_designer.build_controls.visible,
		"The standalone Archive tab must reuse the three-panel workspace arrangement."
	)
	root.remove_child(standalone_designer)
	standalone_designer.free()


func _clear_test_fleet(state: Node) -> void:
	# Combat fixtures below deliberately exercise a single custom ship.
	# Fixture research is explicit and must never come from Archive discovery.
	state.current_research_ids.assign(["foundation", "applied_energy", "field_engineering"])
	state.fleet.clear()
	state.next_ship_id = 1
	state._refresh_fleet()

func _test_starter_drones() -> void:
	var state := root.get_node("GameState")
	state.start_new_run(GameState.Difficulty.MEDIUM, -1, false)
	_check(state.fleet.size() == 3 and state.player_ship_count == 3 and state.can_deploy(), "New runs must begin with three deployable Drones.")
	_check(state.credits == state.STARTING_CREDITS and state.red_tiles_available == state.STARTING_RED_TILE_COUNT and state.blue_tiles_available == state.STARTING_BLUE_TILE_COUNT and state.green_tiles_available == state.STARTING_GREEN_TILE_COUNT, "Starter ships must not consume starting resources.")
	var drone: FleetShip = state.fleet[0]
	_check(state.design_bounds(drone.design).size == Vector2i(7, 6) and drone.design.tiles.size() == 34, "Drone must match the reference's 7 by 6 layout and 34 occupied tiles.")
	_check(drone.design.parts.filter(func(part: ShipPart) -> bool: return part.type == ShipPart.Type.MINI_TURRET).size() == 6, "Drone must have six mini-turrets.")
	_check(drone.is_alive() and drone.repair_cost() == 0, "Starter Drones must be intact and connected.")
	drone.units[0].hp = 0
	_check(state.fleet[1].units[0].hp > 0 and state.fleet[2].units[0].hp > 0, "Each starter Drone must own independent damage state.")
	_check(state.load_saved_ship_design("Drone") and state.ship.tiles.size() == 34, "The built-in Drone must be loadable without a saved file.")
	_check(not state.delete_saved_ship_design("Drone"), "The built-in Drone must be protected from deletion.")
	state.start_new_run(GameState.Difficulty.MEDIUM, -1, false)
	_check(state.fleet.size() == 3 and state.fleet[0].repair_cost() == 0, "Restarting must replace, not accumulate, starter ships.")

func _test_weapon_range() -> void:
	var weapon := ShipWeaponStats.new("Short laser", 1.0, 10.0, 1, 130.0)
	_check(weapon.copy().range_units == 130.0, "Weapon copying must preserve range.")
	var stats := _basic_stats()
	stats.weapons.append(weapon)
	var simulation := BattleSimulation.new()
	_check(simulation.setup(stats, _fleet(3), 1), "Battle setup failed.")
	_check(simulation.player.shortest_range() == 130.0, "AI must use shortest weapon range.")
	simulation.aliens[0].position = Vector2(700.0, 0.0)
	simulation.advance(1.0 / 60.0)
	_check(simulation.beams.is_empty(), "Lasers must not fire outside range.")


func _test_player_fleet() -> void:
	var fleet := _fleet(18, 19)
	var simulation := BattleSimulation.new()
	_check(simulation.setup(_basic_stats(), fleet, 19, 6), "Six-ship battle setup failed.")
	_check(simulation.players.size() == 6, "Battle setup must create the configured player fleet.")
	_check(simulation.living_player_count() == 6, "All deployed player ships must start alive.")
	for player_ship in simulation.players:
		for alien in simulation.aliens:
			_check(
				player_ship.position.distance_to(alien.position) > 500.0,
				"Player and alien ships must start farther apart."
			)

	var scaled_fleet := AlienShip.create_random_fleet(18, 1.0, 20)
	var total_health := 0.0
	for alien in scaled_fleet:
		total_health += alien.stats.integrity + alien.stats.shields
	_check(is_equal_approx(total_health, 21.25),
		"The legacy enemy budget must be independent of player fleet size.")
	_check(simulation.aliens.all(func(alien: BattleSimulation.Combatant) -> bool: return is_equal_approx(alien.radius, 7.0)),
		"Alien combat size and collision radius must be halved.")

	var firing_simulation := BattleSimulation.new()
	firing_simulation.setup(_basic_stats(), _fleet(1, 23), 23, 6)
	var target := firing_simulation.aliens[0]
	target.position = firing_simulation.players[0].position + Vector2(210.0, 0.0)
	target.integrity = 1000.0
	target.shields = 0.0
	target.cooldowns[0] = 100.0
	firing_simulation.advance(1.0 / 60.0)
	_check(
		firing_simulation.beams.size() == 6,
		"Every player ship must fire its weapons as a player ship."
	)
	_check(
		is_equal_approx(target.integrity, 970.0),
		"Every player ship must contribute damage to its target."
	)


func _test_thrust_movement() -> void:
	var low_thrust_stats := _basic_stats()
	low_thrust_stats.thrust = 10.0
	var high_thrust_stats := _basic_stats()
	high_thrust_stats.thrust = 20.0
	var low_thrust_simulation := BattleSimulation.new()
	var high_thrust_simulation := BattleSimulation.new()
	low_thrust_simulation.setup(low_thrust_stats, _fleet(1), 21)
	high_thrust_simulation.setup(high_thrust_stats, _fleet(1), 21)
	_check(
		high_thrust_simulation.player.speed > low_thrust_simulation.player.speed
			and high_thrust_simulation.player.speed < low_thrust_simulation.player.speed * 2.0,
		"Extra thrust improves speed with diminishing returns at fixed mass."
	)
	var enemy := low_thrust_simulation.aliens[0]
	enemy.position = low_thrust_simulation.player.position + Vector2(400.0, 0.0)
	low_thrust_simulation.player.heading = PI
	low_thrust_simulation._update_ship(low_thrust_simulation.player, 1.0 / 60.0)
	_check(
		low_thrust_simulation.player.velocity.x < 0.0
			and low_thrust_simulation.player.velocity.length() < low_thrust_simulation.player.speed * 0.1
			and low_thrust_simulation.player.heading > 2.5,
		"Ships must accelerate forward while gradually turning toward their desired course."
	)
	low_thrust_simulation.player.target = null
	low_thrust_simulation.player.target_refresh_remaining = 1.0
	low_thrust_simulation.player.velocity = Vector2(40.0, 0.0)
	var coast_start := low_thrust_simulation.player.position
	low_thrust_simulation._update_ship(low_thrust_simulation.player, 0.5)
	_check(
		low_thrust_simulation.player.position.x > coast_start.x
			and low_thrust_simulation.player.velocity.x > 0.0
			and low_thrust_simulation.player.velocity.x < 40.0,
		"A ship without a target must coast and decelerate gradually instead of stopping."
	)
	low_thrust_simulation.player.position = Vector2.ZERO
	enemy.position = Vector2(400.0, 0.0)
	var flyby_direction: Vector2 = low_thrust_simulation._flyby_direction(
		low_thrust_simulation.player, enemy
	)
	var flyby_closest_approach := absf(
		(enemy.position - low_thrust_simulation.player.position).cross(flyby_direction)
	)
	_check(
		is_equal_approx(
			flyby_closest_approach,
			low_thrust_simulation.player.shortest_range()
				* low_thrust_simulation.FLYBY_RANGE_FACTOR
		),
		"Pursuit must aim for a broadside pass at minimum weapon range."
	)
	low_thrust_simulation.player.velocity = -flyby_direction * 40.0
	var reverse_test_speed := low_thrust_simulation.player.velocity.length()
	low_thrust_simulation._apply_limited_reverse_thrust(
		low_thrust_simulation.player, flyby_direction * low_thrust_simulation.player.speed, 0.5
	)
	_check(
		low_thrust_simulation.player.velocity.length() < reverse_test_speed
			and low_thrust_simulation.player.velocity.length() > 0.0,
		"Reverse thrust must slow a bad approach without stopping the ship instantly."
	)


func _test_ship_cost() -> void:
	var short_notch_cells: Array[Vector2i] = []
	for y in range(5):
		short_notch_cells.append(Vector2i(0, y))
		short_notch_cells.append(Vector2i(4, y))
	for x in range(1, 4):
		short_notch_cells.append(Vector2i(x, 4))
	var short_notch_hull := Ship.create_hull_polygon(short_notch_cells)
	_check(Geometry2D.is_point_in_polygon(Vector2(2.5, 0.75), short_notch_hull),
		"Hull wedges may bridge at most three empty grid cells.")
	var long_notch_cells: Array[Vector2i] = []
	for y in range(5):
		long_notch_cells.append(Vector2i(0, y))
		long_notch_cells.append(Vector2i(5, y))
	for x in range(1, 5):
		long_notch_cells.append(Vector2i(x, 4))
	var long_notch_hull := Ship.create_hull_polygon(long_notch_cells)
	_check(not Geometry2D.is_point_in_polygon(Vector2(3.0, 0.75), long_notch_hull),
		"Hull edges must follow the occupied squares when a gap exceeds three cells.")
	var state := root.get_node("GameState")
	var top_layer_types := [
		ShipPart.Type.COMMAND_CENTER,
		ShipPart.Type.LASER,
		ShipPart.Type.DOUBLE_LASER,
		ShipPart.Type.MINI_TURRET,
		ShipPart.Type.THRUSTER,
		ShipPart.Type.LARGE_THRUSTER,
	]
	for pattern in ShipPartPattern.get_catalog():
		var expected_tech_category := ShipPart.TechCategory.CORE
		if pattern.part_type in [ShipPart.Type.LASER, ShipPart.Type.DOUBLE_LASER, ShipPart.Type.SHIELD]:
			expected_tech_category = ShipPart.TechCategory.ENERGY
		elif pattern.part_type == ShipPart.Type.LARGE_THRUSTER:
			expected_tech_category = ShipPart.TechCategory.UTILITY
		_check(pattern.tech_category == expected_tech_category,
			"Every equipment pattern must belong to its intended technology branch.")
		if pattern.part_type == ShipPart.Type.DOUBLE_LASER:
			_check(pattern.prerequisite_types == [ShipPart.Type.LASER],
				"Double Laser must depend on Laser in the technology tree.")
		_check(state.is_equipment_available(pattern.part_type) == state.is_equipment_researched(pattern.part_type),
			"Working catalog equipment availability must follow current-run research.")
		_check(
			pattern.renders_on_top == (pattern.part_type in top_layer_types),
			"Guns, thrusters, and the command core must render above the translucent hull."
		)
		var flipped_offsets := pattern.get_offsets_for_transform(0, true)
		_check(
			pattern.get_transform_for_offsets(flipped_offsets).x >= 0,
			"Every component recipe must recognize its horizontal reflection."
		)
		if pattern.part_type == ShipPart.Type.COMMAND_CENTER:
			var flipped_command := Ship.new()
			for index in range(flipped_offsets.size()):
				flipped_command.set_tile_at(
					flipped_offsets[index], pattern.tile_categories[index]
				)
			flipped_command.add_part(ShipPart.new(
				pattern.part_type,
				pattern.category,
				Vector2i.ZERO,
				flipped_offsets,
				pattern.stats
			))
			var reloaded_command := Ship.new()
			_check(
				reloaded_command.load_design_data(flipped_command.to_design_data()),
				"Either green-purple command-center checkerboard must save and reload."
			)
	var ship := Ship.new()
	ship.set_tile_at(Vector2i(0, 0), ShipPart.Category.OFFENSE)
	ship.set_tile_at(Vector2i(1, 0), ShipPart.Category.DEFENSE)
	ship.set_tile_at(Vector2i(2, 0), ShipPart.Category.SPECIAL)
	_check(is_equal_approx(ship.get_filled_hull_area(), 3.0),
		"Test ship hull must have a three-square polygon area.")
	var inventory := [
		state.red_tiles_available,
		state.blue_tiles_available,
		state.green_tiles_available,
		state.core_tiles_available,
	]
	state.red_tiles_available = 1
	state.blue_tiles_available = 1
	state.green_tiles_available = 1
	state.core_tiles_available = 0
	_check(state.get_construction_material_costs(ship) == [1, 1, 1, 0],
		"The displayed material cost must include only materials currently taken from inventory.")
	_check(state.get_construction_credit_cost(ship) == 0,
		"A ship must cost no credits when all of its materials are stored.")
	state.red_tiles_available = 1
	state.blue_tiles_available = 0
	state.green_tiles_available = 0
	_check(state.get_construction_material_costs(ship) == [1, 0, 0, 0],
		"The displayed material cost must exclude missing materials bought with credits.")
	_check(state.get_construction_credit_cost(ship) == 10,
		"A ship's credit cost must equal only the price of its missing materials.")
	_check(state.get_design_material_costs(ship) == [1, 1, 1, 0],
		"Library costs must show fixed blueprint materials regardless of current inventory.")
	state.red_tiles_available = inventory[0]
	state.blue_tiles_available = inventory[1]
	state.green_tiles_available = inventory[2]
	state.core_tiles_available = inventory[3]


func _test_ship_design_storage() -> void:
	var state := root.get_node("GameState")
	var original_ship: Ship = state.ship
	var original_designs: Array[Dictionary] = state.get_saved_ship_designs()
	var original_design_name: String = state.current_ship_design_name
	var original_inventory: Array[int] = [
		state.red_tiles_available,
		state.blue_tiles_available,
		state.green_tiles_available,
	]
	var test_file_path := "user://ship_designs_test_%d.json" % Time.get_ticks_usec()
	_check(
		not FileAccess.file_exists(test_file_path),
		"Ship-design storage test path must be unique."
	)
	if FileAccess.file_exists(test_file_path):
		return

	var turret_pattern: ShipPartPattern
	for pattern in ShipPartPattern.get_catalog():
		if pattern.part_type == ShipPart.Type.MINI_TURRET:
			turret_pattern = pattern
			break
	_check(turret_pattern != null, "The mini turret must be present in the part catalog.")
	if turret_pattern == null:
		return

	state.ship = Ship.new()
	var empty_save_error: String = state.save_current_ship_design(
		"Empty Ship",
		test_file_path
	)
	_check(
		not empty_save_error.is_empty() and not FileAccess.file_exists(test_file_path),
		"An empty ship must not be saved."
	)

	var design_ship := Ship.new()
	for cell in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)]:
		design_ship.set_tile_at(cell, ShipPart.Category.OFFENSE)
	var turret := ShipPart.new(
		turret_pattern.part_type,
		turret_pattern.category,
		Vector2i(2, 0),
		turret_pattern.get_offsets_for_rotation(0),
		turret_pattern.stats
	)
	_check(design_ship.add_part(turret), "Could not add a turret to the saved-design test ship.")

	state.ship = design_ship
	state.saved_ship_designs.clear()
	state.current_ship_design_name = ""
	var design_name := "Mini Turret"
	var save_error: String = state.save_current_ship_design(design_name, test_file_path)
	_check(save_error.is_empty(), "A named non-empty design should save successfully.")
	_check(FileAccess.file_exists(test_file_path), "Saving a design must write a local design file.")
	state.saved_ship_designs.clear()
	_check(
		state._load_saved_ship_designs(test_file_path),
		"Saved designs should load from their local file."
	)
	_check(
		state.saved_ship_designs.size() == 1
			and state.saved_ship_designs[0].get("name", "") == design_name,
		"Loading the design library must restore the saved design name."
	)

	state.ship = Ship.new()
	state.current_ship_design_name = ""
	_check(
		state.load_saved_ship_design(design_name),
		"A saved ship design should load when its tiles are available."
	)
	_check(
		state.current_ship_design_name == design_name,
		"Loading a saved design must retain its name for subsequent saves."
	)
	_check(
		state.ship.parts.size() == 1
			and state.ship.parts[0].type == ShipPart.Type.MINI_TURRET
			and state.ship.get_stats().weapons.size() == 1,
		"Loading a design must reconstruct its ship parts and weapon stats."
	)
	_check(
		state.red_tiles_available == original_inventory[ShipPart.Category.OFFENSE],
		"Loading a blueprint must leave inventory unchanged."
	)

	state.current_ship_design_name = ""
	var duplicate_name_error: String = state.save_current_ship_design(
		design_name,
		test_file_path
	)
	_check(
		not duplicate_name_error.is_empty(),
		"Saving under another design's name must not overwrite it."
	)
	state.current_ship_design_name = design_name

	var oversized_design := Ship.new()
	for index in range(21):
		oversized_design.set_tile_at(Vector2i(index, 0), ShipPart.Category.OFFENSE)
	state.saved_ship_designs.append({
		"name": "Too Many Red Tiles",
		"ship": oversized_design.to_design_data(),
	})
	var ship_before_failed_load: Ship = state.ship
	var red_tiles_before_failed_load: int = state.red_tiles_available
	_check(
		not state.load_saved_ship_design("Too Many Red Tiles"),
		"Oversized blueprints require a build-area upgrade."
	)
	_check(
		state.ship == ship_before_failed_load
			and state.red_tiles_available == red_tiles_before_failed_load,
		"Rejecting an oversized blueprint must preserve the editor and inventory."
	)

	_check(state.delete_saved_ship_design(design_name, test_file_path), "Deleting a saved row must succeed.")
	_check(state._load_saved_ship_designs(test_file_path), "The remaining library must reload after deletion.")
	_check(not state.saved_ship_designs.any(func(entry: Dictionary) -> bool: return entry.name == design_name), "Deleted designs must stay removed on disk.")
	_check(not state.delete_saved_ship_design(design_name, test_file_path), "Deleting a missing design must not change the library.")
	state.ship = original_ship
	state.saved_ship_designs = original_designs
	state.current_ship_design_name = original_design_name
	state.red_tiles_available = original_inventory[ShipPart.Category.OFFENSE]
	state.blue_tiles_available = original_inventory[ShipPart.Category.DEFENSE]
	state.green_tiles_available = original_inventory[ShipPart.Category.SPECIAL]
	if FileAccess.file_exists(test_file_path):
		var cleanup_error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path(test_file_path)
		)
		_check(cleanup_error == OK, "Could not clean up the temporary ship-design test file.")


func _test_archive_progress_storage() -> void:
	var state := root.get_node("GameState")
	var original_discovered: Array[int] = state.discovered_part_types.duplicate()
	var original_unviewed: Array[int] = state.unviewed_discovered_part_types.duplicate()
	var test_file_path := "user://archive_progress_test_%d.json" % Time.get_ticks_usec()
	var test_discovered: Array[int] = [ShipPart.Type.MINI_TURRET, ShipPart.Type.SHIELD]
	var test_unviewed: Array[int] = [ShipPart.Type.SHIELD]
	state.discovered_part_types = test_discovered
	state.unviewed_discovered_part_types = test_unviewed
	_check(
		state._write_archive_progress(test_file_path)
			and FileAccess.file_exists(test_file_path),
		"Archive discoveries must save to a persistent client file."
	)
	state.discovered_part_types.clear()
	state.unviewed_discovered_part_types.clear()
	_check(state._load_archive_progress(test_file_path),
		"Archive discoveries must reload from the client file.")
	_check(
		state.discovered_part_types.has(ShipPart.Type.MINI_TURRET)
			and state.discovered_part_types.has(ShipPart.Type.SHIELD)
			and state.unviewed_discovered_part_types == [ShipPart.Type.SHIELD],
		"Reloading Archive progress must preserve discoveries and their unread state."
	)
	state.discovered_part_types = original_discovered
	state.unviewed_discovered_part_types = original_unviewed
	if FileAccess.file_exists(test_file_path):
		var cleanup_error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path(test_file_path)
		)
		_check(cleanup_error == OK, "Could not clean up the temporary Archive progress file.")


func _test_mini_turret_firing() -> void:
	var turret_pattern: ShipPartPattern
	for pattern in ShipPartPattern.get_catalog():
		if pattern.part_type == ShipPart.Type.MINI_TURRET:
			turret_pattern = pattern
			break
	_check(turret_pattern != null, "The mini turret must be present in the part catalog.")
	if turret_pattern == null:
		return

	var ship := Ship.new()
	ship.set_tile_at(Vector2i.ZERO, ShipPart.Category.OFFENSE)
	ship.set_tile_at(Vector2i(3, 0), ShipPart.Category.OFFENSE)
	var turret := ShipPart.new(
		turret_pattern.part_type,
		turret_pattern.category,
		Vector2i(3, 0),
		turret_pattern.get_offsets_for_rotation(0),
		turret_pattern.stats
	)
	_check(ship.add_part(turret), "Could not add a mini turret to its test ship.")
	var stats := ship.get_stats()
	_check(stats.weapons.size() == 1, "The mini turret must contribute one working weapon.")
	if stats.weapons.is_empty():
		return
	_check(stats.weapons[0].is_projectile_weapon,
		"The mini turret must retain its projectile weapon type in ship stats.")

	var simulation := BattleSimulation.new()
	simulation.setup(stats, _fleet(1), 22)
	var enemy := simulation.aliens[0]
	enemy.position = simulation.player.position + Vector2(150.0, 0.0)
	enemy.integrity = 10.0
	enemy.shields = 0.0
	enemy.cooldowns[0] = 100.0
	simulation.advance(0.0)
	_check(simulation.projectiles.size() == 1, "An in-range mini turret must fire a projectile.")
	_check(simulation.beams.is_empty(), "The mini turret must not fire a laser beam.")
	_check(is_equal_approx(enemy.integrity, 10.0),
		"A mini-turret projectile must deal damage only when it connects.")
	var expected_origin := simulation.player.position + stats.weapons[0].mount_offset.rotated(
		simulation.player.heading
	)
	if not simulation.projectiles.is_empty():
		_check(simulation.projectiles[0].is_player,
			"Mini-turret projectiles must be identified as player projectiles.")
		_check(
			simulation.projectiles[0].position.is_equal_approx(expected_origin),
			"Mini turret fire must originate from its position on the ship."
		)
	for _tick in range(60):
		if simulation.projectiles.is_empty():
			break
		simulation.advance(1.0 / 60.0)
	_check(simulation.projectiles.is_empty(), "A mini-turret projectile must eventually connect.")
	_check(is_equal_approx(enemy.integrity, 9.0), "The mini-turret projectile must damage its target.")


func _test_combat_events() -> void:
	var simulation := BattleSimulation.new()
	simulation.setup(_basic_stats(10.0), _fleet(3), 8)
	var events := {"shots": 0, "shield_hits": 0, "alien_deaths": 0, "player_deaths": 0}
	simulation.weapon_fired.connect(func(): events.shots += 1)
	simulation.shield_hit.connect(func(): events.shield_hits += 1)
	simulation.ship_destroyed.connect(func(is_player: bool):
		if is_player:
			events.player_deaths += 1
		else:
			events.alien_deaths += 1)
	var enemy := simulation.aliens[0]
	enemy.position = simulation.player.position + Vector2(180.0, 0.0)
	enemy.integrity = 100.0
	enemy.shields = 10.0
	for other in simulation.aliens:
		other.cooldowns[0] = 100.0
		if other != enemy:
			other.position = Vector2(700.0, 0.0)
	simulation.advance(1.0 / 60.0)
	_check(events.shots == 1 and events.shield_hits == 1,
		"A laser activation must emit firing and shield-impact events.")
	_check(
		is_equal_approx(enemy.shield_flash, 0.2),
		"Shield damage must start a 200 ms blue ship flash."
	)
	simulation.player.cooldowns[0] = 100.0
	enemy.cooldowns[0] = 0.0
	simulation.advance(1.0 / 60.0)
	_check(events.shots == 2 and events.shield_hits == 1,
		"Alien firing must emit a shot event, but shield impact must wait for projectile arrival.")
	enemy.cooldowns[0] = 100.0
	for tick in range(120):
		simulation.advance(1.0 / 60.0)
	_check(events.shield_hits == 2, "A homing projectile must emit a shield event when it connects.")
	enemy.shields = 0.0
	enemy.shield_flash = 0.0
	simulation._damage(enemy, 1.0)
	_check(events.shield_hits == 2, "Hull-only damage must not emit a shield-hit sound.")
	_check(is_zero_approx(enemy.shield_flash), "Hull-only damage must not flash the ship blue.")
	simulation._damage(enemy, 200.0)
	simulation._damage(enemy, 200.0)
	_check(events.alien_deaths == 1 and events.player_deaths == 0,
		"Alien destruction must emit exactly one alien explosion event.")
	var wreck_position := enemy.position
	var wreck_heading := enemy.heading
	simulation._update_wrecks(0.5)
	_check(
		not enemy.position.is_equal_approx(wreck_position)
		and not is_equal_approx(enemy.heading, wreck_heading),
		"Destroyed ships must remain as drifting, rotating wrecks."
	)
	simulation._damage(simulation.player, 200.0)
	_check(events.player_deaths == 1, "Player destruction must emit a distinct player explosion event.")
	var fleet_simulation := BattleSimulation.new()
	fleet_simulation.setup(_basic_stats(), _fleet(1), 9, 2)
	var fleet_events := {"player_deaths": 0}
	fleet_simulation.ship_destroyed.connect(func(is_player: bool):
		if is_player:
			fleet_events.player_deaths += 1
	)
	fleet_simulation._damage(fleet_simulation.players[1], 200.0)
	_check(
		fleet_events.player_deaths == 1,
		"Destruction of any player ship must emit a player destruction event."
	)


func _check_last_sound(expected_path: String, previous_count: int) -> void:
	var audio := root.get_node("AudioManager")
	_check(audio.get_child_count() == previous_count + 1, "Combat event must start an audio player.")
	var player := audio.get_child(audio.get_child_count() - 1) as AudioStreamPlayer
	_check(player != null and player.stream.resource_path == expected_path and player.bus == &"SFX",
		"Combat event must play %s on the SFX bus." % expected_path)


func _test_battle_sounds(battle: Node) -> void:
	var audio := root.get_node("AudioManager")
	var count := audio.get_child_count()
	battle.simulation.weapon_fired.emit()
	_check_last_sound("res://assets/audio/sfx/shoot-weapon.wav", count)
	count = audio.get_child_count()
	battle.simulation.shield_hit.emit()
	_check_last_sound("res://assets/audio/sfx/shieldHit.wav", count)
	count = audio.get_child_count()
	battle.simulation.ship_destroyed.emit(false)
	_check_last_sound("res://assets/audio/sfx/alien_explode.wav", count)
	count = audio.get_child_count()
	battle.simulation.ship_destroyed.emit(true)
	_check_last_sound("res://assets/audio/sfx/ship_explosion.mp3", count)


func _test_guaranteed_hits() -> void:
	var simulation := BattleSimulation.new()
	simulation.setup(_basic_stats(), _fleet(3), 2)
	var enemy := simulation.aliens[0]
	enemy.position = simulation.player.position + Vector2(180.0, 0.0)
	enemy.shields = 0.0
	enemy.integrity = 100.0
	for other in simulation.aliens:
		if other != enemy:
			other.position = Vector2(700.0, 0.0)
	simulation.advance(1.0 / 60.0)
	_check(is_equal_approx(enemy.integrity, 95.0), "An in-range laser must deal damage immediately.")
	_check(simulation.beams.size() == 1, "Each player shot must create a connected beam.")
	_check(simulation.beams[0].target == enemy, "Beam endpoint must be the damaged target.")
	simulation.player.cooldowns[0] = 100.0
	simulation.projectiles.clear()
	var missile := BattleSimulation.Projectile.new()
	missile.position = simulation.player.position + Vector2(150.0, 0.0)
	missile.target = simulation.player
	missile.damage = 3.0
	simulation.projectiles.append(missile)
	for other in simulation.aliens:
		other.cooldowns[0] = 100.0
	var health_before := simulation.player.integrity
	for tick in range(180):
		simulation.advance(1.0 / 60.0)
	_check(simulation.projectiles.is_empty(), "A homing projectile must eventually connect.")
	_check(is_equal_approx(simulation.player.integrity, health_before - 3.0),
		"Homing projectiles must apply damage exactly once against a moving target.")


func _test_retreat_and_focus() -> void:
	var simulation := BattleSimulation.new()
	simulation.setup(_basic_stats(10.0), _fleet(3), 3)
	simulation.player.shields = 1.0
	for index in range(simulation.aliens.size()):
		var enemy := simulation.aliens[index]
		enemy.position = simulation.player.position + Vector2(160.0, float(index) * 20.0)
		enemy.integrity = 30.0
		enemy.shields = 0.0
	simulation.aliens[1].integrity = 6.0
	simulation.advance(1.0 / 60.0)
	_check(simulation.player.retreat_time > 0.0, "Low shields should trigger retreat.")
	_check(simulation.player.target == simulation.aliens[1], "AI should focus the weakest in-range enemy.")
	_check(simulation.aliens[1].integrity == 1.0, "Focus fire must damage the selected weak enemy.")
	for tick in range(119):
		simulation.advance(1.0 / 60.0)
	_check(absf(angle_difference(0.0, simulation.player.heading)) > 1.0,
		"Retreat should visibly turn the ship before thrust carries it clear.")


func _test_salvage() -> void:
	var simulation := BattleSimulation.new()
	simulation.setup(_basic_stats(), _fleet(3), 4)
	for alien in simulation.aliens:
		alien.integrity = 0.0
	for category in [ShipPart.Category.DEFENSE, ShipPart.Category.OFFENSE, ShipPart.Category.SPECIAL]:
		var drop := BattleSimulation.Drop.new()
		drop.position = Vector2(float(category) * 75.0, 60.0)
		drop.category = category
		simulation.drops.append(drop)
	for tick in range(1200):
		simulation.advance(1.0 / 60.0)
		if simulation.phase == BattleSimulation.Phase.VICTORY:
			break
	_check(simulation.phase == BattleSimulation.Phase.VICTORY, "Victory must resolve immediately.")
	_check(simulation.collected_categories.size() == 3, "Every dropped square must be recovered once.")
	for drop in simulation.drops:
		_check(drop.collected, "Every drop must be marked recovered without a collection flight.")
	simulation.advance(1.0)
	_check(simulation.collected_categories.size() == 3, "Finished salvage must not duplicate rewards.")


func _test_stationary_salvage() -> void:
	var stats := _basic_stats()
	stats.thrust = 0.0
	var simulation := BattleSimulation.new()
	simulation.setup(stats, _fleet(1), 24)
	for alien in simulation.aliens:
		alien.integrity = 0.0
	var drop := BattleSimulation.Drop.new()
	drop.position = Vector2(100.0, 0.0)
	simulation.drops.append(drop)
	simulation.advance(1.0 / 60.0)
	simulation.advance(1.0 / 60.0)
	_check(
		simulation.phase == BattleSimulation.Phase.VICTORY
			and simulation.collected_categories.size() == 1,
		"A ship without thrust must recover drops without a collection flight."
	)


func _test_continuous_pursuit() -> void:
	var stats := _basic_stats()
	stats.weapons.append(ShipWeaponStats.new("Short laser", 100.0, 1.0, 1, 130.0))
	var simulation := BattleSimulation.new()
	simulation.setup(stats, _fleet(1), 6)
	var enemy := simulation.aliens[0]
	enemy.position = simulation.player.position + Vector2(100.0, 0.0)
	enemy.integrity = 100000.0
	enemy.shields = 0.0
	enemy.cooldowns[0] = 10000.0
	simulation.player.heading = 0.0
	simulation.player.velocity = Vector2.RIGHT * simulation.player.speed * 0.75
	simulation._update_ship(simulation.player, 1.0 / 60.0)
	_check(
		simulation.player.velocity.length() > 0.0
			and absf(simulation.player.heading) > 0.001,
		"A ship in weapon range must continue through a turning broadside pass."
	)


func _test_drop_distribution() -> void:
	var simulation := BattleSimulation.new()
	simulation.setup(_basic_stats(), _fleet(3), 7)
	var enemy := simulation.aliens[0]
	var categories: Array[int] = [0, 0, 0, 0]
	for trial in range(3000):
		enemy.integrity = 1.0
		enemy.shields = 0.0
		simulation._damage(enemy, 1.0)
	for drop in simulation.drops:
		categories[drop.category] += 1
	_check(simulation.drops.size() > 1650 and simulation.drops.size() < 1950,
		"Alien drop chance should be approximately 60%.")
	_check(categories[ShipPart.Category.DEFENSE] > categories[ShipPart.Category.OFFENSE]
		and categories[ShipPart.Category.OFFENSE] > categories[ShipPart.Category.SPECIAL]
		and categories[ShipPart.Category.SPECIAL] > categories[ShipPart.Category.CORE]
		and categories[ShipPart.Category.CORE] > 0,
		"Loot must decrease from blue, red, green, to core rarity.")


func _test_defeat() -> void:
	var simulation := BattleSimulation.new()
	simulation.setup(_basic_stats(), _fleet(3), 5)
	simulation.player.integrity = 0.0
	simulation.advance(1.0 / 60.0)
	_check(simulation.phase == BattleSimulation.Phase.DEFEAT, "Destroyed player must lose the battle.")
	_check(simulation.collected_categories.is_empty(), "Defeat must not award uncollected salvage.")


func _test_balance() -> void:
	var min_damage := INF
	var max_damage := 0.0
	var total_damage := 0.0
	var battles := 0
	for count in range(3, 9):
		for trial in range(100):
			var fleet := _fleet(count, count * 100 + trial)
			_check(fleet.size() == count, "Encounter fleet size must match the requested size.")
			var simulation := BattleSimulation.new()
			simulation.setup(_basic_stats(), fleet, count * 100 + trial)
			for tick in range(60 * 120):
				simulation.advance(1.0 / 60.0)
				if simulation.phase in [BattleSimulation.Phase.VICTORY, BattleSimulation.Phase.DEFEAT]:
					break
			_check(simulation.phase == BattleSimulation.Phase.VICTORY,
				"A basic ship must win and collect all loot against %d aliens (trial %d)." % [count, trial])
			var damage := 50.0 - simulation.player.integrity
			min_damage = minf(min_damage, damage)
			max_damage = maxf(max_damage, damage)
			total_damage += damage
			battles += 1
			_check(damage <= 40.0, "Basic encounters should leave a safety margin, not deal %.2f damage (%d aliens)." % [damage, count])
	var average_damage := total_damage / float(battles)
	_check(average_damage >= 4.0 and average_damage <= 10.0,
		"Quarter-health alien encounters should average under 10 damage, not %.2f."
			% average_damage)
	print("%d basic encounters: damage min %.2f, mean %.2f, max %.2f" % [
		battles, min_damage, total_damage / float(battles), max_damage])


func _test_scene() -> void:
	var state := root.get_node("GameState")
	state.start_new_run(GameState.Difficulty.MEDIUM, -1, false)
	_clear_test_fleet(state)
	_check(state.credits == GameState.STARTING_CREDITS,
		"A new run must start with 1200 credits.")
	_check(state.player_ship_count == 0,
		"A new run must have no ships until a design is purchased.")
	for pattern in ShipPartPattern.get_catalog():
		state.discover_part(pattern.part_type)
	state.ship = _fleet_blueprint()
	var ship_cost: int = state.get_construction_credit_cost(state.ship)
	_check(state.purchase_ship(), "A valid ship design should be purchasable.")
	_check(state.player_ship_count == 1, "Each ship purchase must add one fleet ship.")
	_check(state.credits == GameState.STARTING_CREDITS - ship_cost,
		"Purchasing a ship must charge only for missing materials.")
	var credits_after_purchase: int = state.credits
	ship_cost = state.get_construction_credit_cost(state.ship)
	state.credits = ship_cost - 1
	_check(not state.purchase_ship(),
		"A ship purchase must fail when the player cannot afford its cost.")
	_check(state.player_ship_count == 1 and state.credits == ship_cost - 1,
		"An unaffordable purchase must not change credits or fleet size.")
	state.credits = credits_after_purchase
	var credits_before_victory: int = state.credits
	_check(state.set_destination(1), "An armed ship should be able to deploy.")
	var expected_victory_credits: int = state.get_frozen_encounter(1).rewards.credits
	_check(
		state.battle_aliens.size() >= GameState.MIN_ALIEN_FLEET_SIZE
			and state.battle_aliens.size()
				<= GameState.MAX_ALIEN_FLEET_SIZE,
		"Deployment must use the fixed node encounter count regardless of player fleet size."
	)
	# The frozen roster is deterministic; weaken/position it below for the UI test.
	var scene := load("res://scenes/auto_battle.tscn") as PackedScene
	var battle := scene.instantiate()
	root.add_child(battle)
	current_scene = battle
	await process_frame
	battle.set_physics_process(false)
	_check(battle.simulation.player != null, "Battle scene must initialize live combat.")
	_check(not battle.destroy_neutral_targets.button_pressed, "Cleanup checkbox defaults off.")
	battle.destroy_neutral_targets.button_pressed = true
	_check(state.destroy_all_neutral_targets and battle.simulation.destroy_all_neutral_targets,
		"The checkbox must update saved settings and live victory rules.")
	battle.destroy_neutral_targets.button_pressed = false
	_check(not state.destroy_all_neutral_targets and not battle.simulation.destroy_all_neutral_targets,
		"The checkbox must restore ordinary victory rules.")
	_check(
		battle.get_node_or_null("CameraHelp") == null
			and battle.pause_button.toggle_mode
			and battle.fast_forward_button.toggle_mode,
		"Battle must replace camera instructions with Pause and 2x toggle controls."
	)
	battle.pause_button.button_pressed = true
	var paused_elapsed: float = battle.simulation.elapsed
	battle._physics_process(0.1)
	_check(
		battle.pause_button.button_pressed
			and not battle.fast_forward_button.button_pressed
			and battle.simulation.elapsed == paused_elapsed,
		"Pause must disable fast-forward."
	)
	battle.fast_forward_button.button_pressed = true
	var fast_elapsed: float = battle.simulation.elapsed
	battle._physics_process(0.1)
	_check(
		battle.fast_forward_button.button_pressed
			and not battle.pause_button.button_pressed
			and is_equal_approx(battle.simulation.elapsed, fast_elapsed + 0.2),
		"Fast-forward must override Pause."
	)
	battle.fast_forward_button.button_pressed = false
	_check(
		battle.simulation.players.size() == state.player_ship_count,
		"Battle scene must deploy the full player fleet."
	)
	for enemy in battle.simulation.aliens:
		enemy.cooldowns[0] = 10000.0
		enemy.integrity = 1.0
		enemy.shields = 0.0
		enemy.speed = 0.0
		enemy.velocity = Vector2.ZERO
		enemy.position = battle.simulation.player.position + Vector2(100.0, 0.0)
		enemy.previous_position = enemy.position
	_test_battle_sounds(battle)
	# A spent cinematic shot must stop slowing physics even without a render frame.
	# The controller is driven synchronously below, so _process cannot clear it.
	battle._cinematic_projectile = BattleSimulation.Projectile.new()
	battle._simulation_accumulator = 0.0
	var elapsed_before_spent_shot: float = battle.simulation.elapsed
	battle._physics_process(battle.SIMULATION_TICK_SECONDS)
	_check(is_equal_approx(
		battle.simulation.elapsed, elapsed_before_spent_shot + battle.SIMULATION_TICK_SECONDS
	), "A spent finishing shot must restore normal speed on the next physics tick.")
	var zoom_before: float = battle.visuals.camera_zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(300.0, 160.0)
	var cursor_before: Vector2 = battle.visuals.world_transform().affine_inverse() * wheel.position
	battle._input(wheel)
	var cursor_after: Vector2 = battle.visuals.world_transform().affine_inverse() * wheel.position
	_check(battle.visuals.camera_zoom > zoom_before, "Wheel up must zoom in.")
	_check(cursor_before.is_equal_approx(cursor_after), "Zoom must stay anchored under the cursor.")
	var drag := InputEventMouseButton.new()
	drag.button_index = MOUSE_BUTTON_MIDDLE
	drag.pressed = true
	battle._input(drag)
	var camera_before: Vector2 = battle.visuals.camera_position
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(50.0, 20.0)
	battle._input(motion)
	_check(battle.visuals.camera_position != camera_before, "Dragging must pan the camera.")
	_check(not battle._auto_camera_active, "Manual camera movement must suspend auto-camera.")
	battle._process(4.9)
	_check(not battle._auto_camera_active, "Auto-camera must wait for five seconds of inactivity.")
	battle._process(0.2)
	_check(battle._auto_camera_active, "Auto-camera must resume after five seconds of inactivity.")
	state.battle_auto_camera = false
	battle._mark_manual_camera_input()
	battle._process(6.0)
	_check(not battle._auto_camera_active, "Disabled battle auto-camera must not resume after inactivity.")
	state.battle_auto_camera = true
	battle._auto_camera_active = true
	var expected_center := Vector2.ZERO
	var living_count := 0
	for member in battle.simulation.players + battle.simulation.aliens:
		if member.is_alive():
			expected_center += member.position
			living_count += 1
	expected_center /= float(living_count)
	battle._update_auto_camera(1.0)
	_check(battle.visuals.camera_position.is_equal_approx(expected_center), "Auto-camera must center on all living ships.")
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() == 2 and arguments[0] == "--capture":
		battle.visuals.camera_position = Vector2.ZERO
		for tick in range(120):
			battle._physics_process(1.0 / 60.0)
		battle.simulation.player.cooldowns[0] = 0.0
		battle._physics_process(1.0 / 60.0)
		battle.visuals.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		_check(image.save_png(arguments[1]) == OK, "Could not save battle render capture.")
	var red_before: int = state.red_tiles_available
	var blue_before: int = state.blue_tiles_available
	var green_before: int = state.green_tiles_available
	var core_before: int = state.core_tiles_available
	for tick in range(60 * 120):
		battle._physics_process(1.0 / 60.0)
		if battle._finished:
			break
	_check(battle.simulation.phase == BattleSimulation.Phase.VICTORY,
		"Real battle controller must automatically finish combat and salvage.")
	_check(state.current_node_id == 1 and not state.battle_pending,
		"Only a completed victory should advance the map.")
	_check(state.player_ship_count == 1,
		"Surviving purchased ships must carry into the next battle.")
	_check(state.credits == credits_before_victory + expected_victory_credits,
		"A victory must award the frozen node credit reward.")
	var collected: Array[int] = [0, 0, 0, 0]
	for category in battle.simulation.collected_categories:
		collected[category] += 1
	_check(state.red_tiles_available == red_before + collected[ShipPart.Category.OFFENSE]
		and state.blue_tiles_available == blue_before + collected[ShipPart.Category.DEFENSE]
		and state.green_tiles_available == green_before + collected[ShipPart.Category.SPECIAL]
		and state.core_tiles_available == core_before + collected[ShipPart.Category.CORE],
		"Collected salvage must be credited to the correct inventory exactly once.")
	_check(current_scene == battle and not state.last_battle_report.is_empty(),
		"The report must remain open until Continue is selected.")
	var report: Node
	var report_script := load("res://scripts/battle_report.gd")
	for child in battle.get_children():
		if child.get_script() == report_script:
			report = child
			break
	_check(report != null, "Completed battle must create a battle report panel.")
	if report == null:
		print("Controller diagnostic: phase=%s elapsed=%s aliens=%s projectiles=%s finished=%s" % [
			battle.simulation.phase, battle.simulation.elapsed,
			battle.simulation.living_alien_count(), battle.simulation.projectiles.size(), battle._finished])
		return
	report.closed.emit()
	await scene_changed
	var game_map := current_scene
	var left_panel := game_map.get_node_or_null("Layout/UpperArea/WorkspaceContents/PanelsRow/LeftPanel") as PanelContainer
	var center_panel := game_map.get_node_or_null("Layout/UpperArea/WorkspaceContents/PanelsRow/CenterPanel") as PanelContainer
	var details_panel := game_map.get_node_or_null("Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel") as PanelContainer
	var workspace_tabs := game_map.get_node_or_null("Layout/UpperArea/WorkspaceContents/TabButtons") as HBoxContainer
	_check(
		left_panel != null and center_panel != null and details_panel != null
			and workspace_tabs != null
			and left_panel.get_parent() == center_panel.get_parent()
			and center_panel.get_parent() == details_panel.get_parent(),
		"The game map must place its full-width tabs above one shared three-panel row."
	)
	if left_panel != null and center_panel != null and details_panel != null:
		_check(
			left_panel.size_flags_stretch_ratio < details_panel.size_flags_stretch_ratio
				and details_panel.size_flags_stretch_ratio < center_panel.size_flags_stretch_ratio,
			"The center panel must be widest and the new left panel slightly narrower than the right panel."
		)
	var panel_tabs := game_map.get_node(
		"Layout/UpperArea/WorkspaceContents/PanelsRow/CenterPanel/PanelContents/Tabs"
	) as TabContainer
	var fleet_tab_button := game_map.get_node_or_null(
		"Layout/UpperArea/WorkspaceContents/TabButtons/FleetTabButton"
	) as Button
	_check(
		fleet_tab_button != null and fleet_tab_button.focus_mode == Control.FOCUS_NONE,
		"Fleet controls do not take keyboard navigation focus."
	)
	_check(
		game_map.map_button != null and game_map.sector_name_label.text == "SECTOR 2",
		"The top bar must show a Map button beside the current sector name."
	)
	var sector_before_map: int = state.current_node_id
	game_map._on_map_pressed()
	_check(
		state.is_modal_ui_open(),
		"An open map must register as a keyboard-panning blocker for views behind it."
	)
	_check(
		game_map.graph_modal.visible
			and not game_map._graph_map_only
			and state.current_node_id == sector_before_map
			and not state.battle_pending,
		"Map and deploy mode must share the same actionable sector graph."
	)
	game_map.graph_close_button.pressed.emit()
	_check(not game_map.graph_modal.visible, "The graph's top-right X must close the map.")
	_check(panel_tabs != null and panel_tabs.get_tab_count() == 4,
		"The game map must include the Fleet tab.")
	_check(fleet_tab_button != null, "The Fleet tab must have a matching panel button.")
	var ship_designer_button := game_map.get_node_or_null(
		"Layout/UpperArea/WorkspaceContents/TabButtons/BuildTabButton"
	) as Button
	var research_button := game_map.get_node_or_null(
		"Layout/UpperArea/WorkspaceContents/TabButtons/UpgradesTabButton"
	) as Button
	_check(
		ship_designer_button != null and ship_designer_button.text == "SHIP DESIGNER"
			and research_button != null and research_button.text == "RESEARCH",
		"The workspace selectors must use the Ship Designer and Research labels."
	)
	var ship_designer_lock := ship_designer_button.get_node_or_null("Lock") as Control
	var research_lock := research_button.get_node_or_null("Lock") as Control
	var ship_designer_lock_icon := ship_designer_lock.get_node_or_null("Icon") as TextureRect
	_check(
		ship_designer_button.disabled
			and not research_button.disabled
			and research_button.get_index() < ship_designer_button.get_index()
			and ship_designer_lock != null
			and ship_designer_lock_icon != null
			and ship_designer_lock_icon.texture != null
			and ship_designer_lock.anchor_right == 1.0
			and ship_designer_lock.anchor_bottom == 1.0
			and ship_designer_lock.tooltip_text == "Only available at Shipyards"
			and research_lock == null,
		"Research must remain unlocked while Ship Designer retains its contextual shipyard lock."
	)
	if panel_tabs != null and fleet_tab_button != null:
		fleet_tab_button.pressed.emit()
		_check(panel_tabs.current_tab == 0, "The Fleet button must select the Fleet tab.")
		var fleet_panel := panel_tabs.get_node("Fleet")
		_check(game_map.fleet_controls.visible and game_map.fleet_summary.visible and not game_map.get_node("Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost/DetailsContents").visible, "Fleet must show ship slots and the fleet summary instead of ship stats.")
		_check(fleet_panel.slots.size() == 3 and fleet_panel.slot_widgets.size() == 3, "Fleet must provide exactly three ship design slots.")
		var formation_cursor := Vector2(40, 30)
		var formation_world_before: Vector2 = (
			(formation_cursor - fleet_panel.board.size * 0.5) / fleet_panel.board.view_scale
			+ fleet_panel.board.view_center
		)
		var formation_scale_before: float = fleet_panel.board.view_scale
		fleet_panel.board._zoom_at(formation_cursor, 1.2)
		var formation_world_after: Vector2 = (
			(formation_cursor - fleet_panel.board.size * 0.5) / fleet_panel.board.view_scale
			+ fleet_panel.board.view_center
		)
		_check(
			fleet_panel.board.view_scale > formation_scale_before
				and formation_world_before.is_equal_approx(formation_world_after),
			"Fleet formation wheel zoom must remain anchored beneath the cursor."
		)
		_check(
			fleet_panel.board.formation_button != null
				and fleet_panel.board.formation_button.text == "ECHELON (V)"
				and fleet_panel.board.FORMATION_NAMES.size() == 7
				and fleet_panel.board.FORMATION_NAMES[-2] == "HALF CIRCLE"
				and fleet_panel.board.FORMATION_NAMES[-1] == "NONE"
				and fleet_panel.board.clip_contents,
			"The formation panel must provide the six-pattern cycling control."
		)
		var line_positions: Array[Vector2] = fleet_panel.board._formation_positions(5, 1)
		var double_line_positions: Array[Vector2] = fleet_panel.board._formation_positions(6, 2)
		var staggered_positions: Array[Vector2] = fleet_panel.board._formation_positions(5, 3)
		var echelon_positions: Array[Vector2] = fleet_panel.board._formation_positions(5, 0)
		var wedge_positions: Array[Vector2] = fleet_panel.board._formation_positions(5, 4)
		var half_circle_positions: Array[Vector2] = fleet_panel.board._formation_positions(7, 5)
		_check(
			half_circle_positions.size() == 7
				and is_equal_approx(half_circle_positions[0].x, half_circle_positions[-1].x)
				and is_equal_approx(half_circle_positions[0].y, -half_circle_positions[-1].y),
			"Half Circle must form a symmetric rounded arc."
		)
		_check(
			line_positions.all(func(position: Vector2) -> bool: return position.x == 0.0)
				and double_line_positions.all(func(position: Vector2) -> bool:
					return position.x == 0.0 or position.x == -1.0)
				and staggered_positions[0].y < staggered_positions[-1].y
				and staggered_positions.all(func(position: Vector2) -> bool:
					return is_equal_approx(absf(position.x), 0.65)),
			"Line, Double Line, and Staggered must all use vertical arrangements."
		)
		_check(
			wedge_positions.size() == echelon_positions.size()
				and wedge_positions.all(func(position: Vector2) -> bool:
					return echelon_positions.has(Vector2(-position.x, position.y))),
			"Wedge must mirror Echelon (V) in the opposite direction."
		)
		fleet_panel.board._cycle_formation()
		_check(
			fleet_panel.board.formation_button.text == "LINE"
				and (
					state.fleet.size() < 2
					or state.fleet[0].formation != state.fleet[1].formation
				),
			"Cycling the formation control must auto-arrange the fleet in the chosen pattern."
		)
		if not state.fleet.is_empty():
			var expected_formation_centroid := Vector2.ZERO
			for owned in state.fleet:
				expected_formation_centroid += owned.formation * fleet_panel.board.SPACING
			expected_formation_centroid /= float(state.fleet.size())
			fleet_panel.board._fit()
			_check(
				fleet_panel.board.view_center.is_equal_approx(expected_formation_centroid),
				"Automatic formation framing must center the camera on the fleet centroid."
			)
		fleet_panel.call("_open_picker", 0)
		_check(
			not fleet_panel.picker.title_label.visible,
			"The fleet ship-selection window must not repeat a Select Ship heading."
		)
		var assigned_rows: VBoxContainer = fleet_panel.picker.rows
		var assigned_drone_action := (
			assigned_rows.get_child(1).get_child(0).get_child(3) as Button
		)
		_check(
			assigned_drone_action.text == "ASSIGNED TO SLOT 1"
				and assigned_drone_action.disabled,
			"Fleet selector rows must identify the numbered slot already using a design."
		)
		fleet_panel.picker.close_library()
		_check(
			game_map.deploy_button.get_parent() is CenterContainer
				and game_map.deploy_button.get_parent().get_parent() == game_map.fleet_right_panel
				and game_map.deploy_button.custom_minimum_size.x <= 100.0
				and game_map.fleet_right_panel.get_child(-1) == game_map.deploy_button.get_parent(),
			"Deploy must fit inside a bottom-center container owned by the Fleet right panel."
		)
		_check(
			game_map.fleet_controls.get_child_count() == 4,
			"Fleet slots must not include separate Slot A, B, or C captions."
		)
		_check(
			game_map.fleet_controls.get_child(0).text == "SHIP TYPES",
			"The Fleet slot section must be titled Ship Types."
		)
		for widget in fleet_panel.slot_widgets:
			_check(
				widget.salvage_host.get_index() < widget.button.get_index()
					and widget.construct_host.get_index() > widget.button.get_index(),
				"Fleet slot actions must place minus left of the preview and plus right of it."
			)
		for slot_index in range(3):
			var occupied: bool = fleet_panel.slots[slot_index].design != null
			_check(fleet_panel.slot_widgets[slot_index].construct.visible == occupied, "Construct buttons must appear only beside occupied ship slots.")
			_check(fleet_panel.slot_widgets[slot_index].salvage.visible == occupied, "Salvage buttons must appear only beside occupied ship slots.")
		await process_frame
		var fleet_center_width: float = center_panel.size.x
		var fleet_details_width: float = details_panel.size.x
		panel_tabs.current_tab = 1
		_check(not game_map.fleet_controls.visible and not game_map.fleet_summary.visible and game_map.get_node("Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost/DetailsContents").visible, "Build must restore ship stats and hide Fleet's external panels.")
		await process_frame
		_check(
			is_equal_approx(center_panel.size.x, fleet_center_width)
				and is_equal_approx(details_panel.size.x, fleet_details_width),
			"Switching tabs must not change the center or right panel widths."
		)
		panel_tabs.current_tab = 3
		var archive_grid := game_map.get_node_or_null(
			"Layout/UpperArea/WorkspaceContents/PanelsRow/CenterPanel/PanelContents/Tabs/Archive/GridCenter/ArchiveGrid"
		) as GridContainer
		var archive_progress: VBoxContainer = game_map.archive_progress
		var archive_details: VBoxContainer = game_map.archive_details
		_check(
			archive_grid != null and archive_grid.columns >= 1
				and archive_grid.get_child_count() == ShipPartPattern.get_catalog().size(),
			"The Archive must show every component in its responsive grid."
		)
		var archive_tab := panel_tabs.get_node("Archive")
		var thruster_index: int = archive_tab._part_patterns.find_custom(
			func(pattern: ShipPartPattern) -> bool: return pattern.part_type == ShipPart.Type.THRUSTER
		)
		var large_thruster_index: int = archive_tab._part_patterns.find_custom(
			func(pattern: ShipPartPattern) -> bool: return pattern.part_type == ShipPart.Type.LARGE_THRUSTER
		)
		_check(
			thruster_index >= 0 and large_thruster_index == thruster_index + 1,
			"The Archive must group the small and large thrusters in complexity order."
		)
		_check(
			archive_progress != null and archive_progress.visible
				and archive_details != null and archive_details.visible,
			"The Archive tab must use the left panel for details and the right panel for progress."
		)
		_check(
			archive_details.get_parent()
				== game_map.get_node("Layout/UpperArea/WorkspaceContents/PanelsRow/LeftPanel/PanelContents")
				and archive_progress.get_parent()
					== game_map.get_node("Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost"),
			"Archive side-panel content must be swapped without moving the panels themselves."
		)
		panel_tabs.current_tab = 0
	var build_area := game_map.get_node_or_null(
		"Layout/UpperArea/WorkspaceContents/PanelsRow/CenterPanel/PanelContents/Tabs/Build/BuildTilemapArea"
	) as Control
	var build_controls := game_map.get_node_or_null(
		"Layout/UpperArea/WorkspaceContents/PanelsRow/LeftPanel/PanelContents/BuildControls"
	) as VBoxContainer
	_check(build_area != null, "The build screen must contain its ship-design controls.")
	if build_area != null and build_controls != null:
		var save_design_button := build_controls.get_node_or_null(
			"DesignControls/SaveDesignButton"
		) as Button
		var load_design_button := build_controls.get_node_or_null(
			"DesignControls/LoadDesignButton"
		) as Button
		_check(
			save_design_button != null
				and save_design_button.text == "SAVE"
				and save_design_button.custom_minimum_size.x <= 60.0,
			"The build screen must provide a compact text Save button."
		)
		_check(
			load_design_button != null
				and load_design_button.text == "LOAD"
				and load_design_button.custom_minimum_size.x <= 60.0,
			"The build screen must provide a compact text Load button."
		)
		var design_controls := build_controls.get_node("DesignControls") as VBoxContainer
		var selector_row := build_controls.get_node_or_null("SelectorRow") as GridContainer
		var history_controls := build_area.get_node("HistoryControls") as HBoxContainer
		_check(
			design_controls != null
				and design_controls.get_child_count() == 3
				and build_area.assembly_menu != null
				and selector_row != null
				and selector_row.columns == 4
				and selector_row.get_child_count() == 8
				and selector_row.get_child(0).name == "OffenseLabel"
				and selector_row.get_child(1).name == "DefenseLabel"
				and selector_row.get_child(2).name == "TechLabel"
				and selector_row.get_child(3).name == "CivicLabel"
				and selector_row.get_child(4).name == "RedBuildButton"
				and selector_row.get_child(7).name == "CoreBuildButton"
				and selector_row.get_node("OffenseLabel").text == "OFFENSE"
				and selector_row.get_node("DefenseLabel").text == "DEFENSE"
				and selector_row.get_node("TechLabel").text == "TECH"
				and selector_row.get_node("CivicLabel").text == "CIVIC",
			"Build material selectors must form one labeled four-button row in the left panel."
		)
		_check(
			history_controls != null
				and build_area.undo_button.get_parent() == history_controls
				and build_area.redo_button.get_parent() == history_controls
				and history_controls.get_child_count() == 2
				and build_area.undo_button.custom_minimum_size == Vector2(16, 16)
				and build_area.redo_button.custom_minimum_size == Vector2(16, 16)
				and build_area.undo_button.text.is_empty()
				and build_area.redo_button.text.is_empty()
				and build_area.undo_button.icon != null
				and build_area.redo_button.icon != null,
			"Undo and Redo must be compact icon buttons at the bottom-left of the build view."
		)

		save_design_button.pressed.emit()
		await process_frame
		var save_dialog := build_area.get_node("SaveDesignDialog") as PopupPanel
		var name_input := build_area.get_node(
			"SaveDesignDialog/Contents/ShipNameInput"
		) as LineEdit
		_check(
			save_dialog.visible and name_input.text.is_empty(),
			"Saving an unnamed design must prompt for a ship name."
		)
		_check(
			build_area.call("_keyboard_navigation_blocked"),
			"Typing a ship name must suppress Ship Designer keyboard movement and shortcuts."
		)
		var cancel_save_button := build_area.get_node(
			"SaveDesignDialog/CloseX"
		) as TextureButton
		cancel_save_button.pressed.emit()

		var original_designs: Array[Dictionary] = state.get_saved_ship_designs()
		var original_design_name: String = state.current_ship_design_name
		state.saved_ship_designs.clear()
		state.saved_ship_designs.append({
			"name": "Preview Test",
			"ship": state.ship.to_design_data(),
		})
		state.current_run_design_names.append("Preview Test")
		build_area.call("_on_load_design_pressed")
		await process_frame
		var load_dialog := build_area.get_node("LoadDesignDialog") as PopupPanel
		var page_back := load_dialog.get_node("Contents/Pager/PreviousPageButton") as Button
		var page_count_label := load_dialog.get_node("Contents/Pager/PageLabel") as Label
		var page_forward := load_dialog.get_node("Contents/Pager/ForwardButton") as Button
		var design_scroll := load_dialog.get_node("Contents/ScrollContainer") as ScrollContainer
		var design_rows := build_area.get_node(
			"LoadDesignDialog/Contents/ScrollContainer/SavedDesignRows"
		) as VBoxContainer
		_check(load_dialog.visible, "Load Design must open the saved-design modal.")
		_check(
			load_dialog.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,
			"The ship-library panel must use crisp canvas-item scaling instead of a blurry scaled viewport."
		)
		load_dialog.hide()
		await process_frame
		_check(
			not load_dialog.visible,
			"Dismissing the ship library must not reopen it or trap the player."
		)
		build_area._on_load_design_pressed()
		await process_frame
		_check(load_dialog.get_node_or_null("Contents/Pager/PreviousRuns") == null,
			"The ship library must always include saved designs without a previous-runs checkbox.")
		_check(
			not page_back.visible and not page_count_label.visible and not page_forward.visible,
			"Single-page ship libraries must hide their paging controls."
		)
		_check(
			design_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
				and design_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
			"The ship library must use paging instead of scrollbars."
		)
		_check(
			page_back.get_theme_stylebox("normal").texture.resource_path
				== "res://assets/ui/panels/simple_panel.png"
				and page_forward.get_theme_stylebox("normal").texture.resource_path
					== "res://assets/ui/panels/simple_panel.png",
			"Ship-library paging controls must use the simple panel frame."
		)
		_check(
			load_dialog.size.x <= 480 and load_dialog.size.y <= 270,
			"The shared ship-library modal must remain compact, not %s." % load_dialog.size
		)
		_check(
			design_rows.get_child_count() == 3
				and design_rows.get_child(2) is PanelContainer,
			"Each saved design must appear in its own row in the load modal."
		)
		if design_rows.get_child_count() == 3:
			var row_contents := design_rows.get_child(2).get_child(0) as HBoxContainer
			var cost_row := row_contents.get_child(2) as HBoxContainer
			var drone_contents := design_rows.get_child(1).get_child(0) as HBoxContainer
			var drone_cost_row := drone_contents.get_child(2) as HBoxContainer
			_check(
				row_contents.get_child_count() == 5
					and row_contents.get_child(0).get_script().resource_path
						== "res://scripts/ship_design_preview.gd"
					and row_contents.get_child(1) is Label
					and cost_row.get_child_count() % 2 == 0
					and cost_row.get_children().all(func(child: Node) -> bool:
						return not (child is Label) or child.text != "0"),
				"Each design row must show its preview and fixed material costs."
			)
			_check(
				is_equal_approx(cost_row.global_position.x, drone_cost_row.global_position.x),
				"Ship-library costs must remain left-aligned when a row has no delete button."
			)
			_check(
				is_equal_approx(
					(row_contents.get_child(3) as Button).global_position.x,
					(drone_contents.get_child(3) as Button).global_position.x
				),
				"Ship-library Select buttons must align even when deletion is unavailable."
			)
			var delete_button := row_contents.get_child(4) as TextureButton
			delete_button.pressed.emit()
			var delete_confirmation := load_dialog.get_node("DeleteConfirmOverlay") as Control
			_check(delete_confirmation.visible,
				"Deleting a saved design must require confirmation.")
			(load_dialog.get_node(
				"DeleteConfirmOverlay/CenterContainer/ConfirmationPanel/CloseX"
			) as TextureButton).pressed.emit()
			var ship_before_ui_load: Ship = state.ship
			var inventory_before_ui_load: Array[int] = [
				state.red_tiles_available,
				state.blue_tiles_available,
				state.green_tiles_available,
			]
			var row_load_button := row_contents.get_child(3) as Button
			row_load_button.pressed.emit()
			_check(
				not load_dialog.visible and state.ship != ship_before_ui_load,
				"Selecting a design row must load it and close the modal."
			)
			state.ship = ship_before_ui_load
			state.current_ship_design_name = original_design_name
			state.red_tiles_available = inventory_before_ui_load[ShipPart.Category.OFFENSE]
			state.blue_tiles_available = inventory_before_ui_load[ShipPart.Category.DEFENSE]
			state.green_tiles_available = inventory_before_ui_load[ShipPart.Category.SPECIAL]
		else:
			load_dialog.hide()
		state.saved_ship_designs = original_designs
		panel_tabs.current_tab = 1
		_test_builder_history(build_area)
	_check(state.set_destination(3), "A victorious ship should be able to deploy again.")
	_check(change_scene_to_packed(scene) == OK, "Could not open a second battle.")
	await scene_changed
	battle = current_scene
	battle.set_physics_process(false)
	_check(battle.simulation.player != null, "The rebuilt ship must remain armed on its next deployment.")
	if battle.simulation.player == null:
		return
	for player_ship in battle.simulation.players:
		player_ship.integrity = 0.0
	battle._physics_process(1.0 / 60.0)
	for tick in range(61):
		battle._physics_process(1.0 / 60.0)
	_check(state.current_node_id == 1 and not state.battle_pending,
		"Defeat must cancel deployment without advancing the map.")
	_check(state.player_ship_count == 0,
		"Destroyed ships must be removed from the purchased fleet.")
	state.green_tiles_available = 10
	_check(state.run_ended and not state.purchase_ship(), "A terminal fleet defeat cannot be undone by rebuilding.")
	battle.get_child(battle.get_child_count() - 1).closed.emit()
	_check(battle.defeat_dialog.visible, "Terminal defeat must display the end-of-run dialog.")
	battle.defeat_accept_button.pressed.emit()
	await scene_changed
	_check(current_scene != null and current_scene.scene_file_path == "res://scenes/main_menu.tscn",
		"Continuing after terminal defeat must return to the main menu.")
	current_scene.queue_free()
	current_scene = null
	state.cancel_battle()
	await process_frame


func _add_pattern(design: Ship, type: int, origin: Vector2i) -> void:
	for pattern in ShipPartPattern.get_catalog():
		if pattern.part_type != type:
			continue
		for index in range(pattern.cell_offsets.size()):
			design.set_tile_at(origin + pattern.cell_offsets[index], pattern.tile_categories[index])
		design.add_part(ShipPart.new(type, pattern.category, origin, pattern.cell_offsets, pattern.stats, pattern.hidden_tile_offsets))
		return


func _fleet_blueprint() -> Ship:
	var design := Ship.new()
	_add_pattern(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	_add_pattern(design, ShipPart.Type.LASER, Vector2i(2, 0))
	_add_pattern(design, ShipPart.Type.THRUSTER, Vector2i(2, 1))
	return design


func _test_owned_fleet() -> void:
	var state := root.get_node("GameState")
	state.start_new_run(GameState.Difficulty.MEDIUM, -1, false)
	_clear_test_fleet(state)
	state.ship = _fleet_blueprint()
	var credits: int = state.credits
	_check(state.purchase_ship(), "Connected armed blueprint with a core must construct.")
	_check(state.red_tiles_available == 13 and state.green_tiles_available == 3 and state.core_tiles_available == 1,
		"Construction must spend every physical tile once.")
	_check(state.credits == credits, "Construction with stored materials must not spend credits.")
	var after_purchase: int = state.credits
	var effective_second_cost: int = state.get_construction_credit_cost(state.ship)
	_check(effective_second_cost == state.MATERIAL_PRICES[ShipPart.Category.CORE],
		"Construction cost must include only the credit price of missing materials.")
	_check(state.purchase_ship() and state.credits == after_purchase - effective_second_cost and state.fleet.size() == 2,
		"Missing materials must be purchased automatically as part of construction.")
	_check(state.red_tiles_available == 8 and state.green_tiles_available == 0 and state.core_tiles_available == 0,
		"Construction must consume available materials without making inventory negative.")
	var owned: FleetShip = state.fleet[0]
	state.ship.clear()
	_check(owned.design.tiles.size() == 10 and state.can_deploy(),
		"Blueprint changes must not alter owned ships or prevent their deployment.")
	var laser_index: int = owned.cell_units[Vector2i(2, 0)]
	var thrust_index: int = owned.cell_units[Vector2i(2, 1)]
	var old_dps := owned.get_stats().dps
	owned.damage_cell(Vector2i(2, 0), 1.0)
	_check(is_equal_approx(owned.get_stats().dps, old_dps), "Damaged components must retain full output until zero integrity.")
	owned.damage_cell(Vector2i(2, 0), 100.0)
	_check(owned.is_alive() and owned.get_stats().weapons.is_empty(), "A destroyed laser must stop firing without destroying the core.")
	_check(owned.units[thrust_index].hp > 0.0, "Connected thrusters must survive weapon destruction.")
	var inventory := [state.red_tiles_available, state.blue_tiles_available, state.green_tiles_available]
	var quote: Dictionary = state.repair_quote(owned)
	var price: int = quote.credits
	credits = state.credits
	_check(state.repair_ship(owned), "Repair and paid reconstruction restore surviving ships.")
	_check(state.credits == credits - price and inventory[0] - quote.materials[0] == state.red_tiles_available
		and inventory[1] - quote.materials[1] == state.blue_tiles_available and inventory[2] - quote.materials[2] == state.green_tiles_available,
		"Reconstruction consumes existing materials and buys only shortages.")
	_check(owned.units[laser_index].hp == owned.units[laser_index].max_hp, "Repair must restore destroyed components.")
	owned.damage_cell(Vector2i(2, 1), 100.0)
	_check(owned.get_stats().thrust == 0.0, "Destroyed engines must remove thrust.")
	owned.repair()
	var branching := _fleet_blueprint()
	branching.set_tile_at(Vector2i(-1, 0), ShipPart.Category.DEFENSE)
	_add_pattern(branching, ShipPart.Type.MINI_TURRET, Vector2i(-2, 0))
	var disconnected_design := _fleet_blueprint()
	_add_pattern(disconnected_design, ShipPart.Type.MINI_TURRET, Vector2i(-4, 0))
	var disconnected := FleetShip.new()
	disconnected.initialize(disconnected_design, 98, "Disconnected")
	_check(disconnected.construction_error().is_empty(),
		"Disconnected equipment must be valid for construction.")
	var detached := FleetShip.new()
	detached.initialize(branching, 99, "Bridge")
	var result := detached.damage_cell(Vector2i(-1, 0), 100.0)
	_check(result.removed.size() == 1 and detached.has_cell(Vector2i(-2, 0)),
		"Destroying a bridge must not destroy a disconnected intact section.")
	_check(detached.damage_cell(Vector2i(-1, 0), 100.0).removed.is_empty(),
		"Destroyed components must not generate duplicate salvage.")
	var isolated := FleetShip.new()
	isolated.initialize(_fleet_blueprint(), 101, "Isolated")
	isolated.damage_cell(Vector2i(2, 0), 100.0)
	isolated.damage_cell(Vector2i(2, 1), 100.0)
	_check(isolated.is_alive(),
		"A surviving command center must keep operating without a connectivity requirement.")
	var blue_only := FleetShip.new()
	blue_only.initialize(branching, 100, "Armor")
	blue_only.units[blue_only.cell_units[Vector2i(-1, 0)]].hp = 0.0
	_check(blue_only.repair_cost() == 0 and blue_only.material_counts(true)[1] == 1, "Destroyed blue material requires reconstruction, not a cheap repair.")
	var random := RandomNumberGenerator.new()
	random.seed = 62
	for trial in range(30):
		var hit := owned.hit_cell(Vector2(100, 0), random)
		_check(owned.has_cell(hit) and hit.x >= 2, "Incoming front shots must hit exposed front blocks, not the protected core.")
	var simulation := BattleSimulation.new()
	var members: Array[FleetShip] = [owned]
	_check(simulation.setup_owned(members, _fleet(1), 0.0, 0, 7), "Owned fleet must initialize in combat.")
	simulation._damage(simulation.player, 1000.0, simulation.player.position + Vector2(-100, 0), simulation.aliens[0], "Enemy")
	_check(not owned.is_alive() and not simulation.player.is_alive(), "Destroying the command center must destroy the ship.")
	_check(simulation.drops.is_empty(), "Hard difficulty must drop no allied materials.")
	owned.repair()
	simulation.setup_owned(members, _fleet(1), 1.0, 0, 7)
	simulation._damage(simulation.player, 1000.0, simulation.player.position + Vector2(-100, 0), simulation.aliens[0], "Enemy")
	_check(simulation.drops.size() == owned.units[owned.core_index].cells.size(), "Only blocks physically destroyed with the command center may become salvage.")
	_check(owned.units.any(func(unit: Dictionary) -> bool: return unit.hp > 0.0), "Intact blocks must remain in destroyed-ship wreckage.")
	owned.repair()
	for difficulty in range(3):
		state.difficulty = difficulty
		_check(is_equal_approx(state.allied_salvage_chance(), [0.5, 0.3, 0.0][difficulty]), "Difficulty must map to 50/30/0 percent allied salvage.")
	state.red_tiles_available = 25
	state.credits = 170
	for level in range(1, 4):
		_check(state.purchase_laser_upgrade(), "Each specified laser upgrade must be purchasable.")
		var upgraded := owned.get_stats(level).weapons[0]
		var base := owned.get_stats().weapons[0]
		_check(is_equal_approx(upgraded.damage_per_shot / base.damage_per_shot, 1.0 + 0.1 * level), "Laser damage must increase by 10 percent of base per tier.")
		_check(is_equal_approx(upgraded.get_fire_rate_per_second() / base.get_fire_rate_per_second(), 1.0 + 0.1 * level), "Laser fire rate must increase by 10 percent of base per tier.")
	_check(state.credits == 0 and state.red_tiles_available == 0 and not state.purchase_laser_upgrade(), "Three upgrades must spend 25 red and 170 credits and stop at tier three.")
	var second := FleetShip.new()
	second.initialize(_fleet_blueprint(), 2, "Second")
	second.formation = Vector2(2, 1)
	state.fleet.append(second)
	var old_slot := owned.formation
	state.move_ship(owned, second.formation)
	_check(owned.formation == old_slot, "Formation placement must reject overlaps.")
	state.move_ship(owned, Vector2(-1.35, 0.42))
	_check(owned.formation.is_equal_approx(Vector2(-1.35, 0.42)), "Formation placement must preserve fractional positions and allow negative coordinates.")
	members.append(second)
	simulation.setup_owned(members, _fleet(1), 0.3, 0, 1)
	_check(simulation.players[0].position - simulation.players[1].position == Vector2(owned.formation - second.formation) * 65.0, "Deployment must preserve relative formation positions.")
	var report_source := simulation.players[0]
	var enemy := simulation.aliens[0]
	enemy.shields = 0.0
	enemy.integrity = 2.0
	simulation._damage(enemy, 100.0, report_source.position, report_source, "Laser")
	_check(report_source.damage_dealt == 2.0 and report_source.weapon_damage["Laser"] == 2.0, "Reports must count actual damage, excluding overkill.")
	state.record_battle(simulation)
	_check(state.last_battle_report.any(func(entry: Dictionary) -> bool:
		return entry.get("is_alien", false) and entry.get("alien") == enemy.alien
	), "Battle reports must include alien combatants.")
	_test_withdrawal()


func _test_withdrawal() -> void:
	var simulation := BattleSimulation.new()
	simulation.setup(_basic_stats(), _fleet(1), 4)
	for member in [simulation.player, simulation.aliens[0]]:
		member.speed = 0.0
		member.cooldowns[0] = 1000.0
	for tick in range(599):
		simulation.advance(1.0 / 60.0)
	_check(simulation.phase == BattleSimulation.Phase.COMBAT, "Stalemate must wait a full ten seconds.")
	simulation._damage(simulation.player, 0.1)
	# Damage normally occurs during advance; simulate a pending projectile to reset inactivity.
	var projectile := BattleSimulation.Projectile.new()
	projectile.position = simulation.player.position
	projectile.target = simulation.player
	projectile.damage = 0.1
	simulation.projectiles.append(projectile)
	simulation.advance(1.0 / 60.0)
	_check(simulation.inactive_seconds == 0.0, "Damage must reset the stalemate timer.")
	for tick in range(601):
		simulation.advance(1.0 / 60.0)
	_check(simulation.phase == BattleSimulation.Phase.WITHDRAWN and simulation.player.is_alive(), "A ten-second stalemate must preserve survivors.")
	simulation.setup(_basic_stats(), _fleet(1), 5)
	for member in [simulation.player, simulation.aliens[0]]:
		member.cooldowns[0] = 1000.0
	simulation.request_withdrawal()
	for tick in range(599):
		simulation.advance(1.0 / 60.0)
	_check(simulation.phase == BattleSimulation.Phase.COMBAT, "Manual retreat must remain in combat for ten seconds.")
	for tick in range(2):
		simulation.advance(1.0 / 60.0)
	_check(simulation.phase == BattleSimulation.Phase.WITHDRAWN, "Manual retreat must complete after ten seconds even while accelerating.")
	simulation.setup(_basic_stats(10.0), _fleet(1), 7)
	var player_ship := simulation.player
	player_ship.position = Vector2.ZERO
	player_ship.heading = 0.0
	player_ship.retreat_time = 5.0
	simulation.aliens[0].position = Vector2(150, 0)
	simulation._update_ship(player_ship, 1.0)
	_check(player_ship.velocity.dot(Vector2.from_angle(player_ship.heading)) > 0.0,
		"Ships must accelerate forward instead of applying reverse braking thrust.")
	player_ship.heading = PI
	var before_heading := player_ship.heading
	simulation._update_ship(player_ship, 0.1)
	_check(absf(angle_difference(before_heading, player_ship.heading)) <= 0.1501, "Turning must be limited to 1.5 radians per second.")


func _test_design_selection() -> void:
	var state := root.get_node("GameState")
	var originals: Array[Dictionary] = state.get_saved_ship_designs()
	state.start_new_run(GameState.Difficulty.MEDIUM, -1, false)
	_clear_test_fleet(state)
	var blueprint := _fleet_blueprint()
	var fixtures: Array[Dictionary] = [
		{"name": "Old Escort", "ship": blueprint.to_design_data()},
		{"name": "New Frigate", "ship": blueprint.to_design_data()},
	]
	state.saved_ship_designs = fixtures
	_check(state.get_visible_ship_designs().size() == 3,
		"The design library must always include every saved design plus the built-in Drone.")
	_check(state.get_visible_ship_designs("FRIG").size() == 1 and state.get_visible_ship_designs("escort").size() == 1,
		"Saved-design search must be case-insensitive across designs from every run.")
	_check(not state.purchase_saved_ship("Unsaved"), "Construction must reject names that are not saved designs.")
	_check(state.ship.tiles.is_empty() and state.purchase_saved_ship("Old Escort"), "The selected library design must construct independently of the editor.")
	_check(state.ship.tiles.is_empty() and state.fleet[0].display_name.begins_with("Old Escort"), "Constructing a saved design must preserve the editor and use the selected name.")
	_check(state.purchase_saved_ship("Old Escort"), "A second ship of the selected type must construct for salvage testing.")
	var undamaged_escort: FleetShip = state.fleet[0]
	var damaged_escort: FleetShip = state.fleet[1]
	damaged_escort.damage_cell(Vector2i(2, 0), 100.0)
	var salvage_inventory := [
		state.red_tiles_available,
		state.blue_tiles_available,
		state.green_tiles_available,
		state.core_tiles_available,
	]
	var salvage_counts: Array[int] = damaged_escort.material_counts(false)
	_check(state.salvage_ship_type("Old Escort"), "A fleet ship type must be salvageable from its slot.")
	_check(
		state.fleet.has(undamaged_escort) and not state.fleet.has(damaged_escort),
		"Salvage must remove the most damaged ship of the selected type."
	)
	_check(
		[
			state.red_tiles_available,
			state.blue_tiles_available,
			state.green_tiles_available,
			state.core_tiles_available,
		] == [
			salvage_inventory[0] + salvage_counts[0],
			salvage_inventory[1] + salvage_counts[1],
			salvage_inventory[2] + salvage_counts[2],
			salvage_inventory[3] + salvage_counts[3],
		],
		"Salvage must return only physically surviving material."
	)
	var credits_before_rebuild: int = state.credits
	_check(
		state.purchase_saved_ship("Old Escort")
			and state.credits == credits_before_rebuild,
		"Rebuilding a salvaged ship must cost no credits because all materials were returned."
	)
	_check(
		state.salvage_ship_type("Old Escort")
			and state.credits == credits_before_rebuild,
		"Repeated construction and salvage must never drain credits."
	)
	state.ship = _fleet_blueprint()
	state.ship.set_tile_at(Vector2i(7, 7), ShipPart.Category.DEFENSE)
	state.green_tiles_available = 100
	_check(state.purchase_saved_ship("New Frigate") and not state.fleet[1].design.tiles.has(Vector2i(7, 7)), "Construction must use the saved snapshot rather than unsaved edits.")
	state.start_new_run(GameState.Difficulty.MEDIUM, -1, false)
	_clear_test_fleet(state)
	_check(state.get_visible_ship_designs().size() == 3,
		"Starting a new run must not hide designs saved during previous runs.")
	state.saved_ship_designs = originals
	var audio := root.get_node("AudioManager")
	_check(audio.get_bus_volume_percent(audio.MUSIC_BUS) >= 0.0
		and audio.get_bus_volume_percent(audio.MUSIC_BUS) <= 100.0,
		"Persisted audio volume must remain within the valid slider range.")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Master")), -6.0), "Output must be attenuated by 6 dB independently of slider values.")


func _test_settings_storage() -> void:
	var audio := root.get_node("AudioManager")
	var state := root.get_node("GameState")
	var test_path := "user://settings_suite_%d.cfg" % Time.get_ticks_usec()
	var original_music: float = audio.get_bus_volume_percent(audio.MUSIC_BUS)
	var original_ambience: float = audio.get_bus_volume_percent(audio.AMBIENCE_BUS)
	var original_effects: float = audio.get_bus_volume_percent(audio.SFX_BUS)
	var original_auto_camera: bool = state.battle_auto_camera
	var original_fast_forward: bool = state.battle_fast_forward
	audio.set_bus_volume_percent(audio.MUSIC_BUS, 31.0)
	audio.set_bus_volume_percent(audio.AMBIENCE_BUS, 42.0)
	audio.set_bus_volume_percent(audio.SFX_BUS, 53.0)
	state.battle_auto_camera = false
	state.battle_fast_forward = true
	_check(audio.save_settings(test_path), "Settings must save to local storage.")
	audio.set_bus_volume_percent(audio.MUSIC_BUS, 1.0)
	audio.set_bus_volume_percent(audio.AMBIENCE_BUS, 1.0)
	audio.set_bus_volume_percent(audio.SFX_BUS, 1.0)
	state.battle_auto_camera = true
	state.battle_fast_forward = false
	audio.load_settings(test_path)
	_check(
		is_equal_approx(audio.get_bus_volume_percent(audio.MUSIC_BUS), 31.0)
			and is_equal_approx(audio.get_bus_volume_percent(audio.AMBIENCE_BUS), 42.0)
			and is_equal_approx(audio.get_bus_volume_percent(audio.SFX_BUS), 53.0)
			and not state.battle_auto_camera
			and state.battle_fast_forward,
		"Audio and battle preferences must survive a settings reload."
	)
	audio.set_bus_volume_percent(audio.MUSIC_BUS, original_music)
	audio.set_bus_volume_percent(audio.AMBIENCE_BUS, original_ambience)
	audio.set_bus_volume_percent(audio.SFX_BUS, original_effects)
	state.battle_auto_camera = original_auto_camera
	state.battle_fast_forward = original_fast_forward
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))


func _test_material_shortages() -> void:
	var state := root.get_node("GameState")
	var design := preload("res://scripts/builtin_ships.gd").drone()
	for category in range(4):
		state.start_new_run(GameState.Difficulty.MEDIUM, -1, false)
		_clear_test_fleet(state)
		for field in ["red_tiles_available", "blue_tiles_available", "green_tiles_available", "core_tiles_available"]:
			state.set(field, 0)
		state.set(["red_tiles_available", "blue_tiles_available", "green_tiles_available", "core_tiles_available"][category], 1)
		var counts: Array = state.get_design_material_costs(design)
		var expected := 0
		for index in range(4):
			expected += (counts[index] - (1 if index == category else 0)) * state.MATERIAL_PRICES[index]
		state.credits = expected + 100
		_check(state.get_construction_credit_cost(design) == expected and state.purchase_ship(design, "Wildcard"), "Credits cover material shortages during construction at the configured rates.")
		_check(state.credits == 100 and state.get_available_tile_count(category) == 0, "Use owned stock first and charge only the remainder once.")
	_check(not state.has_method("purchase_material"), "Individual material purchases are not a game feature.")
	state.start_new_run(GameState.Difficulty.MEDIUM, -1, false)
	_clear_test_fleet(state)
	for field in ["red_tiles_available", "blue_tiles_available", "green_tiles_available", "core_tiles_available"]:
		state.set(field, 0)
	state.credits = 71
	_check(state.purchase_build_area_upgrade() and state.credits == 0, "An upgrade covers all four missing materials at their distinct rates.")
	state.credits = 35
	_check(state.purchase_laser_upgrade() and state.red_tiles_available == 0 and state.credits == 0, "The existing laser upgrade also covers its Offense shortage on demand.")
	state.start_new_run(GameState.Difficulty.MEDIUM, -1, false)
	_clear_test_fleet(state)

func _test_run_loss() -> void:
	var state := root.get_node("GameState")
	state.start_new_run(GameState.Difficulty.MEDIUM, -1, false)
	_clear_test_fleet(state)
	state.credits = 0
	_check(state.is_run_lost(), "An empty fleet with no affordable ship must lose the run.")
	state.credits = 100000
	_check(not state.is_run_lost(), "An empty fleet that can afford a ship must be allowed to rebuild.")
	state.start_new_run(GameState.Difficulty.MEDIUM, -1, false)

func _test_build_area() -> void:
	var state := root.get_node("GameState")
	state.start_new_run(GameState.Difficulty.MEDIUM, -1, false)
	_clear_test_fleet(state)
	_check(state.credits == 1200 and state.build_area_size() == 20, "New runs must start with 1200 credits and a 20 by 20 build area.")
	var original_inventory := [state.red_tiles_available, state.blue_tiles_available, state.green_tiles_available, state.core_tiles_available]
	_check(state.purchase_build_area_upgrade(), "The first area upgrade must be purchasable.")
	_check(state.build_area_size() == 22 and state.credits == 1150, "Area upgrades must add two tiles per side for 50 credits.")
	_check([state.red_tiles_available, state.blue_tiles_available, state.green_tiles_available, state.core_tiles_available] == [original_inventory[0] - 1, original_inventory[1] - 1, original_inventory[2] - 1, original_inventory[3] - 1], "Area upgrades must consume one of each material.")
	var design := _fleet_blueprint()
	design.set_tile_at(Vector2i(22, 0), ShipPart.Category.DEFENSE)
	_check(not state.design_fits_build_area(design), "The first out-of-bounds column must require an upgrade.")
	state.blue_tiles_available = 0
	_check(state.purchase_build_area_upgrade() and state.build_area_size() == 24 and state.credits == 1098, "Area upgrades automatically cover the missing Defense material for two credits.")
	state.credits = 0
	_check(not state.purchase_build_area_upgrade() and state.build_area_size() == 24 and state.credits == 0, "Unaffordable upgrades must not change size or credits.")
	state.start_new_run(GameState.Difficulty.MEDIUM, -1, false)
	_clear_test_fleet(state)
	_check(state.build_area_size() == 20, "Build upgrades must reset to the 20 by 20 base size for a new run.")


func _test_builder_history(builder: Control) -> void:
	var state := root.get_node("GameState")
	var before: Dictionary = state.ship.tiles.duplicate()
	var materials := [state.red_tiles_available, state.blue_tiles_available, state.green_tiles_available, state.core_tiles_available]
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_4
	builder._unhandled_key_input(key)
	_check(builder._selected_source_id == builder.FOURTH_SOURCE_ID,
		"Number 4 must select the fourth material slot.")
	key.keycode = KEY_1
	builder._unhandled_key_input(key)
	_check(builder._selected_source_id == builder.RED_SOURCE_ID,
		"Number 1 must select the red material slot.")
	builder._unhandled_key_input(key)
	_check(builder._selected_source_id == builder.NO_SOURCE_ID,
		"Selecting the active material again must deselect it.")
	builder._unhandled_key_input(key)
	key.keycode = KEY_ESCAPE
	builder._unhandled_key_input(key)
	_check(builder._selected_source_id == builder.NO_SOURCE_ID,
		"Escape must deselect the active material.")
	key.keycode = KEY_M
	builder._unhandled_key_input(key)
	_check(builder._mirror_enabled, "M must enable the builder mirror line.")
	_check(
		builder._get_mirrored_cell(Vector2i(2, 2))
		== Vector2i(2, builder.map_dimensions.y - 3),
		"The centered mirror line must reflect cells onto the opposite side."
	)
	builder._mirror_axis_half_step = 9
	_check(
		builder._get_mirrored_cell(Vector2i(2, 2)) == Vector2i(2, 6),
		"The mirror axis must support half-grid positions."
	)
	builder._unhandled_key_input(key)
	_check(not builder._mirror_enabled, "M must also disable the builder mirror line.")
	builder._selected_source_id = builder.GREEN_SOURCE_ID
	builder._begin_stroke()
	builder._apply_selected_tool(Vector2i(6, 6))
	builder._apply_selected_tool(Vector2i(7, 6))
	builder._finish_stroke()
	_check(state.ship.tiles.size() == before.size() + 2, "Painting a stroke must add its tiles.")
	key.ctrl_pressed = true
	key.keycode = KEY_Z
	builder._unhandled_key_input(key)
	_check(state.ship.tiles == before, "Ctrl+Z must undo the complete stroke.")
	key.keycode = KEY_Y
	builder._unhandled_key_input(key)
	_check(state.ship.tiles.size() == before.size() + 2, "Ctrl+Y must restore the complete stroke.")
	builder._undo()
	builder._begin_stroke()
	builder._apply_selected_tool(Vector2i(7, 7))
	builder._finish_stroke()
	_check(builder.redo_button.disabled, "A new edit must invalidate redo.")
	builder._undo()
	_check(state.ship.tiles == before and materials == [state.red_tiles_available, state.blue_tiles_available, state.green_tiles_available, state.core_tiles_available], "Undo and redo must never spend materials.")
	_check(not builder.red_count_badge.visible and not builder.blue_count_badge.visible and not builder.green_count_badge.visible and not builder.core_count_badge.visible, "Blueprint tools must hide inventory counts.")
	var camera_position: Vector2 = builder.pan_root.position
	builder._selected_source_id = builder.NO_SOURCE_ID
	_check(
		builder._selected_source_id == builder.NO_SOURCE_ID,
		"Ship dragging must be active whenever material placement is inactive."
	)
	var first_cell: Vector2i = before.keys()[0]
	builder._ship_move_start_cell = first_cell
	builder._update_ship_move_ghost(first_cell + Vector2i(1, 0))
	_check(
		builder.move_ghost_layer.get_used_cells().size() == before.size(),
		"Dragging the move tool must show a complete grid-snapped ghost of the ship."
	)
	builder.move_ghost_layer.clear()
	_check(builder._move_ship_by(Vector2i(1, 0)), "The move tool must translate a ship within the build grid.")
	var shifted_tiles: Dictionary = {}
	for cell in before:
		shifted_tiles[cell + Vector2i(1, 0)] = before[cell]
	_check(
		state.ship.tiles == shifted_tiles and builder.pan_root.position == camera_position,
		"The move tool must move the ship relative to the grid without panning the camera."
	)
	builder._undo()
	_check(state.ship.tiles == before, "Moving a ship within the grid must be undoable.")
