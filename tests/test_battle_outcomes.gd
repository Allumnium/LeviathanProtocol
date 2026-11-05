extends SceneTree

var checks := 0
var failures := 0
var state: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame in range(5):
		await process_frame

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://battle-outcomes.json"
	check(state.start_new_run(1, 810), "New scoring run starts")
	check(state.run_score == RunScore.initial(), "Starting credits never count as earned")
	var data: Dictionary = state.hangar_snapshot()
	check(HangarCheckpoint.valid(data), "Scored checkpoint validates")
	for malformed: Variant in [null, [], {}, {"swarm_damage": -1, "credits_earned": 0},
		{"swarm_damage": NAN, "credits_earned": 0}, {"swarm_damage": 0, "credits_earned": 1.5},
		{"swarm_damage": 0, "credits_earned": -1}, {"swarm_damage": 0, "credits_earned": INF}]:
		var broken: Dictionary = data.duplicate(true)
		broken.score = malformed
		check(not HangarCheckpoint.valid(broken), "Malformed score rejected")
	data.score = {"swarm_damage": 125.5, "credits_earned": 249}
	data.research.research_ids = ["foundation"]
	data.research.research_ids.append("civil_hospitality")
	var points := RunScore.breakdown(data)
	check(points == {"research": 100, "damage": 12, "credits": 24, "leviathan": 0, "total": 136},
		"Score uses agreed weights, excludes Foundation, and floors fractional points")
	data.completed = true
	check(RunScore.breakdown(data).total == 20136 and RunScore.breakdown(data).leviathan == 20000,
		"Leviathan completion grants exactly 20000 bonus points")
	data.erase("score")
	check(HangarCheckpoint.valid(data) and RunScore.breakdown(data).is_empty(), "Older physical runs stay valid without fabricated scores")
	state._apply_hangar(data)
	check(not state.hangar_snapshot().has("score"), "Resaving an older run does not enable scoring")
	check(state.start_new_run(1, 810), "Restart scored fixture")
	check(state.buy_ship("drone"), "Salvage income fixture starts")
	var salvage_id: int = state.fleet[-1].id
	var salvage_value := floori(float(state.fleet[-1].chassis.price) * 0.5)
	check(state.run_score.credits_earned == 0, "Spending never counts as earned credits")
	var before: Dictionary = state.hangar_snapshot()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-score-save.json"
	check(not state.salvage_hangar_ship(salvage_id) and state.hangar_snapshot() == before, "Failed salvage changes neither credits nor score")
	state.run_save_path = path
	check(state.salvage_hangar_ship(salvage_id) and state.run_score.credits_earned == salvage_value,
		"Chassis salvage includes gross credit income once")
	check(state.save_run_checkpoint() and state.load_run_checkpoint() and state.run_score.credits_earned == salvage_value,
		"Score persists across Continue")
	var delivery: Dictionary = state.hangar_snapshot()
	delivery.equipment["3"].load = {"kind": "cargo", "quantity": 10, "unit_value": 6, "origin": 0}
	HangarTrade.arrive(delivery, {"inhabited": true})
	HangarTrade.arrive(delivery, {"inhabited": true})
	check(delivery.score.credits_earned == salvage_value + 60, "Delivery counts gross income exactly once")
	_test_damage()
	await _test_victory()
	await _test_defeat()
	print("Battle outcomes: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_damage() -> void:
	var sim := BattleSimulation.new()
	var source := BattleSimulation.Combatant.new()
	source.faction = BattleSimulation.Faction.PLAYER
	source.entity_id = "player"
	source.stats = ShipStats.new()
	source.integrity = 100
	var enemy := BattleSimulation.Combatant.new()
	enemy.faction = BattleSimulation.Faction.ALIEN
	enemy.entity_id = "swarm"
	enemy.integrity = 100
	enemy.stats = ShipStats.new()
	check(sim.register_entity(source) and sim.register_entity(enemy), "Damage-scoring combatants register")
	sim._damage(enemy, 12.5, Vector2.ZERO, source, "Test")
	check(sim.swarm_damage_dealt == 12.5, "Player damage to Swarm retains exact fractional total")
	var neutral := BattleSimulation.Combatant.new()
	neutral.faction = BattleSimulation.Faction.NEUTRAL
	neutral.entity_id = "neutral"
	neutral.integrity = 100
	neutral.stats = ShipStats.new()
	check(sim.register_entity(neutral), "Neutral scoring fixture registers")
	sim._damage(neutral, 20, Vector2.ZERO, source, "Test")
	sim._damage(enemy, 10, Vector2.ZERO, neutral, "Test")
	check(sim.swarm_damage_dealt == 12.5, "Neutral targets and neutral attackers do not score")
	var craft := BattleSimulation.Combatant.new()
	craft.faction = BattleSimulation.Faction.PLAYER
	craft.carrier_source_id = source.entity_id
	sim._damage(enemy, 10, Vector2.ZERO, craft, "Bomber Torpedo")
	check(sim.swarm_damage_dealt == 22.5 and source.damage_dealt == 42.5,
		"Carrier attribution does not double-count sortie damage in run score")

func _battle() -> Control:
	var target: int = state.get_reachable_nodes(state.current_node_id)[0]
	check(state.travel_to(target), "Outcome travel begins")
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_process(false)
	return battle

func _test_camera(battle: Control) -> void:
	state.battle_auto_pan = true
	state.battle_auto_zoom = true
	battle._pan_resume_seconds = 0
	battle._zoom_resume_seconds = 0
	var wheel := InputEventMouseButton.new()
	wheel.position = battle.visuals.size * 0.5
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	battle._input(wheel)
	check(is_zero_approx(battle._pan_resume_seconds) and battle._zoom_resume_seconds == 5,
		"Wheel input interrupts auto-zoom without interrupting auto-pan")
	battle._zoom_resume_seconds = 0
	battle._dragging = true
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10, 0)
	battle._input(motion)
	battle._dragging = false
	check(battle._pan_resume_seconds == 5 and is_zero_approx(battle._zoom_resume_seconds),
		"Drag input interrupts auto-pan without interrupting auto-zoom")
	battle.visuals.camera_position = Vector2(10000, 10000)
	battle.visuals.camera_zoom = 3.0
	battle._mark_manual_pan_input()
	var position: Vector2 = battle.visuals.camera_position
	battle._update_auto_camera(0.25)
	check(battle.visuals.camera_position == position and battle.visuals.camera_zoom < 3,
		"Manual pan suspends only auto-pan while auto-zoom keeps fitting combat")
	battle._update_camera_recovery(4.99)
	check(battle._pan_resume_seconds > 0, "Auto-pan stays suspended before five real-time seconds")
	battle._update_auto_camera(0.25)
	check(battle.visuals.camera_position == position, "Auto-pan does not resume early")
	battle._update_camera_recovery(0.01)
	battle._update_auto_camera(0.25)
	check(battle.visuals.camera_position != position, "Auto-pan resumes after exactly five seconds")
	battle.visuals.camera_position = position
	battle.visuals.camera_zoom = 3.0
	battle._mark_manual_zoom_input()
	battle._update_auto_camera(0.25)
	check(battle.visuals.camera_position != position and battle.visuals.camera_zoom == 3,
		"Manual zoom suspends only auto-zoom while auto-pan continues following")
	battle._update_camera_recovery(2)
	battle._mark_manual_pan_input()
	battle._update_camera_recovery(3)
	check(is_zero_approx(battle._zoom_resume_seconds) and is_equal_approx(battle._pan_resume_seconds, 2),
		"Pan and zoom recover on independent timers")
	battle._mark_manual_pan_input()
	check(is_equal_approx(battle._pan_resume_seconds, 5), "Repeated input resets only its own five-second delay")
	battle.visuals.camera_zoom = 3
	battle._update_auto_camera(0.25)
	check(battle.visuals.camera_zoom < 3, "Auto-zoom resumes independently while manual pan is still suspended")
	state.battle_auto_pan = false
	state.battle_auto_zoom = false
	battle._update_camera_recovery(5)
	position = battle.visuals.camera_position
	var zoom: float = battle.visuals.camera_zoom
	battle._update_auto_camera(0.25)
	check(battle.visuals.camera_position == position and battle.visuals.camera_zoom == zoom,
		"Recovery never overrides explicitly disabled settings")
	var audio := root.get_node("AudioManager")
	var legacy := ConfigFile.new()
	legacy.set_value("battle", "auto_camera", false)
	check(legacy.save("user://legacy-camera.cfg") == OK, "Write legacy settings fixture")
	audio.load_settings("user://legacy-camera.cfg")
	check(not state.battle_auto_pan and not state.battle_auto_zoom,
		"Legacy auto-camera preference initializes both independent settings")
	state.battle_auto_pan = true
	state.battle_auto_zoom = false
	check(audio.save_settings("user://split-camera.cfg"), "Save independent camera preferences")
	state.battle_auto_pan = false
	state.battle_auto_zoom = true
	audio.load_settings("user://split-camera.cfg")
	check(state.battle_auto_pan and not state.battle_auto_zoom,
		"Independent pan and zoom preferences survive reload")
	state.battle_auto_zoom = true

