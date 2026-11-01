extends SceneTree

var checks := 0
var failures := 0
var state: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func win() -> void:
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0,
		state.battle_simulation_seed(), state.battle_support_context()), "Swarm battle setup")
	sim.battle_id = state.battle_identity()
	sim.phase = BattleSimulation.Phase.VICTORY
	check(state.settle_battle(sim), "Swarm battle settlement")

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://swarm-navigation.json"
	for seed_value in range(128):
		var graph := CampaignGraph.generate(seed_value, 2)
		check(not graph.is_empty() and CampaignGraph.errors(graph).is_empty(), "Valid planar network seed %d" % seed_value)
		if graph.is_empty():
			continue
		for i in range(graph.edges.size()):
			var first: Array = graph.edges[i]
			for j in range(i + 1, graph.edges.size()):
				var second: Array = graph.edges[j]
				if first[0] in second or first[1] in second:
					continue
				var a := Vector2(graph.nodes[first[0]].position[0], graph.nodes[first[0]].position[1])
				var b := Vector2(graph.nodes[first[1]].position[0], graph.nodes[first[1]].position[1])
				var c := Vector2(graph.nodes[second[0]].position[0], graph.nodes[second[0]].position[1])
				var d := Vector2(graph.nodes[second[1]].position[0], graph.nodes[second[1]].position[1])
				check(Geometry2D.segment_intersects_segment(a, b, c, d) == null, "Routes never intersect")
	check(state.start_new_run(1, 19), "New network run")
	var first: int = state.get_reachable_nodes(0)[0]
	var base: Dictionary = state.frozen_encounters[str(first)].duplicate(true)
	var boss_base: Dictionary = state.frozen_encounters[str(state.campaign_dag.bosses[0])]
	var boss := SwarmNavigation.encounter(boss_base, 40)
	check(EncounterGenerator.valid(boss) and boss.warden.damage_multiplier == 1.2
		and boss.warden.warning_seconds == boss_base.warden.warning_seconds,
		"Swarm strengthens Warden lance without changing its telegraph")
	var leviathan_base: Dictionary = state.frozen_encounters[str(state.FINAL_NODE_ID)]
	check(SwarmNavigation.encounter(leviathan_base, 80).roster[0].stats[1] > SwarmNavigation.encounter(leviathan_base, 40).roster[0].stats[1],
		"More time strengthens the Leviathan encounter")
	var days: float = state.research_travel_time(0, first)
	check(state.travel_to(first), "First swarm departure")
	var frozen: Dictionary = state.get_frozen_encounter(first)
	check(state.navigation.intensity == days and state.navigation.days == days, "Days increase intensity at departure")
	check(frozen.roster[0].stats[1] > base.roster[0].stats[1] and frozen.roster[0].weapons[0][2] > base.roster[0].weapons[0][2],
		"Intensity increases hostile hull and damage")
	check(state.load_run_checkpoint() and SaveValidation.same(frozen, state.get_frozen_encounter(first)), "Pending strength survives Continue")
	check(state.cancel_battle() and state.travel_to(first) and state.navigation.intensity == days * 2
		and SaveValidation.same(frozen, state.get_frozen_encounter(first)), "Retry consumes travel time but keeps the first encounter strength")
	win()
	var credits: int = state.credits
	check(state.get_reachable_nodes(first).has(0), "Backtracking is reachable")
	check(state.travel_to(0) and not state.battle_pending and state.navigation.intensity == days * 3, "Backtracking consumes days")
	check(state.travel_to(first) and not state.battle_pending and state.credits == credits, "Cleared encounter pays no repeat reward")
	check(state.visited_nodes.size() == 2 and state.load_run_checkpoint(), "Unique visits survive repeat journeys")
	var before: Dictionary = state.hangar_snapshot()
	var old_path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-save.json"
	check(not state.travel_to(0) and SaveValidation.same(before, state.hangar_snapshot()), "Failed departure rolls back pressure")
	state.run_save_path = old_path
	var event_node: int = -1
	for node: Dictionary in state.campaign_dag.nodes:
		if not SwarmNavigation.event(state.campaign_dag, node.id).is_empty():
			event_node = node.id
			break
	var fixture: Dictionary = state.hangar_snapshot()
	fixture.current = event_node
	fixture.visited.append(event_node)
	check(state._commit_hangar(fixture), "Event fixture")
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	for frame in range(4):
		await process_frame
	for tab: Button in screen.tabs.get_children():
		if tab.text == "MAP":
			tab.pressed.emit()
			break
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		for frame in range(4):
			await process_frame
		screen._select_destination(state.get_reachable_nodes(event_node)[0])
		for frame in range(4):
			await process_frame
		check(screen.details_panel.get_global_rect().end.y <= screen.size.y
			and screen.center.size.x > 100, "Event and travel choices preserve usable map layout")
		for action: Node in screen.map_details.get_children():
			if action is Button:
				check(screen.map_details.get_parent().get_global_rect().encloses(action.get_global_rect()),
					"Single event and travel choices fit without scrolling")
		if DisplayServer.get_name() != "headless":
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/swarm"))
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/swarm/event-%d.png" % resolution.x)
	for action: Node in screen.map_details.get_children():
		if action is Button and action.text == "Relay data":
			var click := InputEventMouseButton.new()
			click.position = action.get_global_rect().get_center()
			click.global_position = click.position
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			root.push_input(click, true)
			click = click.duplicate()
			click.pressed = false
			root.push_input(click, true)
			break
	for frame in range(4):
		await process_frame
	check(state.navigation.quests.has(str(event_node)) and not state.resolve_map_event("relay"), "Native quest choice accepts once")
	check(screen.roster.find_child("SwarmIntensity", true, false) != null and state.quest_targets().size() == 1,
		"Map shows live intensity and accepted quest marker")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/swarm/quest-marker.png")
	screen.queue_free()
	for frame in range(4):
		await process_frame
	var target: int = state.quest_targets()[0]
	fixture = state.hangar_snapshot()
	var source := -1
	for edge: Array in state.campaign_dag.edges:
		if int(edge[1]) == target:
			source = int(edge[0])
			break
	fixture.current = source
	if not fixture.visited.has(source):
		fixture.visited.append(source)
	check(state._commit_hangar(fixture), "Quest approach fixture")
	var reward_credits: int = state.credits
	var arrival_intensity: float = maxf(0, state.navigation.intensity + state.research_travel_time(source, target) - 4)
	check(state.travel_to(target) and state.credits == reward_credits + 60
		and state.navigation.intensity == arrival_intensity, "Actual arrival pays quest and reduces pressure atomically")
	check(state.load_run_checkpoint() and state.quest_targets().is_empty(), "Quest completion persists")
	reward_credits = state.credits
	check(state.travel_to(source) and state.travel_to(target) and state.credits == reward_credits,
		"Returning to quest destination never pays it again")
	var malformed: Dictionary = state.hangar_snapshot()
	malformed.navigation.intensity = -1
	check(not HangarCheckpoint.valid(malformed), "Reject malformed intensity")
	var legacy: Dictionary = state.hangar_snapshot()
	legacy.erase("navigation")
	check(HangarCheckpoint.valid(legacy), "Older physical checkpoint remains readable")
	check(state._commit_hangar(legacy) and state.load_run_checkpoint() and state.navigation.is_empty(), "Legacy navigation retains old graph")
	check(not state.get_reachable_nodes(first).has(0), "Old runs stay forward-only")
	print("SWARM NAVIGATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
