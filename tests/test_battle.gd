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
	stats.weapons.append(ShipWeaponStats.new("Test laser", 0.5, 5.0, 1))
	return stats


func _fleet(count: int, seed_value: int = 0) -> Array[RefCounted]:
	var result: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(count, 1.0, seed_value):
		result.append(alien)
	return result


func _run() -> void:
	_test_weapon_range()
	_test_guaranteed_hits()
	_test_retreat_and_focus()
	_test_range_keeping()
	_test_drop_distribution()
	_test_salvage()
	_test_defeat()
	_test_balance()
	await _test_scene()
	for child in root.get_node("AudioManager").get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	await create_timer(0.1).timeout
	print("Battle tests finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)


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
	var categories: Array[int] = [0, 0, 0]
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
		and categories[ShipPart.Category.SPECIAL] > 0,
		"Loot must be blue/common, red/uncommon, green/rare in decreasing frequency.")


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
	_check(average_damage >= 20.0 and average_damage <= 30.0,
		"Average damage against a basic ship should be about 25, not %.2f." % average_damage)
	print("%d basic encounters: damage min %.2f, mean %.2f, max %.2f" % [
		battles, min_damage, total_damage / float(battles), max_damage])


func _test_scene() -> void:
	var state := root.get_node("GameState")
	state.start_new_run()
	state.discover_part(ShipPart.Type.LASER)
	var part_stats := ShipPartStats.with_weapon("Integration laser", 1.0, 0.5, 5.0, 1)
	part_stats.integrity = 150.0
	for pattern in ShipPartPattern.get_catalog():
		if pattern.part_type == ShipPart.Type.LASER:
			var offsets := pattern.get_offsets_for_rotation(0)
			var part := ShipPart.new(ShipPart.Type.LASER, ShipPart.Category.OFFENSE,
				Vector2i.ZERO, offsets, part_stats)
			for cell in offsets:
				state.ship.set_tile_at(cell, ShipPart.Category.OFFENSE)
			state.ship.add_part(part)
			break
	_check(state.set_destination(1), "An armed ship should be able to deploy.")
	_check(state.battle_aliens.size() >= 3 and state.battle_aliens.size() <= 8,
		"Deployment must create between 3 and 8 aliens.")
	var scene := load("res://scenes/auto_battle.tscn") as PackedScene
	var battle := scene.instantiate()
	root.add_child(battle)
	current_scene = battle
	await process_frame
	battle.set_physics_process(false)
	_check(battle.simulation.player != null, "Battle scene must initialize live combat.")
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
	for tick in range(60 * 120):
		battle._physics_process(1.0 / 60.0)
		if battle._finished:
			break
	_check(battle.simulation.phase == BattleSimulation.Phase.VICTORY,
		"Real battle controller must automatically finish combat and salvage.")
	_check(state.current_node_id == 1 and not state.battle_pending,
		"Only a completed victory should advance the map.")
	var collected: Array[int] = [0, 0, 0]
	for category in battle.simulation.collected_categories:
		collected[category] += 1
	_check(state.red_tiles_available == red_before + collected[ShipPart.Category.OFFENSE]
		and state.blue_tiles_available == blue_before + collected[ShipPart.Category.DEFENSE]
		and state.green_tiles_available == green_before + collected[ShipPart.Category.SPECIAL],
		"Collected salvage must be credited to the correct inventory exactly once.")
	await create_timer(2.2).timeout
	_check(current_scene != null and current_scene.scene_file_path == "res://scenes/game_map.tscn",
		"A completed victory must automatically return to the build/map scene.")
	_check(state.set_destination(3), "A victorious ship should be able to deploy again.")
	_check(change_scene_to_packed(scene) == OK, "Could not open a second battle.")
	await scene_changed
	battle = current_scene
	battle.set_physics_process(false)
	_check(battle.simulation.player != null, "The rebuilt ship must remain armed on its next deployment.")
	if battle.simulation.player == null:
		return
	battle.simulation.player.integrity = 0.0
	battle._physics_process(1.0 / 60.0)
	_check(state.current_node_id == 1 and not state.battle_pending,
		"Defeat must cancel deployment without advancing the map.")
	await create_timer(2.2).timeout
	_check(current_scene != null and current_scene.scene_file_path == "res://scenes/game_map.tscn",
		"A defeat must automatically return to the build/map scene.")
	current_scene.queue_free()
	current_scene = null
	state.cancel_battle()
	await process_frame
