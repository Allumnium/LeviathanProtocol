extends SceneTree

var failures := 0
var requests: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _find(nodes: Array[Dictionary], id: String) -> Dictionary:
	for node in nodes:
		if node.id == id:
			return node
	return {}

func _texts(node: Node) -> String:
	var result := String(node.text) if node is Label or node is Button else ""
	for child in node.get_children():
		result += "\n" + _texts(child)
	return result

func _click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame
	await process_frame

func _run() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://research_ui/run.json"
	_check(state.start_new_run(1, 42), "Start isolated research UI run.")
	var live := GameDefinitions.snapshot()
	var current := ResearchViewModel.nodes(live, ["foundation"], {}, {}, 1000)
	_check(current.size() == 8 and _find(current, "optics_i").is_empty(), "Functional shared research appears while future branches remain hidden.")
	var live_detail := ResearchViewModel.details(live, "foundation", ["foundation"])
	_check(live_detail.contains("Command Center") and live_detail.contains("Research Lab") and not live_detail.contains("Ability: Scan"), "Owned Foundation exposes only implemented grants.")
	# Enable a detached fixture registry, never production definitions/effects.
	var fixture := live.duplicate(true)
	for domain in ["research", "equipment", "abilities"]:
		for entry: Dictionary in fixture[domain]:
			entry.implemented = true
	var visible := ResearchViewModel.nodes(fixture, ["foundation"], {}, {}, 20)
	_check(visible.size() == 46, "Grouped presentation handles the complete registry when definitions are ready.")
	_check(_find(visible, "applied_energy").status == "Ready" and _find(visible, "applied_energy").nearby, "Affordable next options are emphasized.")
	_check(_find(visible, "laboratory_ii").status == "Need RP" and _find(visible, "laboratory_ii").nearby, "Near-term options remain emphasized when RP is short.")
	_check(_find(visible, "optics_ii").depth == 1 and _find(visible, "optics_iii").depth == 2, "Combat branches use three depth columns.")
	_check(_find(visible, "planetary_fracture").depth == 3, "Long shared paths keep their fourth depth column.")
	var ids: Array = visible.map(func(n: Dictionary) -> String: return n.id)
	var energy_detail := ResearchViewModel.details(fixture, "applied_energy", ids)
	_check(energy_detail.contains("Laser") and energy_detail.contains("Double Laser") and energy_detail.contains("OOO\n  OOO"), "One research review presents both equipment grants and their recipes.")
	var concept := ResearchViewModel.details(fixture, "energy_manipulation", ids)
	_check(concept.contains("+10%") and concept.contains("cap +30%") and not concept.contains("• Energy Manipulation"), "Concept-only research has an effect description, not a fictitious component.")
	var lab := ResearchViewModel.details(fixture, "laboratory_iii", ids)
	_check(lab.contains("rank 3") and lab.contains("CCTT") and lab.contains("Bastion Warden"), "Rank grants show their actual footprint and boss gate.")
	var optics := ResearchViewModel.details(fixture, "optics_i", ids)
	_check(optics.contains("Disruption I") and optics.contains("Ion Emitter") and optics.contains("Singularity Projector")
		and optics.contains("Stellar Lance") and optics.contains("Brood Architect") and optics.contains("No respec"), "Review exposes all opposite tiers, downstream rewards and endpoint story gates before commitment.")
	var committed := ResearchViewModel.nodes(fixture, ["foundation", "applied_energy", "optics_i"], {}, {"energy": "optics"}, 1000)
	_check(_find(committed, "disruption_i").status == "Excluded" and _find(committed, "disruption_iii").status == "Excluded", "Owned family commitment labels every opposing tier as excluded.")
	_check(_find(committed, "bastion_i").status == "Ready", "Other families remain independently available.")
	var gates := ResearchViewModel.nodes(fixture, ["foundation", "laboratory_ii"], {}, {}, 1000)
	_check(_find(gates, "laboratory_iii").status == "Story gate", "Unmet boss events remain explicit after prerequisites are met.")

	var map: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await process_frame
	await process_frame
	var view: Control = map.panel_tabs.get_node("Upgrades").grouped_view
	map.panel_tabs.current_tab = 2
	await process_frame
	_check(view.nodes.size() == 7 and not view.card_buttons.has("foundation"), "All seven available technologies share one tree; Foundation is assumed.")
	_check(view.tree_canvas.branch_roots.size() == 3 and view.tree_canvas.edges.size() == 7, "Research categories are connected major branches on the same canvas.")
	view.registry = fixture
	view.state_override = {"research_ids": ["foundation"], "story_flags": {}, "branch_choices": {}, "research_points": 0}
	view.refresh()
	_check(view.card_buttons.size() == 45 and view.tree_canvas.branch_roots.size() == 10, "The complete detached catalog fits one graph without category filtering or a Foundation card.")
	for edge: Array in view.tree_canvas.edges:
		if view.tree_canvas.positions.has(edge[0]):
			_check(view.tree_canvas.positions[edge[1]].x > view.tree_canvas.positions[edge[0]].x, "Cross-category prerequisites retain forward hierarchy: %s." % str(edge))
	view.registry = live
	view.state_override = {}
	view.refresh()
	_check(not _texts(map.research_groups).contains("CATEGORIES") and _texts(map.research_groups).contains("0.5 RP/day"), "The left panel describes baseline production instead of filtering categories.")
	var destination: int = state.get_reachable_nodes(state.current_node_id)[0]
	_check(state.set_planned_destination(destination), "Select a travel plan.")
	_check(_texts(map.research_groups).contains("days") and _texts(map.research_groups).contains("RP on arrival"), "Planning a route refreshes its days and expected RP.")
	view._select("applied_energy")
	_check(not state.is_modal_ui_open() and not view.focus_button.disabled, "Zero-RP focus stays inline and available.")
	await _click(view.focus_button)
	_check(state.research_focus == "applied_energy" and view.focus_button.text == "FOCUSED", "Pointer sets focus at zero RP.")
	state.research_points = 20.0
	_check(state.set_research_focus("applied_energy") and state.current_research_ids.has("applied_energy"), "Complete a real focused node.")
	_check(view.card_buttons.applied_energy.find_child("Completed", true, false) is Line2D, "Completion is a drawn green check above the name, not a font glyph or Complete label.")
	state.research_points = 12.5
	_check(state.set_research_focus("energy_manipulation"), "Set a partially funded concept.")
	var marker: Label = view.card_buttons.energy_manipulation.find_child("Progress", true, false)
	_check(marker.text == "12.5 / 40", "Node progress preserves fractional RP and displays X / Y above its name.")
	_check(not _texts(map.research_details).contains("Ordinary") and not _texts(map.research_details).contains("RESEARCH DETAILS"), "Details keep only the effect, progress and focus action.")
	_check(state.load_run_checkpoint() and state.research_progress.get("energy_manipulation") == 12.5, "Partial half-RP research reloads without truncation.")
	view._select("laboratory_iii")
	_check(view.focus_button.disabled and _texts(map.research_details).contains("Laboratory II"), "Prerequisites still block focus with concise inline feedback.")
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await process_frame
		await process_frame
		view.tree_canvas.fit_view()
		var camera: Vector2 = view.tree_canvas.camera_position
		var point: Vector2 = view.tree_canvas.get_global_rect().end - Vector2(8, 8)
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = point if pressed else point - Vector2(24, 0)
			event.button_index = MOUSE_BUTTON_MIDDLE
			event.pressed = pressed
			root.push_input(event, true)
			if pressed:
				var movement := InputEventMouseMotion.new()
				movement.position = point - Vector2(24, 0)
				movement.relative = Vector2(-24, 0)
				movement.button_mask = MOUSE_BUTTON_MASK_MIDDLE
				root.push_input(movement, true)
		_check(view.tree_canvas.camera_position.x > camera.x, "Pointer pans the unified tree at %s." % resolution)
		view.tree_canvas.camera_position = view.tree_canvas.positions.energy_manipulation + view.tree_canvas.CARD_SIZE * 0.5
		view.tree_canvas._update_camera()
		await _click(view.card_buttons.energy_manipulation)
		_check(view.selected_id == "energy_manipulation" and not state.is_modal_ui_open(), "Pointer selects a node and updates right details at %s." % resolution)
		_check(map.research_details.get_global_rect().encloses(view.focus_button.get_global_rect()), "Focus remains in the right panel.")
		var zoom: float = view.tree_canvas.camera_zoom
		var wheel := InputEventMouseButton.new()
		wheel.position = point
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		root.push_input(wheel, true)
		_check(view.tree_canvas.camera_zoom > zoom, "Pointer zooms the unified tree.")
		wheel.pressed = false
		root.push_input(wheel, true)
		view.tree_canvas.camera_zoom = 1.0
		view.tree_canvas.camera_position = Vector2(205, 88)
		view.tree_canvas._update_camera()
		_check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(map.get_node("Layout").get_global_rect()), "Research layout fits the viewport at %s." % resolution)
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/research-tree/captures"))
			root.get_texture().get_image().save_png("res://.local/research-tree/captures/tree-%dx%d.png" % [resolution.x, resolution.y])
		view.tree_canvas.camera_zoom = 0.4
		view.tree_canvas.camera_position = Vector2(180, 225)
		view.tree_canvas._update_camera()
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/research-tree/captures/overview-%dx%d.png" % [resolution.x, resolution.y])
	map.panel_tabs.current_tab = 0
	_check(not map.research_groups.visible and not map.research_details.visible, "Research sidebars hide on other tabs.")
	map.queue_free()
	current_scene = null
	await process_frame
	print("Grouped research UI tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