func _test_header(battle: Control) -> void:
	battle.set_physics_process(false)
	await create_timer(0.25).timeout
	check(battle.battle_speed_controls.get_parent() == battle.command_header.middle,
		"Battle controls occupy the shared command header's top recess")
	check(battle.command_header.background.texture is CanvasTexture
		and SurfaceArt.diffuse(battle.command_header.background.texture).resource_path.ends_with("top_bar_d.png"),
		"Battle uses the same mapped top-bar artwork as management")
	check(battle.pause_button.text.is_empty() and battle.fast_forward_button.text.is_empty()
		and battle.five_times_button.text.is_empty()
		and battle.battle_speed_controls.get_node("Speed2Label").text == "2x"
		and battle.battle_speed_controls.get_node("Speed5Label").text == "5x",
		"Battle replaces speed prose with shared glyphs and exact multiplier labels")
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		battle.objective_label.text = "WARDEN: Destroy body | Exposed 12s | Lance 5s"
		battle.repair_label.set_content("REPAIR: 100.0 HP | REBUILD: 3 | CRAFT: 10 ready / 4 active")
		battle.repair_label.show()
		await settle()
		check(root.get_visible_rect().encloses(battle.command_header.get_global_rect()),
			"Battle frame stays on screen at %d" % resolution.x)
		check(battle.command_header.middle.get_global_rect().encloses(battle.battle_speed_controls.get_global_rect()),
			"Compact battle controls fit inside the top recess at %d" % resolution.x)
		check(not battle._battlefield_input(battle.pause_button.get_global_rect().get_center())
			and not battle._battlefield_input(battle.objective_label.get_global_rect().get_center()),
			"Header clicks never reach battle targeting or camera input at %d" % resolution.x)
		check(is_equal_approx(battle.command_header.background.scale.x, battle.command_header.background.scale.y),
			"Battle frame retains its original aspect ratio at %d" % resolution.x)
		check(battle.command_header.course.get_global_rect().encloses(battle.objective_label.get_global_rect())
			and battle.objective_label.get_line_count() <= 2
			and battle.repair_label.get_global_rect().position.y >= battle.command_header.get_global_rect().end.y
			and battle.repair_label.get_content_width() <= battle.repair_label.size.x,
			"Full objective and support readouts do not overlap or truncate at %d" % resolution.x)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/battle-header-%d.png" % resolution.x)
	battle.fast_forward_button.set_pressed_no_signal(false)
	state.battle_speed = 1
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = battle.fast_forward_button.get_global_rect().get_center()
		click.global_position = click.position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		root.push_input(click, true)
		await process_frame
	check(state.battle_speed == 2 and battle.fast_forward_button.button_pressed
		and not battle._dragging, "Actual pointer clicks activate framed speed controls without panning")
	battle.fast_forward_button.button_pressed = false
	battle.fast_forward_button.button_pressed = true
	check(state.battle_speed == 2 and not battle.pause_button.button_pressed
		and not battle.five_times_button.button_pressed, "2x enables only its own speed")
	battle.fast_forward_button.button_pressed = false
	check(state.battle_speed == 1, "Toggling 2x off restores 1x")
	battle.five_times_button.button_pressed = true
	check(state.battle_speed == 5 and not battle.pause_button.button_pressed
		and not battle.fast_forward_button.button_pressed, "5x enables only its own speed")
	battle.pause_button.button_pressed = true
	check(state.battle_speed == 1 and not battle.fast_forward_button.button_pressed
		and not battle.five_times_button.button_pressed, "Pause still resets fast speeds")
	battle.five_times_button.button_pressed = true
	check(state.battle_speed == 5 and not battle.pause_button.button_pressed,
		"Selecting a speed still resumes from pause")
	battle.five_times_button.button_pressed = false
	battle.objective_label.text = battle.simulation.encounter.label(battle.simulation)
	battle.repair_label.set_content("")
	var motion := InputEventMouseMotion.new()
	motion.position = battle.visuals.size * 0.5
	motion.global_position = motion.position
	root.push_input(motion, true)
	await process_frame

