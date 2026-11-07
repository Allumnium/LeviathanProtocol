extends SceneTree

var checks := 0
var failures := 0
var state: Node
var battle_frame_completed := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for index in range(5):
		await process_frame

func fixture(available := true, equipped := true) -> BattleSimulation:
	var ship := HangarShip.new()
	check(ship.initialize_chassis("corsair", 1, true), "Initialize ability source")
	ship.mounts["aft"] = {"uid": "1", "equipment_id": "mini_turret", "rank": 1}
	if equipped:
		ship.mounts["port"] = {"uid": "2", "equipment_id": "ion_emitter", "rank": 1}
	ship.rebuild_units()
	ship.hull_hp = ship.hull_max
	var stats := ShipStats.new()
	stats.integrity = 100000
	stats.shields = 100
	stats.weight = 10
	stats.weapons.append(ShipWeaponStats.new("Enemy", 1, 100, 1, 200))
	var enemy := AlienShip.new("Ability target", load(AlienShip.definition("core:scout").art), stats)
	var ships: Array[FleetShip] = [ship]
	var enemies: Array[RefCounted] = [enemy]
	var initial := BattleAbilities.initial_state()
	initial.auto["ion_pulse"] = false
	var simulation := BattleSimulation.new()
	check(simulation.setup_owned(ships, enemies, 0, 0, 9412,
		{"credits_only": true, "ability_ids": ["ion_pulse"] if available else [], "ability_state": initial}),
		"Initialize cooldown-only physical ability context")
	simulation.player.position = Vector2.ZERO
	simulation.aliens[0].position = Vector2(150, 0)
	for member in simulation._members:
		member.speed = 0
		member.acceleration = 0
	return simulation

func mechanics() -> void:
	var sim := fixture(false)
	check(not sim.abilities.can_cast(sim, "ion_pulse", sim.aliens[0].position),
		"An installed starting Ion Emitter does not grant unearned Ion Pulse")
	sim = fixture(true, false)
	check(sim.abilities.sources(sim, 0, "ion_pulse").is_empty()
		and not sim.abilities.can_cast(sim, "ion_pulse", sim.aliens[0].position),
		"Earned research needs an installed living source")
	sim = fixture()
	var target := sim.aliens[0]
	var point: Vector2 = target.position
	check(not sim.visibility_enabled and sim.abilities.can_cast(sim, "ion_pulse", point),
		"Physical ability uses existing sight without changing global fog/AI rules")
	check(not sim.abilities.can_cast(sim, "ion_pulse", Vector2(1000, 0))
		and not sim.abilities.can_cast(sim, "ion_pulse", point, "missing")
		and not sim.abilities.can_cast(sim, "gravity_well", point),
		"Out-of-range, invalid sources and deferred abilities are rejected")
	sim.doctrines.charges["fixture"] = {"source": target.entity_id}
	check(sim.issue_command("ability_cast", {"ability": "ion_pulse", "position": [point.x, point.y]}),
		"Manual Ion Pulse uses the shared command path")
	check(sim.doctrines.charges.is_empty() and sim.abilities.suppressed(target)
		and is_equal_approx(sim.abilities.remaining("ion_pulse"), 24),
		"Cast interrupts a charge, suppresses recovery and starts one fleet cooldown")
	target.position += Vector2(10, 0)
	sim.abilities.advance(sim, 0)
	check(sim.abilities.effects[0].position == target.position, "Suppression ring follows its moving target")
	target.position = point
	check(not sim.abilities.can_cast(sim, "ion_pulse", point)
		and sim.abilities.effects.size() == 1, "Cooldown prevents repeated casts")
	target.shields = 0
	target.since_damage = 10
	sim._update_ship(target, 1)
	check(target.shields == 0, "Ion Pulse prevents actual shield regeneration")
	sim.abilities.advance(sim, 4)
	check(not sim.abilities.suppressed(target) and is_equal_approx(sim.abilities.remaining("ion_pulse"), 20),
		"Suppression ends after four simulation seconds, before the cooldown")
	sim._update_ship(target, 1)
	check(target.shields > 0, "Shield regeneration resumes after suppression")
	sim.abilities.advance(sim, 20)
	check(sim.abilities.can_cast(sim, "ion_pulse", point), "Ability becomes ready exactly at 24 seconds")
	check(sim.abilities.cast(sim, "ion_pulse", point), "Recast ready ability")
	sim.player.owned_ship.hull_hp = -1
	sim.abilities.advance(sim, 0)
	check(sim.abilities.effects.is_empty() and sim.abilities.sources(sim, 0, "ion_pulse").is_empty(),
		"Source destruction ends its effect and prevents further casts")
	sim = fixture()
	sim.player.owned_ship.flagship = false
	var emitter := Vector2.ZERO
	for unit in sim.player.owned_ship.units:
		if unit.part.definition_id == "ion_emitter":
			emitter = sim.player.owned_ship.local_cell_position(unit.cells[0])
	check(sim.abilities.origin(sim.player, "ion_pulse").is_equal_approx(
		sim.player.position + (emitter * sim.player.owned_ship.fleet_view_scale()).rotated(sim.player.heading)),
		"Escort source range begins at its actual scaled equipment mount")
	check(sim.abilities.cast(sim, "ion_pulse", sim.aliens[0].position), "Escort can cast")
	sim.aliens[0].integrity = -1
	sim.abilities.advance(sim, 0)
	check(sim.abilities.effects.is_empty(), "Target destruction removes its suppression effect")
	sim = fixture()
	var unchanged := sim.abilities.snapshot()
	sim.abilities.auto_cast(sim)
	check(sim.abilities.snapshot() == unchanged and sim.abilities.effects.is_empty(),
		"New physical encounters default to manual use")
	check(sim.issue_command("ability_auto", {"ability": "ion_pulse", "enabled": true}),
		"Player may enable existing Auto control")
	sim.abilities.auto_cast(sim)
	check(sim.abilities.remaining("ion_pulse") == 24 and sim.abilities.effects.size() == 1,
		"Auto casts through normal cooldown/visibility rules")
	sim.phase = BattleSimulation.Phase.VICTORY
	check(not sim.abilities.can_cast(sim, "ion_pulse", sim.aliens[0].position),
		"Resolved battles cannot cast")
	var first := fixture()
	var second := fixture()
	for replay in [first, second]:
		check(replay.issue_command("ability_cast", {"ability": "ion_pulse", "position": [150, 0]}),
			"Replay accepts deterministic ability command")
		for tick in range(30):
			replay.advance(1.0 / 30)
	check(SaveValidation.same(first.authoritative_snapshot(), second.authoritative_snapshot()),
		"Physical replay includes equal ability cooldown/effect state")
	check(first.authoritative_snapshot().has("ability_state"), "Physical diagnostic state includes abilities without fog")

