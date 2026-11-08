extends SceneTree

var state: Node
var checks := 0
var failures := 0
var changes := 0
var order: Array[String] = []
var base: DefDatabase

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func content_roundtrip() -> void:
	base = Content.load_all(["res://packs"])
	var snapshot := RunContent.capture(base)
	var restored := RunContent.restore(JSON.parse_string(JSON.stringify(snapshot)))
	check(restored.has("database"), "Frozen resolved content survives JSON: " + str(restored.get("error", "")))
	if not restored.has("database"):
		return
	check(restored.database.content_hash == base.content_hash and restored.database.get_def("equipment", "core:laser") == base.get_def("equipment", "core:laser"), "Frozen content retains hash and effective definitions")
	var broken := snapshot.duplicate(true)
	broken.records[0].data["tampered"] = true
	check(RunContent.restore(broken).has("error"), "Frozen content rejects checksum damage")
	broken = snapshot.duplicate(true)
	broken.content_hash = "0000000000000000"
	broken.sha256 = RunContent.digest(broken)
	check(RunContent.restore(broken).has("error"), "Resolved definition hash is independently verified")
	broken = snapshot.duplicate(true)
	broken.records.append(broken.records[0])
	broken.sha256 = RunContent.digest(broken)
	check(RunContent.restore(broken).has("error"), "Duplicate frozen identities fail closed")
	ExprContexts.register("fixture", {"credits": "number", "danger": "number", "flag": "bool"})
	var fixtures := PackLoader.new().load_packs(["res://tests/fixtures/content/good"], ["res://tests/fixtures/content/schemas"])
	var formulas := RunContent.restore(JSON.parse_string(JSON.stringify(RunContent.capture(fixtures))))
	check(formulas.has("database") and formulas.database.formula("widget", "base:scout", "weight").number({"credits": 500}) == 6,
		"Frozen schemas rebuild formula evaluators without source definitions")
	check(formulas.has("database") and formulas.database.formula("widget", "base:brick", "weight").number() == 2,
		"Frozen abstract inheritance and literal expressions preserve their effective values")
	ExprContexts.unregister("fixture")

func starts_and_trade() -> void:
	state.run_save_path = ""
	check(state.start_new_run(1, 3741), "Actual New Run publishes its document and content")
	if state.run_session == null:
		return
	var path: String = state.run_save_path
	check(path == RunRepository.run_path(state.run_id) and FileAccess.file_exists(path.get_base_dir() + "/content.json"), "Production run uses its own directory")
	var doc: Dictionary = state.run_session.snapshot()
	check(RunDocument.valid(doc) and doc.meta.seed == "3741" and not doc.has("format")
		and doc.fleet.ships.size() == 13 and doc.fleet.equipment.size() == state.equipment_inventory.size(), "Sectioned document holds the real fleet and references")
	check(SaveValidation.same(RunDocument.to_hangar(doc), state.hangar_snapshot()), "Temporary adapter loses no live gameplay state")
	var repo := RunRepository.new()
	check(repo.list_runs().any(func(entry: Dictionary) -> bool: return entry.id == state.run_id), "Published run is discoverable")
	var original_content := bytes(path.get_base_dir() + "/content.json")
	state.run_session.changed.connect(func(_sections: PackedStringArray) -> void: changes += 1)
	check(state.buy_missiles() and state.credits == 650 and state.missiles == 40 and changes == 1, "Actual ammunition command commits once through TradeSystem")
	doc = state.run_session.snapshot()
	check(doc.chronicle.size() == 1 and doc.chronicle[0].data.count == 10
		and doc.chronicle[0].data.credits == 50, "Successful trade records its committed chronicle entry")
	var before: Dictionary = state.hangar_snapshot()
	var previous_doc: Dictionary = state.run_session.snapshot()
	var previous_bytes := bytes(path)
	state.run_save_path = "res://project.godot/blocked-run.json"
	check(not state.buy_missiles() and not state.last_save_error.is_empty(), "A failed transaction surfaces its storage error")
	check(SaveValidation.same(before, state.hangar_snapshot()) and SaveValidation.same(previous_doc, state.run_session.snapshot())
		and bytes(path) == previous_bytes and changes == 1 and state.run_session.path == path, "Failed trade preserves live state, document, RNG, chronicle, save and notifications")
	check(not state.start_new_run(1, 61) and SaveValidation.same(before, state.hangar_snapshot())
		and bytes(path) == previous_bytes, "Failed new-run publication restores the previous live run and its file")
	state.run_save_path = path
	check(state.load_run_checkpoint() and SaveValidation.same(before, state.hangar_snapshot()), "Production Continue restores the new document")
	check(state.run_session.snapshot().fleet.credits is int and state.run_session.snapshot().meta.version is int
		and state.run_session.snapshot().fleet.ships[0].id is int and state.run_session.snapshot().fleet.squadrons[0].id is int,
		"Schema normalization restores declared whole numbers without changing string seeds")
	check(bytes(path.get_base_dir() + "/content.json") == original_content, "Trades and Continue never rewrite immutable content")
	var orphan := RunRepository.ROOT + "/" + "f".repeat(32)
	DirAccess.make_dir_recursive_absolute(orphan)
	FileAccess.open(orphan + "/content.json", FileAccess.WRITE).store_string("incomplete")
	check(not repo.list_runs().any(func(entry: Dictionary) -> bool: return entry.id == "f".repeat(32)), "Orphan content is absent from the run list")