func _test_victory() -> void:
	var battle := _battle()
	await settle()
	await _test_header(battle)
	_test_camera(battle)
	battle.simulation.player.damage_dealt = 98765.5
	battle.simulation.player.shield_damage_taken = 1234
	battle.simulation.swarm_damage_dealt = 123.5
	battle.simulation.phase = BattleSimulation.Phase.VICTORY
	battle._finish_battle(true)
	await settle()
	check(state.run_score.swarm_damage == 123.5 and state.run_score.credits_earned >= 120, "Victory settles damage and rewards with the checkpoint")
	var committed: Dictionary = state.hangar_snapshot()
	check(not state.settle_battle(battle.simulation) and state.hangar_snapshot() == committed, "Repeated settlement cannot duplicate score or credits")
	var report: Control = battle.find_child("VictoryBanner", true, false).get_parent().get_parent()
	check(report.theme_type_variation == &"VictoryPanel", "Victory uses supplied themed background and banner")
	check(report.find_children("*", "StatDisplayRow", true, false).is_empty(), "Reports contain no unbounded damage segment flows")
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		var label: ResourceText = report.find_child("ShipName", true, false)
		check(label.size.x > 200 and label.get_line_count() <= 2, "Report names have real width at every supported resolution")
		check(label.get_parent().size.y < 100, "Large damage totals never inflate report row height")
		var accept: Button = report.find_child("AcceptButton", true, false)
		check(root.get_visible_rect().encloses(accept.get_global_rect()), "Report acceptance remains on screen")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/outcome-victory-%d.png" % resolution.x)
	report.queue_free()
	await settle()
	await _test_report_table(battle)
	state.completed = true
	var final_report: Control = load("res://scripts/battle_report.gd").new()
	battle.add_child(final_report)
	var materials: Array[int] = []
	final_report.show_report(state.last_battle_report, "Victory", materials, 100, state.last_equipment_loot)
	root.size = Vector2i(640, 360)
	await settle()
	var score_labels := final_report.find_children("*", "ResourceText", true, false)
	check(score_labels.any(func(label: ResourceText) -> bool: return label.source_text.contains("Leviathan defeated  +20000")),
		"Final victory shows Leviathan bonus in score breakdown")
	check(root.get_visible_rect().encloses(final_report.find_child("AcceptButton", true, false).get_global_rect()),
		"Final victory score does not push acceptance off small screens")
	check(final_report.find_child("RunScore", true, false).get_global_rect().end.y
		<= final_report.find_child("ShipName", true, false).get_global_rect().position.y,
		"Final score reserves its own height above ship summaries")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/outcome-final-victory-640.png")
	battle.queue_free()
	await settle()

