extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var state: Node
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for _frame in range(3):
		await process_frame

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await settle()

func mixed_design() -> Ship:
	var design := Ship.new()
	BUILTINS._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(design, ShipPart.Type.CARGO_HOLD, Vector2i(2, 0))
	BUILTINS._add_part(design, ShipPart.Type.CREW_QUARTERS, Vector2i(0, 2))
	BUILTINS._add_part(design, ShipPart.Type.PASSENGER_CABIN, Vector2i(0, 3))
	BUILTINS._add_part(design, ShipPart.Type.THRUSTER, Vector2i(3, 3))
	BUILTINS._add_part(design, ShipPart.Type.MINI_TURRET, Vector2i(3, 2))
	return design

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://economy-ui/run.json"
	check(state.start_new_run(1, 42), "Start isolated economy UI campaign.")
	state.research_points = 20
	check(state.set_research_focus("civil_hospitality"), "Unlock functional cabins through research focus.")
	check(state.purchase_ships(mixed_design(), "Mixed trader", "regular", 2), "Construct two normal mixed-role hulls within starting resources.")
	for _visit in range(7):
		var next: int = state.get_reachable_nodes(state.current_node_id)[0]
		check(state.travel_to(next), "Reach an actual inhabited destination.")
		if state.battle_pending:
			check(state.complete_battle(), "Secure the fixture's actual arrival.")
		if state.is_shipyard_node(state.current_node_id):
			break
	var first: FleetShip = state.fleet[-2]
	var second: FleetShip = state.fleet[-1]
	var summary: Dictionary = state.fleet_economy_summary()
	check(summary.passengers == 8 and summary.places == 8 and summary.cargo == 20 and summary.cargo_capacity == 20
		and summary.cargo_value == 60 and summary.tickets == 64 and summary.income == 124,
		"Fleet summary quotes real operational capacity, stock, frozen cargo value and next-port tickets.")
	var scoped: Dictionary = state.fleet_economy_summary(first.id)
	check(scoped.passengers == 4 and scoped.cargo == 10 and scoped.luxury_min == 1 and scoped.income == 62, "Selected ship summary excludes the other hull.")
	check(state.set_planned_destination(state.get_reachable_nodes(state.current_node_id)[0]) and state.fleet_economy_summary().income == 0,
		"An uninhabited planned arrival promises no port income.")
	state.planned_destination_node_id = -1
	state.credits = -5
	state.red_tiles_available = 0
	state.blue_tiles_available = 0
	state.green_tiles_available = 0
	state.core_tiles_available = 0
	check(not state.construction_error(BUILTINS.drone()).is_empty() and CargoRules.value(state.economy_state) == 60,
		"Held cargo value cannot be spent as signed credits or construction material.")
	check(state.save_run_checkpoint(), "Persist debt and the loaded fleet.")
	var before := RunCheckpoint.capture(state)
	var path: String = state.run_save_path
	var blocker := FileAccess.open("user://economy-ui/blocker", FileAccess.WRITE)
	blocker.store_string("file")
	blocker.close()
	state.run_save_path = "user://economy-ui/blocker/run.json"
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	check(not state.offload_cargo(first.id) and not state.disembark_passengers(first.id) and RunCheckpoint.capture(state) == before,
		"Failed unloading writes change neither stock, occupancy, ledger nor signed credits.")
	Engine.print_error_messages = printed
	state.run_save_path = path
	root.gui_embed_subwindows = true
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var map: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await settle()
	var fleet: Control = map.panel_tabs.get_node("Fleet")
	fleet.board.selected_ships.assign([first])
	fleet.board.selection_changed.emit()
	await settle()
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		var bar: Control = map.get_node("Layout/TopBar/BarContents")
		check(bar.get_node("CreditAmount").text == "-5" and bar.get_node("HeldCargoValue").text == "Cargo 60 cr", "Header separates signed credits from held cargo value.")
		check(bar.get_global_rect().encloses(bar.get_node("SettingsButton").get_global_rect()), "Resources, RP and navigation fit the header at %s." % resolution)
		check(fleet.ship_actions.visible and fleet.board.get_global_rect().encloses(fleet.ship_actions.get_global_rect()), "Selected economy/actions fit the formation viewport at %s." % resolution)
		check(not fleet.ship_actions.get_global_rect().intersects(fleet.board.previews[first].get_global_rect()), "The economy actions do not cover the selected hull at %s: actions %s, hull %s, center %s, scale %s." % [resolution, fleet.ship_actions.get_global_rect(), fleet.board.previews[first].get_global_rect(), fleet.board._screen_position(first), fleet.board.view_scale])
		check(fleet.ship_actions.find_child("ShipEconomy", true, false).text == "Passengers 4/4\nLuxury 1\nCargo 10/10", "Selected hull displays concise occupancy, luxury and cargo.")
		check(fleet.ship_actions.find_child("ReserveAction", true, false).disabled and fleet.ship_actions.find_child("SalvageAction", true, false).disabled,
			"Loaded hull actions stay guarded until safe unloading.")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/step33/economy-%d.png" % resolution.x)
	root.size = Vector2i(640, 360)
	await settle()
	await click(fleet.ship_actions.find_child("DisembarkPassengers", true, false))
	check(PassengerRules.occupied(state.economy_state, first.id) == 0 and PassengerRules.occupied(state.economy_state, second.id) == 4 and state.credits == -5,
		"Disembark click safely empties only the selected ship, without tickets, refund or fee.")
	await click(fleet.ship_actions.find_child("OffloadCargo", true, false))
	check(CargoRules.quantity(state.economy_state, first.id) == 0 and CargoRules.quantity(state.economy_state, second.id) == 10 and state.credits == 25,
		"Offload click sells only the selected physical load at its frozen value.")
	check(not fleet.ship_actions.find_child("ReserveAction", true, false).disabled, "Safe unloading releases the selected ship's guard.")
	var ledger_size: int = state.transaction_ledger.size()
	check(state.disembark_passengers(first.id) and state.offload_cargo(first.id) and state.dispatch_arrival()
		and state.transaction_ledger.size() == ledger_size and state.credits == 25 and CargoRules.quantity(state.economy_state, first.id) == 0,
		"Repeated clicks and reopening the same port neither refill loads nor repeat income.")
	var revision := mixed_design()
	BUILTINS._add_part(revision, ShipPart.Type.SINGLE_PLATE, Vector2i(5, 2))
	var slot: int = state.roster_state.active.find(first.family_id)
	check(not state.assign_fleet_design(slot, "Mixed trader", revision, true), "A family revision remains blocked while another physical copy is loaded.")
	check(state.disembark_passengers(second.id) and state.offload_cargo(second.id) and state.assign_fleet_design(slot, "Mixed trader", revision, true),
		"Releasing each physical load permits the paid-replacement revision flow.")
	check(state.load_run_checkpoint() and PassengerRules.occupied(state.economy_state) == 0 and CargoRules.quantity(state.economy_state) == 0 and state.credits == 55,
		"Scoped releases and exact sale proceeds survive reload without erasing losses or granting free replacement hulls.")
	map.free()
	current_scene = null
	print("Economy UI/loaded-refit tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