func transaction_failures() -> void:
	var session: RunSession = state.run_session
	var before := session.snapshot()
	var durable := bytes(session.path)
	var tx := session.begin("probe.failed_rng")
	tx.rng("probe", "roll").next_u32()
	tx.doc.fleet.credits -= 3
	tx.interrupt_after = "before_stage"
	check(not tx.commit() and SaveValidation.same(before, session.snapshot()) and durable == bytes(session.path), "Pre-stage failure rolls back resources and random counters")
	check(not tx.commit(), "Closed transactions cannot commit twice")
	tx = session.begin("probe.invalid")
	tx.doc.fleet.equipment["1"]["hp"] = 4
	check(not tx.commit() and SaveValidation.same(before, session.snapshot()), "New transaction path retains physical equipment invariants")
	tx = session.begin("probe.identity")
	tx.doc.meta.content_hash = "0000000000000000"
	check(not tx.commit() and durable == bytes(session.path), "Transactions cannot replace their run identity/content")
	check(session.accepts(before), "Warm exact validated-payload cache")
	tx = session.begin("probe.float_precision")
	tx.doc.fleet.ships[0].hull_hp += 0.000000001
	check(not tx.commit(), "Full-precision cache key cannot admit a distinct invalid hull value")
	var stale := session.begin("probe.stale")
	tx = session.begin("probe.staged")
	tx.doc.vars.dictionary_dot_key = &"saved text"
	var roll := tx.rng("probe", "roll").next_u32()
	tx.doc.fleet.credits -= 3
	tx.interrupt_after = "after_stage"
	check(tx.commit() and FileAccess.file_exists(session.path + ".next"), "Verified staged state is a durable successful commit")
	check(SaveValidation.json_value(session.snapshot()) and session.snapshot().vars.dictionary_dot_key == "saved text",
		"Transaction boundary normalizes StringName keys/text added by GDScript dictionary assignments")
	var committed := session.snapshot()
	tx.doc.fleet.credits = 0
	check(SaveValidation.same(committed, session.snapshot()), "A committed transaction cannot mutate the session through a retained alias")
	check(not stale.commit(), "Stale transactions cannot overwrite a later generation")
	check(state.load_run_checkpoint() and state.credits == committed.fleet.credits
		and SaveValidation.same(committed, state.run_session.snapshot()), "Continue selects the latest staged generation and its RNG counters")
	var same := RngStreams.new()
	same.restore(before.rng)
	check(same.rng("probe", "roll").next_u32() == roll, "The failed RNG transaction consumed no durable draw")
	check(state.buy_missiles() and not FileAccess.file_exists(state.run_save_path + ".next"), "Next real command recovers staged state before committing")
	session = state.run_session
	var external := AtomicRunStore.new().commit(session.path, session.snapshot(), session.accepts, session.generation)
	check(external.ok, "Simulate another writer committing the same run")
	durable = bytes(session.path)
	tx = session.begin("probe.external_stale")
	tx.doc.fleet.credits -= 1
	check(not tx.commit() and tx.error.contains("changed") and durable == bytes(session.path), "On-disk generation guard rejects stale writes from another session")
	check(state.load_run_checkpoint(), "Continue reloads the external generation")

