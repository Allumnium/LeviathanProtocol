extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _laser_blueprint() -> Ship:
	var design := Ship.new()
	BUILTINS._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(design, ShipPart.Type.LASER, Vector2i(2, 0))
	BUILTINS._add_part(design, ShipPart.Type.THRUSTER, Vector2i(2, 1))
	return design

func _snapshot(state: Node) -> Dictionary:
	return RunCheckpoint.capture(state)

func _run() -> void:
	var basics := ["foundation", "applied_energy", "field_engineering", "guided_munitions"]
	var selected := basics.duplicate()
	var choices: Dictionary = {}
	for family: String in ResearchRules.FAMILY_PATHS:
		var path: String = ResearchRules.FAMILY_PATHS[family][0]
		choices[family] = path
		selected.append(path + "_i")
	_check(ResearchRules.selection_error(selected, {}, choices).is_empty(), "Independent first-tier commitments form a valid current-run grant source.")
	for family: String in ResearchRules.FAMILY_PATHS:
		var conflicting := selected.duplicate()
		conflicting.append(ResearchRules.FAMILY_PATHS[family][1] + "_i")
		_check(not ResearchRules.selection_error(conflicting, {}, choices).is_empty(), "Every opposing family path is rejected at the authorization boundary.")
	_check(not ResearchRules.selection_error(["foundation", "laboratory_ii", "laboratory_iii"], {}, {}).is_empty(), "Missing boss gate cannot authorize physical ranks.")
	_check(ResearchRules.selection_error(["foundation", "laboratory_ii", "laboratory_iii"], {"boss_i_defeated": true}, {}).is_empty(), "Valid prior ranks and boss gate satisfy the authorization model.")
	_check(not ResearchRules.selection_error(["foundation", "foundation"], {}, {}).is_empty()
		and not ResearchRules.selection_error(["foundation", "unknown"], {}, {}).is_empty(), "Duplicate/unknown grant sources fail closed.")

	var state := root.get_node("GameState")
	state.run_save_path = "user://enforcement/run.json"
	_check(state.start_new_run(1, 42), "Start isolated enforcement fixture.")
	var cached_grants: Dictionary = state.research_grants()
	cached_grants.equipment_ids.clear()
	_check(state.is_equipment_available(ShipPart.Type.MINI_TURRET), "Callers cannot mutate cached authorization.")
	state.credits = 100000
	var blueprint := _laser_blueprint()
	state.saved_ship_designs.assign([{"name": "Imported Laser", "ship": blueprint.to_design_data()}])
	_check(state.load_saved_ship_design("Imported Laser"), "Locked imported blueprints remain viewable for planning.")
	var before := _snapshot(state)
	_check(not state.purchase_ship(blueprint) and not state.purchase_saved_ship("Imported Laser"), "Direct and library construction reject locked equipment.")
	_check(not state.assign_fleet_design(1, "Imported Laser", blueprint)
		and not state.assign_fleet_design(0, "Locked revision", blueprint, true), "Assignment and revision registration cannot bypass authorization.")
	_check(_snapshot(state) == before, "Rejected construction/assignment preserves IDs, balances, inventory, roster and physical ships.")

	var map: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await process_frame
	await process_frame
	var builder: Control = map.build_area
	builder.auto_assemble = false
	state.ship.clear()
	BUILTINS._add_part(state.ship, ShipPart.Type.MINI_TURRET, Vector2i.ZERO)
	for x in [1, 2, 5, 6, 7]:
		state.ship.set_tile_at(Vector2i(x, 0), ShipPart.Category.OFFENSE)
	builder._evaluate_part_patterns()
	var turret: ShipPart = state.ship.parts[0]
	var laser_pattern: ShipPartPattern
	for pattern in ShipPartPattern.get_catalog():
		if pattern.part_type == ShipPart.Type.LASER:
			laser_pattern = pattern
	builder._refresh_assembly_menu()
	_check(not builder.recipe_matches.any(func(m: Dictionary) -> bool: return m.pattern.part_type == ShipPart.Type.LASER), "Locked recipes do not appear in assembly choices.")
	_check(not builder._try_morph_pattern(Vector2i(5, 0), laser_pattern) and state.active_part_transformations == 0,
		"Direct morph calls cannot start a locked assembly or discovery animation.")
	var blocked_part := ShipPart.new(laser_pattern.part_type, laser_pattern.category, Vector2i(5, 0), laser_pattern.cell_offsets, laser_pattern.stats)
	builder._begin_part_transformation(blocked_part)
	_check(state.active_part_transformations == 0, "The discovery-animation entry point independently enforces research.")
	var editor_before: Dictionary = state.ship.to_design_data()
	var fleet_before: Dictionary = _snapshot(state)
	state.current_research_ids.append("applied_energy")
	state.research_changed.emit()
	_check(state.ship.to_design_data() == editor_before and state.ship.parts[0] == turret, "Research changes neither assembled identities nor loose material.")
	_check(_snapshot(state).fleet == fleet_before.fleet, "Research never refits, heals or replaces physical ships.")
	builder._refresh_assembly_menu()
	var match_index: int = builder.recipe_matches.find_custom(func(m: Dictionary) -> bool: return m.pattern.part_type == ShipPart.Type.LASER)
	_check(match_index >= 0, "Newly authorized loose recipe becomes selectable.")
	if match_index >= 0:
		await builder._assembly_action(100 + match_index)
	_check(state.ship.parts.has(turret) and state.ship.parts.size() == 2, "Explicit post-research assembly preserves the existing turret instead of reinterpreting it.")
	_check(state.assign_fleet_design(1, "Imported Laser", blueprint) and state.purchase_saved_ship("Imported Laser"), "Authorized imported equipment constructs normally.")
	var physical: FleetShip = state.fleet.back()
	var laser_unit: int = physical.cell_units[Vector2i(2, 0)]
	physical.units[laser_unit].hp = 0
	_check(state.repair_ship(physical) and physical.units[laser_unit].hp == physical.units[laser_unit].max_hp, "Authorized reconstruction restores the original component.")
	state.current_research_ids.assign(["foundation"])
	state.research_changed.emit()
	physical.units[laser_unit].hp = 0
	var locked_before := _snapshot(state)
	_check(not state.repair_ship(physical) and not state.can_deploy(), "Locked reconstruction and existing physical deployment are both rejected.")
	_check(_snapshot(state) == locked_before, "Rejected repair/deployment cannot charge resources or restore HP.")
	_check(state.set_ship_reserve(physical, true) and state.can_deploy(), "Illegal physical hulls can be quarantined in reserve while legal ships remain usable.")
	_check(not state.set_ship_reserve(physical, false), "Reserve activation rechecks current research.")
	state.current_research_ids.append("applied_energy")
	_check(state.repair_ship(physical) and state.set_ship_reserve(physical, false), "Restoring authorization permits paid reconstruction and reactivation.")
	_check(state.save_run_checkpoint() and state.load_run_checkpoint() and state.can_deploy(), "Authorization derives correctly after checkpoint reload.")
	_check(state.set_destination(state.get_reachable_nodes(0)[0]) and state.cancel_battle(), "Legal deployment passes the same authorization boundary.")

	state.current_research_ids.assign(["foundation", "applied_energy", "optics_i", "disruption_i"])
	state.research_branch_choices.energy = "optics"
	_check(not state.research_grants().error.is_empty() and not state.purchase_ship(BUILTINS.drone()) and not state.can_deploy(),
		"Contradictory branch state cannot manufacture grants through raw IDs, even for a Foundation design.")
	state.current_research_ids.assign(["foundation", "applied_energy"])
	state.research_branch_choices.clear()
	var forged := _laser_blueprint()
	forged.parts[1].definition_id = "mini_turret"
	var forged_before := _snapshot(state)
	_check(not state.purchase_ship(forged), "Forged stable equipment identity is rejected before spending.")
	forged = _laser_blueprint()
	forged.parts[1].rank = 2
	_check(not state.purchase_ship(forged), "Forged/unresearched physical rank is rejected before spending.")
	forged = _laser_blueprint()
	forged.parts[0].quarter_turns = 9
	var original_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	_check(not state.purchase_ship(forged), "Invalid component orientation returns a construction rejection instead of creating an empty physical hull.")
	Engine.print_error_messages = original_errors
	_check(_snapshot(state) == forged_before, "All forged direct-construction paths preserve physical/accounting state.")
	var invalid_physical := FleetShip.new()
	_check(not invalid_physical.initialize(Ship.new(), 100, "Invalid") and not invalid_physical.is_alive(), "Empty physical initialization fails safely.")
	map.queue_free()
	current_scene = null
	await process_frame

	state.current_research_ids.assign(["foundation"])
	state.ship.clear()
	for x in range(3):
		state.ship.set_tile_at(Vector2i(x, 0), ShipPart.Category.OFFENSE)
	var legacy_before: Dictionary = state.ship.to_design_data()
	var designer: Control = load("res://scenes/ship_designer.tscn").instantiate()
	root.add_child(designer)
	current_scene = designer
	await process_frame
	await process_frame
	_check(designer.canvas is SlotShipCanvas, "Standalone Designer uses chassis slots without materials.")
	designer._switch_chassis(4)
	_check(designer.design.equip("fore", "mini_turret", 1, state.research_grants()), "Starting tech can be equipped directly.")
	_check(not designer.design.equip("fore", "laser", 1, state.research_grants()), "Slot fitting requires current research.")
	_check(state.ship.to_design_data() == legacy_before and not state.is_equipment_available(ShipPart.Type.LASER), "Slot editing neither mutates legacy campaign ships nor grants research.")
	_check(not Ship.new().load_design_data(designer.design.to_data()), "Slot blueprints cannot be silently used as legacy square designs.")
	designer.queue_free()
	current_scene = null
	await process_frame
	print("Research enforcement tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
