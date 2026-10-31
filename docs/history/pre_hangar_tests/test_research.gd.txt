extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _node(registry: Dictionary, id: String) -> Dictionary:
	for node: Dictionary in registry.research:
		if node.id == id:
			return node
	return {}

func _reject(edit: Callable, message: String) -> void:
	var registry := GameDefinitions.snapshot()
	edit.call(registry)
	_check(not GameDefinitions.validate(registry).is_empty(), message)

func _run() -> void:
	var registry := GameDefinitions.snapshot()
	_check(GameDefinitions.validate(registry).is_empty() and registry.research.size() == 46, "Complete section 7 registry contains Foundation plus 45 purchasable definitions.")
	var all_ids: Array[String] = []
	for node: Dictionary in registry.research:
		all_ids.append(node.id)
	var all := ResearchRules.resolve(all_ids)
	_check(all.equipment_ids.size() == 56 and all.ability_ids.size() == 20 and all.ranks.research_lab == 3, "All planned grants cover 56 equipment types, 20 abilities and the three lab ranks.")
	var energy := ResearchRules.resolve(["foundation", "applied_energy"])
	_check(energy.equipment_ids.has("laser") and energy.equipment_ids.has("double_laser"), "One Applied Energy source grants both lasers.")
	var concept := ResearchRules.resolve(["energy_manipulation"])
	_check(concept.equipment_ids.is_empty() and concept.modifiers.energy_efficiency.value == 0.1
		and concept.modifiers.energy_efficiency.targets == ["beam", "shield"], "Energy Manipulation grants its concept modifier without inventing an equipment item.")
	_check(concept.modifiers.energy_efficiency.ordinary_efficiency_cap == 0.3, "Concept records the ordinary +30% efficiency cap.")
	var same := ResearchRules.resolve(["energy_manipulation", "energy_manipulation"])
	_check(same == concept, "Repeated grant source cannot multiply efficiency.")
	var extraction := ResearchRules.resolve(["foundation", "mineral_spectroscopy", "basic_extraction", "deep_extraction", "freight_engineering"])
	_check(extraction.modifiers.extractable_materials.values == ["civic", "defense", "offense", "tech"], "Deep extraction extends material permissions instead of replacing the earlier pair.")
	_check(extraction.modifiers.scan_spectroscopy.value == true and extraction.modifiers.cargo_hold_capacity.value == 15
		and extraction.modifiers.cargo_hold_capacity.refill_existing == false, "Boolean and capacity concepts preserve their semantics without granting cargo.")
	var reverse_ids: Array = ["deep_extraction", "basic_extraction", "mineral_spectroscopy", "foundation", "freight_engineering"]
	_check(ResearchRules.resolve(reverse_ids) == extraction, "Grant resolution is independent of acquisition-list order.")
	var unknown := ResearchRules.resolve(["foundation", "not_a_node"])
	_check(not unknown.error.is_empty() and unknown.equipment_ids.is_empty(), "Unknown grant sources fail closed without partial permissions.")
	energy.equipment_ids.clear()
	concept.modifiers.energy_efficiency.value = 99
	_check(ResearchRules.resolve(["applied_energy"]).equipment_ids.size() == 2
		and ResearchRules.resolve(["energy_manipulation"]).modifiers.energy_efficiency.value == 0.1, "Resolved grants cannot mutate shared content.")

	var needed := ResearchRules.requirements("quantum_observation", ["foundation", "analysis_methods"], {"boss_ii_defeated": true})
	_check(needed.missing_prerequisites == ["laboratory_iii"] and needed.missing_story_gates.is_empty(), "Multiple prerequisites use AND, with separate story gates.")
	needed = ResearchRules.requirements("laboratory_iii", ["foundation", "laboratory_ii"])
	_check(needed.missing_prerequisites.is_empty() and needed.missing_story_gates == ["boss_i_defeated"], "Lab III retains its first-boss gate.")
	needed = ResearchRules.requirements("disruption_iii", ["foundation", "applied_energy", "optics_i"], {}, {"energy": "optics"})
	_check(needed.conflicts == ["optics_i"] and needed.branch_conflict, "First family commitment excludes downstream opposite tiers.")
	needed = ResearchRules.requirements("renewal_i", ["foundation", "field_engineering", "optics_i"], {}, {"energy": "optics"})
	_check(needed.conflicts.is_empty() and not needed.branch_conflict, "Commitment in one family leaves other families independent.")
	needed = ResearchRules.requirements("civil_hospitality", ["foundation", "optics_i"], {}, {"energy": "optics"})
	_check(needed.conflicts.is_empty() and not needed.branch_conflict, "Economic/shared research stays nonexclusive.")
	_check(not ResearchRules.requirements("unknown", []).known, "Unknown research has an explicit unknown status.")
	var accessible := 0
	var commitments := {"energy": "optics", "survival": "bastion", "force_projection": "siege", "fleet_operations": "command"}
	for node: Dictionary in registry.research:
		if node.id != "foundation" and (node.family_id.is_empty() or commitments[node.family_id] == node.path_id):
			accessible += 1
	_check(accessible == 33, "Four independent family commitments leave 33 purchasable definitions accessible.")

	_reject(func(r: Dictionary) -> void: _node(r, "applied_energy").grants.equipment_ids.append("laser"), "Reject duplicate equipment grants.")
	_reject(func(r: Dictionary) -> void: _node(r, "foundation").grants.ability_ids.append("scan"), "Reject duplicate ability grants.")
	_reject(func(r: Dictionary) -> void: _node(r, "applied_energy").prerequisite_ids = ["energy_manipulation"], "Reject cyclic prerequisites.")
	_reject(func(r: Dictionary) -> void: _node(r, "laboratory_iii").grants.ranks[0].rank = 4, "Reject a nonexistent physical rank.")
	_reject(func(r: Dictionary) -> void: _node(r, "laboratory_iii").prerequisite_ids = ["foundation"], "Reject skipping the prior physical rank.")
	_reject(func(r: Dictionary) -> void: _node(r, "laboratory_ii").grants.ranks.append({"equipment_id": "research_lab", "rank": 2}), "Reject duplicate rank grants.")
	_reject(func(r: Dictionary) -> void: _node(r, "laboratory_iii").story_gate_ids = ["boss_typo"], "Reject misspelled story gates.")
	_reject(func(r: Dictionary) -> void: _node(r, "optics_i").exclusion_ids.erase("disruption_iii"), "Reject incomplete or asymmetric opposite-path exclusions.")
	_reject(func(r: Dictionary) -> void: _node(r, "optics_i").path_id = "typo", "Reject unknown family paths.")
	_reject(func(r: Dictionary) -> void: _node(r, "industrial_integration").prerequisite_ids = ["bastion_i", "renewal_i"], "Reject mutually exclusive prerequisites.")
	_reject(func(r: Dictionary) -> void: _node(r, "applied_energy").cost_rp = INF, "Reject nonfinite research costs.")
	_reject(func(r: Dictionary) -> void: _node(r, "applied_energy").grants.equipment_ids.clear(), "Reject empty research nodes.")
	_reject(func(r: Dictionary) -> void: _node(r, "applied_energy").grants.equipment_ids.erase("double_laser"), "Reject equipment missing a grant source.")
	_reject(func(r: Dictionary) -> void: _node(r, "foundation").grants.ability_ids.clear(), "Reject abilities missing a grant source.")
	_reject(func(r: Dictionary) -> void: _node(r, "optics_i").grants.ability_ids.append("forecast"), "Reject an ability lacking its equipment source.")
	_reject(func(r: Dictionary) -> void: _node(r, "energy_manipulation").grants.modifiers[0].value = true, "Reject boolean efficiency values.")
	_reject(func(r: Dictionary) -> void: _node(r, "energy_manipulation").grants.modifiers[0].id = "energy_typo", "Reject unknown concept modifiers.")
	_reject(func(r: Dictionary) -> void: _node(r, "energy_manipulation").grants.modifiers[0].targets = ["beam", "beam"], "Reject duplicate modifier targets.")
	_reject(func(r: Dictionary) -> void: _node(r, "freight_engineering").grants.modifiers[0].refill_existing = true, "Freight capacity research cannot create existing loads.")
	_reject(func(r: Dictionary) -> void: _node(r, "basic_extraction").grants.modifiers[0].values = ["unknown_material"], "Reject unknown extraction materials.")
	_reject(func(r: Dictionary) -> void: _node(r, "foundation").story_gate_ids = ["boss_i_defeated"], "Foundation cannot require a later story event.")

	var state := root.get_node("GameState")
	state.run_save_path = "user://research/run.json"
	_check(state.start_new_run(1, 42), "Start isolated grant fixture.")
	_check(not state.is_equipment_available(ShipPart.Type.LASER), "New run grants only implemented Foundation equipment.")
	state.current_research_ids.append("applied_energy")
	state.current_research_ids.append("energy_manipulation")
	_check(state.is_equipment_available(ShipPart.Type.LASER) and state.is_equipment_available(ShipPart.Type.DOUBLE_LASER)
		and state.research_grants().modifiers.energy_efficiency.value == 0.1, "GameState exposes grouped and concept grants through one resolver.")
	_check(state.save_run_checkpoint() and state.load_run_checkpoint() and state.research_grants().modifiers.energy_efficiency.value == 0.1,
		"Grants recompute from persisted research IDs without a second mutable unlock ledger.")
	_check(state.is_equipment_available(ShipPart.Type.RESEARCH_LAB) and state.is_equipment_available(ShipPart.Type.CREW_QUARTERS)
		and GameDefinitions.entries("research", true).size() == 18, "Only functional shared, mining and intermediate Energy/Survival research is ready for purchase.")
	_check(state.start_new_run(1, 42) and not state.research_grants().equipment_ids.has("laser") and state.research_grants().modifiers.is_empty(), "New runs reset resolved grants.")
	print("Research definition tests finished: %d failures; 46 nodes; 56 equipment; 20 abilities" % failures)
	quit(0 if failures == 0 else 1)
