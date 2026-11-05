extends SceneTree

var state: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func start(science := false) -> void:
	check(state.start_new_run(1, 7341, true, "flagship_science" if science else "flagship_basic"), "Start isolated research run")
	state.pending_intro = false

func fund(amount: float) -> void:
	var data: Dictionary = state.hangar_snapshot()
	state._allocate_research(data.research, amount)
	check(state._commit_hangar(data), "Commit earned research points")

func mechanics() -> void:
	start()
	check(state.current_research_ids == ["foundation"] and state.research_offer.is_empty(), "New run grants no choices or upgrades")
	check(HangarResearch.threshold(state.run_progress_snapshot()) == 20, "First shared bar costs 20 RP")
	fund(19.75)
	check(not state.research_choice_ready() and not state.choose_research("applied_energy"), "Partial bar cannot grant any upgrade")
	fund(0.5)
	var offer: Array = state.research_offer.duplicate()
	check(offer.size() == 3 and HangarResearch.valid(state.run_progress_snapshot()), "Full bar generates three valid unique options")
	var repeated: Dictionary = state.run_progress_snapshot()
	repeated.research_offer = []
	HangarResearch.prepare_offer(repeated, state.run_seed, 3, state.get_deployed_fleet())
	check(repeated.research_offer == offer, "Seeded draw is reproducible without sharing combat RNG")
	check(state.load_run_checkpoint() and state.research_offer == offer and state.research_points == 20.25,
		"Continue preserves exact offer order and fractional excess")
	var before: Dictionary = state.hangar_snapshot()
	check(not state.choose_research("fleet_logistics_iii") and SaveValidation.same(before, state.hangar_snapshot()),
		"Cannot select removed research")
	state.research_completion_notices.clear()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/blocked-choice.json"
	check(not state.choose_research(offer[0]) and SaveValidation.same(before, state.hangar_snapshot())
		and state.research_completion_notices.is_empty(), "Failed choice saves no RP debit, upgrade, reroll or success notice")
	state.run_save_path = path
	check(state.choose_research(offer[0]) and state.research_points == 0.25 and state.current_research_ids.has(offer[0])
		and state.research_completion_notices == [offer[0]], "Successful choice grants one upgrade and preserves excess")
	check(not state.choose_research(offer[0]), "Repeated choice cannot duplicate a grant")
	check(HangarResearch.threshold(state.run_progress_snapshot()) == 40, "Next shared bar increases by 20")
	fund(100)
	offer = state.research_offer.duplicate()
	check(state.choose_research(offer[0]) and state.research_points == 60.25 and state.research_offer.size() > 0,
		"Large earnings carry into another saved choice at the new threshold")
	check(HangarResearch.threshold(state.run_progress_snapshot()) == 60, "Each choice increases threshold once")
	check(state.load_run_checkpoint() and state.research_choice_ready(), "Continue retains a queued overflow choice")
	var invalid: Dictionary = state.hangar_snapshot()
	invalid.research.research_offer = [state.research_offer[0], state.research_offer[0]]
	check(not HangarCheckpoint.valid(invalid), "Reject duplicate saved cards")
	invalid = state.hangar_snapshot()
	invalid.research.research_offer = ["foundation"]
	check(not HangarCheckpoint.valid(invalid), "Reject already-owned saved cards")
	invalid = state.hangar_snapshot()
	invalid.research.research_points = 0
	check(not HangarCheckpoint.valid(invalid), "Reject unfunded saved offer")
	var progress := {"research_ids": ["foundation"], "research_offer": [], "research_points": 10000.0,
		"story_flags": {}, "branch_choices": {}}
	check("guided_munitions" in HangarResearch.available(progress) and "siege_i" not in HangarResearch.available(progress),
		"Backend prerequisites hide later tiers")
	progress.research_ids.append("guided_munitions")
	check("siege_i" in HangarResearch.available(progress) and "siege_ii" not in HangarResearch.available(progress),
		"Level one permits level two, never level three")
	progress.research_ids.append_array(["applied_energy", "optics_ii"])
	progress.branch_choices.energy = "optics"
	check("disruption_i" not in HangarResearch.available(progress) and "laboratory_iii" not in HangarResearch.available(progress),
		"Branch exclusions and story gates constrain offered pool")
	# Exhaust the real pool by choosing legal options, including both story gates.
	progress.story_flags = {"boss_i_defeated": true, "boss_ii_defeated": true, "boss_iii_defeated": true}
	var smallest := 4
	for index in range(40):
		progress.research_offer = []
		HangarResearch.prepare_offer(progress, 73, 4)
		if progress.research_offer.is_empty():
			break
		smallest = mini(smallest, progress.research_offer.size())
		var id: String = progress.research_offer[0]
		progress.research_ids.append(id)
		var definition := GameDefinitions.find("research", id)
		if not definition.family_id.is_empty():
			progress.branch_choices[definition.family_id] = definition.path_id
	check(HangarResearch.available(progress).is_empty() and progress.research_offer.is_empty() and smallest < 3,
		"Depleted catalog shows remaining options and then stops without duplicates or filler")
	start(true)
	fund(20)
	check(state.research_offer.size() == 4 and HangarResearch.option_count(state.get_deployed_fleet()) == 4,
		"Science flagship adds a fourth unique eligible option")
	check(SlotCatalog.chassis_bonuses(state.fleet[0].chassis).contains("+1 research option")
		and state.fleet[0].chassis.research_rate_multiplier == 1.25, "Science keeps lab output bonus and advertises extra choice")
	start()
	for event: Dictionary in state.expedition_simulation.events:
		state.expedition_simulation.state.event_receipts[event.id] = true
	fund(19.95) # Current starter fleet earns 0.1 RP during this travel second.
	check(state.depart_expedition("refuel_station_1"), "Depart with a nearly full research bar")
	before = state.hangar_snapshot()
	state.run_save_path = "res://project.godot/blocked-ready.json"
	var result: Dictionary = state.advance_expedition(1)
	check(not result.ok and not result.research_ready and SaveValidation.same(before, state.hangar_snapshot()),
		"Failed readiness checkpoint rolls back travel, fuel, bank and cards together")
	state.run_save_path = path
	result = state.advance_expedition(1)
	check(result.ok and result.saved and result.research_ready and state.research_choice_ready()
		and state.current_research_ids == ["foundation"], "Travel crossing the threshold saves an offer without granting an upgrade")
	offer = state.research_offer.duplicate()
	check(state.load_run_checkpoint() and state.research_offer == offer, "Continue restores a travel-earned offer")

