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
	stats.weapons.append(ShipWeaponStats.new("Test laser", 0.5, 5.0, 1))
	return stats


func _fleet(count: int, seed_value: int = 0) -> Array[RefCounted]:
	var result: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(count, 1.0, seed_value):
		result.append(alien)
	return result


func _run() -> void:
	await _test_main_menu_setup_flow()
	_test_starter_drones()
	_test_weapon_range()
	_test_player_fleet()
	_test_thrust_movement()
	_test_ship_cost()
	_test_owned_fleet()
	_test_design_selection()
	_test_material_shop()
	_test_build_area()
	_test_ship_design_storage()
	_test_mini_turret_firing()
	_test_guaranteed_hits()
	_test_retreat_and_focus()
	_test_range_keeping()
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
	print("Battle tests finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _test_main_menu_setup_flow() -> void:
	var menu: Variant = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu.play_button.pressed.emit()
	_check(
		menu.game_setup.visible and not menu.menu_ui.visible
			and is_zero_approx(menu.starfield._warp_progress),
		"Play must show mission setup before beginning the starfield warp."
	)
	_check(menu.game_setup.difficulty_button.text == "NORMAL", "Mission setup must default to Normal difficulty.")
	menu.game_setup.difficulty_button.pressed.emit()
	_check(menu.game_setup.difficulty_button.text == "HARD", "Difficulty must cycle from Normal to Hard.")
	menu.game_setup.difficulty_button.pressed.emit()
	_check(menu.game_setup.difficulty_button.text == "EASY", "Difficulty must cycle from Hard to Easy.")
	menu.game_setup.difficulty_button.pressed.emit()
	_check(menu.game_setup.difficulty_button.text == "NORMAL", "Difficulty must cycle from Easy to Normal.")
	menu.game_setup.back_requested.emit()
	_check(
		not menu.game_setup.visible and menu.menu_ui.visible,
		"Backing out of mission setup must restore the title menu."
	)
	root.remove_child(menu)
	menu.free()


func _clear_test_fleet(state: Node) -> void:
	# Combat fixtures below deliberately exercise a single custom ship.
	state.fleet.clear()
	state.next_ship_id = 1
	state._refresh_fleet()

func _test_starter_drones() -> void:
	var state := root.get_node("GameState")
	state.start_new_run()
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
	state.start_new_run()
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

	var scaled_fleet := AlienShip.create_random_fleet(18, 1.0, 20, 6)
	var total_health := 0.0
	for alien in scaled_fleet:
		total_health += alien.stats.integrity + alien.stats.shields
	_check(is_equal_approx(total_health, 510.0),
		"Alien encounter health must scale with the player fleet.")

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
		is_equal_approx(
			high_thrust_simulation.player.speed,
			low_thrust_simulation.player.speed * 2.0
		),
		"Ship speed must scale directly with thrust."
	)
	var enemy := low_thrust_simulation.aliens[0]
	enemy.position = low_thrust_simulation.player.position + Vector2(400.0, 0.0)
	low_thrust_simulation.player.heading = PI
	low_thrust_simulation._update_ship(low_thrust_simulation.player, 1.0 / 60.0)
	_check(
		low_thrust_simulation.player.velocity.x > 0.0
			and low_thrust_simulation.player.heading > 2.5,
		"Thrust must allow movement in a direction independent of ship heading."
	)


func _test_ship_cost() -> void:
	var ship := Ship.new()
	ship.set_tile_at(Vector2i(0, 0), ShipPart.Category.OFFENSE)
	ship.set_tile_at(Vector2i(1, 0), ShipPart.Category.DEFENSE)
	ship.set_tile_at(Vector2i(2, 0), ShipPart.Category.SPECIAL)
	_check(is_equal_approx(ship.get_filled_hull_area(), 3.0),
		"Test ship hull must have a three-square polygon area.")
	_check(ship.cost == 20,
		"Ship cost must add hull area to red, blue and green tile costs.")


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
	for index in range(19):
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
	_check(simulation.player.velocity.x < 0.0, "Retreat should move away from the enemy.")
	_check(simulation.player.target == simulation.aliens[1], "AI should focus the weakest in-range enemy.")
	_check(simulation.aliens[1].integrity == 1.0, "Focus fire must damage the selected weak enemy.")


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
	_check(simulation.phase == BattleSimulation.Phase.VICTORY, "Salvage must finish automatically.")
	_check(simulation.collected_categories.size() == 3, "Every dropped square must be collected once.")
	for drop in simulation.drops:
		_check(drop.collected, "Player must fly over every drop.")
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
			and simulation.collected_categories.is_empty(),
		"A ship without thrust must finish salvage without collecting unreachable drops."
	)


