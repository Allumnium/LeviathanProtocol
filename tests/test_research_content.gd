extends SceneTree

const Loadouts = preload("res://scripts/ship_loadouts.gd")
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

func setup() -> bool:
	var db := Content.load_all(["res://packs", "res://tests/fixtures/content/research_patch"])
	check(db.problems.items.is_empty(), "Research tuning fixture loads without Problems: " + db.problems.text())
	if not db.problems.errors().is_empty():
		return false
	var started: bool = state.start_new_run(1, 3741)
	check(started, "Start a production convoy with patched research")
	return started

func gated_offer() -> void:
	check(HangarResearch.threshold(state.run_progress_snapshot()) == 12
		and HangarResearch.option_count(state.get_deployed_fleet()) == 2, "Research bar and base card count read tuning defs")
	var data: Dictionary = state.hangar_snapshot()
	state._allocate_research(data.research, 12)
	check(data.research.research_offer.is_empty() and state._commit_hangar(data), "A blocked authored gate banks earned research")
	check(not HangarResearch.eligible("applied_energy", state.run_progress_snapshot())
		and not HangarResearch.eligible("field_engineering", state.run_progress_snapshot()), "The declared gate and offered=false control eligibility")
	data = state.hangar_snapshot()
	data.research.story_flags.field_trial = true
	state._allocate_research(data.research, 0)
	check(state._commit_hangar(data), "Commit a custom declared story gate")
	var offer: Array = state.research_offer.duplicate()
	check(offer.size() == 2 and "applied_energy" in offer and "field_notes" in offer,
		"Actual offers include the patched card and a newly authored inherited card")
	check(state.load_run_checkpoint() and state.research_offer == offer, "Continue preserves custom offers exactly")

func mechanics() -> void:
	var shipped := Content.load_all(["res://packs"])
	check(shipped.problems.items.is_empty() and HangarResearch.view_registry().research.size() == 16, "Shipped pool stays at fifteen upgrades plus Foundation")
	check(Loadouts.equipment_available(SlotCatalog.find_equipment("tactical_computer"), ["foundation"]), "Warm ordinary equipment access before replacement")
	check(setup(), "Configure research authority fixture")
	if state.run_id.is_empty():
		return
	check(ResearchRules.validate_registry(GameDefinitions.snapshot()).is_empty(), "Custom family, gate and shared unlocks validate without an ID whitelist")
	check(not Loadouts.equipment_available(SlotCatalog.find_equipment("tactical_computer"), ["foundation"]), "Equipment access changes when its data says research is required")
	gated_offer()
	check(ResearchViewModel.description(HangarResearch.view_registry(), "applied_energy") == "Lasers strike harder."
		and ResearchUpgrades.requirement("applied_energy") == "Deploy a research lab.", "Card and actionable requirement text use authored fields")
	check(ResearchUpgrades.matches("applied_energy", state.get_deployed_fleet()), "Patched matching follows living labs instead of lasers")
	var drone_id: int = state.fleet[3].id
	check(state.refit_ship(drone_id, "laser_drone"), "Fit an ordinary laser for effect verification")
	var weapon_before: float = state.owned_ship(drone_id).get_stats().weapons[0].damage_per_shot
	var before: Dictionary = state.hangar_snapshot()
	var save_path: String = state.run_save_path
	state.run_save_path = "res://project.godot/blocked-research-content.json"
	check(not state.choose_research("applied_energy") and SaveValidation.same(before, state.hangar_snapshot()), "Failed patched choice rolls back RP, grants, branch and offer")
	state.run_save_path = save_path
	check(state.choose_research("applied_energy") and state.research_points == 0
		and state.research_branch_choices.get("fieldcraft") == "practical", "Actual choice commits the custom family path and shared-bar debit")
	check(is_equal_approx(state.owned_ship(drone_id).get_stats().weapons[0].damage_per_shot, weapon_before * 1.35), "Patched modifier changes actual fitted laser damage")
	check(Loadouts.equipment_available(SlotCatalog.find_equipment("beam_lance"), state.current_research_ids)
		and Loadouts.equipment_available(SlotCatalog.find_equipment("tactical_computer"), state.current_research_ids), "Authored equipment grants are applied without filtering by card ID")
	check(state.load_run_checkpoint() and state.research_branch_choices.get("fieldcraft") == "practical"
		and is_equal_approx(state.owned_ship(drone_id).get_stats().weapons[0].damage_per_shot, weapon_before * 1.35), "Custom grants and branch survive Continue")
	var opposite := Content.get_def("research", "applied_energy").duplicate(true)
	opposite.id = "opposite"
	opposite.family_id = "fieldcraft"
	opposite.path_id = "theory"
	var opposite_catalog: Array[Dictionary] = [opposite]
	check(ResearchRules.requirements("opposite", state.current_research_ids, state.story_flags,
		state.research_branch_choices, opposite_catalog).branch_conflict, "Qualified and local family references share one commitment")
	check(HangarResearch.threshold(state.run_progress_snapshot()) == 24, "Patched progression advances to its next threshold")
	var data: Dictionary = state.hangar_snapshot()
	state._allocate_research(data.research, 24)
	check(state._commit_hangar(data) and state.research_offer == ["field_notes"] and state.choose_research("field_notes"), "A new inherited research ID can be offered and chosen")
	for event: Dictionary in state.expedition_simulation.events:
		state.expedition_simulation.state.event_receipts[event.id] = true
	check(state.depart_expedition("refuel_station_1"), "Depart to verify the new authored effect")
	var result: Dictionary = state.advance_expedition(10, true)
	check(result.ok and result.income == 6, "New-card travel income executes through the actual travel transaction")
	check(state.current_research_ids.has("field_notes") and not state.current_research_ids.has("civil_hospitality"), "An inherited card does not require or silently grant its template")
	Content.set_database(shipped)
	check(Loadouts.equipment_available(SlotCatalog.find_equipment("tactical_computer"), ["foundation"])
		and HangarResearch.threshold({"research_ids": ["foundation"]}) == 20, "Restoring shipped content restores its access and bar tuning")
	broken_patches(shipped)

