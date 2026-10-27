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

func _run() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://research_ui/run.json"
	_check(state.start_new_run(1, 42), "Start isolated research UI run.")
	var live := GameDefinitions.snapshot()
	var current := ResearchViewModel.nodes(live, ["foundation"], {}, {}, 1000)
	_check(current.size() == 1 and current[0].id == "foundation", "Future research stays hidden regardless of RP or satisfied prerequisites.")
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
	if is_instance_valid(map.campaign_overlay):
		map.campaign_overlay.queue_free()
	var view: Control = map.panel_tabs.get_node("Upgrades").grouped_view
	_check(view != null and view.nodes.size() == 1 and not map.research_groups.visible, "New campaign mounts the gated grouped UI without showing it on Fleet.")
	map.panel_tabs.current_tab = 2
	_check(map.research_groups.visible and map.research_details.visible and not map.build_controls.visible, "Research tab activates its family and detail sidebars.")
	var before: Dictionary = state.run_progress_snapshot()
	view.card_buttons.foundation.pressed.emit()
	_check(is_instance_valid(view.details_dialog) and state.is_modal_ui_open() and view.review_action == null, "Owned review is modal and cannot request another purchase.")
	view.close_details()
	await process_frame
	_check(not state.is_modal_ui_open() and state.run_progress_snapshot() == before, "Review and close do not mutate run state.")
	view.registry = fixture
	view.state_override = {"research_ids": ["foundation"], "story_flags": {}, "branch_choices": {}, "research_points": 20}
	view.refresh()
	view.purchase_requested.connect(func(id: String) -> void: requests.append(id))
	view.card_buttons.applied_energy.pressed.emit()
	_check(_texts(view.details_dialog).contains("Double Laser") and view.review_action != null
		and view.review_action.text.contains("20 RP") and requests.is_empty(), "Selection opens the complete review before any acquisition request.")
	view.review_action.pressed.emit()
	_check(requests == ["applied_energy"] and state.run_progress_snapshot() == before, "Only an explicit reviewed action emits a request; the view never spends RP or grants content.")
	await process_frame
	view.state_override.research_points = 0
	view.refresh()
	view.card_buttons.applied_energy.pressed.emit()
	_check(view.review_action == null and _texts(view.details_dialog).contains("20 more RP"), "Insufficient RP cannot emit an acquisition request.")
	view.close_details()
	await process_frame
	view.state_override.research_points = 1000
	view.collapsed.energy = false
	view.refresh()
	view.card_buttons.optics_i.pressed.emit()
	_check(view.review_action == null and _texts(view.details_dialog).contains("Still needed: Applied Energy"), "Unmet prerequisites block the review action.")
	view.close_details()
	await process_frame
	view.state_override.research_ids = ["foundation", "applied_energy"]
	view.refresh()
	view.card_buttons.optics_i.pressed.emit()
	_check(_texts(view.details_dialog).contains("locks every Disruption tier") and view.review_action != null,
		"Permanent branch warning is pinned beside the reviewed acquisition action.")
	view.state_override.research_points = 0
	view.refresh()
	_check(not view.details_dialog.visible and view.review_action == null, "State refresh closes stale acquisition reviews.")
	view.collapsed.energy = true
	view.refresh()
	_check(not view.card_buttons.has("optics_i"), "Collapsed families remove their tier cards.")
	view.group_headers.energy.pressed.emit()
	_check(view.card_buttons.has("optics_i"), "Family headers reopen depth cards.")
	view.state_override = {}
	view.registry = live
	state.research_points = 73
	state.research_changed.emit()
	_check(view.nodes.size() == 1 and view.rp_label.text.contains("73 RP"), "Research signals refresh state and restore production gating.")
	map.panel_tabs.current_tab = 0
	_check(not map.research_groups.visible and not map.research_details.visible, "Research sidebars hide on other tabs.")
	map.queue_free()
	current_scene = null
	await process_frame
	print("Grouped research UI tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
