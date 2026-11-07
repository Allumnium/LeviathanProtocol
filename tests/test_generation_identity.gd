extends "res://tests/test_act1_content.gd"

func generation_checks() -> void:
	var graph := CampaignGraph.generate(3741, 2)
	check(not graph.is_empty() and CampaignGraph.errors(graph).is_empty(), "Stable graph generation preserves topology invariants")
	check(SaveValidation.same(graph, CampaignGraph.generate(3741, 2)), "Graph repeats exactly at the same seed")
	var content := CampaignContent.populate(graph, 3741)
	check(CampaignContent.valid(content) and SaveValidation.same(content, CampaignContent.populate(graph, 3741)), "Named content/environment streams repeat exactly")
	var reordered := graph.duplicate(true)
	reordered.nodes.reverse()
	var reordered_content := CampaignContent.populate(reordered, 3741)
	for node: Dictionary in content.nodes:
		var other: Dictionary = reordered_content.nodes.filter(func(candidate: Dictionary) -> bool: return candidate.id == node.id)[0]
		check(node == other, "Node content and environment do not depend on processing order: " + str(node.id))
	var plan := EncounterGenerator.generate(3741, "leviathan:stable_trial", 9, 1, "patrol", 5)
	check(EncounterGenerator.valid(plan) and plan.node_id == "leviathan:stable_trial", "Encounter accepts an explicit qualified instance ID")
	check(SaveValidation.same(plan, EncounterGenerator.generate(3741, "leviathan:stable_trial", 9, 1, "core:patrol", 5)), "Qualified and scoped template aliases use the same stream")
	var sparse := {"version": 1, "asteroid_density": 1, "solar_intensity": 1.0, "nebula": false}
	var dense := sparse.duplicate()
	dense.asteroid_density = 3
	var first := EncounterGenerator.generate(3741, "leviathan:stable_trial", 9, 1, "patrol", 5, false, sparse)
	var second := EncounterGenerator.generate(3741, "leviathan:stable_trial", 9, 1, "patrol", 5, false, dense)
	check(EncounterGenerator.valid(first) and EncounterGenerator.valid(second) and first.roster == second.roster and first.rewards == second.rewards, "Asteroid draw counts cannot perturb roster allocation or rewards")
	check(first.asteroids.roots.size() == 16 and second.asteroids.roots.size() == 48, "Each independent field keeps its requested density")
	check(SaveValidation.same(second, EncounterGenerator.generate(3741, "leviathan:stable_trial", 9, 1, "patrol", 5, false, dense)), "Dense field geometry and ore repeat exactly")
	var different := EncounterGenerator.generate(3741, "leviathan:another_trial", 9, 1, "patrol", 5)
	check(plan.seed != different.seed and plan.roster[0].entity_id != different.roster[0].entity_id, "Independent instance IDs separate battle seeds and entity identities")
	var progress := {"research_ids": ["foundation"], "research_offer": [], "research_points": 20.0, "story_flags": {}, "branch_choices": {}}
	HangarResearch.prepare_offer(progress, 3741, 3)
	var again := progress.duplicate(true)
	again.research_offer = []
	HangarResearch.prepare_offer(again, 3741, 3)
	check(progress.research_offer == again.research_offer and progress.research_offer.size() == 3, "Research offers repeat from the same earned-research scope")
	check(plan.seed == "8105533581428749320" and plan.roster.map(func(unit: Dictionary) -> String: return unit.definition_id)
		== ["core:fighter", "core:scout", "core:scout", "core:scout", "core:fighter", "core:scout", "core:scout", "core:scout", "core:fighter", "core:scout", "core:scout", "core:scout"], "Named encounter stream retains its reference seed and roster")
	check(progress.research_offer == ["civil_hospitality", "bastion_ii", "renewal_i"], "Named research stream retains its reference offer")

