extends SceneTree

var state: Node
var checks := 0
var failures := 0
var changes := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)

func completion_hook(tx: RunTransaction, data: Dictionary) -> void:
	tx.doc.vars["last_research"] = data.research_id

func transactions() -> void:
	check(state.start_new_run(1, 7341), "Start actual research transaction fixture")
	var session: RunSession = state.run_session
	session.changed.connect(func(_sections: PackedStringArray) -> void: changes += 1)
	var before := session.snapshot()
	var durable := bytes(session.path)
	var tx := session.begin("research.failed_award")
	check(ResearchSystem.allocate(tx, session.content, 20.25, "fixture") and tx.doc.fleet.research.research_offer.size() == 3,
		"Allocation prepares a funded offer using document capabilities")
	tx.interrupt_after = "before_stage"
	check(not tx.commit() and SaveValidation.same(before, session.snapshot()) and bytes(session.path) == durable and changes == 0,
		"Failed award leaves points, offer, RNG, receipt, save and notifications unchanged")
	tx = session.begin("research.invalid_award")
	check(not ResearchSystem.allocate(tx, session.content, NAN) and not ResearchSystem.allocate(tx, session.content, 20)
		and not tx.commit(), "Invalid awards poison the transaction without consuming a later award")
	tx = session.begin("research.award")
	var replay := session.begin("research.award_replay")
	check(ResearchSystem.allocate(tx, session.content, 100.25, "fixture") and tx.commit() and changes == 1,
		"Funded award commits exactly once")
	var expected := session.snapshot()
	check(expected.chronicle.back().type == "research.offer_prepared" and expected.fleet.research.research_points == 100.25,
		"Prepared offer and fractional bank share the durable receipt")
	check(ResearchSystem.allocate(replay, session.content, 100.25, "fixture")
		and SaveValidation.same(RunDocument.normalized(replay.doc), expected) and not replay.commit(),
		"Same award reproduces offer/receipt/RNG exactly and stale generation cannot commit")
	check(state.load_run_checkpoint() and state.research_points == 100.25, "Continue exposes the committed research bank")
	session = state.run_session
	check(session.hooks.register("research.completed", "research.test", completion_hook), "Register transaction-local completion hook")
	var id: String = state.research_offer[0]
	tx = session.begin("research.failed_choice")
	before = session.snapshot()
	durable = bytes(session.path)
	check(ResearchSystem.choose(tx, session.content, id), "Stage actual offered choice and overflow")
	tx.interrupt_after = "before_stage"
	check(not tx.commit() and SaveValidation.same(before, session.snapshot()) and bytes(session.path) == durable,
		"Failed choice rolls back debit, grants, branch, next offer, chronicle and hook changes")
	tx = session.begin("research.choice")
	replay = session.begin("research.choice_replay")
	check(ResearchSystem.choose(tx, session.content, id) and tx.commit(), "Commit actual offered choice")
	expected = session.snapshot()
	check(expected.fleet.research.research_ids.has(id) and expected.fleet.research.research_points == 80.25
		and not expected.fleet.research.research_offer.is_empty() and expected.vars.last_research == id,
		"One completion consumes one threshold, derives grants and queues an excess-RP offer")
	check(ResearchSystem.choose(replay, session.content, id), "Replay choice against original private proposal")
	check(session.hooks.drain(replay) and SaveValidation.same(RunDocument.normalized(replay.doc), expected),
		"Choice and deterministic engine hook replay to identical document")
	check(not replay.commit(), "Stale replay cannot repeat completion")
	check(state.load_run_checkpoint() and state.current_research_ids.has(id), "Continue retains chosen upgrade and overflow offer")
	tx = state.run_session.begin("research.duplicate")
	check(not ResearchSystem.choose(tx, state.run_session.content, id) and not tx.commit(), "Repeated choice cannot grant an already-completed upgrade")

func facts() -> void:
	check(state.start_new_run(1, 7341, true, "flagship_science") and state.refit_ship(1, "observatory"),
		"Fit real M and XL labs on the science flagship")
	var doc: Dictionary = state.run_session.snapshot()
	var content: DefDatabase = state.run_session.content
	var view := FactView.new(doc, content)
	check(view.research_option_count() == 4 and is_equal_approx(view.research_production_rate(), 5.0)
		and is_equal_approx(view.research_production_rate(), ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet()))),
		"Document facts match existing M/XL ranks, chassis multiplier and card bonus")
	for node: Dictionary in HangarResearch.catalog(content):
		check(view.matches_research(node.id) == ResearchUpgrades.matches(node.id, state.get_deployed_fleet(), content),
			"Document capability matching agrees for " + str(node.id))
	doc.fleet.ships[0].hull_hp = 0.0
	check(FactView.new(doc, content).research_production_rate() == 5.0, "Zero hull lab remains operational")
	doc.fleet.ships[0].hull_hp = -0.001
	check(FactView.new(doc, content).research_production_rate() == 0.0
		and FactView.new(doc, content).research_option_count() == 3, "Destroyed lab host supplies neither output nor flagship card bonus")
	var tx: RunTransaction = state.run_session.begin("research.missing_lab")
	tx.doc.fleet.research.research_points = 20.0
	tx.doc.fleet.research.research_offer = ["laboratory_ii"]
	for entry: Dictionary in tx.doc.fleet.ships:
		for slot: String in entry.mounts.keys():
			var item: Dictionary = tx.doc.fleet.equipment[entry.mounts[slot]]
			if item.equipment_id == "research_lab":
				entry.mounts.erase(slot)
	check(not ResearchSystem.choose(tx, content, "laboratory_ii") and tx.error == "Deploy a research lab." and not tx.commit(),
		"Choice checks private document equipment rather than the still-fitted live projection")

func frozen_context() -> void:
	var base := Content.installed()
	Content.load_all(["res://packs", "res://tests/fixtures/content/research_patch"])
	check(state.start_new_run(1, 7341), "Create run with custom family/gate/research tuning")
	var session: RunSession = state.run_session
	Content.bind_run(base)
	var tx := session.begin("research.frozen_context")
	tx.doc.fleet.research.story_flags["field_trial"] = true
	check(ResearchSystem.allocate(tx, session.content, 12.5, "fixture") and tx.doc.fleet.research.research_offer.size() == 2
		and "applied_energy" in tx.doc.fleet.research.research_offer, "Owner context controls threshold, matching and custom gate despite foreign global rules")
	check(ResearchSystem.choose(tx, session.content, "core:applied_energy")
		and tx.doc.fleet.research.branch_choices.get("research_tuning_test:fieldcraft") == "practical"
		and tx.doc.fleet.research.research_points == 0.5, "Qualified choice resolves custom family and debits the owner's price")
	var grants := FactView.new(tx.doc, session.content).research_grants()
	check(grants.equipment_ids.has("tactical_computer") and is_equal_approx(grants.modifiers.laser_damage_multiplier.value, 1.35),
		"Owner context derives custom physical grants and modifiers")
	check(HangarResearch.valid(tx.doc.fleet.research, session.content)
		and ResearchRules.validate_registry(GameDefinitions.snapshot(session.content), session.content).is_empty(),
		"Semantic research/registry validation stays in the same explicit family/gate context")
	check(not tx.commit(), "Foreign active run rejects publication without rebinding")
	Content.bind_run(session.content)

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://run-research.json"
	Content.load_all(["res://packs"])
	transactions()
	facts()
	frozen_context()
	print("RUN RESEARCH COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