func integration() -> void:
	state.run_save_path = "user://research-abilities.json"
	check(state.start_new_run(1, 9412), "Start isolated ability research run")
	check(state.battle_support_context().ability_ids.is_empty(), "Foundation grants no physical ability")
	var proposal: Dictionary = state.hangar_snapshot()
	proposal.research.research_ids.append_array(["applied_energy", "disruption_i"])
	proposal.research.branch_choices["energy"] = "disruption"
	check(state._commit_hangar(proposal), "Persist earned Disruption I")
	check(state.research_grants().ability_ids == ["ion_pulse"]
		and state.battle_support_context().ability_ids == ["ion_pulse"],
		"Research grant reaches physical battle context")
	check(state.load_run_checkpoint() and state.battle_support_context().ability_ids == ["ion_pulse"],
		"Continue derives the same ability from existing saved research")
	var sim := fixture()
	sim.abilities.cast(sim, "ion_pulse", sim.aliens[0].position)
	var restarted := fixture()
	check(restarted.abilities.remaining("ion_pulse") == 0 and restarted.abilities.effects.is_empty(),
		"A restarted encounter begins from original cooldown state, like weapon cooldowns")
	var view: Control = load("res://scripts/battle_visuals.gd").new()
	view.simulation = restarted
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.camera_position = Vector2(75, 0)
	var bar: Control = load("res://scripts/battle_ability_bar.gd").new()
	bar.simulation = restarted
	bar.visuals = view
	root.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bar.offset_top = -80
	bar.offset_right = 500
	bar.offset_bottom = -8
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		bar.offset_top = -8 - maxf(54, bar.get_combined_minimum_size().y)
		bar.offset_right = minf(500, 8 + bar.get_combined_minimum_size().x)
		await settle()
		bar.refresh()
		var button: Button = bar.action_buttons["ion_pulse"]
		check(bar.selected_id == "ion_pulse" and not button.disabled and button.text == "ION PULSE",
			"Ability bar initializes its actual researched selection at " + str(resolution))
		check(not bar.source_picker.visible, "Single-source choice does not add a redundant dropdown")
		check(Rect2(Vector2.ZERO, Vector2(resolution)).encloses(bar.get_global_rect()),
			"Ability bar fits the viewport at %s: %s" % [resolution, bar.get_global_rect()])
		button.pressed.emit()
		check(bar.targeting and view.ability_preview.id == "ion_pulse", "Ability control enters targeting")
		bar.cancel_targeting()
	bar.begin_targeting("ion_pulse")
	check(bar.cast_at(restarted.aliens[0].position), "Ability bar casts on the real visible target")
	bar.refresh()
	check(bar.action_buttons["ion_pulse"].disabled and bar.action_buttons["ion_pulse"].text == "ION PULSE 24"
		and not bar.targeting, "Cooldown is visible and targeting exits after cast")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("user://ion-pulse.png") == OK, "Save native ability capture")
	bar.queue_free()
	view.queue_free()
	await settle()

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func battle_scene() -> void:
	var source: HangarShip = state.get_deployed_fleet()[0]
	var fitted := false
	for slot: Dictionary in source.chassis.slots:
		if SlotCatalog.compatible(slot, SlotCatalog.find_equipment("ion_emitter")):
			fitted = state.swap_part(source.id, slot.id, "ion_emitter")
			break
	check(fitted, "Install Ion Emitter through the real atomic shipyard refit")
	var enemy := fixture().aliens[0].alien
	check(state.travel_to(state.get_reachable_nodes(state.current_node_id)[0]), "Save a real ability-test deployment")
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.size = Vector2i(1280, 720)
	root.add_child(battle)
	current_scene = battle
	battle.set_physics_process(false)
	battle.set_process(false)
	await settle()
	check(battle.deploying and not battle.ability_bar.input_enabled, "Abilities stay disabled during deployment")
	battle._begin_combat()
	check(not battle.deploying, "Ability interaction starts through atomic Begin Combat")
	var context: Dictionary = state.battle_support_context()
	context.encounter_plan = {}
	var enemies: Array[RefCounted] = [enemy]
	check(battle.simulation.setup_owned(state.get_deployed_fleet(), enemies, 0, 0, 9412, context),
		"Use the controlled target after starting the real encounter")
	# This fixture replaces the live roster after scene admission. Rebuild its
	# readout so the original frozen deployment is not retained as lost ships.
	for row: Dictionary in battle.enemy_readout.rows.values():
		battle.enemy_readout.column.remove_child(row.box)
		row.box.queue_free()
	battle.enemy_readout.rows.clear()
	battle.enemy_readout.registered.clear()
	battle.enemy_readout.refresh()
	battle.simulation.player.position = Vector2.ZERO
	battle.simulation.aliens[0].position = Vector2(150, 0)
	battle.visuals.camera_position = Vector2(75, 0)
	battle.visuals.camera_zoom = 1.0
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await create_timer(0.25).timeout
		await settle()
		var viewport := root.get_visible_rect()
		for panel: Control in [battle.squadron_readout.get_parent(), battle.enemy_readout.get_parent(), battle.footer_panel]:
			check(viewport.encloses(panel.get_global_rect()), "Shared battle panel fits " + str(resolution))
			check(not battle._battlefield_input(panel.get_global_rect().get_center()), "Frame consumes battlefield clicks")
		check(battle.footer_panel.get_global_rect().encloses(battle.ability_bar.get_global_rect()),
			"Ability controls fit inside the authored footer")
		check(battle.battlefield.size.x > viewport.size.x * 0.4 and battle.battlefield.size.y > viewport.size.y * 0.5,
			"Battlefield retains usable central space")
		check(battle.visuals.world_center().is_equal_approx(battle.battlefield.get_global_rect().get_center()),
			"Camera frames the open battlefield")
		check(battle.enemy_readout.rows.size() == 1, "Enemy panel shows deployed ships")
		await click(battle.pause_button.get_global_rect().get_center())
		check(battle.pause_button.button_pressed, "Native top bar pause remains clickable")
		await click(battle.pause_button.get_global_rect().get_center())
		check(not battle.pause_button.button_pressed, "Native top bar resumes")
		if DisplayServer.get_name() != "headless":
			battle.visuals.queue_redraw()
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("user://battle-frame-%d.png" % resolution.x) == OK,
				"Capture shared battle frame")
	root.size = Vector2i(1280, 720)
	await settle()
	var enemy_row: Dictionary = battle.enemy_readout.rows.values()[0]
	battle.simulation.visibility_enabled = true
	battle.enemy_readout.refresh()
	check(not enemy_row.box.visible, "Enemy panel conceals ships outside current visibility")
	battle.simulation.visibility_enabled = false
	battle.enemy_readout.refresh()
	check(enemy_row.box.visible, "Enemy panel restores visible ship readouts")
	var wheel := InputEventMouseButton.new()
	wheel.position = battle.battlefield.get_global_rect().get_center() + Vector2(20, 10)
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	var hover := InputEventMouseMotion.new()
	hover.position = wheel.position
	root.push_input(hover, true)
	await process_frame
	var world_point: Vector2 = battle.visuals.world_transform().affine_inverse() * wheel.position
	battle._input(wheel)
	check(battle.visuals.camera_zoom > 1 and world_point.is_equal_approx(
		battle.visuals.world_transform().affine_inverse() * wheel.position), "Zoom keeps the world point under the pointer")
	var drag := InputEventMouseMotion.new()
	drag.position = wheel.position
	drag.relative = Vector2(10, 5)
	battle._dragging = true
	var camera_before: Vector2 = battle.visuals.camera_position
	battle._input(drag)
	check(not battle.visuals.camera_position.is_equal_approx(camera_before), "Battlefield drag pans the camera")
	battle._dragging = false
	check(battle.ability_bar != null and not battle.simulation.visibility_enabled
		and not battle.simulation.ability_commit.is_valid(),
		"Production battle builds researched bar without global fog or a resource-save callback")
	battle.simulation.player.position = Vector2.ZERO
	battle.simulation.aliens[0].position = Vector2(150, 0)
	var targets: Array[String] = [battle.simulation.aliens[0].entity_id]
	check(battle.simulation.set_objective_targets(targets),
		"Scene fixture has a living objective instead of an already-complete empty encounter")
	battle.visuals.camera_position = Vector2(75, 0)
	battle.visuals.camera_zoom = 1.0
	var button: Button = battle.ability_bar.action_buttons["ion_pulse"]
	await click(button.get_global_rect().get_center())
	check(battle.ability_bar.targeting, "Pointer click on the native battle control enters targeting")
	var target_point: Vector2 = battle.visuals.world_transform() * battle.simulation.aliens[0].position
	await click(target_point)
	check(battle.simulation.abilities.remaining("ion_pulse") == 24
		and battle.simulation.abilities.suppressed(battle.simulation.aliens[0])
		and not battle.ability_bar.targeting,
		"Pointer click on enemy casts through production battlefield input")
	var remaining: float = battle.simulation.abilities.remaining("ion_pulse")
	battle.pause_button.set_pressed_no_signal(true)
	battle._physics_process(1)
	check(battle.simulation.abilities.remaining("ion_pulse") == remaining, "Pause freezes ability cooldown")
	battle.pause_button.set_pressed_no_signal(false)
	battle._advance_fixed_simulation(0.05, 2)
	check(is_equal_approx(battle.simulation.abilities.remaining("ion_pulse"), remaining - 0.1),
		"Battle speed advances cooldown by simulation time")
	battle.ability_bar.refresh()
	if DisplayServer.get_name() != "headless":
		battle.visuals.queue_redraw()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("user://ion-pulse-battle.png") == OK,
			"Capture the actual native battle ability and effect")
	var reinforcement := BattleSimulation.Combatant.new()
	reinforcement.entity_id = "readout-reinforcement"
	reinforcement.alien = battle.simulation.aliens[0].alien
	reinforcement.squadron_id = battle.simulation.aliens[0].squadron_id
	reinforcement.faction = BattleSimulation.Faction.ALIEN
	reinforcement.tags = {"combatant": true}
	reinforcement.stats = reinforcement.alien.stats
	reinforcement.integrity = reinforcement.stats.integrity
	reinforcement.position = Vector2(10000, 10000)
	check(battle.simulation.register_entity(reinforcement), "Register a later enemy arrival")
	battle.enemy_readout.refresh()
	check(enemy_row.label.source_text.ends_with("2/2"), "Enemy readout includes later arrivals")
	reinforcement.integrity = -1
	battle.enemy_readout.refresh()
	check(enemy_row.label.source_text.ends_with("1/2"), "Enemy readout retains losses and original capacity")
	battle.queue_free()
	await settle()
	check(state.start_new_run(1, 9413), "Start a battle without researched abilities")
	check(state.travel_to(state.get_reachable_nodes(state.current_node_id)[0]), "Save the no-ability deployment")
	var empty_battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.size = Vector2i(640, 360)
	root.add_child(empty_battle)
	current_scene = empty_battle
	empty_battle.set_physics_process(false)
	empty_battle.set_process(false)
	await create_timer(0.25).timeout
	await settle()
	check(empty_battle.ability_bar == null and empty_battle.footer_panel.is_visible_in_tree(),
		"Authored footer stays visible when no abilities are available")
	check(root.get_visible_rect().encloses(empty_battle.footer_panel.get_global_rect()),
		"Empty ability footer fits the smallest supported viewport")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("user://battle-frame-empty.png") == OK, "Capture empty footer")
	empty_battle.queue_free()
	await settle()
	battle_frame_completed = true

func run() -> void:
	state = root.get_node("GameState")
	mechanics()
	await integration()
	await battle_scene()
	check(battle_frame_completed, "Production battle-frame checks reached completion")
	print("RESEARCH ABILITIES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