func settle() -> void:
	for index in range(6):
		await process_frame

func click(control: Control) -> void:
	check(control.is_visible_in_tree(), "Pointer target is visible")
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = motion.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func native_ui() -> void:
	for science: bool in [false, true]:
		start(science)
		for event: Dictionary in state.expedition_simulation.events:
			state.expedition_simulation.state.event_receipts[event.id] = true
		fund(20)
		check(state.depart_expedition("refuel_station_1"), "Depart before opening the upgrade cards")
		var screen: Control = load("res://scenes/game_map.tscn").instantiate()
		root.add_child(screen)
		current_scene = screen
		var blocker: Dictionary = load("res://scripts/ui_kit.gd").dialog(screen, "ResearchTestModal", "Existing window", "")
		await settle()
		check(not is_instance_valid(screen.research_dialog), "Upgrade selection waits for an existing modal")
		blocker.root.queue_free()
		await create_timer(0.25).timeout
		await settle()
		screen.set_process(false)
		check(is_instance_valid(screen.research_dialog) and screen.active_tab == "MAP", "Full bar automatically opens cards over the map")
		var dialog: Control = screen.research_dialog
		check(dialog.buttons.size() == (4 if science else 3), "Production screen shows correct card count")
		var position_before: Vector2 = state.expedition_simulation.state.position_nu
		screen._advance_expedition(1)
		check(state.expedition_simulation.state.position_nu == position_before, "Visible cards pause travel without changing speed or pause preferences")
		for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.size = resolution
			await settle()
			check(root.get_visible_rect().encloses(dialog.panel.get_global_rect()), "Selection panel fits " + str(resolution))
			for id: String in dialog.buttons:
				check(dialog.cards[id].get_global_rect().encloses(dialog.buttons[id].get_global_rect())
					and dialog.panel.get_global_rect().encloses(dialog.cards[id].get_global_rect()),
					"Card and Choose button are visible at " + str(resolution))
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("user://research-%d-%d.png" % [dialog.buttons.size(), resolution.x]) == OK,
				"Capture native upgrade cards")
		var offer: Array = state.research_offer.duplicate()
		var before: Dictionary = state.hangar_snapshot()
		await click(dialog.find_child("CloseX", true, false))
		screen._maybe_show_research_choices()
		check(not is_instance_valid(screen.research_dialog) and SaveValidation.same(before, state.hangar_snapshot()),
			"Shared X defers the same offer without immediately reopening")
		screen._advance_expedition(1)
		check(state.expedition_simulation.state.position_nu != position_before, "Closing cards resumes the prior travel state")
		await click(screen.research_button)
		check(is_instance_valid(screen.research_dialog) and state.research_offer == offer, "Header reopens exact saved cards")
		dialog = screen.research_dialog
		var path: String = state.run_save_path
		state.run_save_path = "res://project.godot/blocked-native-choice.json"
		await click(dialog.buttons[offer[0]])
		check(not dialog.feedback.text.is_empty() and state.research_offer == offer, "Failed pointer choice retains cards and shows actionable save error")
		state.run_save_path = path
		await click(dialog.buttons[offer[0]])
		check(state.current_research_ids.has(offer[0]) and not is_instance_valid(screen.research_dialog),
			"Native Choose grants the selected upgrade and dismisses selection")
		check(screen.get_node_or_null("ResearchCompletion") == null,
			"Choosing research does not add a redundant completion banner")
		check(screen.research_status.text == "%d / 40 RP" % floori(state.research_points)
			and screen.research_progress.visible and screen.research_progress.max_value == 40,
			"Header advances to the next shared threshold with exact RP progress")
		check(screen.get_global_rect().encloses(screen.research_button.get_global_rect()),
			"Progress header remains visible after choosing")
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("user://research-after-choice-%d.png" % (4 if science else 3)) == OK,
			"Capture next-bar progress in the actual header")
		check(state.load_run_checkpoint() and state.current_research_ids.has(offer[0]), "Native choice survives Continue")
		screen.queue_free()
		await settle()