func hooks() -> void:
	var session: RunSession = state.run_session
	check(session.hooks.register("probe", "later", func(tx, _data: Dictionary) -> void:
		order.append("later")
		tx.emit_hook("child"), 5), "Register an engine hook")
	check(session.hooks.register("probe", "first", func(_tx, _data: Dictionary) -> void: order.append("first")), "Register a higher-priority hook")
	session.hooks.register("child", "child", func(_tx, _data: Dictionary) -> void: order.append("child"))
	var tx := session.begin("probe.hooks")
	tx.emit_hook("probe")
	check(tx.commit() and order == ["first", "later", "child"], "Hook delivery has stable priority/ID ordering and FIFO cascades")
	session.hooks.register("loop", "again", func(next, _data: Dictionary) -> void: next.emit_hook("loop"))
	var before := session.snapshot()
	var durable := bytes(session.path)
	tx = session.begin("probe.cascade")
	tx.doc.fleet.credits -= 10
	tx.emit_hook("loop")
	check(not tx.commit() and tx.error.contains("64") and SaveValidation.same(before, session.snapshot())
		and durable == bytes(session.path), "Hook cascade limit cancels the entire transaction before any durable change")
	session.hooks.register("identity", "invalid", func(next, _data: Dictionary) -> void: next.doc.meta.scenario = "fixture:changed")
	tx = session.begin("probe.hook_identity")
	tx.emit_hook("identity")
	check(not tx.commit() and tx.error.contains("identity") and durable == bytes(session.path), "Hooks cannot bypass immutable run metadata")
	check(state.load_run_checkpoint(), "Resynchronize the facade after direct transaction checks")

func installed_changes() -> void:
	var first_path: String = state.run_save_path
	var first: Dictionary = state.hangar_snapshot()
	var first_bytes := bytes(first_path)
	var first_content: DefDatabase = state.run_session.content
	var patched := Content.load_all(["res://packs", "res://tests/fixtures/content/p2"])
	check(patched.content_hash != first_content.content_hash and Content.db() == first_content
		and state.missile_quote().price == 50, "Installed pack reload cannot rebind active prices or catalog caches")
	state.run_save_path = "res://project.godot/updated-start-failure.json"
	check(not state.start_new_run(1, 3741) and Content.db() == first_content
		and SaveValidation.same(first, state.hangar_snapshot()) and bytes(first_path) == first_bytes,
		"Failed start with updated rules restores the old run's definitions, fleet and durable state")
	state.run_save_path = first_path
	check(state.start_new_run(1, 3741) and state.missile_quote().price == 17 and state.fleet.size() == 5, "New Run uses installed updates and freezes its own rules")
	var second_path: String = state.run_save_path
	var second: Dictionary = state.hangar_snapshot()
	check(first_path != second_path and bytes(first_path) == first_bytes, "New Run preserves the earlier run file")
	state.run_save_path = first_path
	check(state.load_run_checkpoint() and SaveValidation.same(first, state.hangar_snapshot()) and state.missile_quote().price == 50, "Switching to the first run restores its original content and state")
	state.run_save_path = second_path
	check(state.load_run_checkpoint() and SaveValidation.same(second, state.hangar_snapshot()) and state.missile_quote().price == 17, "Switching back restores updated rules and scoped catalog caches")
	var target := RunRepository.content_path(second_path, state.run_id)
	var good_content := bytes(target)
	FileAccess.open(target, FileAccess.WRITE).store_string("corrupt")
	var before: Dictionary = state.run_session.snapshot()
	var bound := Content.run_database()
	check(not state.buy_missiles() and SaveValidation.same(second, state.hangar_snapshot()), "A transaction cannot publish state against damaged frozen content")
	check(not state.load_run_checkpoint() and Content.run_database() == bound
		and SaveValidation.same(before, state.run_session.snapshot()) and SaveValidation.same(second, state.hangar_snapshot()), "Failed frozen-content load preserves the previous live run and binding")
	FileAccess.open(target, FileAccess.WRITE).store_buffer(good_content)
	Content.load_all(["user://no_installed_packs"])
	check(state.load_run_checkpoint() and SaveValidation.same(second, state.hangar_snapshot())
		and state.missile_quote().price == 17, "Cold Continue reconstructs frozen definitions without installed pack sources")
	Content.set_database(base)

