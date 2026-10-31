extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0
var state: Node

func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://general-fleet/run.json"
	check(state.start_new_run(1, 42), "Start general-slot campaign.")
	state.credits = 10000
	state.research_points = 20
	check(state.purchase_research("civil_hospitality"), "Research equipment normally.")
	var mixed := Ship.new()
	BUILTINS._add_part(mixed, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(mixed, ShipPart.Type.RESEARCH_LAB, Vector2i(2, 0))
	BUILTINS._add_part(mixed, ShipPart.Type.CARGO_HOLD, Vector2i(3, 3))
	BUILTINS._add_part(mixed, ShipPart.Type.PASSENGER_CABIN, Vector2i(0, 3))
	BUILTINS._add_part(mixed, ShipPart.Type.MINI_TURRET, Vector2i(0, 2))
	check(state.purchase_ships(mixed, "Mixed ship", "regular", 2), "Construct multiple mixed combat/lab/cargo/passenger ships in one general family.")
	check(state.fleet.back().slot_role == "regular" and state.is_ship_deployed(state.fleet.back())
		and CargoRules.manifest(state.fleet).size() == 2 and PassengerRules.manifest(state.fleet).size() == 2,
		"Both copies operate their equipment without singleton or segregation rules.")
	var cargo := Ship.new()
	BUILTINS._add_part(cargo, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(cargo, ShipPart.Type.CARGO_HOLD, Vector2i(2, 0))
	BUILTINS._add_part(cargo, ShipPart.Type.PASSENGER_CABIN, Vector2i(0, 2))
	check(state.purchase_ship(cargo, "Trader"), "An unarmed logistics design uses a general family.")
	var owned: FleetShip = state.fleet.back()
	state.economy_state = CargoRules.register_components(state.economy_state, state.fleet)
	state.economy_state = PassengerRules.register_components(state.economy_state, state.fleet)
	state.economy_state.passengers.components[PassengerRules.component_id(owned.id, 2)].occupied = 4
	var hold_id := PassengerRules.component_id(owned.id, 1)
	state.economy_state.cargo.holds[hold_id].merge({"quantity": 7, "origin": "node/old-port", "grade": "basic", "unit_value": 3}, true)
	owned.units[1].hp *= 0.5
	var hp: float = owned.units[1].hp
	var old := RunCheckpoint.capture(state)
	old.fleet_roster.version = 1
	old.fleet_roster.active[2] = ""
	old.progress.active_design_families[2] = ""
	old.fleet_roster.families.erase(owned.family_id)
	old.fleet_roster.support_ids.civic = owned.id
	old.fleet_roster.support_names.civic = "Trader"
	old.fleet.back().slot_role = "civic"
	old.fleet.back().family_id = ""
	var store := AtomicRunStore.new()
	var path := "user://general-fleet/legacy.json"
	check(store.commit(path, old, RunCheckpoint.valid).ok, "Store an actual legacy dedicated cargo checkpoint.")
	state.run_save_path = path
	check(state.load_run_checkpoint(), "Load and durably migrate legacy support roles.")
	owned = state.fleet.back()
	check(state.roster_state.version == 2 and owned.slot_role == "regular" and state.is_ship_deployed(owned)
		and is_equal_approx(owned.units[1].hp, hp) and CargoRules.quantity(state.economy_state) == 7
		and PassengerRules.occupied(state.economy_state, owned.id) == 4
		and state.credits == old.progress.credits and JSON.parse_string(JSON.stringify(state.transaction_ledger)) == JSON.parse_string(JSON.stringify(old.ledger)),
		"Migration preserves physical hull identity, damage, cargo and funds/ledger.")
	check(store.load_latest(path, RunCheckpoint.valid).payload.fleet_roster.version == 2, "Migration is saved before exposing live state.")
	check(not state.assign_fleet_design(3, "Bonus slot", mixed), "A fourth/dedicated selector is unavailable.")
	await _test_ui()
	_test_pending_migration(cargo)
	print("General fleet tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _test_pending_migration(cargo: Ship) -> void:
	check(state.start_new_run(1, 42), "Start pending legacy-role migration fixture.")
	state.credits = 10000
	state.research_points = 20
	check(state.purchase_research("civil_hospitality"), "Authorize passenger equipment for pending migration fixture.")
	check(state.purchase_ship(cargo, "Trader") and state.set_destination(state.get_reachable_nodes(0)[0]), "Freeze an actual mixed-role deployment.")
	var owned: FleetShip = state.fleet.back()
	var old := RunCheckpoint.capture(state)
	old.fleet_roster.version = 1
	old.fleet_roster.active[1] = ""
	old.progress.active_design_families[1] = ""
	old.fleet_roster.families.erase(owned.family_id)
	old.fleet_roster.support_ids.civic = owned.id
	old.fleet_roster.support_names.civic = "Trader"
	old.fleet.back().slot_role = "civic"
	old.fleet.back().family_id = ""
	var ids: Array = old.encounter_progress[str(state.destination_node_id)].ship_ids.duplicate()
	var path := "user://general-fleet/pending.json"
	var store := AtomicRunStore.new()
	check(store.commit(path, old, RunCheckpoint.valid).ok, "Store pending legacy deployment.")
	state.run_save_path = path
	check(state.load_run_checkpoint() and state.battle_pending and state.get_deployed_fleet().size() == ids.size(), "Migration preserves the authoritative in-flight deployment membership.")
	check(state.cancel_battle() and state.load_run_checkpoint() and not state.battle_pending, "A migrated pending attempt can settle and reload normally.")
	var old_id: int = state.fleet.back().id
	var revision := Ship.new()
	check(revision.load_design_data(cargo.to_design_data()), "Clone cargo revision after migration.")
	revision.set_tile_at(Vector2i(5, 0), ShipPart.Category.DEFENSE)
	check(state.assign_fleet_design(1, "Trader revision", revision, true) and state.purchase_ship(revision, "Trader revision"), "Select and build a new general revision after withdrawal.")
	check(state.set_destination(state.get_reachable_nodes(state.current_node_id)[0]), "Retry the frozen encounter with the new selection.")
	var progress: Dictionary = state.encounter_progress[str(state.destination_node_id)]
	check(not progress.get("migrated_support_attempt", false) and not progress.ship_ids.has(old_id), "Retry cannot resurrect a historical hull through migration compatibility.")
func _test_ui() -> void:
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		var map: Control = load("res://scenes/game_map.tscn").instantiate()
		root.add_child(map)
		current_scene = map
		for _frame in range(3):
			await process_frame
		var fleet: Control = map.panel_tabs.get_node("Fleet")
		check(fleet.slot_widgets.size() == 3 and fleet.slot_widgets.all(func(widget: Dictionary) -> bool: return not widget.label.text.begins_with("SCIENCE:") and not widget.label.text.begins_with("CIVIC:")), "Only general slots are displayed.")
		check(map.fleet_controls.find_child("FleetServices", true, false) == null and not is_instance_valid(map.campaign_overlay)
			and not map.sector_name_label.visible, "Port/Story controls and automatic story/Act/row presentation are absent.")
		var top: Label = map.get_node("Layout/TopBar/BarContents/StatsSpace")
		check(top.text == "Level %d" % state.campaign_level(), "Top bar contains level rather than duplicate fleet condition.")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/unified-fleet/fleet-%dx%d.png" % [resolution.x, resolution.y])
		map.free()
		current_scene = null