func native_saved_match() -> void:
	start(true)
	var fixture: Dictionary = state.hangar_snapshot()
	fixture.research.research_points = 20
	fixture.research.research_offer = ["laboratory_ii", "bastion_ii", "field_engineering", "civil_hospitality"]
	check(state._commit_hangar(fixture), "Save a four-card lab offer before refitting")
	var restore_ship := 0
	var restore_slot := ""
	var restore_key := ""
	for owned: HangarShip in state.fleet.duplicate():
		for slot: String in owned.mounts.keys():
			if owned.mounts[slot].equipment_id == "research_lab":
				restore_ship = owned.id
				restore_slot = slot
				restore_key = "research_lab@%d" % int(owned.mounts[slot].rank)
				check(state.swap_part(owned.id, slot, ""), "Defer a lab card and remove matching equipment")
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	await settle()
	screen.set_process(false)
	var dialog: Control = screen.research_dialog
	check(dialog.buttons.laboratory_ii.disabled and dialog.requirements.laboratory_ii.visible,
		"Reopened saved card is disabled with its matching-equipment requirement")
	var unchanged: Dictionary = state.hangar_snapshot()
	await click(dialog.buttons.laboratory_ii)
	check(SaveValidation.same(unchanged, state.hangar_snapshot()), "Clicking disabled native card spends nothing")
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		check(root.get_visible_rect().encloses(dialog.panel.get_global_rect())
			and dialog.cards.laboratory_ii.get_global_rect().encloses(dialog.requirements.laboratory_ii.get_global_rect()),
			"Matching requirement remains visibly inside four cards at " + str(resolution))
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("user://research-requirement-%d.png" % resolution.x) == OK, "Capture disabled matching card")
	check(state.swap_part(restore_ship, restore_slot, restore_key), "Restore operating lab while preserving saved offer")
	await settle()
	check(not dialog.buttons.laboratory_ii.disabled and not dialog.requirements.laboratory_ii.visible,
		"Restored equipment re-enables the same saved card")
	await click(dialog.buttons.laboratory_ii)
	check("laboratory_ii" in state.current_research_ids, "Pointer chooses restored research card")
	screen.queue_free()
	await settle()

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://research-choices.json"
	if DisplayServer.get_name() == "headless":
		mechanics()
	else:
		await native_ui()
		if "--choice-only" not in OS.get_cmdline_user_args():
			await native_saved_match()
	print("RESEARCH CHOICES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