func _test_range_keeping() -> void:
	var stats := _basic_stats()
	stats.weapons.append(ShipWeaponStats.new("Short laser", 100.0, 1.0, 1, 130.0))
	var simulation := BattleSimulation.new()
	simulation.setup(stats, _fleet(3), 6)
	var enemy := simulation.aliens[0]
	enemy.position = simulation.player.position + Vector2(180.0, 0.0)
	enemy.integrity = 100000.0
	enemy.shields = 0.0
	for alien in simulation.aliens:
		alien.integrity = 100000.0
		alien.cooldowns[0] = 10000.0
		if alien != enemy:
			alien.position = Vector2(700.0, 0.0)
	for tick in range(300):
		simulation._update_ship(simulation.player, 1.0 / 60.0)
	var distance := simulation.player.position.distance_to(enemy.position)
	_check(distance > 115.0 and distance < 130.0,
		"AI should hold near the shortest weapon's maximum range, not %.2f." % distance)


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
	_check(average_damage >= 12.0 and average_damage <= 20.0,
		"Spaced, thrust-driven basic encounters should average about 16 damage, not %.2f."
			% average_damage)
	print("%d basic encounters: damage min %.2f, mean %.2f, max %.2f" % [
		battles, min_damage, total_damage / float(battles), max_damage])


