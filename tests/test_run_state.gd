extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _laser_blueprint() -> Ship:
	var ship := Ship.new()
	for spec in [[ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO],
		[ShipPart.Type.LASER, Vector2i(2, 0)], [ShipPart.Type.THRUSTER, Vector2i(2, 1)]]:
		for pattern in ShipPartPattern.get_catalog():
			if pattern.part_type != spec[0]:
				continue
			for index in range(pattern.cell_offsets.size()):
				ship.set_tile_at(spec[1] + pattern.cell_offsets[index], pattern.tile_categories[index])
			ship.add_part(ShipPart.new(pattern.part_type, pattern.category, spec[1],
				pattern.cell_offsets, pattern.stats, pattern.hidden_tile_offsets))
	return ship


func _run() -> void:
	var state := root.get_node("GameState")
	state.archive_progress_file_path = "user://run_state_archive_test.json"
	state.saved_ship_designs.clear()
	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 12345, false), "Start a seeded run.")
	var initial_nodes: Array = state.NODE_POSITIONS.duplicate()
	var initial_edges: Array = state.GRAPH_EDGES.duplicate()
	var blueprint := _laser_blueprint()
	state.ship = blueprint
	_check(state.save_current_ship_design("Archived Laser", "user://run_state_blueprints_test.json").is_empty(),
		"A locked design can still be saved as knowledge.")
	state.discover_part(ShipPart.Type.LASER)
	var archived_file := FileAccess.get_file_as_string(state.archive_progress_file_path)
	var designs: Array = state.get_saved_ship_designs()
	_check(state.has_discovered_part(ShipPart.Type.LASER), "Archive remembers discovered laser.")
	_check(not state.is_equipment_available(ShipPart.Type.LASER), "Archive knowledge must not authorize construction.")
	var before: Dictionary = state.run_progress_snapshot()
	var fleet_size: int = state.fleet.size()
	var inventory: Array = [state.red_tiles_available, state.blue_tiles_available, state.green_tiles_available, state.core_tiles_available]
	_check(not state.purchase_saved_ship("Archived Laser"), "Archived locked equipment must not construct.")
	_check(not state.purchase_ship(blueprint), "Direct construction must use current-run authorization.")
	_check(state.run_progress_snapshot() == before and state.fleet.size() == fleet_size,
		"Rejected archived construction must not claim a family slot or spend credits.")
	_check([state.red_tiles_available, state.blue_tiles_available, state.green_tiles_available, state.core_tiles_available] == inventory,
		"Rejected construction must not spend materials.")
	_check(state.load_saved_ship_design("Archived Laser"), "Locked archived blueprints remain viewable/editable.")
	_check(not state.design_research_error(state.ship).is_empty(), "Loading a blueprint cannot grant its research.")

	# Simulate completed research for this state test; purchases stay unexposed until later milestones.
	state.current_research_ids.append("applied_energy")
	_check(state.is_equipment_available(ShipPart.Type.LASER) and state.is_equipment_available(ShipPart.Type.DOUBLE_LASER),
		"Current-run grouped research authorizes both implemented grants.")
	_check(state.purchase_saved_ship("Archived Laser"), "Current-run authorization permits archived construction.")
	state.research_points = 75
	state.current_research_ids.append("optics_i")
	state.research_branch_choices["energy"] = "optics"
	state.story_flags["boss_i_defeated"] = true
	state.credits = -12
	state.run_seed = 9007199254740993
	var progress: Dictionary = state.run_progress_snapshot()
	var serialized: Variant = JSON.parse_string(JSON.stringify(progress))
	_check(RunProgressData.validate(serialized).is_empty(), "Run metadata must be JSON-compatible: %s" % RunProgressData.validate(serialized))
	progress.story_flags.clear()
	_check(state.story_flags.get("boss_i_defeated", false), "Snapshots must not alias run dictionaries.")

	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 12345, false), "Restart the same seed.")
	_check(state.NODE_POSITIONS == initial_nodes and state.GRAPH_EDGES == initial_edges, "Same run seed must reproduce the current graph.")
	_check(state.current_research_ids == ["foundation"] and state.research_points == 0,
		"New runs reset authorization and research points to Foundation.")
	_check(state.research_branch_choices.is_empty() and state.story_flags.is_empty(), "New runs reset branches and story.")
	_check(state.fleet_design_slots == ["Drone", "", ""] and state.current_run_design_names.is_empty(),
		"New runs reset active families but retain the starter family.")
	_check(state.credits == GameState.STARTING_CREDITS, "A new run resets signed credits.")
	_check(state.get_saved_ship_designs() == designs and state.has_discovered_part(ShipPart.Type.LASER),
		"Blueprints and discovered knowledge must survive a new run.")
	_check(FileAccess.get_file_as_string(state.archive_progress_file_path) == archived_file,
		"Resetting research must not erase or rewrite established Archive knowledge.")
	_check(not state.is_equipment_available(ShipPart.Type.LASER) and not state.purchase_saved_ship("Archived Laser"),
		"Previous-run research cannot authorize construction after restart.")

	_check(state.restore_run_progress(serialized), "Restore validated run metadata.")
	_check(state.credits == -12 and state.run_seed == 9007199254740993 and state.research_points == 75,
		"Signed debt, RP and full-precision seed must survive JSON round-trip.")
	_check(state.is_equipment_available(ShipPart.Type.LASER) and state.research_branch_choices.get("energy") == "optics",
		"Restore research and branch commitment from the run, not Archive.")
	_check(state.is_equipment_available(ShipPart.Type.FOCUSING_LENS) and not state.is_equipment_available(ShipPart.Type.STELLAR_LANCE),
		"Restored intermediate grants are available while unimplemented endpoints stay unavailable.")
	_check(state.fleet_design_slots.has("Archived Laser") and state.story_flags.get("boss_i_defeated", false),
		"Restore active design families and story flags.")
	var valid: Dictionary = state.run_progress_snapshot()
	for key in ["version", "credits", "research_ids", "branch_choices", "active_design_families", "seed"]:
		var invalid := valid.duplicate(true)
		invalid[key] = null
		_check(not state.restore_run_progress(invalid) and state.run_progress_snapshot() == valid,
			"Invalid %s must not partially mutate a run." % key)
	var contradictory := valid.duplicate(true)
	contradictory.research_ids.append("disruption_i")
	_check(not state.restore_run_progress(contradictory), "Reject opposite research paths.")
	contradictory = valid.duplicate(true)
	contradictory.research_ids.append("laboratory_iii")
	_check(not state.restore_run_progress(contradictory), "Reject missing rank prerequisites.")
	contradictory = valid.duplicate(true)
	contradictory.research_ids.append("laboratory_ii")
	contradictory.research_ids.append("laboratory_iii")
	contradictory.story_flags.clear()
	_check(not state.restore_run_progress(contradictory), "Reject missing research story gates.")
	_check(state.get_saved_ship_designs() == designs, "Restore/rejection never mutates archived designs.")
	print("Run state tests finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)
