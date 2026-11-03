extends SceneTree

# Arrival dialogs describe where the fleet is and its local actions; courses
# are set from the Map (GO TO or double-click) at any time, including mid-flight.
const Travel = preload("res://scripts/expedition_state.gd")
var checks := 0
var failures := 0
var state: Node
var screen: Control
var expedition

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

func open_screen() -> void:
	screen = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	await settle()

func reopen_checkpoint() -> void:
	screen.queue_free()
	await settle()
	check(state.load_run_checkpoint(), "Reload committed expedition")
	expedition = state.expedition_simulation
	await open_screen()

func map_go(id: String) -> void:
	screen._open_map()
	await settle()
	screen.graph.selected_id = id
	screen.graph._place_go_button()
	check(screen.graph.go_button.visible, "Map offers GO TO beside " + id)
	screen.graph.go_button.pressed.emit()
	await settle()

func run() -> void:
	root.size = Vector2i(1280, 720)
	state = root.get_node("GameState")
	state.run_save_path = "user://arrival-dialog-test.json"
	check(state.start_new_run(1, 1501), "Start arrival fixture")
	expedition = state.expedition_simulation
	for authored: Dictionary in expedition.events:
		expedition.state.event_receipts[authored.id] = true
	await open_screen()
	check(screen.arrival_modal == null and not expedition.state.departure_choice_pending,
			"Starting dock never forces a destination choice")
	screen.departure_button.pressed.emit()
	await settle()
	check(screen.active_tab == "MAP" and screen.graph != null, "Set Course opens the map")
	screen.graph.selected_id = "start_station"
	screen.graph._place_go_button()
	check(not screen.graph.go_button.visible, "The fleet's own location offers no GO TO")
	check(expedition.set_speed(10) and expedition.set_pause(Travel.PauseReason.USER, true),
		"Remember paused fast-forward speed before selecting a course")
	var original_position: Vector2 = expedition.state.position_nu
	screen.graph.location_selected.emit("refuel_station_1")
	check(expedition.state.destination_location_id.is_empty() and expedition.state.position_nu == original_position
		and screen.departure_button.text == "ENGAGE", "Map selection prepares Engage without departing")
	var engage_save_path: String = state.run_save_path
	state.run_save_path = "res://project.godot/blocked-engage.json"
	var loads_before: Dictionary = state.equipment_inventory.duplicate(true)
	screen.departure_button.pressed.emit()
	check(expedition.state.destination_location_id.is_empty() and expedition.state.position_nu == original_position
		and Travel.PauseReason.USER in expedition.state.pause_reasons
		and state.equipment_inventory == loads_before,
		"Failed Engage save preserves route, user pause and physical loads")
	state.run_save_path = engage_save_path
	screen._on_expedition_retry_pressed()
	screen.departure_button.pressed.emit()
	await settle()
	check(expedition.state.requested_speed == 10 and Travel.PauseReason.USER not in expedition.state.pause_reasons,
		"Engage clears only user pause and starts at the last set speed")
	check(screen.course_readout.visible and not screen.departure_button.visible
		and screen.course_readout.text.begins_with(expedition.locations["refuel_station_1"].name),
		"In flight without selection, the lower recess shows destination and remaining distance")
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		check(screen.command_header.get_global_rect().encloses(screen.course_readout.get_global_rect())
			and screen.command_header.course.get_global_rect().encloses(screen.course_readout.get_global_rect()),
			"Destination and remaining-distance readout fit the lower recess at each resolution")
	root.size = Vector2i(1280, 720)
	await settle()
	screen.graph.location_selected.emit("settlement_1")
	check(screen.departure_button.visible and screen.departure_button.text == "CHANGE COURSE",
		"Selecting another destination in flight offers Change Course")
	screen.graph.location_selected.emit("")
	check(expedition.state.destination_location_id == "refuel_station_1"
			and expedition.state.travel_state == Travel.TravelState.CRUISING, "GO TO departs immediately")
	screen.speed_buttons[10].pressed.emit()
	screen._process(0.5)
	var midway: Vector2 = expedition.state.position_nu
	screen.graph.go_requested.emit("settlement_1")
	await settle()
	check(expedition.state.destination_location_id == "settlement_1"
			and expedition.state.position_nu == midway and expedition.state.requested_speed == 10,
			"Double-click course changes reroute mid-flight from the current position at the same speed")
	await map_go("refuel_station_1")
	check(state.save_expedition_checkpoint(), "Save an in-flight checkpoint")
	var position: Vector2 = expedition.state.position_nu
	check(state.load_run_checkpoint() and state.prepare_checkpoint_resume(), "Prepare Continue transaction")
	expedition = state.expedition_simulation
	check(expedition.state.position_nu == position and expedition.state.requested_speed == 10
			and Travel.PauseReason.USER in expedition.state.pause_reasons,
			"Continue preserves exact position and requested speed but starts paused")
	var tick: int = expedition.state.simulation_tick
	check(expedition.advance(20) and expedition.state.simulation_tick == tick, "Continue cannot advance before Play")
	var save_path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-save.json"
	var before: Dictionary = expedition.state.snapshot()
	check(not state.prepare_checkpoint_resume() and expedition.state.snapshot() == before,
			"Failed Continue checkpoint preserves navigation and reports failure")
	state.run_save_path = save_path
	await reopen_checkpoint()
	screen.speed_buttons[10].pressed.emit()
	before = expedition.state.snapshot()
	state.run_save_path = "res://project.godot/no-save.json"
	screen._process(100)
	check(screen.arrival_modal == null
			and expedition.state.position_nu == Vector2(before.position_nu[0], before.position_nu[1])
			and Travel.PauseReason.SAVE_ERROR in expedition.state.pause_reasons,
			"Failed arrival save rolls back before showing an arrival")
	state.run_save_path = save_path
	screen._on_expedition_retry_pressed()
	screen._process(100)
	check(expedition.state.docked_location_id == "refuel_station_1" and is_instance_valid(screen.arrival_modal)
			and screen.arrival_location_id == "refuel_station_1" and expedition.state.requested_speed == 10,
			"Retried arrival docks, describes the station and keeps fast-forward")
	tick = expedition.state.simulation_tick
	check(expedition.advance(1) and expedition.state.simulation_tick > tick,
			"Docked time keeps running while the arrival dialog is open")
	# Arrival actions reflect real station services.
	state.fleet[0].hull_hp -= 40
	screen._fill_arrival_actions()
	var repair: Button = screen.arrival_modal.find_child("ArrivalRepairAll", true, false)
	var refuel: Button = screen.arrival_modal.find_child("ArrivalRefuel", true, false)
	check(repair != null and not repair.disabled and refuel != null, "Docked shipyard offers Repair all and Refuel")
	var credits: int = state.credits
	repair.pressed.emit()
	await settle()
	check(state.fleet[0].hull_hp == state.fleet[0].hull_max and state.credits < credits
			and screen.arrival_modal.find_child("ArrivalRepairAll", true, false) == null,
			"Repair all charges once and the action disappears")
	screen.arrival_modal.find_child("ArrivalRefuel", true, false).pressed.emit()
	await settle()
	check(is_equal_approx(expedition.state.fuel, expedition.state.fuel_capacity)
			and screen.arrival_modal.find_child("ArrivalRefuel", true, false) == null, "Refuel fills the tank")
	check(screen.get_global_rect().encloses(screen.arrival_modal.find_child("ArrivalDialogPanel", true, false).get_global_rect()),
			"Arrival dialog fits the viewport")
	screen.arrival_modal.find_child("ArrivalShipyard", true, false).pressed.emit()
	await settle()
	check(screen.arrival_modal == null and screen.active_tab == "SHIPS", "Visit Shipyard opens Ships")
	# A failed course save changes nothing and offers retry.
	var before_route: Dictionary = state.hangar_snapshot()
	state.run_save_path = "res://project.godot/no-save.json"
	check(not screen._set_course("derelict_1") and expedition.state.destination_location_id.is_empty()
			and state.hangar_snapshot().ships == before_route.ships and state.credits == before_route.credits,
			"Failed course save preserves route, fleet and credits")
	screen._refresh_expedition_controls()
	check(screen.travel_retry_button.visible, "Failed course save offers retry")
	state.run_save_path = save_path
	screen._on_expedition_retry_pressed()
	await map_go("derelict_1")
	screen._process(100)
	check(expedition.state.travel_state == Travel.TravelState.STOPPED and is_instance_valid(screen.arrival_modal)
			and screen.arrival_modal.find_child("ArrivalRepairAll", true, false) == null
			and screen.arrival_modal.find_child("ArrivalSetCourse", true, false) != null,
			"POI arrival describes the location without station services")
	screen.arrival_modal.find_child("ArrivalSetCourse", true, false).pressed.emit()
	await settle()
	check(screen.active_tab == "MAP" and screen.arrival_modal == null, "Arrival Set Course opens the map")
	await map_go("start_station")
	screen._on_expedition_stop_pressed()
	check(state.save_expedition_checkpoint(), "Persist manually stopped route")
	await reopen_checkpoint()
	check(screen.arrival_modal == null and expedition.state.destination_location_id == "start_station",
			"Stopping a route is not mistaken for an arrival on Continue")
	# A finished demo always leaves Main Menu reachable above every other dialog.
	state.completed = true
	check(state.save_run_checkpoint(), "Persist completed demo")
	await reopen_checkpoint()
	var run_end: Control = screen.get_node_or_null("RunEnd")
	check(run_end != null and screen.arrival_modal == null and screen.encounter_modal == null,
			"Demo complete is the only dialog")
	run_end.find_child("RunEndMainMenu", true, false).pressed.emit()
	await settle()
	check(current_scene != null and current_scene.scene_file_path == "res://scenes/main_menu.tscn",
			"Demo complete Main Menu leaves the run")
	print("EXPEDITION_ARRIVAL_CHECKS=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
