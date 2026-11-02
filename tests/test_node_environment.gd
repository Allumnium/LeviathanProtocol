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
	var densities := {}
	var nebulae := {}
	var solar := {}
	for seed_value in [42, 351, 907]:
		var graph := CampaignContent.populate(CampaignGraph.generate(seed_value, 2), seed_value)
		check(CampaignContent.valid(graph), "Generated campaign validates node conditions")
		check(SaveValidation.same(graph, CampaignContent.populate(CampaignGraph.generate(seed_value, 2), seed_value)),
			"Node conditions regenerate deterministically")
		var encounters := EncounterGenerator.freeze_campaign(seed_value, 1, graph)
		for node: Dictionary in graph.nodes:
			var conditions: Dictionary = node.environment
			check(NodeEnvironment.valid(conditions) and NodeEnvironment.valid(JSON.parse_string(JSON.stringify(conditions))),
				"Every node has valid ambient conditions before and after JSON roundtrip")
			densities[int(conditions.asteroid_density)] = true
			nebulae[conditions.nebula] = true
			solar[conditions.solar_intensity] = true
			if node.inhabited or node.row <= 1:
				check(conditions.asteroid_density == 0, "Ports and opening battles remain clear")
			if not encounters.has(str(node.id)):
				continue
			var encounter: Dictionary = encounters[str(node.id)]
			check(EncounterGenerator.valid(encounter) and SaveValidation.same(encounter.environment, conditions),
				"Frozen encounter preserves validated node conditions")
			var count: int = NodeEnvironment.ROCK_COUNTS[int(conditions.asteroid_density)]
			check(encounter.get("asteroids", {}).get("roots", {}).size() == count,
				"Clear/sparse/medium/dense conditions produce exactly 0/3/6/9 asteroids")
	check(densities.size() == 4 and nebulae.size() == 2 and solar.size() > 10,
		"Campaigns contain varied densities, solar intensities and nebula presence")
	for bad in [{"version": 1, "asteroid_density": 4, "solar_intensity": 1.0, "nebula": false},
		{"version": 1, "asteroid_density": 1, "solar_intensity": NAN, "nebula": false},
		{"version": 1, "asteroid_density": 1, "solar_intensity": 1.0, "nebula": "yes"}]:
		check(not NodeEnvironment.valid(bad), "Malformed ambient conditions are rejected")
	state = root.get_node("GameState")
	state.run_save_path = "user://node-environment.json"
	check(state.start_new_run(1, 907), "Start isolated environment run")
	for step in range(10):
		var routes: Array = state.get_reachable_nodes(state.current_node_id)
		var destination: int = routes[0]
		for id: int in routes:
			if state.get_frozen_encounter(id).has("asteroids"):
				destination = id
				break
		var departed: bool = state.travel_to(destination)
		check(departed, "Travel commits node conditions: " + state.last_save_error + " " + state.deployment_error())
		if not departed:
			print("NODE ENVIRONMENT: %d checks, %d failures" % [checks, failures])
			quit(1)
			return
		if not state.battle_pending:
			continue
		if state.get_frozen_encounter(destination).has("asteroids"):
			break
		var opening := BattleSimulation.new()
		check(opening.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0,
			state.battle_simulation_seed(), state.battle_support_context()), "Clear battle setup")
		opening.battle_id = state.battle_identity()
		opening.phase = BattleSimulation.Phase.VICTORY
		check(state.settle_battle(opening), "Traverse clear encounter to asteroid region")
	check(state.battle_pending and state.pending_encounter.has("asteroids"), "Reach actual generated asteroid encounter")
	var saved: Dictionary = state.hangar_snapshot()
	check(state.load_run_checkpoint() and SaveValidation.same(state.hangar_snapshot(), saved),
		"Continue preserves frozen conditions, rock identity and positions")
	var context: Dictionary = state.battle_support_context()
	check(context.has("asteroids") and context.has("environment") and not context.has("extraction")
		and not context.has("mining_materials") and context.credits_only,
		"Physical battle context includes hazards without enabling mining or material rewards")
	var simulation := BattleSimulation.new()
	check(simulation.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0,
		state.battle_simulation_seed(), context), "Actual physical battle attaches generated field")
	check(simulation.other_entities.size() == context.asteroids.roots.size()
		and SaveValidation.same(simulation.environment, context.environment), "All generated rocks and conditions reach simulation")
	var ambient_context := context.duplicate(true)
	ambient_context.environment.solar_intensity = 0.5 if context.environment.solar_intensity != 0.5 else 1.5
	ambient_context.environment.nebula = not context.environment.nebula
	var ambient := BattleSimulation.new()
	check(ambient.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0,
		state.battle_simulation_seed(), ambient_context), "Alternate ambient conditions configure")
	check(ambient.random.state == simulation.random.state and ambient.player.stats.dps == simulation.player.stats.dps
		and ambient.player.stats.shields == simulation.player.stats.shields
		and ambient.player.stats.top_speed == simulation.player.stats.top_speed
		and ambient.visibility_enabled == simulation.visibility_enabled,
		"Solar/nebula metadata changes neither weapons, shields, mobility, visibility nor combat RNG")
	check(SaveValidation.same(simulation.authoritative_snapshot().environment, context.environment),
		"Shared global conditions are retained in battle diagnostic snapshots")
	check(simulation.set_objective_targets(state.battle_objective_ids()), "Asteroids are not required hostile objectives")
	var first: BattleSimulation.Combatant = simulation.other_entities[0]
	var initial := first.position
	simulation.asteroid_field.advance(simulation, 1.0 / 30.0)
	check(not first.position.is_equal_approx(initial), "Asteroids drift on the simulation clock")
	first.position = simulation.player.position
	var hull: float = state.fleet[0].hull_hp
	var shields := simulation.player.shields
	simulation.asteroid_field.advance(simulation, 1.0 / 30.0)
	check(simulation.player.shields < shields or state.fleet[0].hull_hp < hull, "Asteroid collision damages real shields/hull")
	check(simulation.collected_categories.is_empty() and simulation.drops.is_empty()
		and not simulation.mining_enabled and simulation.asteroid_field.extraction.rate == 0,
		"Asteroid hazards never introduce material payouts")
	first.position = Vector2.ZERO
	check(simulation.asteroid_field.intercept(simulation, Vector2(-60, 0), Vector2(60, 0)) == first,
		"Generated asteroid intercepts a shot crossing its collider")
	var frozen: Dictionary = state.pending_encounter.duplicate(true)
	check(SaveValidation.same(frozen.asteroids, context.asteroids), "Live drift/damage never mutate frozen retry field")
	var malformed := saved.duplicate(true)
	malformed.pending_encounter.environment.solar_intensity = -1
	malformed.navigation.encounters[str(malformed.destination)] = malformed.pending_encounter.duplicate(true)
	check(not HangarCheckpoint.valid(malformed), "Malformed frozen conditions invalidate physical saves")
	var legacy := saved.duplicate(true)
	legacy.pending_encounter.erase("environment")
	legacy.navigation.encounters[str(legacy.destination)] = legacy.pending_encounter.duplicate(true)
	check(HangarCheckpoint.valid(legacy) and state._commit_hangar(legacy), "Older frozen encounters without conditions remain supported")
	check(state.battle_support_context().has("asteroids"), "Older saved asteroid fields also reach physical combat")
	check(state._commit_hangar(saved), "Restore pristine frozen field")
	await _test_views()
	print("NODE ENVIRONMENT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_views() -> void:
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	screen.active_tab = "MAP"
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	await settle()
	var before: Dictionary = state.hangar_snapshot()
	screen._select_destination(state.destination_node_id)
	var label: Label = screen.map_details.find_child("NodeConditions", true, false)
	check(label == null and state.hangar_snapshot() == before,
		"Informational expedition Map does not present legacy node conditions as active journey hazards")
	screen.queue_free()
	await settle()
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	await settle()
	battle.set_physics_process(false)
	battle.set_process(false)
	check(battle.simulation.asteroid_field.roots.size() == state.pending_encounter.asteroids.roots.size(),
		"Playable battle scene actually includes every generated asteroid")
	check(SaveValidation.same(battle.simulation.environment, state.pending_encounter.environment),
		"Combat retains the exact frozen density, solar intensity and nebula")
	check(battle.visuals._rock_texture is CanvasTexture, "Visible asteroid atlas uses supplied diffuse, normal and surface maps")
	if DisplayServer.get_name() != "headless":
		for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.size = resolution
			battle.visuals.camera_position = Vector2.ZERO
			battle.visuals.camera_zoom = 0.5
			battle.visuals.queue_redraw()
			await settle()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/asteroid-battle-%d.png" % resolution.x)
		var visible: Image = root.get_texture().get_image()
		var rocks: Array[BattleSimulation.Combatant] = battle.simulation.other_entities.duplicate()
		battle.simulation.other_entities.clear()
		battle.visuals.queue_redraw()
		await settle()
		await RenderingServer.frame_post_draw
		var without: Image = root.get_texture().get_image()
		var changed := 0
		var scale := Vector2(visible.get_size()) / root.get_visible_rect().size
		for rock: BattleSimulation.Combatant in rocks:
			var point: Vector2 = (battle.visuals.world_transform() * rock.position) * scale
			var radius: float = rock.radius * battle.visuals.camera_zoom * scale.x
			var rect := Rect2i(Vector2i(point - Vector2.ONE * radius), Vector2i.ONE * ceili(radius * 2))
			rect = rect.intersection(Rect2i(Vector2i.ZERO, visible.get_size()))
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					if visible.get_pixel(x, y).is_equal_approx(without.get_pixel(x, y)):
						continue
					changed += 1
		check(changed > 20, "Mapped asteroid sprites produce visible pixels at their actual collider positions")
		battle.simulation.other_entities.assign(rocks)
	battle.queue_free()
	await settle()
