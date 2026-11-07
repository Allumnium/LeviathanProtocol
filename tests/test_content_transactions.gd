extends SceneTree

const Loadouts = preload("res://scripts/ship_loadouts.gd")
const Travel = preload("res://scripts/expedition_state.gd")
var state: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://content-transactions.json"
	if "--native-only" in OS.get_cmdline_user_args():
		await native_interface()
		print("CONTENT NATIVE COMPLETE: %d checks, %d failures" % [checks, failures])
		quit(1 if failures else 0)
		return
	var shipped := Content.load_all(["res://packs"])
	check(shipped.problems.items.is_empty(), "Shipped definitions have zero Problems")
	check(state.start_new_run(1, 7341), "Start shipped convoy")
	check(state.credits == 700 and state.missiles == 30 and state.fleet.size() == 13,
		"Shipped start retains resources and thirteen ships")
	var original_ability: String = GameDefinitions.find("abilities", "ion_pulse").display_name
	var original_price: int = SlotCatalog.find_equipment("cargo_hold").price
	check(Loadouts.default_for("fighter").id == "interceptor", "Warm the explicit shipped default and catalog caches")
	var patched := Content.load_all(["res://packs", "res://tests/fixtures/content/p2"])
	check(patched.problems.items.is_empty(), "Patch-only tuning pack has zero Problems: " + patched.problems.text())
	check(patched.content_hash != shipped.content_hash, "Tuning changes the content hash")
	check(SlotCatalog.find_equipment("cargo_hold").price == 777
		and GameDefinitions.find("abilities", "ion_pulse").display_name == "Fixture Pulse",
		"Existing catalog views read the replacement database")
	check(Loadouts.default_for("fighter").id == "skirmisher", "Patched default uses its ID despite being fourth in the file")
	check(state.start_new_run(1, 7341), "Start the patched convoy through the production entry point")
	check(state.credits == 913 and state.missiles == 7 and state.run_score.credits_earned == 0,
		"Patched starting resources apply without counting as income")
	check(state.fleet.size() == 5 and state.fleet[0].flagship
		and state.fleet.filter(func(ship: HangarShip) -> bool: return ship.chassis_id == "drone").size() == 2,
		"Patched fleet count applies and a reordered flagship remains the lead ship")
	var fighter: HangarShip = state.fleet.filter(func(ship: HangarShip) -> bool: return ship.chassis_id == "fighter")[0]
	check(state.ship_loadout_id(fighter.id) == "skirmisher", "The patched default reaches installed equipment")
	var uids := {}
	for ship: HangarShip in state.fleet:
		for instance: Dictionary in ship.mounts.values():
			check(not uids.has(instance.uid), "Each starting mount owns a fresh equipment UID")
			uids[instance.uid] = true
	check(uids.size() == state.equipment_inventory.size() and HangarCheckpoint.valid(state.hangar_snapshot()),
		"The patched fleet has no inventory stock and passes checkpoint validation")
	var before: Dictionary = state.hangar_snapshot()
	var save_path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-new-run.json"
	check(not state.start_new_run(1, 7341, true, "flagship_civic")
		and SaveValidation.same(before, state.hangar_snapshot()), "Failed patched new run rolls back the existing run")
	state.run_save_path = save_path
	check(state.load_run_checkpoint() and SaveValidation.same(before, state.hangar_snapshot()), "Continue retains the fitted patched fleet")
	check(state.buy_missiles() and state.credits == 896 and state.missiles == 10,
		"Ammunition uses patched pack size and price")
	before = state.hangar_snapshot()
	state.run_save_path = "res://project.godot/no-purchase.json"
	check(not state.buy_missiles() and SaveValidation.same(before, state.hangar_snapshot()), "Failed ammunition save spends nothing")
	state.run_save_path = save_path
	state.expedition_simulation.state.fuel = 90.5
	check(state.refuel_expedition() and state.credits == int(before.credits) - 29
		and state.expedition_simulation.state.fuel == 100, "Refueling uses patched unit price with ceiling rounding")
	for event: Dictionary in state.expedition_simulation.events:
		state.expedition_simulation.state.event_receipts[event.id] = true
	check(state.depart_expedition("refuel_station_1"), "Load goods at the patched origin")
	var transport: HangarShip = state.fleet.filter(func(ship: HangarShip) -> bool: return ship.chassis_id == "transport")[0]
	var hold_uid: String = transport.mounts.hold.uid
	check(transport.mounts.hold.load.origin == 1017 and transport.mounts.hold.load.unit_value == 5
		and HangarTrade.valid(transport.mounts.hold), "Load stores the explicit origin and patched fare outside the former whitelist")
	var ids: Array = state.expedition_simulation.locations.keys()
	ids.reverse()
	var reordered := {}
	for id: String in ids:
		reordered[id] = state.expedition_simulation.locations[id]
	state.expedition_simulation.locations = reordered
	check(state.station_trade_node("start_station").id == 1017
		and state.station_trade_node("refuel_station_1").id == 22, "Reordering locations cannot change trade identities")
	before = state.hangar_snapshot()
	check(state._deliver_loads("start_station") == 0 and SaveValidation.same(before, state.hangar_snapshot()),
		"Returning to the same origin cannot cash out")
	state.expedition_simulation.set_speed(20)
	check(state.advance_expedition(100, true).delivered == 50, "Actual arrival pays the patched goods fare once")
	check(state.equipment_inventory.has(hold_uid) and not HangarTrade.has_load(state.equipment_inventory[hold_uid]),
		"Delivery empties the original equipment UID")
	check(state.advance_expedition(100, true).delivered == 0, "Docked arrival cannot duplicate delivery")
	check(state.refit_ship(transport.id, "passenger_liner") and state.depart_expedition("start_station"), "Refit and board passengers at the destination")
	transport = state.owned_ship(transport.id)
	var berth_uid: String = transport.mounts.hold.uid
	check(transport.mounts.hold.load.unit_value == 11 and transport.mounts.hold.load.origin == 22,
		"Passenger fare is read from economy defs at boarding")
	var loaded: Dictionary = state.hangar_snapshot()
	var losses := loaded.duplicate(true)
	HangarTrade.settle_losses(losses, [transport.id])
	check(losses.credits == loaded.credits - 12 * 31 and not HangarTrade.has_load(losses.equipment[berth_uid]),
		"Patched casualty fee clears loads on the original UID")
	var charged: int = losses.credits
	HangarTrade.settle_losses(losses, [transport.id])
	check(losses.credits == charged, "Casualty fee is charged exactly once")
	check(state.advance_expedition(100, true).delivered == 132, "Actual passenger arrival pays the patched frozen fare")
	state.expedition_simulation.state.fuel = 0
	state.expedition_simulation.state.position_nu = Vector2(100, 0)
	state.expedition_simulation.state.docked_location_id = ""
	state.expedition_simulation.state.travel_state = Travel.TravelState.CRUISING
	state.expedition_simulation.set_pause(Travel.PauseReason.FUEL, true)
	var tow: Dictionary = state.rescue_quote()
	check(tow.location_id == "start_station" and tow.fee == 420, "Tug quote uses patched refill, base and distance prices")
	before = state.hangar_snapshot()
	state.run_save_path = "res://project.godot/no-tug.json"
	check(not state.accept_rescue() and SaveValidation.same(before, state.hangar_snapshot()), "Failed tug save spends no credits or fuel")
	state.run_save_path = save_path
	check(state.accept_rescue() and state.credits == int(before.credits) - 420
		and state.expedition_simulation.state.fuel == 100
		and state.expedition_simulation.state.docked_location_id == "start_station", "Accepted tug settles the disclosed price atomically")
	var locations := Travel.locations_catalog()
	locations.locations[1].trade_id = locations.locations[0].trade_id
	check(not Travel.valid_locations(locations), "Duplicate explicit trade identities are rejected")
	before = state.hangar_snapshot()
	var invalid := Content.get_def("fleet_package", "core:convoy").duplicate(true)
	invalid.members.append(invalid.members[0].duplicate(true))
	check(state._prepare_starting_fleet(invalid, "flagship_basic").is_empty()
		and not state.last_save_error.is_empty() and SaveValidation.same(before, state.hangar_snapshot()),
		"Duplicate group IDs fail before mutating a run")
	invalid = Content.get_def("fleet_package", "core:convoy").duplicate(true)
	invalid.members[1].count = 2
	check(state._prepare_starting_fleet(invalid, "flagship_basic").is_empty(), "Multiple flagships cannot start a run")
	check(not state.start_new_run(1, 7341, true, "flagship_basic", "missing")
		and SaveValidation.same(before, state.hangar_snapshot()), "A missing start definition leaves the run unchanged")
	check(state.start_new_run(1, 7341) and state.buy_ship("fighter")
		and state.ship_loadout_id(state.fleet.back().id) == "skirmisher", "An unspecified shipyard purchase uses the patched explicit default")
	Content.set_database(shipped)
	check(Loadouts.default_for("fighter").id == "interceptor" and SlotCatalog.find_equipment("cargo_hold").price == original_price
		and GameDefinitions.find("abilities", "ion_pulse").display_name == original_ability, "Restoring content invalidates every warmed catalog view")
	check(HangarTrade.valid(loaded.equipment[berth_uid]) and loaded.equipment[berth_uid].load.unit_value == 11,
		"Existing loads retain their departure fare even after the current fare changes")
	print("CONTENT TRANSACTIONS COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func settle() -> void:
	await create_timer(0.25).timeout
	for index in 4:
		await process_frame

func click(button: Button) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = motion.position
	press.global_position = motion.position
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := press.duplicate()
	release.pressed = false
	release.button_mask = 0
	root.push_input(release, true)
	await settle()

func native_interface() -> void:
	check(DisplayServer.get_name() != "headless", "Price interaction check requires a native renderer")
	if DisplayServer.get_name() == "headless":
		return
	var db := Content.load_all(["res://packs", "res://tests/fixtures/content/p2"])
	check(db.problems.items.is_empty() and state.start_new_run(1, 7341), "Start native patched convoy")
	state.pending_intro = false
	state.expedition_simulation.state.fuel = 90.5
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	screen.active_tab = "MAP"
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	await settle()
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		screen._refresh_expedition_controls()
		var missile_text: ResourceText = screen.missile_buy_button.get_node("ResourceText")
		check(missile_text.source_text == "+3 MISSILES / 17 cr" and screen.missile_buy_button.is_visible_in_tree()
			and screen.get_global_rect().encloses(screen.missile_buy_button.get_global_rect()), "Patched ammunition quote is visible and fits at %s" % resolution)
		var refuel: Button = screen.find_child("StationRefuel", true, false)
		check(is_instance_valid(refuel) and refuel.is_visible_in_tree()
			and refuel.get_node("ResourceText").source_text == "REFUEL 29 cr"
			and screen.get_global_rect().encloses(refuel.get_global_rect()), "Patched station refuel quote is visible and fits at %s" % resolution)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("user://content-prices-%d.png" % resolution.x) == OK, "Capture native patched prices")
	root.size = Vector2i(1280, 720)
	await settle()
	await click(screen.missile_buy_button)
	check(state.missiles == 10 and state.credits == 896, "Actual ammunition pointer click spends the displayed patched price")
	var refuel: Button = screen.find_child("StationRefuel", true, false)
	await click(refuel)
	check(state.expedition_simulation.state.fuel == 100 and state.credits == 867,
		"Actual refuel pointer click spends the displayed patched price")
	check(screen.find_child("StationRefuel", true, false) == null, "Full tanks remove the station refuel action")
	screen.queue_free()
	await settle()
