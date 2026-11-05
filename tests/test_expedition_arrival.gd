extends SceneTree

# Ordinary arrivals expose local actions without a modal or a new pause.
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
	check(screen.get_node_or_null("ArrivalDialog") == null and not expedition.state.departure_choice_pending,
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
	check(screen.get_node_or_null("ArrivalDialog") == null
			and expedition.state.position_nu == Vector2(before.position_nu[0], before.position_nu[1])
			and Travel.PauseReason.SAVE_ERROR in expedition.state.pause_reasons,
			"Failed arrival save rolls back before showing an arrival")
	state.run_save_path = save_path
	screen._on_expedition_retry_pressed()
	screen._process(100)
	check(expedition.state.docked_location_id == "refuel_station_1"
			and screen.get_node_or_null("ArrivalDialog") == null
			and screen.station_actions.find_child("StationRefuel", true, false) != null
			and expedition.state.requested_speed == 10,
			"Retried arrival exposes station services without a popup and keeps fast-forward")
	tick = expedition.state.simulation_tick
	check(expedition.advance(1) and expedition.state.simulation_tick > tick,
			"Docked time keeps running with contextual station services")
	# Arrival actions reflect real station services.
	state.fleet[0].hull_hp -= 40
	screen._sync_station_actions()
	var repair: Button = screen.station_actions.find_child("StationRepairAll", true, false)
	var refuel: Button = screen.station_actions.find_child("StationRefuel", true, false)
	check(repair != null and not repair.disabled and refuel != null, "Docked shipyard offers Repair all and Refuel")
	screen.graph.location_selected.emit("refuel_station_1")
	var repeated_state := false
	for child in screen.map_details.get_children():
		if child is Label and child.text.contains("Fleet is here"):
			repeated_state = true
	check(not repeated_state, "The fleet marker and station actions replace routine Fleet is here prose")
	check(repair.get_meta("resource_text", "") == "REPAIR ALL %d cr" % state.fleet_repair_cost()
			and refuel.get_meta("resource_text", "") == "REFUEL %d cr" % ceili(
				(expedition.state.fuel_capacity - expedition.state.fuel) * 2),
			"Contextual service controls expose exact current prices")
	screen.graph.user_moved = true
	var camera: Vector2 = screen.graph.camera_position
	var zoom: float = screen.graph.camera_zoom
	var selected: String = screen.map_selected_id
	var service_snapshot: Dictionary = state.hangar_snapshot()
	state.run_save_path = "res://project.godot/failed-service.json"
	repair.pressed.emit()
	service_snapshot.expedition.pause_reasons = expedition.state.snapshot().pause_reasons
	check(screen.instrument_seconds.hull == 0,
			"Failed repair never triggers a success-shaped condition cue")
	check(state.hangar_snapshot() == service_snapshot and not screen.expedition_status_override.is_empty()
			and screen.travel_retry_button.visible,
			"Failed contextual repair preserves hull, loads and credits and exposes save retry")
	state.run_save_path = save_path
	screen._on_expedition_retry_pressed()
	screen.station_actions.find_child("StationRefuel", true, false).pressed.emit()
	await settle()
	check(screen.instrument_seconds.fuel > 0,
			"Successful refuel triggers a cue at the fuel instrument")
	screen._update_instrument_feedback(0.2)
	check(screen.travel_fuel.self_modulate != Color.WHITE,
			"Refueling is visibly acknowledged without audio or routine text")
	screen._update_instrument_feedback(1)
	check(screen.travel_fuel.self_modulate == Color.WHITE,
			"Fuel cue restores its original appearance after its brief pulse")
	# Restore a missing-fuel quote to exercise refuel failure independently.
	expedition.state.fuel -= 10
	check(state.save_expedition_checkpoint(), "Persist partial fuel service fixture")
	screen._refresh_expedition_controls()
	service_snapshot = state.hangar_snapshot()
	state.run_save_path = "res://project.godot/failed-service.json"
	screen.station_actions.find_child("StationRefuel", true, false).pressed.emit()
	service_snapshot.expedition.pause_reasons = expedition.state.snapshot().pause_reasons
	check(screen.instrument_seconds.fuel == 0,
			"Failed refuel cannot pulse the fuel instrument as if it succeeded")
	check(state.hangar_snapshot() == service_snapshot and screen.travel_retry_button.visible
			and not screen.expedition_status_override.is_empty(),
			"Failed contextual refuel preserves fuel and credits with explicit retry")
	state.run_save_path = save_path
	screen._on_expedition_retry_pressed()
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		check(screen.roster_panel.get_global_rect().grow(1).encloses(screen.station_actions.get_global_rect()),
			"Contextual services fit the existing frame at %s" % resolution)
		check(screen.graph.camera_position == camera and screen.graph.camera_zoom == zoom
				and screen.map_selected_id == selected,
				"Service updates preserve map selection, pan and zoom")
		for action: Node in screen.station_actions.get_children():
			if action is Button:
				check(screen.roster_panel.get_global_rect().grow(1).encloses(action.get_global_rect()),
					"Cost-bearing service button fits its frame")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/checks/contextual-arrival/services-%d.png" % resolution.x)
	root.size = Vector2i(1280, 720)
	await settle()
	var credits: int = state.credits
	screen.station_actions.find_child("StationRepairAll", true, false).pressed.emit()
	await settle()
	check(screen.instrument_seconds.hull > 0,
			"Successful paid repair triggers a condition cue after the atomic transaction")
	check(state.fleet[0].hull_hp == state.fleet[0].hull_max and state.credits < credits
			and screen.station_actions.find_child("StationRepairAll", true, false) == null,
			"Repair all charges once and the action disappears")
	screen.station_actions.find_child("StationRefuel", true, false).pressed.emit()
	await settle()
	check(is_equal_approx(expedition.state.fuel, expedition.state.fuel_capacity)
			and screen.station_actions.find_child("StationRefuel", true, false) == null, "Refuel fills the tank")
	await reopen_checkpoint()
	check(screen.get_node_or_null("ArrivalDialog") == null
			and screen.station_actions.find_child("StationShipyard", true, false) != null,
			"Continue at a dock restores contextual services without an arrival notice or popup")
	check(screen.roster_panel.get_global_rect().encloses(screen.station_actions.get_global_rect()),
			"Station actions fit their existing side panel")
	screen.station_actions.find_child("StationShipyard", true, false).pressed.emit()
	await settle()
	check(screen.get_node_or_null("ArrivalDialog") == null and screen.active_tab == "FLEET", "Shipyard opens Fleet without an arrival modal")
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
	check(expedition.state.travel_state == Travel.TravelState.STOPPED
			and screen.get_node_or_null("ArrivalDialog") == null
			and screen.station_actions.get_child_count() == 0 and screen.departure_button.visible,
			"POI arrival has no station services or popup; Engage remains available")
	expedition.state.event_receipts.erase("derelict_salvage")
	check(state.save_expedition_checkpoint(), "Persist a withdrawn-arrival retry fixture")
	screen._sync_station_actions()
	var face: Button = screen.station_actions.find_child("StationRetryEvent", true, false)
	check(face != null and face.text == "FACE DERELICT FIELD",
			"An unresolved arrival encounter retains its named retry action in the side panel")
	var retry_snapshot: Dictionary = expedition.state.snapshot()
	state.run_save_path = "res://project.godot/failed-face.json"
	face.pressed.emit()
	check(screen.encounter_modal == null and expedition.state.pending_event_id.is_empty()
			and expedition.state.position_nu == Vector2(retry_snapshot.position_nu[0], retry_snapshot.position_nu[1])
			and screen.travel_retry_button.visible,
			"Failed encounter readmission rolls back and exposes save retry before opening a dialog")
	state.run_save_path = save_path
	screen._on_expedition_retry_pressed()
	screen.station_actions.find_child("StationRetryEvent", true, false).pressed.emit()
	check(is_instance_valid(screen.encounter_modal) and expedition.state.pending_event_id == "derelict_salvage"
			and Travel.PauseReason.ENCOUNTER in expedition.state.pause_reasons,
			"Retrying an arrival opens the real encounter and retains its mandatory pause")
	screen._choose_encounter("derelict_salvage", "careful")
	check(screen.encounter_modal == null and expedition.state.pending_event_id.is_empty(),
			"Encounter resolution returns to the same nonmodal location view")
	screen.departure_button.pressed.emit()
	await settle()
	check(screen.active_tab == "MAP" and screen.get_node_or_null("ArrivalDialog") == null, "Arrival Engage opens the map")
	await map_go("start_station")
	screen._on_expedition_stop_pressed()
	check(state.save_expedition_checkpoint(), "Persist manually stopped route")
	await reopen_checkpoint()
	check(screen.get_node_or_null("ArrivalDialog") == null and expedition.state.destination_location_id == "start_station",
			"Stopping a route is not mistaken for an arrival on Continue")
	# A finished demo always leaves Main Menu reachable above every other dialog.
	state.completed = true
	check(state.save_run_checkpoint(), "Persist completed demo")
	await reopen_checkpoint()
	var run_end: Control = screen.get_node_or_null("RunEnd")
	check(run_end != null and screen.get_node_or_null("ArrivalDialog") == null and screen.encounter_modal == null,
			"Demo complete is the only dialog")
	run_end.find_child("RunEndMainMenu", true, false).pressed.emit()
	await settle()
	check(current_scene != null and current_scene.scene_file_path == "res://scenes/main_menu.tscn",
			"Demo complete Main Menu leaves the run")
	print("EXPEDITION_ARRIVAL_CHECKS=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
