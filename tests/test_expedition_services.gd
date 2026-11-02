extends SceneTree

const Travel = preload("res://scripts/expedition_state.gd")
const Transfer = preload("res://scripts/hangar_equipment_transfer.gd")

var checks := 0
var failures := 0
var state: Node
var screen: Control
var loose_uid := ""
var installed_uid := ""
var flagship_id := 0
var escort_id := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func settle() -> void:
	for index in range(4):
		await process_frame

func denied(command: Callable, label: String) -> void:
	var before: Dictionary = state.hangar_snapshot()
	var generation: int = state.hangar_generation
	state.last_save_error = ""
	check(not bool(command.call()), label + " is rejected")
	check(not state.last_save_error.is_empty(), label + " explains missing access")
	check(state.hangar_snapshot() == before and state.hangar_generation == generation,
			label + " leaves ownership, credits, hull, loads and checkpoint unchanged")

func check_no_shipyard(label: String) -> void:
	check(not state.can_use_shipyard() and not state.is_shipyard_node(state.current_node_id),
			label + " does not inherit the starting node's shipyard")
	denied(func() -> bool: return state.buy_equipment("mini_turret"), label + " equipment purchase")
	denied(func() -> bool: return state.buy_chassis("drone"), label + " chassis purchase")
	denied(func() -> bool: return state.fit_equipment(flagship_id, "port", loose_uid), label + " fitting")
	denied(func() -> bool: return state.fit_equipment(flagship_id, "port", ""), label + " unequipping")
	denied(func() -> bool: return state.fit_equipment(escort_id, "port", installed_uid), label + " transfer")
	denied(func() -> bool: return state.sell_equipment(loose_uid), label + " stock sale")
	denied(func() -> bool: return state.salvage_hangar_ship(escort_id), label + " salvage")
	denied(func() -> bool: return state.repair_ship(state.owned_ship(flagship_id)), label + " repair")
	denied(func() -> bool: return state.repair_all_ships(), label + " fleet repair")
	check(not Transfer.can_fit(flagship_id, "port", Transfer.payload(loose_uid))
			and not Transfer.can_store(Transfer.payload(installed_uid)),
			label + " has no fitting or unequip drop targets")