func replay() -> void:
	var original := Content.run_database()
	var content: DefDatabase = state.run_session.content
	Content.bind_run(content)
	var initial: Dictionary = state.run_session.snapshot()
	initial.meta.id = "a".repeat(32)
	var results: Array[Dictionary] = []
	for index in 2:
		var repo := RunRepository.new()
		var path := "user://replay-%d.json" % index
		var session := repo.create(path, initial, state.run_session.frozen, content)
		check(session != null, "Create deterministic replay fixture")
		for command in 3:
			var tx := session.begin("trade.ammunition")
			check(TradeSystem.buy_ammunition(tx, content) and tx.commit(), "Replay actual trade command")
			if command == 0:
				var loaded := repo.load_run(path)
				check(loaded != null, "Replay survives a process-boundary reload")
				session = loaded
				content = session.content
				Content.bind_run(content)
			var draw := session.begin("probe.roll")
			draw.doc.vars["roll_%d" % command] = draw.rng("replay.roll", "example").randi_range(1, 1000)
			check(draw.commit(), "Persist replay RNG counter and outcome together")
		results.append(session.snapshot())
	check(SaveValidation.same(results[0], results[1]), "Same initial identity, seed and commands produce identical documents across reloads")
	Content.bind_run(original)

func removed_art() -> void:
	var folder := "user://temporary_pack/gone"
	DirAccess.make_dir_recursive_absolute(folder + "/defs")
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.CYAN)
	check(image.save_png(folder + "/ship.png") == OK, "Create isolated removable pack art")
	FileAccess.open(folder + "/pack.json", FileAccess.WRITE).store_string(JSON.stringify({
		"id": "gone", "name": "Removable art fixture", "kind": "content", "version": "1.0.0", "depends": [{"id": "core", "version": ">=1.0"}]}))
	FileAccess.open(folder + "/defs/patch.json", FileAccess.WRITE).store_string(JSON.stringify({"defs": [
		{"def": "patch", "id": "drone_art", "target_def": "chassis", "target": "core:drone", "set": {"art": "gone:ship.png"}},
		{"def": "patch", "id": "enemy_art", "target_def": "enemy_unit", "target": "core:scout", "set": {"art": "gone:ship.png", "tier_art": "gone:ship.png"}},
		{"def": "patch", "id": "laser_art", "target_def": "equipment", "target": "core:laser", "set": {"art": "gone:ship.png"}}
	]}))
	var loaded := Content.load_all(["res://packs", "user://temporary_pack"])
	check(loaded.problems.items.is_empty() and state.start_new_run(1, 3741), "Run freezes rules with pack-relative art")
	var before: Dictionary = state.hangar_snapshot()
	DirAccess.remove_absolute(folder + "/ship.png")
	DirAccess.remove_absolute(folder + "/defs/patch.json")
	DirAccess.remove_absolute(folder + "/pack.json")
	Content.load_all(["user://no_installed_packs"])
	check(state.load_run_checkpoint() and SaveValidation.same(before, state.hangar_snapshot()), "Continue restores fleet after its source pack and image are removed")
	var placeholder := preload("res://scripts/placeholders.gd").art()
	check(state.fleet[3].art_texture == placeholder and SlotCatalog.equipment_texture(SlotCatalog.find_equipment("laser")) == placeholder,
		"Missing chassis/equipment art uses the existing visible marker")
	var enemy := AlienShip.threat_variant("scout", 1)
	check(enemy.texture == placeholder and AlienShip.from_snapshot(enemy.to_snapshot()) != null,
		"Missing enemy/tier art preserves actual stats and frozen snapshot reconstruction")
	Content.set_database(base)

func run() -> void:
	state = root.get_node("GameState")
	content_roundtrip()
	if failures == 0:
		starts_and_trade()
		if state.run_session != null:
			transaction_failures()
			hooks()
			installed_changes()
			replay()
			removed_art()
	print("RUN CORE COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
