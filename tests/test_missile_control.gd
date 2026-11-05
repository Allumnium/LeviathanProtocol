extends "res://tests/test_equipment_balance.gd"

var native_completed := false

func mechanics() -> void:
	var rack := SlotCatalog.stats_for("missile_rack").weapons[0]
	check(rack.range_units == 1320 and rack.range_units == SlotCatalog.stats_for("laser").weapons[0].range_units * 2
		and rack.range_units == SlotCatalog.stats_for("mini_turret").weapons[0].range_units * 2, "Missile base range is twice basic laser and gun range")
	ResearchUpgrades.apply_weapon(rack, {"missile_range_multiplier": {"value": 1.25}})
	check(rack.range_units == 1650, "Guided Munitions scales the new base range")
	var sim := setup([owned(["missile_rack", "laser"]), owned(["missile_rack"], 2)])
	check(sim.missile_fire_enabled and sim.issue_command("missile_fire", {"enabled": false}), "Missiles default ON and accept hold command")
	for member in sim.players:
		sim._update_ship(member, 0.01)
	check(sim.missile_supply == 30 and sim.projectiles.is_empty(), "Fleet-wide OFF prevents launches and ammo spending on all hosts")
	check(sim.player.damage_dealt > 0, "Other weapons fire while missiles are held")
	check(not sim.issue_command("missile_fire", {"enabled": "false"}), "Malformed toggle is rejected")
	check(sim.issue_command("missile_fire", {"enabled": true}), "Resume command accepted")
	for member in sim.players:
		sim._update_ship(member, 0.01)
	check(sim.projectiles.size() == 10 and sim.missile_supply == 20, "Resuming enables both racks with normal per-missile spending")
	sim = setup([owned(["missile_rack"])])
	sim._update_ship(sim.player, 0.01)
	var origin := sim.projectiles[0].position
	check(sim.issue_command("missile_fire", {"enabled": false}), "Hold after launch")
	sim._update_projectiles(0.05)
	check(sim.projectiles[0].position != origin and sim.missile_supply == 25, "Launched missiles continue flying without refunds while OFF")
	sim._update_ship(sim.player, 1)
	check(is_equal_approx(sim.player.cooldowns[0], 7), "Cooldown continues while OFF")
	sim.issue_command("missile_fire", {"enabled": true})
	sim._update_ship(sim.player, 0.01)
	check(sim.projectiles.size() == 5, "Toggling cannot reset cooldown for an extra burst")
	sim.issue_command("missile_fire", {"enabled": false})
	sim._update_ship(sim.player, 9)
	check(sim.player.cooldowns[0] == 0 and sim.projectiles.size() == 5, "Ready rack remains held without banking extra clusters")
	sim.issue_command("missile_fire", {"enabled": true})
	sim._update_ship(sim.player, 0.01)
	check(sim.projectiles.size() == 10 and sim.missile_supply == 20, "Ready rack resumes immediately with one cluster")
	sim.issue_command("missile_fire", {"enabled": false})
	var enemy := sim.aliens[0]
	enemy.stats.weapons = [SlotCatalog.stats_for("missile_rack").weapons[0]]
	enemy.cooldowns = [0.0]
	sim._update_ship(enemy, 0.01)
	check(sim.projectiles.filter(func(shot: BattleSimulation.Projectile) -> bool: return not shot.is_player).size() == 5
		and sim.missile_supply == 20, "Player toggle and ammo pool do not restrict enemy missiles")
	var a := setup([owned(["missile_rack"])])
	var b := setup([owned(["missile_rack"])])
	a.issue_command("missile_fire", {"enabled": false})
	check(b.execute_command(a.command_log[0]) and SaveValidation.same(a.authoritative_snapshot(), b.authoritative_snapshot()), "Toggle replays through recorded commands and authoritative state")
	check(b.execute_command(a.command_log[0]) and b.command_log.size() == 1, "Repeated command is idempotent")
	check(a.setup_owned([owned(["missile_rack"])], [alien()], 0, 0, 9401, {"credits_only": true, "missiles": 30})
		and a.missile_fire_enabled, "New encounter resets fire control to ON")
	b.phase = BattleSimulation.Phase.VICTORY
	check(not b.issue_command("missile_fire", {"enabled": true}), "Resolved encounters reject toggles")

func settle() -> void:
	for frame in range(5):
		await process_frame

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await settle()

func native() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://missile-control.json"
	check(state.start_new_run(1, 8402), "Start isolated production UI fixture")
	state.pending_intro = false
	check(state.swap_part(state.fleet[3].id, "center", "missile_rack"), "Fit real rack for native control")
	var with_ability := "--ability-only" in OS.get_cmdline_user_args()
	if with_ability:
		var progress: Dictionary = state.hangar_snapshot()
		progress.research.research_ids.append_array(["applied_energy", "disruption_i"])
		progress.research.branch_choices.energy = "disruption"
		check(state._commit_hangar(progress), "Synthetic earned ability for shared footer layout")
		for index in [4, 5]:
			check(state.swap_part(state.fleet[index].id, "center", "ion_emitter"), "Fit multiple sources for footer layout")
	check(state.travel_to(state.get_reachable_nodes(state.current_node_id)[0]), "Save pending encounter")
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_process(false)
	battle.set_physics_process(false)
	await settle()
	if with_ability:
		check(battle.ability_bar != null and battle.ability_bar.source_picker.is_visible_in_tree(), "Shared footer includes real ability and source controls")
	check(battle.missile_button.is_visible_in_tree() and battle.missile_button.button_pressed, "Missile control appears ON during deployment")
	await click(battle.missile_button)
	check(not battle.simulation.missile_fire_enabled and battle.missile_button.text == "MISSILES OFF", "Pointer can hold first launch before Begin Combat")
	await click(battle.begin_button)
	check(not battle.deploying, "Begin Combat retains selected fire control")
	await click(battle.pause_button)
	var elapsed: float = battle.simulation.elapsed
	await click(battle.missile_button)
	check(battle.simulation.missile_fire_enabled and battle.simulation.elapsed == elapsed, "Pointer toggles while paused without advancing time")
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		await click(battle.missile_button)
		check(not battle.simulation.missile_fire_enabled and battle.missile_button.text == "MISSILES OFF", "Pointer OFF at " + str(resolution))
		check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(battle.missile_button.get_global_rect()), "Button remains within supported viewport")
		if with_ability:
			check(not battle.missile_button.get_global_rect().intersects(battle.ability_bar.get_global_rect())
				and Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(battle.ability_bar.get_global_rect()), "Ability controls fit beside missile toggle")
		await RenderingServer.frame_post_draw
		var suffix := "-ability" if with_ability else ""
		check(root.get_texture().get_image().save_png("user://missile-control-%d%s.png" % [resolution.x, suffix]) == OK, "Capture control")
		await click(battle.missile_button)
		check(battle.simulation.missile_fire_enabled, "Pointer ON at " + str(resolution))
	battle.queue_free()
	await settle()
	native_completed = true

func run() -> void:
	if "--native-only" not in OS.get_cmdline_user_args():
		mechanics()
	if DisplayServer.get_name() != "headless":
		await native()
		check(native_completed, "Native interaction section completed")
	print("MISSILE CONTROL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
