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
	check(state.buy_equipment("mini_turret"), "Purchase fixture")
	var uid := str(state.next_equipment_id - 1)
	var before: Dictionary = state.hangar_snapshot()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-score-save.json"
	check(not state.sell_equipment(uid) and state.hangar_snapshot() == before, "Failed sale changes neither credits nor score")
	state.run_save_path = path
	check(state.sell_equipment(uid) and state.run_score.credits_earned == 20, "Sale income counts once")
	check(state.save_run_checkpoint() and state.load_run_checkpoint() and state.run_score.credits_earned == 20,
		"Score persists across Continue")
	var delivery: Dictionary = state.hangar_snapshot()
	delivery.equipment["3"].load = {"kind": "cargo", "quantity": 10, "unit_value": 6, "origin": 0}
	HangarTrade.arrive(delivery, {"inhabited": true})
	HangarTrade.arrive(delivery, {"inhabited": true})
	check(delivery.score.credits_earned == 80, "Delivery counts gross income exactly once")
	check(state.buy_chassis("drone"), "Salvage income fixture starts")
	var salvage_id: int = state.fleet[-1].id
	var salvage_value := floori(float(state.fleet[-1].chassis.price) * 0.5)
	check(state.run_score.credits_earned == 20, "Spending never reduces accumulated earned credits")
	check(state.salvage_hangar_ship(salvage_id) and state.run_score.credits_earned == 20 + salvage_value,
		"Chassis salvage includes gross credit income")
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

func _test_victory() -> void:
	var battle := _battle()
	await settle()
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

func _test_defeat() -> void:
	check(state.start_new_run(1, 810), "Defeat scoring fixture starts")
	check(state.buy_chassis("drone"), "Surviving escort defeat fixture starts")
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
	check(state.fleet.size() == 4 and state.fleet.all(func(ship: HangarShip) -> bool: return ship.is_alive() and not ship.flagship),
		"Surviving escorts do not prevent flagship-loss Game Over")
	check(state.run_score.swarm_damage == 432 and state.load_run_checkpoint() and state.run_score.swarm_damage == 432,
		"Defeat damage persists once")
	check(battle.defeat_dialog.get_node("Backdrop").color == Color.BLACK, "Game Over fully blacks out the battle")
	check(battle.defeat_accept_button.text == "ACCEPT DEFEAT"
		and battle.defeat_accept_button.theme_type_variation == &"DefeatButton", "Defeat action uses red themed button")
	check(battle.defeat_dialog.get_node("CenterContainer/Panel/Contents/Score").text.contains("RUN SCORE  43"), "Game Over displays persisted score")
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
	var toggle: TextureButton = settings.battle_auto_camera_button
	check(toggle.texture_normal == load("res://assets/ui/Switch_Off.png")
		and toggle.texture_pressed == load("res://assets/ui/Switch_On.png")
		and toggle.stretch_mode == TextureButton.STRETCH_KEEP_ASPECT_CENTERED, "Boolean setting uses aspect-preserving supplied switches")
	toggle.button_pressed = not state.battle_auto_camera
	check(toggle.button_pressed == state.battle_auto_camera, "Switch still changes and saves auto-camera preference")
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