func _test_scene() -> void:
	var state := root.get_node("GameState")
	state.start_new_run()
	_clear_test_fleet(state)
	_check(state.credits == GameState.STARTING_CREDITS,
		"A new run must start with 1200 credits.")
	_check(state.player_ship_count == 0,
		"A new run must have no ships until a design is purchased.")
	for pattern in ShipPartPattern.get_catalog():
		state.discover_part(pattern.part_type)
	state.ship = _fleet_blueprint()
	var ship_cost: int = state.ship.cost
	_check(state.purchase_ship(), "A valid ship design should be purchasable.")
	_check(state.player_ship_count == 1, "Each ship purchase must add one fleet ship.")
	_check(state.credits == GameState.STARTING_CREDITS - ship_cost,
		"Purchasing a ship must deduct its design cost.")
	var credits_after_purchase: int = state.credits
	state.credits = ship_cost - 1
	_check(not state.purchase_ship(),
		"A ship purchase must fail when the player cannot afford its cost.")
	_check(state.player_ship_count == 1 and state.credits == ship_cost - 1,
		"An unaffordable purchase must not change credits or fleet size.")
	state.credits = credits_after_purchase
	var credits_before_victory: int = state.credits
	_check(state.set_destination(1), "An armed ship should be able to deploy.")
	_check(
		state.battle_aliens.size() >= GameState.MIN_ALIEN_FLEET_SIZE * state.player_ship_count
			and state.battle_aliens.size()
				<= GameState.MAX_ALIEN_FLEET_SIZE * state.player_ship_count,
		"Deployment must multiply the base alien fleet by the player fleet size."
	)
	var scene := load("res://scenes/auto_battle.tscn") as PackedScene
	var battle := scene.instantiate()
	root.add_child(battle)
	current_scene = battle
	await process_frame
	battle.set_physics_process(false)
	_check(battle.simulation.player != null, "Battle scene must initialize live combat.")
	_check(
		battle.simulation.players.size() == state.player_ship_count,
		"Battle scene must deploy the full player fleet."
	)
	for enemy in battle.simulation.aliens:
		enemy.cooldowns[0] = 10000.0
		enemy.integrity = 1.0
		enemy.shields = 0.0
	_test_battle_sounds(battle)
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
	_check(state.credits == credits_before_victory + GameState.VICTORY_CREDIT_REWARD,
		"A victory must award the fixed credit reward.")
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
	var report := battle.get_child(battle.get_child_count() - 1)
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
	if panel_tabs != null and fleet_tab_button != null:
		fleet_tab_button.pressed.emit()
		_check(panel_tabs.current_tab == 0, "The Fleet button must select the Fleet tab.")
		_check(game_map.shop.visible and not game_map.get_node("Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost/DetailsContents").visible, "Fleet must show the shop instead of ship stats.")
		await process_frame
		var fleet_center_width: float = center_panel.size.x
		var fleet_details_width: float = details_panel.size.x
		panel_tabs.current_tab = 1
		_check(not game_map.shop.visible and game_map.get_node("Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost/DetailsContents").visible, "Build must restore ship stats and hide the shop.")
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
		var archive_progress := game_map.get_node_or_null(
			"Layout/UpperArea/WorkspaceContents/PanelsRow/LeftPanel/PanelContents/ArchiveProgress"
		) as VBoxContainer
		var archive_details := game_map.get_node_or_null(
			"Layout/UpperArea/WorkspaceContents/PanelsRow/DetailsPanel/ContentHost/ArchiveDetails"
		) as VBoxContainer
		_check(
			archive_grid != null and archive_grid.columns == 6
				and archive_grid.get_child_count() == ShipPartPattern.get_catalog().size(),
			"The Archive must show every component as a button in a six-column grid."
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
			"The Archive tab must use the left panel for progress and the right panel for details."
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
				and design_controls.get_child_count() == 2
				and selector_row != null
				and selector_row.columns == 2
				and selector_row.get_child_count() == 4,
			"Build material selectors and an empty fourth slot must form a 2-by-2 grid in the left panel."
		)
		_check(
			history_controls != null
				and build_area.undo_button.get_parent() == history_controls
				and build_area.redo_button.get_parent() == history_controls
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
		var cancel_save_button := build_area.get_node(
			"SaveDesignDialog/Contents/Buttons/CancelButton"
		) as Button
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
		var design_rows := build_area.get_node(
			"LoadDesignDialog/Contents/ScrollContainer/SavedDesignRows"
		) as VBoxContainer
		_check(load_dialog.visible, "Load Design must open the saved-design modal.")
		_check(
			design_rows.get_child_count() == 3
				and design_rows.get_child(2) is PanelContainer,
			"Each saved design must appear in its own row in the load modal."
		)
		if design_rows.get_child_count() == 3:
			var row_contents := design_rows.get_child(2).get_child(0) as HBoxContainer
			var summary_label := row_contents.get_child(1).get_child(1) as Label
			_check(
				row_contents.get_child_count() == 4
					and row_contents.get_child(0).get_script().resource_path
						== "res://scripts/ship_design_preview.gd"
					and row_contents.get_child(1) is VBoxContainer
					and summary_label.text.contains("Integrity:")
					and summary_label.text.contains("DPS:"),
				"Each design row must show a ship preview beside its stat summary."
			)
			var ship_before_ui_load: Ship = state.ship
			var inventory_before_ui_load: Array[int] = [
				state.red_tiles_available,
				state.blue_tiles_available,
				state.green_tiles_available,
			]
			var row_load_button := row_contents.get_child(2) as Button
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
	_check(state.current_node_id == 1 and not state.battle_pending,
		"Defeat must cancel deployment without advancing the map.")
	_check(state.player_ship_count == 0,
		"Destroyed ships must be removed from the purchased fleet.")
	state.green_tiles_available = 10
	_check(state.purchase_ship(), "A lost ship can be replaced with new materials.")
	_check(state.player_ship_count == 1,
		"Repurchasing after a loss must restore one ship to the fleet.")
	battle.get_child(battle.get_child_count() - 1).closed.emit()
	await scene_changed
	_check(current_scene != null and current_scene.scene_file_path == "res://scenes/game_map.tscn",
		"Continuing after defeat must return to the map.")
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
	state.start_new_run()
	_clear_test_fleet(state)
	state.ship = _fleet_blueprint()
	var credits: int = state.credits
	_check(state.purchase_ship(), "Connected armed blueprint with a core must construct.")
	_check(state.red_tiles_available == 13 and state.green_tiles_available == 1,
		"Construction must spend every physical tile once.")
	_check(state.credits == credits - state.ship.cost, "Construction must spend credits.")
	var after_purchase: int = state.credits
	var effective_second_cost: int = state.get_construction_credit_cost(state.ship)
	_check(effective_second_cost == state.ship.cost + 4 * state.MATERIAL_PRICES[ShipPart.Category.SPECIAL],
		"Construction cost must include the credit price of every missing material.")
	_check(state.purchase_ship() and state.credits == after_purchase - effective_second_cost and state.fleet.size() == 2,
		"Missing materials must be purchased automatically as part of construction.")
	_check(state.red_tiles_available == 8 and state.green_tiles_available == 0,
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
	var price := owned.repair_cost()
	credits = state.credits
	_check(state.repair_ship(owned), "Credit-only repairs must restore surviving ships.")
	_check(state.credits == credits - price and inventory == [state.red_tiles_available, state.blue_tiles_available, state.green_tiles_available], "Repairs must spend only credits.")
	_check(owned.units[laser_index].hp == owned.units[laser_index].max_hp, "Repair must restore destroyed components.")
	owned.damage_cell(Vector2i(2, 1), 100.0)
	_check(owned.get_stats().thrust == 0.0, "Destroyed engines must remove thrust.")
	owned.repair()
	var branching := _fleet_blueprint()
	branching.set_tile_at(Vector2i(-1, 0), ShipPart.Category.DEFENSE)
	_add_pattern(branching, ShipPart.Type.MINI_TURRET, Vector2i(-2, 0))
	var detached := FleetShip.new()
	detached.initialize(branching, 99, "Bridge")
	var result := detached.damage_cell(Vector2i(-1, 0), 100.0)
	_check(result.removed.size() == 2 and not detached.has_cell(Vector2i(-2, 0)), "Destroying a bridge must detach the isolated section exactly once.")
	_check(detached.damage_cell(Vector2i(-1, 0), 100.0).removed.is_empty(), "Lost sections must not generate duplicate salvage.")
	var isolated := FleetShip.new()
	isolated.initialize(_fleet_blueprint(), 101, "Isolated")
	isolated.damage_cell(Vector2i(2, 0), 100.0)
	isolated.damage_cell(Vector2i(2, 1), 100.0)
	_check(not isolated.is_alive(), "A command center detached from every other component must lose the ship.")
	var blue_only := FleetShip.new()
	blue_only.initialize(branching, 100, "Armor")
	blue_only.units[blue_only.cell_units[Vector2i(-1, 0)]].hp = 0.0
	_check(blue_only.repair_cost() == 1, "Blue damage must have a very low rounded credit repair cost.")
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
	_check(simulation.drops.size() == owned.design.tiles.size(), "Every lost material must roll salvage once, including detached sections.")
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
	simulation.setup(_basic_stats(), _fleet(1), 6)
	simulation.phase = BattleSimulation.Phase.SALVAGE
	simulation.request_withdrawal()
	for tick in range(599):
		simulation.advance(1.0 / 60.0)
	_check(simulation.phase == BattleSimulation.Phase.SALVAGE, "Withdrawal during salvage must also wait ten seconds.")
	for tick in range(2):
		simulation.advance(1.0 / 60.0)
	_check(simulation.phase == BattleSimulation.Phase.WITHDRAWN, "Withdrawal must work during salvage.")
	simulation.setup(_basic_stats(10.0), _fleet(1), 7)
	var player_ship := simulation.player
	player_ship.position = Vector2.ZERO
	player_ship.heading = 0.0
	player_ship.retreat_time = 5.0
	simulation.aliens[0].position = Vector2(150, 0)
	simulation._update_ship(player_ship, 1.0)
	_check(player_ship.velocity.dot(Vector2.from_angle(player_ship.heading)) >= -player_ship.speed * 0.2 - 0.001, "Backward movement must be capped at 20 percent of forward thrust.")
	player_ship.heading = PI
	var before_heading := player_ship.heading
	simulation._update_ship(player_ship, 0.1)
	_check(absf(angle_difference(before_heading, player_ship.heading)) <= 0.1501, "Turning must be limited to 1.5 radians per second.")


func _test_design_selection() -> void:
	var state := root.get_node("GameState")
	var originals: Array[Dictionary] = state.get_saved_ship_designs()
	state.start_new_run()
	_clear_test_fleet(state)
	var blueprint := _fleet_blueprint()
	var fixtures: Array[Dictionary] = [
		{"name": "Old Escort", "ship": blueprint.to_design_data()},
		{"name": "New Frigate", "ship": blueprint.to_design_data()},
	]
	state.saved_ship_designs = fixtures
	state.current_run_design_names.append("New Frigate")
	_check(state.get_visible_ship_designs().size() == 2, "Previous-run designs must be hidden by default.")
	_check(state.get_visible_ship_designs("FRIG").size() == 1 and state.get_visible_ship_designs("escort").is_empty(), "Search must be case-insensitive and respect the run filter.")
	state.set_include_previous_designs(true)
	_check(state.get_visible_ship_designs("escort").size() == 1, "The checkbox must reveal previous-run designs.")
	_check(not state.purchase_saved_ship("Unsaved"), "Construction must reject names that are not saved designs.")
	_check(state.ship.tiles.is_empty() and state.purchase_saved_ship("Old Escort"), "The selected library design must construct independently of the editor.")
	_check(state.ship.tiles.is_empty() and state.fleet[0].display_name.begins_with("Old Escort"), "Constructing a saved design must preserve the editor and use the selected name.")
	state.ship = _fleet_blueprint()
	state.ship.set_tile_at(Vector2i(7, 7), ShipPart.Category.DEFENSE)
	state.green_tiles_available = 100
	_check(state.purchase_saved_ship("New Frigate") and not state.fleet[1].design.tiles.has(Vector2i(7, 7)), "Construction must use the saved snapshot rather than unsaved edits.")
	state.start_new_run()
	_clear_test_fleet(state)
	_check(not state.include_previous_run_designs and state.get_visible_ship_designs().size() == 1 and state.get_visible_ship_designs()[0].name == "Drone", "A new run must reset the previous-run toggle and current-run design list.")
	state.saved_ship_designs = originals
	var audio := root.get_node("AudioManager")
	_check(is_equal_approx(audio.get_bus_volume_percent(audio.MUSIC_BUS), 50.0), "Quieter audio must still show 50 percent by default.")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Master")), -6.0), "Output must be attenuated by 6 dB independently of slider values.")


func _test_material_shop() -> void:
	var state := root.get_node("GameState")
	state.start_new_run()
	_clear_test_fleet(state)
	for category in range(state.MATERIAL_PRICES.size()):
		var before: int = state.get_available_tile_count(category)
		var credits_before: int = state.credits
		_check(state.purchase_material(category), "Each material must be purchasable.")
		_check(state.get_available_tile_count(category) == before + 1 and state.credits == credits_before - state.MATERIAL_PRICES[category], "Buying a material must add one tile and debit its exact price.")
	state.credits = 1
	_check(not state.purchase_material(1) and state.credits == 1, "Unaffordable material purchases must not spend credits.")
	_check(not state.purchase_material(-1) and not state.purchase_material(4), "Invalid material categories must be rejected.")
	state.credits = 100
	state.battle_pending = true
	_check(not state.purchase_material(0) and state.credits == 100, "The shop must be unavailable during deployment.")
	state.battle_pending = false
	state.start_new_run()
	_clear_test_fleet(state)

func _test_build_area() -> void:
	var state := root.get_node("GameState")
	state.start_new_run()
	_clear_test_fleet(state)
	_check(state.credits == 1200 and state.build_area_size() == 8, "New runs must start with 1200 credits and an 8 by 8 build area.")
	var original_inventory := [state.red_tiles_available, state.blue_tiles_available, state.green_tiles_available, state.core_tiles_available]
	_check(state.purchase_build_area_upgrade(), "The first area upgrade must be purchasable.")
	_check(state.build_area_size() == 10 and state.credits == 1150, "Area upgrades must add two tiles per side for 50 credits.")
	_check([state.red_tiles_available, state.blue_tiles_available, state.green_tiles_available, state.core_tiles_available] == [original_inventory[0] - 1, original_inventory[1] - 1, original_inventory[2] - 1, original_inventory[3] - 1], "Area upgrades must consume one of each material.")
	var design := _fleet_blueprint()
	design.set_tile_at(Vector2i(10, 0), ShipPart.Category.DEFENSE)
	_check(not state.design_fits_build_area(design), "The first out-of-bounds column must require an upgrade.")
	state.blue_tiles_available = 0
	_check(not state.purchase_build_area_upgrade() and state.build_area_size() == 10 and state.credits == 1150, "Unaffordable upgrades must not change size or credits.")
	state.start_new_run()
	_clear_test_fleet(state)
	_check(state.build_area_size() == 8, "Build upgrades must reset for a new run.")


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
