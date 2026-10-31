extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://research_focus/run.json"
	check(ScienceRules.journey_rp({"labs": []}, 3) == 1.5, "Baseline earns half RP per day without labs.")
	check(state.start_new_run(1, 42), "Start focus fixture.")
	check(state.commit_event("node_reward", "half-rp-fixture", 0, [0, 0, 0, 0], 0.5) and state.research_points == 0.5,
		"The public accounting path preserves fractional RP.")
	check(state.load_run_checkpoint() and state.research_points == 0.5 and state.commit_event("node_reward", "half-rp-fixture", 0, [0, 0, 0, 0], 0.5)
		and state.research_points == 0.5, "Half-RP ledger events reload and replay without truncation or duplicate payment.")
	var old: Dictionary = state.run_progress_snapshot()
	old.erase("research_focus")
	old.erase("research_progress")
	check(RunProgressData.validate(old).is_empty(), "Older saves default to no focus or partial projects.")
	var price := ResearchFocusRules.cost("laboratory_ii", state.run_progress_snapshot())
	var partial := price - 5
	state.research_points = partial
	check(state.set_research_focus("laboratory_ii"), "An eligible node can be focused before it is affordable.")
	check(state.research_focus == "laboratory_ii" and state.research_points == 0 and state.research_progress.get("laboratory_ii") == partial,
		"Existing banked RP funds partial progress immediately.")
	check(state.set_research_focus("applied_energy") and state.research_progress.get("laboratory_ii") == partial,
		"Changing focus preserves earlier partial work.")
	check(state.set_research_focus("laboratory_ii") and state.load_run_checkpoint() and state.research_progress.get("laboratory_ii") == partial,
		"Switching back and reloading retain focus and progress.")
	check(not state.set_research_focus("laboratory_iii") and not state.set_research_focus("foundation") and not state.set_research_focus("bad"),
		"Unknown, owned and prerequisite-gated nodes cannot be focused.")
	var forged: Dictionary = state.run_progress_snapshot()
	forged.research_progress.laboratory_ii = price
	check(not RunProgressData.validate(forged).is_empty(), "Completed progress must be converted into a real grant.")
	forged.research_progress.laboratory_ii = "bad"
	check(not RunProgressData.validate(forged).is_empty(), "Reject nonnumeric research progress.")
	var legacy: Dictionary = state.run_progress_snapshot()
	legacy.erase("research_pricing_version")
	legacy.research_progress = {"laboratory_ii": 35}
	check(RunProgressData.validate(legacy).is_empty() and ResearchFocusRules.cost("laboratory_ii", legacy) == 40,
		"Historical 35/40 projects remain valid at their original price.")
	check(state.restore_run_progress(legacy) and state.research_pricing_version == 0,
		"Loading old progress preserves historical research pricing.")
	check(state.save_run_checkpoint() and state.load_run_checkpoint() and state.research_pricing_version == 0
		and state.research_progress.get("laboratory_ii") == 35, "Historical pricing and partial work survive full checkpoint reload.")
	check(state.restore_run_progress(forged.merged({"research_progress": {"laboratory_ii": partial}}, true)),
		"Restore the new-run project after compatibility checks.")
	for bad in [-1, 2, 0.5, "1"]:
		var invalid: Dictionary = state.run_progress_snapshot()
		invalid["research_pricing_version"] = bad
		check(not RunProgressData.validate(invalid).is_empty(), "Reject malformed research pricing metadata.")
	state.credits = 100000
	var design := Ship.new()
	BUILTINS._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(design, ShipPart.Type.RESEARCH_LAB, Vector2i(2, 0))
	BUILTINS._add_part(design, ShipPart.Type.MINI_TURRET, Vector2i(0, 2))
	check(state.purchase_ship(design, "Research vessel"), "Players can mix a lab into a general design.")
	var science := ScienceRules.snapshot(state.get_deployed_fleet())
	check(ScienceRules.journey_rp(science, 1) == 1.5 and ScienceRules.journey_rp(science, 3) == 4.5 and ScienceRules.journey_rp(science, 0) == 0,
		"One lab plus baseline earns 1.5 RP per travel day.")
	var next: int = state.get_reachable_nodes(state.current_node_id)[0]
	var after_battle: float = partial + ScienceRules.journey_rp(science, state.research_travel_time(state.current_node_id, next))
	check(state.travel_to(next) and state.battle_pending, "First journey freezes a combat departure.")
	check(not state.set_research_focus("applied_energy"), "Research focus stays fixed during a pending deployment.")
	check(state.load_run_checkpoint(), "Pending research journey reloads.")
	for frame in range(12):
		await process_frame
	check(state.research_progress.get("laboratory_ii") == partial and state.research_points == 0,
		"Waiting during battle produces no RP.")
	check(state.cancel_battle() and state.research_progress.get("laboratory_ii") == partial, "Withdrawal does not complete travel or fund research.")
	check(state.travel_to(next), "Retry frozen encounter.")
	var blocker := FileAccess.open("user://research_focus/blocker", FileAccess.WRITE)
	blocker.store_string("file")
	blocker.close()
	var path: String = state.run_save_path
	state.run_save_path = "user://research_focus/blocker/run.json"
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	check(not state.complete_battle() and state.research_progress.get("laboratory_ii") == partial and state.battle_pending,
		"Failed reward save leaves RP, partial work and pending battle untouched.")
	Engine.print_error_messages = printed
	state.run_save_path = path
	check(state.complete_battle() and state.research_progress.get("laboratory_ii") == after_battle and state.research_points == 0,
		"Completed battle distance applies frozen productivity to focused research once.")
	check(state.load_run_checkpoint() and state.research_progress.get("laboratory_ii") == after_battle, "Partial journey progress is durable.")
	Engine.print_error_messages = false
	check(not state.complete_battle(), "An already completed battle cannot pay again.")
	Engine.print_error_messages = printed
	next = state.get_reachable_nodes(state.current_node_id)[0]
	check(state.campaign_node(next).kind not in ["combat", "boss"], "Next route is a quiet journey.")
	var overflow: float = after_battle + ScienceRules.journey_rp(science, state.research_travel_time(state.current_node_id, next)) - price
	state.run_save_path = "user://research_focus/blocker/run.json"
	Engine.print_error_messages = false
	check(not state.travel_to(next) and state.research_progress.get("laboratory_ii") == after_battle and state.research_points == 0
		and not state.current_research_ids.has("laboratory_ii"), "Failed quiet travel cannot award RP or complete research.")
	Engine.print_error_messages = printed
	state.run_save_path = path
	check(state.travel_to(next) and state.current_research_ids.has("laboratory_ii") and state.research_focus.is_empty()
		and state.research_points == overflow and not state.research_progress.has("laboratory_ii"),
		"Quiet travel counts distance too; completion unlocks the node and retains excess RP.")
	var ledger_size: int = state.transaction_ledger.size()
	check(state.load_run_checkpoint() and state.research_points == overflow, "Completion and overflow reload together.")
	if state.campaign_node(next).inhabited:
		check(state.dispatch_arrival() and state.transaction_ledger.size() == ledger_size and state.research_points == overflow,
			"Reopening an arrival cannot repeat research earnings.")
	check(not state.travel_to(next) and state.research_points == overflow, "The same completed journey cannot be paid twice.")
	state.run_save_path = "user://research_focus/blocker/run.json"
	Engine.print_error_messages = false
	check(not state.set_research_focus("applied_energy") and state.research_points == overflow and state.research_focus.is_empty(),
		"Failed focus save cannot consume banked points or change the active project.")
	Engine.print_error_messages = printed
	state.run_save_path = path
	check(state.set_research_focus("applied_energy") and state.research_progress.get("applied_energy") == overflow,
		"Banked overflow can fund the next explicitly chosen project.")
	check(state.start_new_run(1, 43) and state.research_focus.is_empty() and state.research_progress.is_empty(), "New runs reset focus and partial work.")
	print("Research focus/journey tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