func actual_story_identity() -> void:
	check(state.start_new_run(1, 8302), "Start production story identity fixture")
	var event := Events.find(state.expedition_simulation.events, "first_contact")
	var effects: Dictionary = Events.option(event, "fight").effects
	var plan: Dictionary = state._expedition_encounter("first_contact", effects)
	check(plan.node_id == "leviathan:first_contact_fight" and EncounterGenerator.valid(plan), "Production story combat uses the authored encounter ID")
	state.expedition_simulation.events.reverse()
	state.expedition_simulation.events.push_front({"id": "unrelated_fixture"})
	check(SaveValidation.same(plan, state._expedition_encounter("first_contact", effects)), "Inserting/reordering unrelated events does not reroll a story battle")
	opening()
	choose("meridian_departure", "return")
	reach("first_contact")
	unaffordable_story()
	choose("first_contact", "fight")
	var frozen: Dictionary = state.pending_encounter.duplicate(true)
	check(state.load_run_checkpoint() and SaveValidation.same(frozen, state.pending_encounter) and state.battle_pending, "Continue preserves the committed explicit-ID encounter")
	check(state.battle_aliens.size() == EncounterGenerator.initial_fleet(frozen).size(), "Continue reconstructs the exact frozen first wave")

func unaffordable_story() -> void:
	var shipped := Content.db()
	var folder := "user://expensive/patches"
	DirAccess.make_dir_recursive_absolute(folder + "/defs")
	FileAccess.open(folder + "/pack.json", FileAccess.WRITE).store_string(JSON.stringify({
		"id": "expensive", "name": "Expensive required unit", "version": "1.0.0", "kind": "content",
		"depends": [{"id": "core", "version": ">=1.0"}]}))
	FileAccess.open(folder + "/defs/patch.json", FileAccess.WRITE).store_string(JSON.stringify({
		"def": "patch", "id": "price", "target_def": "enemy_unit", "target": "core:scout", "set": {"cost": 10000}}))
	var db := Content.load_all(["res://packs", "user://expensive"])
	check(db.problems.items.is_empty(), "A positive but unaffordable price is structurally valid")
	var before: Dictionary = state.hangar_snapshot()
	var bytes := FileAccess.get_file_as_bytes(state.run_save_path)
	check(not state.resolve_expedition_event("first_contact", "fight")
		and state.last_save_error.contains("cannot afford required") and state.last_save_error.contains("core:scout")
		and state.last_save_error.contains("points available"), "Actual story choice explains the unaffordable unit and budget: " + state.last_save_error)
	check(SaveValidation.same(before, state.hangar_snapshot()) and bytes == FileAccess.get_file_as_bytes(state.run_save_path), "Generation failure preserves pending choice, receipt, resources and save bytes")
	Content.set_database(shipped)

func loader_paths_and_errors() -> void:
	var shipped := PackLoader.new().load_packs(["res://packs"])
	var direct := PackLoader.new().load_packs(["res://packs/core", "res://packs/leviathan"])
	check(direct.problems.items.is_empty() and direct.content_hash == shipped.content_hash, "Direct pack folders load the same definitions as their container")
	var overlap := PackLoader.new().load_packs(["res://packs", "res://packs/core", ProjectSettings.globalize_path("res://packs/leviathan")])
	check(overlap.problems.items.is_empty() and overlap.content_hash == shipped.content_hash, "Overlapping direct/container roots do not load a pack twice")
	var folder := "user://identity_bad/patches/defs"
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open("user://identity_bad/patches/pack.json", FileAccess.WRITE).store_string(JSON.stringify({"id": "identity_bad", "name": "Bad encounter IDs", "version": "1.0.0", "kind": "content", "depends": [{"id": "leviathan", "version": ">=1.0"}]}))
	FileAccess.open(folder + "/ids.json", FileAccess.WRITE).store_string(JSON.stringify({"def": "patch", "id": "duplicate", "target_def": "event", "target": "leviathan:asteroid_corridor", "set": {"options[blast].effects.combat.id": "first_contact_fight"}}))
	var broken := PackLoader.new().load_packs(["res://packs", "user://identity_bad"])
	check(broken.has_pack("core") and broken.has_pack("leviathan") and not broken.has_pack("identity_bad") and broken.content_hash == shipped.content_hash, "Duplicate instance IDs disable the patch without damaging shipped content")
	check(broken.problems.errors().any(func(problem: Dictionary) -> bool: return problem.pack == "identity_bad" and problem.def == "duplicate" and problem.path.ends_with("combat.id")), "Duplicate-ID Problems identify the authored choice path and causal patch")

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://generation-identity.json"
	generation_checks()
	actual_story_identity()
	loader_paths_and_errors()
	print("GENERATION IDENTITY COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