func _test_report_table(battle: Control) -> void:
	var entries: Array[Dictionary] = []
	for index in range(3):
		entries.append({"ship": state.fleet[index], "destroyed": index == 1,
			"damage": 123456 + index, "deflected": 321 + index, "repair_damage": 20 * index,
			"passenger_deaths": 3 if index == 1 else 0, "passenger_fees": 60 if index == 1 else 0})
	var report: Control = load("res://scripts/battle_report.gd").new()
	battle.add_child(report)
	var materials: Array[int] = []
	report.show_report(entries, "Victory", materials)
	var grid: GridContainer = report.find_child("FleetTable", true, false)
	check(grid != null and grid.columns == 4 and grid.get_child_count() == 16,
		"Reports share four headings instead of repeating labels on every ship")
	check(grid.get_child(4).get_node("ShipName").source_text.contains("DESTROYED")
		and grid.get_child(8).get_node("ShipName").source_text.begins_with("%s #%d" % [state.fleet[2].chassis.name, state.fleet[2].squadron_id]),
		"Reports prioritize losses, then greatest repair need")
	check(grid.get_child(5).text == "123457" and grid.get_child(6).text == "322"
		and grid.get_child(7).text == "-" and grid.get_child(11).text == "40",
		"Shared columns retain exact damage, deflection and repair HP without repair offers for wrecks")
	var fees: ResourceText = report.find_child("PassengerCasualties", true, false)
	check(fees.source_text.contains("Passengers lost: 3") and fees.source_text.contains("Fees: -60 cr")
		and fees.source_text.contains("Balance:"), "Passenger losses, fees and resulting balance remain explicit")
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		for cell: Control in grid.get_children():
			check(grid.get_global_rect().encloses(cell.get_global_rect()),
				"Report table cells stay aligned and unclipped at %d" % resolution.x)
		check(root.get_visible_rect().encloses(report.find_child("AcceptButton", true, false).get_global_rect()),
			"Report acceptance stays discoverable at %d" % resolution.x)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/report-table-%d.png" % resolution.x)
	report.queue_free()
	await settle()