func run() -> void:
	root.size = Vector2i(1280, 720)
	state = root.get_node("GameState")
	state.run_save_path = "user://expedition-services-test.json"
	if not state.start_new_run(1, 921):
		check(false, "Start expedition service fixture: " + state.last_save_error)
		quit(1)
		return
	# Keep this service-access fixture independent of the signal decision.
	for authored: Dictionary in state.expedition_simulation.events:
		state.expedition_simulation.state.event_receipts[authored.id] = true
	var fixture: Dictionary = state.hangar_snapshot()
	fixture.credits = 5000
	check(state._commit_hangar(fixture), "Fund service fixture")
	flagship_id = state.fleet[0].id
	escort_id = state.fleet[2].id
	installed_uid = state.owned_ship(flagship_id).mounts.port.uid
	check(state.can_use_shipyard(), "Starting station exposes its declared shipyard")
	check(state.buy_equipment("mini_turret"), "Buy loose physical equipment while docked")
	loose_uid = str(state.next_equipment_id - 1)
	state.owned_ship(flagship_id).hull_hp -= 12
	check(state.save_run_checkpoint(), "Persist damaged repair fixture")

	screen = load("res://scenes/game_map.tscn").instantiate()
	screen.active_tab = "SHIPS"
	screen.selected_ship_id = flagship_id
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	await settle()
	screen._open_shop("EQUIPMENT")
	await settle()
	check(screen.buy_open and screen.shop != null, "Docked shop uses the existing embedded panel")
	var stock: Control = screen.stock
	stock._set_pending_sale(loose_uid)
	check(stock.pending_sale == loose_uid, "Docked stock retains the existing inline sale interaction")
	var row: Button = stock.row_buttons[loose_uid]
	row.force_drag(Transfer.payload(loose_uid), Control.new())
	check(root.gui_is_dragging(), "A docked stock drag can begin")
	screen._apply_expedition_action(func() -> bool:
		return state.expedition_simulation.request_destination("refuel_station_1"))
	check(not root.gui_is_dragging(), "Undocking cancels an active fitting drag")
	await settle()
	check(not screen.buy_open and screen.shop == null, "Undocking closes the embedded shop")
	check(screen.stock.pending_sale.is_empty()
			and screen.stock.sale_controls[loose_uid].sell.disabled,
			"Undocking cancels sale confirmation and disables selling")
	check(screen.roster.find_child("BuyEquipment", true, false).disabled
			and screen.roster.find_child("StationServiceReason", true, false) != null,
			"Ships retains its layout with a disabled purchase action and service reason")
	check(screen.canvas.slot_buttons.port._get_drag_data(Vector2.ZERO) == null
			and screen.stock.row_buttons[loose_uid]._get_drag_data(Vector2.ZERO) == null,
			"Installed and loose equipment remain visible but cannot start flight-time drags")
	screen._inspect_equipment("mini_turret", 1, loose_uid)
	check(screen.inspection != null, "Equipment inspection remains available in flight")
	check_no_shipyard("Cruising")
	denied(func() -> bool: return state.refuel_expedition(), "Cruising refuel")
	check(state.set_research_focus("applied_energy"), "Research focus remains available in flight")
	check(state.move_ships({escort_id: Vector2(-1, -1)}), "Formation edits remain available in flight")

	var simulation = state.expedition_simulation
	check(simulation.stop(), "Stop retains the route")
	check_no_shipyard("Stopped")
	check(simulation.set_pause(Travel.PauseReason.USER, true), "Pause stopped travel")
	check_no_shipyard("Paused in space")
	check(simulation.set_pause(Travel.PauseReason.USER, false), "Unpause stopped travel")
	check(simulation.set_speed(20) and simulation.request_destination("derelict_1")
			and simulation.advance(10), "Reach a non-station POI")
	check(simulation.state.travel_state == Travel.TravelState.STOPPED, "POI arrival is not docking")
	check_no_shipyard("At a POI")

	check(simulation.set_speed(20) and simulation.request_destination("settlement_1") and simulation.advance(10),
			"Reach a settlement without a shipyard")
	check(simulation.state.travel_state == Travel.TravelState.DOCKED, "Settlement arrival docks")
	check_no_shipyard("Docked without a shipyard")
	check(state.refuel_expedition(), "Settlement still offers its declared refueling service")
	check(state.save_expedition_checkpoint() and state.load_run_checkpoint(), "Reload settlement checkpoint")
	check(not state.can_use_shipyard(), "Continue does not regain a stale node's shipyard")

	simulation = state.expedition_simulation
	check(simulation.set_speed(20) and simulation.request_destination("refuel_station_1")
			and simulation.advance(10), "Travel to an actual shipyard")
	screen._refresh_expedition_controls()
	await settle()
	check(state.can_use_shipyard() and not screen.roster.find_child("BuyEquipment", true, false).disabled
			and not screen.stock.sale_controls[loose_uid].sell.disabled,
			"Shipyard arrival restores existing management actions automatically")
	check(simulation.set_pause(Travel.PauseReason.USER, true) and state.can_use_shipyard(),
			"User pause does not block docked management")
	check(state.fit_equipment(flagship_id, "port", loose_uid), "Shipyard fitting moves the owned instance")
	check(state.fit_equipment(flagship_id, "port", ""), "Shipyard unequipping returns the same instance")
	check(state.sell_equipment(loose_uid), "Shipyard stock sale succeeds")
	check(state.repair_all_ships(), "Shipyard fleet repair succeeds")
	check(state.buy_chassis("drone"), "Shipyard chassis purchase succeeds")
	check(state.salvage_hangar_ship(state.fleet[-1].id), "Shipyard salvage succeeds")

	screen._confirm_salvage(escort_id)
	check(screen.shop != null, "Shipyard salvage uses the existing confirmation modal")
	simulation.set_pause(Travel.PauseReason.SAVE_ERROR, true)
	screen._refresh_expedition_controls()
	check(screen.shop == null, "Losing station access cancels an open salvage confirmation")
	check_no_shipyard("Save-error pause")
	denied(func() -> bool: return state.refuel_expedition(), "Save-error refuel")
	simulation.set_pause(Travel.PauseReason.SAVE_ERROR, false)
	simulation.state.travel_state = Travel.TravelState.ENGAGED
	check_no_shipyard("Engaged with a stale dock ID")
	simulation.state.travel_state = Travel.TravelState.DOCKED
	simulation.state.position_nu += Vector2.ONE
	check(not state.can_use_shipyard(), "A stale station ID cannot grant services away from its position")
	print("EXPEDITION_SERVICES_CHECKS=%d failures=%d" % [checks, failures])
	screen.queue_free()
	await settle()
	quit(1 if failures else 0)