func broken_patches(shipped: DefDatabase) -> void:
	var folder := "user://research_bad/invalid/defs"
	DirAccess.make_dir_recursive_absolute(folder)
	var manifest := {"id": "invalid_research", "name": "Invalid research fixture", "version": "1.0.0", "kind": "content", "depends": [{"id": "core", "version": ">=1.0"}]}
	FileAccess.open("user://research_bad/invalid/pack.json", FileAccess.WRITE).store_string(JSON.stringify(manifest))
	var probes := [
		{"set": {"grants.modifiers[laser_damage_multiplier].value": 0}, "path": "grants.modifiers[laser_damage_multiplier]"},
		{"set": {"family_id": "energy", "path_id": "nonexistent"}, "path": "path_id"},
		{"set": {"prerequisite_ids": ["applied_energy"]}, "path": "prerequisite_ids"},
		{"set": {"prerequisite_ids": ["energy_manipulation"]}, "path": "prerequisite_ids"},
		{"set": {"prerequisite_ids": 3}, "path": "prerequisite_ids"},
		{"target": "core:energy", "target_def": "research_family", "set": {"paths": ["new_optics", "disruption"]}, "path": "path_id"},
		{"target": "core:energy", "target_def": "research_family", "set": {"paths": 3}, "path": "paths"},
		{"set": {"implemented": false}, "path": "offered"},
		{"set": {"description": ""}, "path": "description"},
		{"target": "core:carrier_i", "set": {"offered": true}, "path": "offered"}
	]
	for probe: Dictionary in probes:
		var patch := {"def": "patch", "id": "broken", "target": probe.get("target", "core:applied_energy"), "target_def": probe.get("target_def", "research"), "set": probe.set}
		FileAccess.open(folder + "/patch.json", FileAccess.WRITE).store_string(JSON.stringify(patch))
		var db := PackLoader.new().load_packs(["res://packs", "user://research_bad"])
		check(db.has_pack("core") and db.has_pack("leviathan") and not db.has_pack("invalid_research")
			and db.content_hash == shipped.content_hash, "Invalid research patch is disabled without changing shipped content: " + probe.path)
		var blamed := false
		for problem: Dictionary in db.problems.errors():
			if problem.pack == "invalid_research" and problem.def == "broken" and problem.path == probe.path:
				blamed = true
		check(blamed, "Problems identify the patch and field: " + probe.path)

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://research-content.json"
	if "--native-only" in OS.get_cmdline_user_args():
		await native_cards()
		print("RESEARCH CONTENT NATIVE COMPLETE: %d checks, %d failures" % [checks, failures])
	else:
		mechanics()
		print("RESEARCH CONTENT COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func settle() -> void:
	await create_timer(0.25).timeout
	for frame in 4:
		await process_frame

func text_under(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label else ""
	for child in node.get_children():
		result += text_under(child)
	return result

func native_cards() -> void:
	check(DisplayServer.get_name() != "headless", "Native card check requires a renderer")
	if DisplayServer.get_name() == "headless":
		return
	check(setup(), "Start native research fixture")
	gated_offer()
	state.pending_intro = false
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	await settle()
	screen.set_process(false)
	var dialog: Control = screen.research_dialog
	check(is_instance_valid(dialog) and dialog.buttons.size() == 2, "Real management UI opens the two authored cards")
	if not is_instance_valid(dialog):
		screen.queue_free()
		return
	check(text_under(dialog).contains("Lasers strike harder.") and text_under(dialog).contains("Cruising earns extra expedition funding.")
		and text_under(dialog).contains("Locks other fieldcraft paths."), "Native cards show authored descriptions and family label")
	for size: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		await settle()
		check(screen.get_global_rect().encloses(dialog.panel.get_global_rect()), "Authored cards fit at %s" % size)
		for id: String in dialog.cards:
			check(dialog.cards[id].get_global_rect().encloses(dialog.buttons[id].get_global_rect()), "Choose remains inside card at %s" % size)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("user://research-content-%d.png" % size.x) == OK, "Capture authored research cards")
	var button: Button = dialog.buttons.applied_energy
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = motion.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await settle()
	check(state.current_research_ids.has("applied_energy") and state.research_branch_choices.get("fieldcraft") == "practical"
		and not is_instance_valid(screen.research_dialog), "Actual pointer choice commits the authored research and closes its window")
	check(screen.research_status.text == "0 / 24 RP", "The header displays the patched next threshold")
	screen.queue_free()
	await settle()