func _test_defeat() -> void:
	check(state.start_new_run(1, 810), "Defeat scoring fixture starts")
	check(state.buy_ship("drone"), "Surviving escort defeat fixture starts")
	var battle := _battle()
	await settle()
	state.fleet[0].hull_hp = -1
	battle.simulation.swarm_damage_dealt = 432
	battle.simulation.phase = BattleSimulation.Phase.DEFEAT
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-score-save.json"
	battle._finish_battle(false)
	check(not battle.defeat_dialog.visible and not state.run_ended and state.run_score.swarm_damage == 0,
		"Failed defeat settlement does not show success UI or mutate score")
	state.run_save_path = path
	battle._finish_battle(false)
	await settle()
	check(state.run_ended and battle.defeat_dialog.visible and battle.find_child("VictoryBanner", true, false) == null,
		"Flagship loss goes directly to Game Over, even without a report")
	check(state.fleet.size() == 13 and state.fleet.all(func(ship: HangarShip) -> bool: return ship.is_alive() and not ship.flagship),
		"Surviving escorts do not prevent flagship-loss Game Over")
	check(state.run_score.swarm_damage == 432 and state.load_run_checkpoint() and state.run_score.swarm_damage == 432,
		"Defeat damage persists once")
	check(battle.defeat_dialog.get_node("Backdrop").color == Color.BLACK, "Game Over fully blacks out the battle")
	check(battle.defeat_accept_button.text == "ACCEPT DEFEAT"
		and battle.defeat_accept_button.theme_type_variation == &"DefeatButton", "Defeat action uses red themed button")
	check(battle.defeat_dialog.get_node("CenterContainer/Panel/Contents/Score").text.contains("RUN SCORE  43"), "Game Over displays persisted score without fabricated starting research")
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720)]:
		root.size = resolution
		await settle()
		check(root.get_visible_rect().encloses(battle.defeat_dialog.get_node("CenterContainer/Panel").get_global_rect()),
			"Game Over popup fits supported viewport")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/outcome-defeat-%d.png" % resolution.x)
	var settings: PopupPanel = load("res://scenes/settings_dialog.tscn").instantiate()
	root.add_child(settings)
	await settle()
	var toggle: TextureButton = settings.battle_auto_pan_button
	check(toggle.texture_normal == load("res://assets/ui/Switch_Off.png")
		and toggle.texture_pressed == load("res://assets/ui/Switch_On.png")
		and toggle.stretch_mode == TextureButton.STRETCH_KEEP_ASPECT_CENTERED, "Boolean setting uses aspect-preserving supplied switches")
	toggle.button_pressed = not state.battle_auto_pan
	check(toggle.button_pressed == state.battle_auto_pan, "Switch still changes and saves auto-pan preference")
	settings.popup_centered()
	await settle()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/outcome-settings.png")
	settings.hide()
	settings.queue_free()
	battle.defeat_accept_button.pressed.emit()
	await settle()
	check(current_scene.scene_file_path == "res://scenes/main_menu.tscn", "Accept Defeat returns to main menu")
